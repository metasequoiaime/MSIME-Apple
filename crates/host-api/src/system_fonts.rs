//! Installed family names only; never expose font files or paths to the webview.
pub fn supported() -> bool {
    cfg!(target_os = "macos")
}

#[cfg(not(target_os = "macos"))]
pub fn list() -> Result<Vec<String>, &'static str> {
    Err("unsupported")
}

#[cfg(target_os = "macos")]
pub fn list() -> Result<Vec<String>, &'static str> {
    macos::list()
}

#[cfg(target_os = "macos")]
mod macos {
    use std::collections::BTreeSet;
    use std::ffi::{c_char, c_void, CStr};

    const MAX_FAMILIES: usize = 16_384;
    const MAX_BYTES: usize = 128;
    type CFRef = *const c_void;

    #[link(name = "CoreText", kind = "framework")]
    unsafe extern "C" {
        fn CTFontManagerCopyAvailableFontFamilyNames() -> CFRef;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFArrayGetCount(array: CFRef) -> isize;
        fn CFArrayGetValueAtIndex(array: CFRef, index: isize) -> CFRef;
        fn CFStringGetCString(string: CFRef, buffer: *mut c_char, size: isize, encoding: u32)
            -> u8;
        fn CFRelease(value: CFRef);
    }

    struct OwnedArray(CFRef);
    impl Drop for OwnedArray {
        fn drop(&mut self) {
            // SAFETY: this guard exclusively owns the non-null Copy-rule array.
            unsafe { CFRelease(self.0) };
        }
    }

    fn insert(names: &mut BTreeSet<String>, name: &str) {
        if !name.is_empty() && name.len() <= MAX_BYTES {
            names.insert(name.to_owned());
        }
    }

    pub(super) fn list() -> Result<Vec<String>, &'static str> {
        // SAFETY: CoreText takes no arguments and returns an owned CFArray of CFStrings.
        let array = unsafe { CTFontManagerCopyAvailableFontFamilyNames() };
        if array.is_null() {
            return Err("font_catalog");
        }
        let array = OwnedArray(array);
        // SAFETY: the owned array remains alive throughout enumeration.
        let count = unsafe { CFArrayGetCount(array.0) };
        if count < 0 || count as usize > MAX_FAMILIES {
            return Err("font_catalog_limit");
        }
        let mut names = BTreeSet::new();
        for index in 0..count {
            // SAFETY: index is in bounds; the borrowed CFString is retained by array.
            let name = unsafe { CFArrayGetValueAtIndex(array.0, index) };
            if name.is_null() {
                continue;
            }
            let mut buffer = [0 as c_char; MAX_BYTES + 1];
            // SAFETY: buffer has the specified capacity; name is a live CFString.
            // kCFStringEncodingUTF8. Failed conversions (including long names) are skipped.
            let converted = unsafe {
                CFStringGetCString(name, buffer.as_mut_ptr(), buffer.len() as isize, 0x08000100)
            };
            if converted != 0 {
                // SAFETY: successful CFStringGetCString guarantees a terminating NUL.
                if let Ok(name) = unsafe { CStr::from_ptr(buffer.as_ptr()) }.to_str() {
                    insert(&mut names, name);
                }
            }
        }
        Ok(names.into_iter().collect())
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn bounds_unicode_and_deduplication() {
            let mut names = BTreeSet::new();
            insert(&mut names, "");
            insert(&mut names, &"a".repeat(129));
            insert(&mut names, &"字".repeat(43));
            assert!(names.is_empty());
            insert(&mut names, &"a".repeat(128));
            insert(&mut names, "示例字体");
            insert(&mut names, "示例字体");
            assert_eq!(names.len(), 2);
        }

        #[test]
        fn native_catalog_is_bounded_sorted_and_nonempty() {
            let names = list().expect("native catalog unavailable");
            // Do not print installed names, even on assertion failure.
            assert!(!names.is_empty());
            assert!(names.len() <= MAX_FAMILIES);
            assert!(names
                .iter()
                .all(|name| !name.is_empty() && name.len() <= MAX_BYTES));
            assert!(names.windows(2).all(|pair| pair[0] < pair[1]));
        }
    }
}
