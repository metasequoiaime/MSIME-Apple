//! Host integration shared by iOS and Android.

pub(crate) mod mobile_community;

/// The account session storage of the running mobile target. Shared commands name it instead of either platform's type, so one body compiles for both.
#[cfg(target_os = "android")]
pub(crate) type MobileStorage = super::android::android_account::AndroidAccountStorage<tauri::Wry>;
#[cfg(target_os = "ios")]
pub(crate) type MobileStorage = super::ios::ios_account::IosAccountStorage<tauri::Wry>;
