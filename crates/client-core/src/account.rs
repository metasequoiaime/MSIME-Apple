//! Account protocol and session state independent of UI and platform hosts.

use reqwest::blocking::{Client, Response};
use reqwest::{Method, StatusCode, Url};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::future::Future;
use std::io::Read;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const ACCOUNT_ORIGIN: &str = "https://api.msime.app";
const MAX_JSON_BYTES: usize = 1024 * 1024;
const REFRESH_EARLY_SECONDS: u64 = 30;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountIdentity {
    pub user_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountUser {
    pub id: String,
    pub display_name: String,
    pub created_at: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountChallenge {
    pub challenge_id: String,
    pub expires_in: u64,
    pub nonce: Option<String>,
    pub authorization_url: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountProfileIdentity {
    pub provider: String,
    pub subject: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountProfile {
    pub user: AccountUser,
    pub identities: Vec<AccountProfileIdentity>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct AccountTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: u64,
    pub user: AccountUser,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct SavedAccountSession {
    pub tokens: AccountTokens,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, thiserror::Error)]
pub enum AccountError {
    #[error("invalid account request")]
    Invalid,
    #[error("account authorization is required")]
    Unauthorized,
    #[error("account operation is forbidden")]
    Forbidden,
    #[error("account data changed")]
    Conflict,
    #[error("account resource was not found")]
    NotFound,
    #[error("account request was rate limited")]
    RateLimited,
    #[error("account service is unavailable")]
    Unavailable,
    #[error("secure account storage is unavailable")]
    Storage,
    #[error("account operation was cancelled")]
    Cancelled,
}

impl AccountError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Invalid => "account_invalid",
            Self::Unauthorized | Self::Forbidden => "account_unauthorized",
            Self::RateLimited => "account_rate_limited",
            Self::Storage => "account_storage",
            Self::Cancelled => "account_cancelled",
            Self::Conflict | Self::NotFound | Self::Unavailable => "account_unavailable",
        }
    }

    fn from_status(status: StatusCode) -> Self {
        match status.as_u16() {
            400 => Self::Invalid,
            401 => Self::Unauthorized,
            403 => Self::Forbidden,
            404 => Self::NotFound,
            409 => Self::Conflict,
            429 => Self::RateLimited,
            503 => Self::Unavailable,
            _ => Self::Unavailable,
        }
    }
}

pub trait AccountApi: Send + Sync + 'static {
    fn providers(&self) -> Result<std::collections::HashMap<String, bool>, AccountError>;
    fn challenge(&self, provider: &str, target: &str) -> Result<AccountChallenge, AccountError>;
    fn login(&self, challenge: &str, credential: &str) -> Result<AccountTokens, AccountError>;
    fn refresh(&self, refresh_token: &str) -> Result<AccountTokens, AccountError>;
    fn profile(&self, access_token: &str) -> Result<AccountProfile, AccountError>;
    fn rename(&self, display_name: &str, access_token: &str) -> Result<(), AccountError>;
    fn logout(&self, access_token: &str, all: bool) -> Result<(), AccountError>;
    fn delete_account(&self, access_token: &str) -> Result<(), AccountError>;
}

pub trait AccountSessionStorage: Send + Sync + 'static {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError>;
    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError>;
    fn clear(&self) -> Result<(), AccountError>;
}

#[derive(Clone)]
pub struct BackendAccountClient {
    client: Client,
    origin: Url,
}

impl BackendAccountClient {
    pub fn new() -> Result<Self, AccountError> {
        Self::with_origin(ACCOUNT_ORIGIN, false)
    }

    fn with_origin(origin: &str, allow_http_loopback: bool) -> Result<Self, AccountError> {
        let origin = Url::parse(origin).map_err(|_| AccountError::Invalid)?;
        let valid_scheme = origin.scheme() == "https"
            || (allow_http_loopback
                && origin.scheme() == "http"
                && origin.host_str() == Some("127.0.0.1"));
        if !valid_scheme
            || origin.cannot_be_a_base()
            || origin.username() != ""
            || origin.password().is_some()
            || origin.query().is_some()
            || origin.fragment().is_some()
        {
            return Err(AccountError::Invalid);
        }
        let client = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(30))
            .user_agent("MSIME/Android")
            .build()
            .map_err(|_| AccountError::Unavailable)?;
        Ok(Self { client, origin })
    }

    #[cfg(test)]
    pub(crate) fn loopback(origin: &str) -> Result<Self, AccountError> {
        Self::with_origin(origin, true)
    }

    fn request(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
    ) -> Result<Vec<u8>, AccountError> {
        self.request_with_limit(method, path, token, body, MAX_JSON_BYTES)
    }

    pub(crate) fn request_with_limit(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
        maximum_response_bytes: usize,
    ) -> Result<Vec<u8>, AccountError> {
        self.request_with_limit_timeout(
            method,
            path,
            token,
            body,
            maximum_response_bytes,
            Duration::from_secs(30),
        )
    }

    pub(crate) fn request_with_limit_timeout(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
        maximum_response_bytes: usize,
        timeout: Duration,
    ) -> Result<Vec<u8>, AccountError> {
        if !path.starts_with("/v1/") || path.contains('\\') {
            return Err(AccountError::Invalid);
        }
        if body
            .as_ref()
            .is_some_and(|value| value.len() > MAX_JSON_BYTES)
            || token.is_some_and(|value| value.is_empty() || value.chars().any(char::is_whitespace))
        {
            return Err(AccountError::Invalid);
        }
        let url = self.origin.join(path).map_err(|_| AccountError::Invalid)?;
        if url.scheme() != self.origin.scheme()
            || url.host_str() != self.origin.host_str()
            || url.port_or_known_default() != self.origin.port_or_known_default()
            || url.username() != ""
            || url.password().is_some()
            || url.fragment().is_some()
        {
            return Err(AccountError::Invalid);
        }
        let mut request = self
            .client
            .request(method, url)
            .header(reqwest::header::ACCEPT, "application/json");
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request
                .header(reqwest::header::CONTENT_TYPE, "application/json")
                .body(body);
        }
        let response = request
            .timeout(timeout)
            .send()
            .map_err(|_| AccountError::Unavailable)?;
        read_bounded_response(response, maximum_response_bytes)
    }

    pub(crate) fn json<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
    ) -> Result<T, AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        let bytes = self.request(method, path, token, body)?;
        serde_json::from_slice(&bytes).map_err(|_| AccountError::Unavailable)
    }

    pub(crate) fn json_with_limit<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
        maximum_response_bytes: usize,
    ) -> Result<T, AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        let bytes = self.request_with_limit(method, path, token, body, maximum_response_bytes)?;
        serde_json::from_slice(&bytes).map_err(|_| AccountError::Unavailable)
    }

    pub(crate) fn json_with_limit_timeout<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
        maximum_response_bytes: usize,
        timeout: Duration,
    ) -> Result<T, AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        let bytes = self.request_with_limit_timeout(
            method,
            path,
            token,
            body,
            maximum_response_bytes,
            timeout,
        )?;
        serde_json::from_slice(&bytes).map_err(|_| AccountError::Unavailable)
    }

    fn empty<B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
    ) -> Result<(), AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        self.request(method, path, token, body).map(|_| ())
    }
}

fn read_bounded_response(
    mut response: Response,
    maximum_response_bytes: usize,
) -> Result<Vec<u8>, AccountError> {
    if !response.status().is_success() {
        return Err(AccountError::from_status(response.status()));
    }
    if response
        .content_length()
        .is_some_and(|length| length > maximum_response_bytes as u64)
    {
        return Err(AccountError::Unavailable);
    }
    let mut bytes = Vec::new();
    response
        .by_ref()
        .take((maximum_response_bytes + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| AccountError::Unavailable)?;
    if bytes.len() > maximum_response_bytes {
        return Err(AccountError::Unavailable);
    }
    Ok(bytes)
}

impl AccountApi for BackendAccountClient {
    fn providers(&self) -> Result<std::collections::HashMap<String, bool>, AccountError> {
        #[derive(Deserialize)]
        struct Providers {
            providers: std::collections::HashMap<String, bool>,
        }
        self.json::<Providers, ()>(Method::GET, "/v1/auth/providers", None, None)
            .map(|value| value.providers)
    }

    fn challenge(&self, provider: &str, target: &str) -> Result<AccountChallenge, AccountError> {
        validate_provider_target(provider, target)?;
        #[derive(Serialize)]
        struct Body<'a> {
            provider: &'a str,
            target: &'a str,
            purpose: &'static str,
        }
        let challenge = self.json(
            Method::POST,
            "/v1/auth/challenges",
            None,
            Some(&Body {
                provider,
                target,
                purpose: "login",
            }),
        )?;
        validate_challenge(&challenge)?;
        Ok(challenge)
    }

    fn login(&self, challenge: &str, credential: &str) -> Result<AccountTokens, AccountError> {
        validate_login(challenge, credential)?;
        #[derive(Serialize)]
        struct Body<'a> {
            challenge_id: &'a str,
            credential: &'a str,
        }
        let tokens = self.json(
            Method::POST,
            "/v1/auth/login",
            None,
            Some(&Body {
                challenge_id: challenge,
                credential,
            }),
        )?;
        validate_tokens(&tokens)?;
        Ok(tokens)
    }

    fn refresh(&self, refresh_token: &str) -> Result<AccountTokens, AccountError> {
        if !valid_token(refresh_token) {
            return Err(AccountError::Invalid);
        }
        #[derive(Serialize)]
        struct Body<'a> {
            refresh_token: &'a str,
        }
        let tokens = self.json(
            Method::POST,
            "/v1/auth/refresh",
            None,
            Some(&Body { refresh_token }),
        )?;
        validate_tokens(&tokens)?;
        Ok(tokens)
    }

    fn profile(&self, access_token: &str) -> Result<AccountProfile, AccountError> {
        if !valid_token(access_token) {
            return Err(AccountError::Invalid);
        }
        let profile =
            self.json::<AccountProfile, ()>(Method::GET, "/v1/users/me", Some(access_token), None)?;
        validate_profile(&profile)?;
        Ok(profile)
    }

    fn rename(&self, display_name: &str, access_token: &str) -> Result<(), AccountError> {
        validate_display_name(display_name)?;
        #[derive(Serialize)]
        struct Body<'a> {
            display_name: &'a str,
        }
        self.empty(
            Method::PATCH,
            "/v1/users/me",
            Some(access_token),
            Some(&Body { display_name }),
        )
    }

    fn logout(&self, access_token: &str, all: bool) -> Result<(), AccountError> {
        #[derive(Serialize)]
        struct Body {
            all: bool,
        }
        self.empty(
            Method::POST,
            "/v1/auth/logout",
            Some(access_token),
            Some(&Body { all }),
        )
    }

    fn delete_account(&self, access_token: &str) -> Result<(), AccountError> {
        self.empty::<()>(Method::DELETE, "/v1/users/me", Some(access_token), None)
    }
}

fn validate_provider_target(provider: &str, target: &str) -> Result<(), AccountError> {
    if !matches!(provider, "email" | "phone")
        || target.is_empty()
        || target.len() > 320
        || target.trim() != target
        || target.chars().any(char::is_control)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_challenge(challenge: &AccountChallenge) -> Result<(), AccountError> {
    if challenge.challenge_id.is_empty()
        || challenge.challenge_id.len() > 256
        || challenge.challenge_id.chars().any(char::is_control)
        || challenge.expires_in == 0
        || challenge
            .nonce
            .as_ref()
            .is_some_and(|value| value.len() > 4096 || value.chars().any(char::is_control))
        || challenge
            .authorization_url
            .as_ref()
            .is_some_and(|value| value.len() > 4096 || value.chars().any(char::is_control))
    {
        return Err(AccountError::Unavailable);
    }
    Ok(())
}

fn validate_login(challenge: &str, credential: &str) -> Result<(), AccountError> {
    if challenge.is_empty()
        || challenge.len() > 256
        || challenge.chars().any(char::is_control)
        || credential.len() != 6
        || !credential.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_display_name(value: &str) -> Result<(), AccountError> {
    if value.is_empty()
        || value.trim() != value
        || value.chars().count() > 64
        || value.chars().any(char::is_control)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_tokens(tokens: &AccountTokens) -> Result<(), AccountError> {
    if tokens.token_type != "Bearer"
        || tokens.expires_in == 0
        || !valid_token(&tokens.access_token)
        || !valid_token(&tokens.refresh_token)
    {
        return Err(AccountError::Unavailable);
    }
    validate_user(&tokens.user).map_err(|_| AccountError::Unavailable)
}

fn valid_token(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn validate_user(user: &AccountUser) -> Result<(), AccountError> {
    validate_identity(&AccountIdentity {
        user_id: user.id.clone(),
    })
    .map_err(|_| AccountError::Invalid)?;
    if user.display_name.chars().count() > 64
        || user.display_name.chars().any(char::is_control)
        || user.created_at.len() > 128
        || user.created_at.chars().any(char::is_control)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_profile(profile: &AccountProfile) -> Result<(), AccountError> {
    validate_user(&profile.user)?;
    if profile.identities.len() > 16
        || profile.identities.iter().any(|identity| {
            identity.provider.is_empty()
                || identity.provider.len() > 32
                || !identity
                    .provider
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte == b'_' || byte == b'-')
                || identity.subject.len() > 512
                || identity.subject.chars().any(char::is_control)
        })
    {
        return Err(AccountError::Unavailable);
    }
    Ok(())
}

pub fn validate_identity(identity: &AccountIdentity) -> Result<(), &'static str> {
    if identity.user_id.is_empty()
        || identity.user_id.len() > 256
        || identity.user_id.chars().any(char::is_control)
    {
        return Err("invalid account identity");
    }
    Ok(())
}

struct SessionState {
    loaded: bool,
    saved: Option<SavedAccountSession>,
    generation: u64,
    refresh: Option<Arc<RefreshFlight>>,
}

struct RefreshFlight {
    result: Mutex<Option<Result<String, AccountError>>>,
    ready: Condvar,
}

impl RefreshFlight {
    fn new() -> Self {
        Self {
            result: Mutex::new(None),
            ready: Condvar::new(),
        }
    }

    fn finish(&self, result: Result<String, AccountError>) {
        if let Ok(mut slot) = self.result.lock() {
            *slot = Some(result);
            self.ready.notify_all();
        }
    }

    fn wait(&self) -> Result<String, AccountError> {
        let mut slot = self.result.lock().map_err(|_| AccountError::Unavailable)?;
        while slot.is_none() {
            slot = self
                .ready
                .wait(slot)
                .map_err(|_| AccountError::Unavailable)?;
        }
        slot.clone().ok_or(AccountError::Unavailable)?
    }
}

pub struct BackendAccountSession<A: AccountApi, S: AccountSessionStorage> {
    api: A,
    storage: S,
    state: Mutex<SessionState>,
}

impl<A: AccountApi, S: AccountSessionStorage> BackendAccountSession<A, S> {
    pub fn new(api: A, storage: S) -> Self {
        Self {
            api,
            storage,
            state: Mutex::new(SessionState {
                loaded: false,
                saved: None,
                generation: 0,
                refresh: None,
            }),
        }
    }

    fn lock(&self) -> Result<MutexGuard<'_, SessionState>, AccountError> {
        self.state.lock().map_err(|_| AccountError::Unavailable)
    }

    fn load_locked(&self, state: &mut SessionState) -> Result<(), AccountError> {
        if !state.loaded {
            let saved = self.storage.load()?;
            if let Some(value) = &saved {
                validate_tokens(&value.tokens).map_err(|_| AccountError::Storage)?;
            }
            state.saved = saved;
            state.loaded = true;
        }
        Ok(())
    }

    pub fn status(&self) -> Result<Option<AccountUser>, AccountError> {
        let mut state = self.lock()?;
        self.load_locked(&mut state)?;
        Ok(state.saved.as_ref().map(|saved| saved.tokens.user.clone()))
    }

    pub fn providers(&self) -> Result<std::collections::HashMap<String, bool>, AccountError> {
        self.api.providers()
    }

    pub fn request_code(
        &self,
        provider: &str,
        target: &str,
    ) -> Result<AccountChallenge, AccountError> {
        validate_provider_target(provider, target)?;
        self.api.challenge(provider, target)
    }

    pub fn sign_in(&self, challenge: &str, credential: &str) -> Result<AccountUser, AccountError> {
        validate_login(challenge, credential)?;
        let version = {
            let mut state = self.lock()?;
            state.generation = state.generation.wrapping_add(1);
            state.refresh = None;
            state.generation
        };
        let tokens = self.api.login(challenge, credential)?;
        validate_tokens(&tokens)?;
        let value = saved_session(tokens)?;
        let user = value.tokens.user.clone();
        let mut state = self.lock()?;
        if state.generation != version {
            return Err(AccountError::Cancelled);
        }
        self.storage.save(&value)?;
        state.saved = Some(value);
        state.loaded = true;
        Ok(user)
    }

    pub fn access_token(&self, rejected_token: Option<&str>) -> Result<String, AccountError> {
        let (flight, version, refresh_token) = {
            let mut state = self.lock()?;
            self.load_locked(&mut state)?;
            let current = state.saved.as_ref().ok_or(AccountError::Unauthorized)?;
            if current.expires_at_unix_ms > refresh_deadline_ms()
                && rejected_token != Some(current.tokens.access_token.as_str())
            {
                return Ok(current.tokens.access_token.clone());
            }
            if let Some(flight) = &state.refresh {
                let flight = Arc::clone(flight);
                drop(state);
                return flight.wait();
            }
            let version = state.generation;
            let refresh_token = current.tokens.refresh_token.clone();
            let flight = Arc::new(RefreshFlight::new());
            state.refresh = Some(Arc::clone(&flight));
            (flight, version, refresh_token)
        };

        let api_result = self.api.refresh(&refresh_token);
        let result = {
            let mut state = self.lock()?;
            let result = if state.generation != version {
                Err(AccountError::Cancelled)
            } else {
                match api_result {
                    Ok(tokens) => {
                        match validate_tokens(&tokens).and_then(|_| saved_session(tokens)) {
                            Ok(value) => match self.storage.save(&value) {
                                Ok(()) => {
                                    let token = value.tokens.access_token.clone();
                                    state.saved = Some(value);
                                    state.loaded = true;
                                    Ok(token)
                                }
                                Err(error) => Err(error),
                            },
                            Err(error) => Err(error),
                        }
                    }
                    Err(AccountError::Unauthorized) => {
                        state.saved = None;
                        state.loaded = true;
                        self.storage.clear().and(Err(AccountError::Unauthorized))
                    }
                    Err(error) => Err(error),
                }
            };
            if state
                .refresh
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(current, &flight))
            {
                state.refresh = None;
            }
            result
        };
        flight.finish(result.clone());
        result
    }

    pub fn credentials(
        &self,
        rejected_token: Option<&str>,
        expected_user_id: Option<&str>,
    ) -> Result<(String, String), AccountError> {
        {
            let mut state = self.lock()?;
            self.load_locked(&mut state)?;
            if expected_user_id.is_some_and(|expected| {
                state
                    .saved
                    .as_ref()
                    .map(|saved| saved.tokens.user.id.as_str())
                    != Some(expected)
            }) {
                return Err(AccountError::Cancelled);
            }
        }
        let token = self.access_token(rejected_token)?;
        let mut state = self.lock()?;
        self.load_locked(&mut state)?;
        let saved = state.saved.as_ref().ok_or(AccountError::Cancelled)?;
        if saved.tokens.access_token != token
            || expected_user_id.is_some_and(|expected| saved.tokens.user.id != expected)
        {
            return Err(AccountError::Cancelled);
        }
        Ok((saved.tokens.user.id.clone(), token))
    }

    pub fn profile(&self) -> Result<AccountProfile, AccountError> {
        let (user_id, token) = self.credentials(None, None)?;
        let profile = match self.api.profile(&token) {
            Err(AccountError::Unauthorized) => {
                let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
                self.api.profile(&replacement)?
            }
            result => result?,
        };
        validate_profile(&profile)?;
        if profile.user.id != user_id {
            return Err(AccountError::Cancelled);
        }
        self.update_user(profile.user.clone())?;
        Ok(profile)
    }

    pub fn rename(&self, display_name: &str) -> Result<AccountProfile, AccountError> {
        validate_display_name(display_name)?;
        let (user_id, token) = self.credentials(None, None)?;
        if let Err(error) = self.api.rename(display_name, &token) {
            if error != AccountError::Unauthorized {
                return Err(error);
            }
            let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
            self.api.rename(display_name, &replacement)?;
        }
        self.profile()
    }

    pub fn logout(&self, all: bool) -> Result<(), AccountError> {
        let token = match self.access_token(None) {
            Ok(token) => token,
            Err(error) => {
                self.forget()?;
                return Err(error);
            }
        };
        self.forget()?;
        self.api.logout(&token, all)
    }

    pub fn delete_account(&self) -> Result<(), AccountError> {
        let (user_id, token) = self.credentials(None, None)?;
        let result = match self.api.delete_account(&token) {
            Err(AccountError::Unauthorized) => {
                let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
                self.api.delete_account(&replacement)
            }
            result => result,
        };
        result?;
        self.forget()
    }

    pub fn forget(&self) -> Result<(), AccountError> {
        let mut state = self.lock()?;
        state.generation = state.generation.wrapping_add(1);
        state.refresh = None;
        state.saved = None;
        state.loaded = true;
        self.storage.clear()
    }

    fn update_user(&self, user: AccountUser) -> Result<(), AccountError> {
        let mut state = self.lock()?;
        self.load_locked(&mut state)?;
        let current = state.saved.as_mut().ok_or(AccountError::Cancelled)?;
        if current.tokens.user.id != user.id {
            return Err(AccountError::Cancelled);
        }
        current.tokens.user = user;
        self.storage.save(current)
    }
}

fn saved_session(tokens: AccountTokens) -> Result<SavedAccountSession, AccountError> {
    let now = unix_ms()?;
    let duration = tokens
        .expires_in
        .checked_mul(1000)
        .ok_or(AccountError::Unavailable)?;
    let expires_at_unix_ms = now.checked_add(duration).ok_or(AccountError::Unavailable)?;
    Ok(SavedAccountSession {
        tokens,
        expires_at_unix_ms,
    })
}

fn unix_ms() -> Result<u64, AccountError> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| AccountError::Unavailable)?
        .as_millis();
    u64::try_from(millis).map_err(|_| AccountError::Unavailable)
}

fn refresh_deadline_ms() -> u64 {
    unix_ms()
        .unwrap_or(u64::MAX)
        .saturating_add(REFRESH_EARLY_SECONDS * 1000)
}

pub trait AccountSession {
    type Error;
    fn identity(&self) -> impl Future<Output = Result<AccountIdentity, Self::Error>> + Send;
    fn bearer_token(&self) -> impl Future<Output = Result<String, Self::Error>> + Send;
    fn refresh(&self) -> impl Future<Output = Result<String, Self::Error>> + Send;
}

impl<A: AccountApi, S: AccountSessionStorage> AccountSession for BackendAccountSession<A, S> {
    type Error = AccountError;

    async fn identity(&self) -> Result<AccountIdentity, Self::Error> {
        self.status()?
            .map(|user| AccountIdentity { user_id: user.id })
            .ok_or(AccountError::Unauthorized)
    }

    async fn bearer_token(&self) -> Result<String, Self::Error> {
        self.access_token(None)
    }

    async fn refresh(&self) -> Result<String, Self::Error> {
        let current = self.access_token(None)?;
        self.access_token(Some(&current))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::thread;

    fn token(byte: u8) -> String {
        std::iter::repeat_n(char::from(byte), 64).collect()
    }

    fn user() -> AccountUser {
        AccountUser {
            id: "fixture-user".into(),
            display_name: "Fixture".into(),
            created_at: "2026-01-01T00:00:00Z".into(),
        }
    }

    fn tokens(access: u8, refresh: u8, expires_in: u64) -> AccountTokens {
        AccountTokens {
            access_token: token(access),
            refresh_token: token(refresh),
            token_type: "Bearer".into(),
            expires_in,
            user: user(),
        }
    }

    #[derive(Clone, Default)]
    struct MemoryStorage(Arc<Mutex<Option<SavedAccountSession>>>);

    impl AccountSessionStorage for MemoryStorage {
        fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
            self.0
                .lock()
                .map(|value| value.clone())
                .map_err(|_| AccountError::Storage)
        }

        fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
            *self.0.lock().map_err(|_| AccountError::Storage)? = Some(session.clone());
            Ok(())
        }

        fn clear(&self) -> Result<(), AccountError> {
            *self.0.lock().map_err(|_| AccountError::Storage)? = None;
            Ok(())
        }
    }

    #[derive(Clone)]
    struct FakeApi {
        refreshes: Arc<AtomicUsize>,
        reject_refresh: Arc<AtomicBool>,
        refresh_gate: Option<Arc<(Mutex<bool>, Condvar)>>,
    }

    impl FakeApi {
        fn new() -> Self {
            Self {
                refreshes: Arc::new(AtomicUsize::new(0)),
                reject_refresh: Arc::new(AtomicBool::new(false)),
                refresh_gate: None,
            }
        }
    }

    impl AccountApi for FakeApi {
        fn providers(&self) -> Result<HashMap<String, bool>, AccountError> {
            Ok(HashMap::from([("email".into(), true)]))
        }

        fn challenge(
            &self,
            _provider: &str,
            _target: &str,
        ) -> Result<AccountChallenge, AccountError> {
            Ok(AccountChallenge {
                challenge_id: "fixture-challenge".into(),
                expires_in: 300,
                nonce: None,
                authorization_url: None,
            })
        }

        fn login(
            &self,
            _challenge: &str,
            _credential: &str,
        ) -> Result<AccountTokens, AccountError> {
            Ok(tokens(b'a', b'b', 900))
        }

        fn refresh(&self, _refresh_token: &str) -> Result<AccountTokens, AccountError> {
            self.refreshes.fetch_add(1, Ordering::SeqCst);
            if let Some(gate) = &self.refresh_gate {
                let (lock, ready) = &**gate;
                let mut open = lock.lock().map_err(|_| AccountError::Unavailable)?;
                while !*open {
                    open = ready.wait(open).map_err(|_| AccountError::Unavailable)?;
                }
            }
            if self.reject_refresh.load(Ordering::SeqCst) {
                Err(AccountError::Unauthorized)
            } else {
                Ok(tokens(b'c', b'd', 900))
            }
        }

        fn profile(&self, _access_token: &str) -> Result<AccountProfile, AccountError> {
            Ok(AccountProfile {
                user: user(),
                identities: vec![AccountProfileIdentity {
                    provider: "email".into(),
                    subject: "masked-fixture".into(),
                }],
            })
        }

        fn rename(&self, _display_name: &str, _access_token: &str) -> Result<(), AccountError> {
            Ok(())
        }

        fn logout(&self, _access_token: &str, _all: bool) -> Result<(), AccountError> {
            Ok(())
        }

        fn delete_account(&self, _access_token: &str) -> Result<(), AccountError> {
            Ok(())
        }
    }

    fn installed(storage: &MemoryStorage, expires_at_unix_ms: u64) {
        *storage.0.lock().unwrap() = Some(SavedAccountSession {
            tokens: tokens(b'a', b'b', 900),
            expires_at_unix_ms,
        });
    }

    #[test]
    fn validates_public_inputs_and_tokens() {
        assert!(validate_identity(&AccountIdentity {
            user_id: "user-1".into()
        })
        .is_ok());
        assert!(validate_identity(&AccountIdentity {
            user_id: "bad\n".into()
        })
        .is_err());
        assert_eq!(
            validate_provider_target("email", " fixture@example.test"),
            Err(AccountError::Invalid)
        );
        assert_eq!(
            validate_login("challenge", "１２３４５６"),
            Err(AccountError::Invalid)
        );
        let mut invalid = tokens(b'a', b'b', 900);
        invalid.access_token = token(b'A');
        assert_eq!(validate_tokens(&invalid), Err(AccountError::Unavailable));
    }

    #[test]
    fn refreshes_once_for_concurrent_callers() {
        let storage = MemoryStorage::default();
        installed(&storage, 0);
        let gate = Arc::new((Mutex::new(false), Condvar::new()));
        let mut api = FakeApi::new();
        api.refresh_gate = Some(Arc::clone(&gate));
        let count = Arc::clone(&api.refreshes);
        let session = Arc::new(BackendAccountSession::new(api, storage));
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let session = Arc::clone(&session);
                thread::spawn(move || session.access_token(None))
            })
            .collect();
        while count.load(Ordering::SeqCst) == 0 {
            thread::yield_now();
        }
        let (lock, ready) = &*gate;
        *lock.lock().unwrap() = true;
        ready.notify_all();
        let values: Vec<_> = handles
            .into_iter()
            .map(|handle| handle.join().unwrap().unwrap())
            .collect();
        assert_eq!(count.load(Ordering::SeqCst), 1);
        assert!(values.iter().all(|value| value == &token(b'c')));
    }

    #[test]
    fn unauthorized_refresh_clears_storage() {
        let storage = MemoryStorage::default();
        installed(&storage, 0);
        let api = FakeApi::new();
        api.reject_refresh.store(true, Ordering::SeqCst);
        let session = BackendAccountSession::new(api, storage.clone());
        assert_eq!(session.access_token(None), Err(AccountError::Unauthorized));
        assert!(storage.load().unwrap().is_none());
        assert_eq!(session.status().unwrap(), None);
    }

    #[test]
    fn late_refresh_cannot_restore_forgotten_session() {
        let storage = MemoryStorage::default();
        installed(&storage, 0);
        let gate = Arc::new((Mutex::new(false), Condvar::new()));
        let mut api = FakeApi::new();
        api.refresh_gate = Some(Arc::clone(&gate));
        let count = Arc::clone(&api.refreshes);
        let session = Arc::new(BackendAccountSession::new(api, storage.clone()));
        let worker = {
            let session = Arc::clone(&session);
            thread::spawn(move || session.access_token(None))
        };
        while count.load(Ordering::SeqCst) == 0 {
            thread::yield_now();
        }
        session.forget().unwrap();
        let (lock, ready) = &*gate;
        *lock.lock().unwrap() = true;
        ready.notify_all();
        assert_eq!(worker.join().unwrap(), Err(AccountError::Cancelled));
        assert!(storage.load().unwrap().is_none());
    }

    #[test]
    fn logout_clears_local_session_before_remote_result() {
        let storage = MemoryStorage::default();
        installed(&storage, u64::MAX);
        let session = BackendAccountSession::new(FakeApi::new(), storage.clone());
        session.logout(true).unwrap();
        assert!(storage.load().unwrap().is_none());
        assert_eq!(session.status().unwrap(), None);
    }

    fn serve_once(response: Vec<u8>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0_u8; 4096];
            let _ = stream.read(&mut request);
            std::io::Write::write_all(&mut stream, &response).unwrap();
        });
        format!("http://{address}")
    }

    #[test]
    fn transport_rejects_redirects() {
        let origin = serve_once(
            b"HTTP/1.1 302 Found\r\nLocation: https://example.test/\r\nContent-Length: 0\r\n\r\n"
                .to_vec(),
        );
        let client = BackendAccountClient::loopback(&origin).unwrap();
        assert_eq!(client.providers(), Err(AccountError::Unavailable));
    }

    #[test]
    fn transport_rejects_oversized_responses() {
        let body = vec![b'x'; MAX_JSON_BYTES + 1];
        let header = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n",
            body.len()
        );
        let mut response = header.into_bytes();
        response.extend(body);
        let origin = serve_once(response);
        let client = BackendAccountClient::loopback(&origin).unwrap();
        assert_eq!(client.providers(), Err(AccountError::Unavailable));
    }
}
