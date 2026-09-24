//! The C ABI other IME hosts link against.
//!
//! Every function here is a thin shim: it validates the pointers and lengths it
//! was handed, calls into the crate's own logic, and hands back an owned JSON
//! string the caller frees with `msime_client_string_free`. Keeping them in one
//! file separates "what the library does" from "how a foreign caller reaches
//! it", which is the boundary the header in include/ describes.
//!
//! `#[no_mangle]` exports the symbol regardless of which module it sits in, so
//! moving these out of the crate root does not change the ABI.

use crate::*;

// Shared by the session and host modules below, so it lives in the parent.
/// The file name the reranking model is published under inside the resource set.
pub(crate) const SENTENCE_MODEL_FILE: &str = "sentence-model.safetensors";

/// The larger model, published beside the first, run only once typing settles.
///
/// A separate file rather than a preset flag inside one, because the two are wanted at once: the
/// small one on every keystroke and this one when the user pauses. Installations that ship only
/// the small one keep today's behaviour exactly.
pub(crate) const SETTLED_MODEL_FILE: &str = "sentence-model-desktop.safetensors";

/// The candidate reranking model, loaded once per path and shared by every session using it.
///
/// The path is separate from the dictionaries because the two artifacts change on entirely
/// different schedules. A resource set is identified by a hash over all of its artifacts, so adding
/// a seven megabyte model to the dictionary lock would make every model revision re-download the
/// hundred and eighty five megabytes of dictionaries alongside it. Hosts that have not adopted a
/// separate model artifact still find one placed next to the dictionaries.
///
/// Absence is the normal case for an installation that ships no model, so it is not an error and
/// leaves behaviour exactly as it was.
/// The settled model for a resource directory, or `None` when the set does not ship one.
///
/// Shares `sentence_model`'s cache by going through it, so two sessions on the same resources load
/// the twenty five megabytes once between them rather than once each.
pub(crate) fn sentence_model_settled(
    dictionaries: &str,
    configured: Option<&str>,
) -> Option<Arc<SentenceModel>> {
    let path = match configured {
        Some(path) => PathBuf::from(path),
        None => Path::new(dictionaries).join(SETTLED_MODEL_FILE),
    };
    // Absence is the normal case — most installations ship one model — so it is checked rather
    // than reported. A host that named a path and got nothing gets the same silence: a second
    // model is not worth failing a session over.
    if !path.is_file() {
        return None;
    }
    sentence_model(dictionaries, path.to_str())
}

pub(crate) fn sentence_model(
    dictionaries: &str,
    configured: Option<&str>,
) -> Option<Arc<SentenceModel>> {
    static MODELS: OnceLock<Mutex<HashMap<PathBuf, Option<Arc<SentenceModel>>>>> = OnceLock::new();
    let path = match configured {
        Some(path) => PathBuf::from(path),
        None => Path::new(dictionaries).join(SENTENCE_MODEL_FILE),
    };
    let cache = MODELS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut cache = cache.lock().ok()?;
    // Keyed by path: two sessions may legitimately be pointed at different models, and a cache that
    // remembered only the first would silently serve one of them the other's weights.
    if let Some(cached) = cache.get(&path) {
        return cached.clone();
    }
    let loaded = std::fs::read(&path)
        .ok()
        .and_then(|bytes| match SentenceModel::load(&bytes) {
            Ok(model) => Some(Arc::new(model)),
            Err(error) => {
                // A corrupt or mismatched model is worth saying out loud: the input method keeps
                // working without it, so nothing else would ever reveal that it is not running.
                eprintln!("msime: ignoring {}: {error}", path.display());
                None
            }
        });
    cache.insert(path, loaded.clone());
    loaded
}

pub mod candidates;
pub mod host;
pub mod input;
pub mod lifecycle;
pub mod mcp;
pub mod providers;
pub mod session;
pub mod translation;
pub mod voice;

// Every export has always been reachable at the crate root; the domain split
// below is for readers, not for callers, so each module is flattened back out.
pub use candidates::*;
pub use host::*;
pub use input::*;
pub use lifecycle::*;
pub use mcp::*;
pub use providers::*;
pub use session::*;
pub use translation::*;
pub use voice::*;
