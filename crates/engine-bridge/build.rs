use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=native");
    println!("cargo:rerun-if-changed=../../vendor/MSIME-Engine");
    println!("cargo:rerun-if-env-changed=CMAKE_PREFIX_PATH");
    let mut config = cmake::Config::new("native");
    let mut android_include = None;
    let android = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android");
    let windows_gnu = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows")
        && std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("gnu");
    println!("cargo:rerun-if-env-changed=MSIME_WINDOWS_DEPS");
    if windows_gnu {
        let prefix = PathBuf::from(
            std::env::var_os("MSIME_WINDOWS_DEPS")
                .expect("MSIME_WINDOWS_DEPS is required for Windows GNU"),
        );
        assert!(
            prefix.is_absolute(),
            "Windows dependency path must be absolute"
        );
        config
            .configure_arg("--fresh")
            .define("CMAKE_PREFIX_PATH", &prefix)
            .define("CMAKE_FIND_ROOT_PATH", &prefix)
            .define("CMAKE_FIND_ROOT_PATH_MODE_PROGRAM", "NEVER")
            .define("CMAKE_FIND_ROOT_PATH_MODE_LIBRARY", "ONLY")
            .define("CMAKE_FIND_ROOT_PATH_MODE_INCLUDE", "ONLY")
            .define("CMAKE_FIND_ROOT_PATH_MODE_PACKAGE", "ONLY");
    }
    for name in ["MSIME_ANDROID_NDK", "MSIME_ANDROID_DEPS"] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    if android {
        let ndk = PathBuf::from(
            std::env::var_os("MSIME_ANDROID_NDK").expect("MSIME_ANDROID_NDK is required"),
        );
        let prefix = PathBuf::from(
            std::env::var_os("MSIME_ANDROID_DEPS").expect("MSIME_ANDROID_DEPS is required"),
        );
        assert!(
            ndk.is_absolute() && prefix.is_absolute(),
            "Android build paths must be absolute"
        );
        android_include = Some(prefix.join("include"));
        let abi = match std::env::var("TARGET").unwrap().as_str() {
            "aarch64-linux-android" => "arm64-v8a",
            "x86_64-linux-android" => "x86_64",
            target => panic!("Android ABI not configured: {target}"),
        };
        config
            // Native dependency roots can move; don't retain stale FindPackage paths.
            .configure_arg("--fresh")
            .define(
                "CMAKE_TOOLCHAIN_FILE",
                ndk.join("build/cmake/android.toolchain.cmake"),
            )
            .define("ANDROID_ABI", abi)
            .define("ANDROID_PLATFORM", "android-28")
            .define("ANDROID_STL", "c++_shared")
            .define("CMAKE_PREFIX_PATH", &prefix)
            .define("CMAKE_FIND_ROOT_PATH", &prefix);
    }
    if let Ok(triplet) = std::env::var("VCPKG_TARGET_TRIPLET") {
        config.define("VCPKG_TARGET_TRIPLET", triplet);
    }
    println!("cargo:rerun-if-env-changed=VCPKG_TARGET_TRIPLET");
    let destination = config.build();
    let engine = PathBuf::from("../../vendor/MSIME-Engine");
    let mut bridge = cxx_build::bridge("src/lib.rs");
    bridge
        .file("native/bridge.cpp")
        .include("native")
        .include(&engine)
        .include(engine.join("include"));
    if let Some(include) = android_include {
        bridge.include(include);
    }
    bridge.std("c++17").compile("msime-engine-cxx");
    println!(
        "cargo:rustc-link-search=native={}/lib",
        destination.display()
    );
    println!("cargo:rustc-link-lib=static=MetasequoiaImeEngine");
    println!("cargo:rustc-link-lib=static=MetasequoiaHandwriting");
    let sqlite = std::fs::read_to_string(destination.join("build/sqlite-path.txt"))
        .expect("CMake SQLite path");
    let sqlite = PathBuf::from(sqlite.trim());
    println!(
        "cargo:rustc-link-search=native={}",
        sqlite.parent().unwrap().display()
    );
    println!(
        "cargo:rustc-link-lib={}sqlite3",
        if android || windows_gnu {
            "static="
        } else {
            ""
        }
    );
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rustc-link-lib=ole32");
        println!("cargo:rustc-link-lib=shell32");
        println!("cargo:rustc-link-lib=uuid");
    }
}
