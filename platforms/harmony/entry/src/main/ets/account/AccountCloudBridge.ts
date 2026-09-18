export type AccountTransportResponse = { status: number; body: string };

export interface AccountTransport {
  request(method: string, path: string, token?: string, body?: Record<string, unknown>): Promise<AccountTransportResponse>;
}

export interface AccountSessionStore {
  load(): string | null;
  save(value: string): void;
  clear(): void;
}

type Session = {
  access_token: string;
  refresh_token: string;
  token_type: "Bearer";
  expires_at: number;
  user: { id: string; display_name: string; created_at: string };
};

type Action = Record<string, unknown>;

const MAX_ACTION_BYTES = 64 * 1024;
const MAX_CLIPBOARD_TEXT = 4000;
const MAX_SEARCH = 256;

function error(code: string): string {
  return JSON.stringify({ ok: false, error: code });
}

function success(value: unknown): string {
  return JSON.stringify({ ok: true, value });
}

function validString(value: unknown, maximum: number, allowEmpty = false): value is string {
  return typeof value === "string" && (allowEmpty || value.length > 0) && value.length <= maximum
    && ![...value].some(character => {
      const code = character.codePointAt(0) ?? 0;
      return code <= 0x1f || code === 0x7f;
    });
}

function validToken(value: unknown): value is string {
  return typeof value === "string" && value.length === 64 && /^[0-9a-f]+$/.test(value);
}

function parseBody(body: string): Action | null {
  if (body.length === 0 || new TextEncoder().encode(body).length > MAX_ACTION_BYTES) return null;
  try {
    const value: unknown = JSON.parse(body);
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? value as Action : null;
  } catch {
    return null;
  }
}

function mapStatus(status: number): string {
  if (status === 400) return "account_invalid";
  if (status === 401 || status === 403) return "account_unauthorized";
  if (status === 404) return "account_unavailable";
  if (status === 409) return "account_conflict";
  if (status === 429) return "account_rate_limited";
  return "account_unavailable";
}

function parseJson(body: string): Action | null {
  try {
    const value: unknown = JSON.parse(body);
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? value as Action : null;
  } catch {
    return null;
  }
}

function validateUser(value: unknown): value is Session["user"] {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const user = value as Action;
  return validString(user.id, 256) && validString(user.display_name, 256, true)
    && validString(user.created_at, 128, true);
}

function validateSession(value: unknown): value is Session {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const session = value as Action;
  return validToken(session.access_token) && validToken(session.refresh_token)
    && session.token_type === "Bearer" && typeof session.expires_at === "number"
    && Number.isFinite(session.expires_at) && validateUser(session.user);
}

export class AccountCloudBridge {
  private readonly transport: AccountTransport;
  private readonly store: AccountSessionStore;
  private session: Session | null = null;
  private generation = 0;

  constructor(transport: AccountTransport, store: AccountSessionStore) {
    this.transport = transport;
    this.store = store;
    const saved = store.load();
    if (saved !== null) {
      try {
        const value: unknown = JSON.parse(saved);
        if (validateSession(value)) this.session = value;
        else store.clear();
      } catch {
        store.clear();
      }
    }
  }

  async handle(document: string): Promise<string> {
    const action = parseBody(document);
    if (action === null || typeof action.operation !== "string") return error("account_invalid");
    const operation = action.operation;
    try {
      switch (operation) {
        case "status":
          if (this.session !== null && this.session.expires_at <= Date.now()) this.clearExpired();
          return success({ user: this.session?.user ?? null });
        case "providers": return this.requestPublic("GET", "/v1/auth/providers");
        case "request_code": return await this.requestCode(action);
        case "login": return await this.login(action);
        case "profile": return await this.authenticated("GET", "/v1/users/me");
        case "rename": return await this.rename(action);
        case "logout": return await this.logout(action);
        case "delete_account": return await this.deleteAccount();
        case "clear_expired": this.clearExpired(); return success({});
        case "clipboard": return await this.clipboard(action);
        default: return error("account_invalid");
      }
    } catch (cause) {
      return error(cause instanceof Error ? cause.message : "account_unavailable");
    }
  }

  private async requestCode(action: Action): Promise<string> {
    const provider = action.provider;
    const target = action.target;
    if (!validString(provider, 16) || !["email", "phone"].includes(provider)
      || !validString(target, 320) || target.trim() !== target) return error("account_invalid");
    return this.requestPublic("POST", "/v1/auth/challenges", { provider, target, purpose: "login" });
  }

  private async login(action: Action): Promise<string> {
    if (!validString(action.challenge_id, 256) || !validString(action.credential, 6)
      || !/^\d{6}$/.test(action.credential)) return error("account_invalid");
    const response = await this.transport.request("POST", "/v1/auth/login", undefined, {
      challenge_id: action.challenge_id, credential: action.credential
    });
    if (response.status < 200 || response.status >= 300) return error(mapStatus(response.status));
    const value = parseJson(response.body);
    if (value === null || !validToken(value.access_token) || !validToken(value.refresh_token)
      || value.token_type !== "Bearer" || typeof value.expires_in !== "number" || !validateUser(value.user)) {
      return error("account_unavailable");
    }
    const session: Session = {
      access_token: value.access_token,
      refresh_token: value.refresh_token,
      token_type: "Bearer",
      expires_at: Date.now() + Math.max(1, value.expires_in) * 1000,
      user: value.user
    };
    this.session = session;
    this.store.save(JSON.stringify(session));
    this.generation++;
    return success({ user: session.user });
  }

  private async rename(action: Action): Promise<string> {
    if (!validString(action.display_name, 256) || action.display_name.trim() !== action.display_name) {
      return error("account_invalid");
    }
    return this.authenticated("PATCH", "/v1/users/me", { display_name: action.display_name });
  }

  private async logout(action: Action): Promise<string> {
    if (typeof action.all !== "boolean") return error("account_invalid");
    const result = await this.authenticated("POST", "/v1/auth/logout", { all: action.all });
    if (JSON.parse(result).ok) this.clearExpired();
    return result;
  }

  private async deleteAccount(): Promise<string> {
    const result = await this.authenticated("DELETE", "/v1/users/me");
    if (JSON.parse(result).ok) this.clearExpired();
    return result;
  }

  private async clipboard(action: Action): Promise<string> {
    const operation = action.clipboard_operation;
    if (operation === "list") {
      if (!validString(action.search, MAX_SEARCH, true)) return error("account_invalid");
      return this.authenticated("GET", `/v1/users/me/clipboard?q=${encodeURIComponent(action.search)}`);
    }
    if (operation === "add") {
      if (!validString(action.text, MAX_CLIPBOARD_TEXT) || action.text.trim().length === 0) return error("account_invalid");
      return this.authenticated("POST", "/v1/users/me/clipboard", { text: action.text });
    }
    if (operation === "delete") {
      if (!validString(action.id, 256)) return error("account_invalid");
      return this.authenticated("DELETE", `/v1/users/me/clipboard/${encodeURIComponent(action.id)}`);
    }
    if (operation === "set_enabled") {
      if (typeof action.enabled !== "boolean") return error("account_invalid");
      const result = await this.authenticated("PUT", "/v1/users/me/clipboard/settings", { enabled: action.enabled });
      return JSON.parse(result).ok ? success({ enabled: action.enabled }) : result;
    }
    return error("account_invalid");
  }

  private async requestPublic(method: string, path: string, body?: Record<string, unknown>): Promise<string> {
    const response = await this.transport.request(method, path, undefined, body);
    return this.response(response);
  }

  private async authenticated(method: string, path: string, body?: Record<string, unknown>): Promise<string> {
    const session = this.session;
    if (session === null) return error("account_unauthorized");
    const generation = this.generation;
    if (session.expires_at <= Date.now()) return error("account_unauthorized");
    const response = await this.transport.request(method, path, session.access_token, body);
    if (generation !== this.generation) return error("account_cancelled");
    if (response.status === 401 && generation === this.generation) {
      this.clearExpired();
      return error("account_unauthorized");
    }
    return this.response(response);
  }

  private response(response: AccountTransportResponse): string {
    if (response.status < 200 || response.status >= 300) return error(mapStatus(response.status));
    const value = parseJson(response.body);
    return value === null && response.body.length > 0 ? error("account_unavailable") : success(value ?? {});
  }

  private clearExpired(): void {
    this.session = null;
    this.generation++;
    this.store.clear();
  }
}
