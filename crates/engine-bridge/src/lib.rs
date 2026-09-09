//! Owning CXX bridge to the pinned C++ Session. No Tauri or native UI dependency.
//! Sessions remain thread-confined; no unsafe Send/Sync implementation is provided.

#[cxx::bridge(namespace = "msime")]
mod ffi {
    pub struct EngineOptions {
        pub resources: String,
        pub user_data: String,
        pub cache: String,
        pub dictionaries: String,
        pub scheme: u8,
        pub learning: bool,
        pub chinese_punctuation: bool,
    }
    #[derive(Debug)]
    pub struct EngineSnapshot {
        pub preedit: String,
        pub editing_text: String,
        pub caret_position: usize,
        pub candidates: Vec<String>,
    }
    #[derive(Debug)]
    pub struct EngineResult {
        pub handled: bool,
        pub has_commit: bool,
        pub commit: String,
        pub diagnostic: String,
    }
    unsafe extern "C++" {
        include!("bridge.h");
        type EngineSession;
        fn create_session(options: &EngineOptions) -> Result<UniquePtr<EngineSession>>;
        fn prepare_options(
            resources: &str,
            user_data: &str,
            cache: &str,
            content_id: &str,
        ) -> Result<EngineOptions>;
        fn snapshot(self: &EngineSession) -> Result<EngineSnapshot>;
        fn character(self: Pin<&mut EngineSession>, value: u8, shift: bool)
            -> Result<EngineResult>;
        fn command(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
        fn select(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn finish(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn punctuation(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
    }
}

pub use ffi::{EngineOptions, EngineResult, EngineSnapshot};

/// Delegate working-dictionary preparation and learning replay to the Engine.
/// Caller verifies resources first and quiesces all users of these data paths.
pub fn prepare_options(
    resources: &str,
    user_data: &str,
    cache: &str,
    content_id: &str,
) -> Result<EngineOptions, cxx::Exception> {
    ffi::prepare_options(resources, user_data, cache, content_id)
}

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum Command {
    Backspace,
    CommitCandidate,
    CommitRaw,
    Cancel,
    MoveLeft,
    MoveRight,
    MoveHome,
    MoveEnd,
    DeleteForward,
}

pub struct Session {
    inner: cxx::UniquePtr<ffi::EngineSession>,
    _thread_confined: std::marker::PhantomData<std::rc::Rc<()>>,
}

impl Session {
    pub fn new(options: &EngineOptions) -> Result<Self, cxx::Exception> {
        Ok(Self {
            inner: ffi::create_session(options)?,
            _thread_confined: std::marker::PhantomData,
        })
    }
    pub fn snapshot(&self) -> Result<EngineSnapshot, cxx::Exception> {
        self.inner.snapshot()
    }
    pub fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().character(value, shift)
    }
    pub fn command(&mut self, command: Command) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().command(command as u8)
    }
    pub fn select(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().select(index)
    }
    pub fn finish(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().finish(index)
    }
    pub fn punctuation(&mut self, value: u8) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().punctuation(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn options(root: &std::path::Path) -> EngineOptions {
        let path = |name| {
            let path = root.join(name);
            std::fs::create_dir_all(&path).unwrap();
            path.to_str().unwrap().to_owned()
        };
        EngineOptions {
            resources: path("resources"),
            user_data: path("user"),
            cache: path("cache"),
            dictionaries: path("dictionaries"),
            scheme: 0,
            learning: false,
            chinese_punctuation: true,
        }
    }
    #[test]
    fn invalid_options_return_errors_instead_of_unwinding_into_rust() {
        let dir = tempfile::tempdir().unwrap();
        let mut value = options(dir.path());
        value.scheme = 255;
        assert!(Session::new(&value).is_err());
        value.scheme = 0;
        value.resources = "relative".into();
        assert!(Session::new(&value).is_err());
    }
    #[test]
    fn real_engine_handles_unicode_mode_without_a_dictionary_bundle() {
        let dir = tempfile::tempdir().unwrap();
        let mut session = Session::new(&options(dir.path())).unwrap();
        assert!(session.character(b'U', true).unwrap().handled);
        for character in b"4e2d" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        let snapshot = session.snapshot().unwrap();
        assert!(snapshot
            .candidates
            .iter()
            .any(|candidate| candidate == "中"));
        let result = session.select(0).unwrap();
        assert!(result.has_commit);
        assert_eq!(result.commit, "中");
        assert!(session.snapshot().unwrap().preedit.is_empty());
    }
}
