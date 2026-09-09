use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=native");
    println!("cargo:rerun-if-changed=../../vendor/MSIME-Engine");
    println!("cargo:rerun-if-env-changed=CMAKE_PREFIX_PATH");
    let mut config = cmake::Config::new("native");
    let android = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android");
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
    cxx_build::bridge("src/lib.rs")
        .file("native/bridge.cpp")
        .include("native")
        .include(&engine)
        .include(engine.join("include"))
        .std("c++17")
        .compile("msime-engine-cxx");
    println!(
        "cargo:rustc-link-search=native={}/lib",
        destination.display()
    );
    println!("cargo:rustc-link-lib=static=MetasequoiaImeEngine");
    let sqlite = std::fs::read_to_string(destination.join("build/sqlite-path.txt"))
        .expect("CMake SQLite path");
    let sqlite = PathBuf::from(sqlite.trim());
    println!(
        "cargo:rustc-link-search=native={}",
        sqlite.parent().unwrap().display()
    );
    println!(
        "cargo:rustc-link-lib={}sqlite3",
        if android { "static=" } else { "" }
    );
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rustc-link-lib=ole32");
        println!("cargo:rustc-link-lib=shell32");
    }
}
