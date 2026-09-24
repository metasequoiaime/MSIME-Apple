use std::path::PathBuf;

/// Put the locked Engine tree in place before anything is compiled against it.
///
/// It used to arrive as a git submodule, which meant a clone without `--recursive` produced an empty
/// directory and a hundred lines of compiler errors that named neither the cause nor the cure. The
/// lock file is fetched and verified here instead, so the failure — if there is one — is a sentence
/// about the Engine rather than a missing header.
fn prepare_engine() {
    let script = PathBuf::from("../../scripts/fetch_engine.py");
    println!("cargo:rerun-if-changed=../../engine-lock.json");
    println!("cargo:rerun-if-changed={}", script.display());
    // And every overlay the lock names. An overlay rewrites Engine source, so editing one changes
    // what gets compiled - but the lock file it is listed in does not change, so without this the
    // build script does not run, the tree is not re-prepared, and the binary keeps the old rule
    // while the source on disk shows the new one. That is how a test that should fail passes.
    //
    // Read by scanning rather than by parsing: a build script that parsed this would need a JSON
    // dependency of its own, and what is wanted is one array of file names out of a file this
    // repository writes.
    if let Ok(lock) = std::fs::read_to_string("../../engine-lock.json") {
        for field in ["overlay_scripts", "overlay_assets"] {
            if let Some(rest) = lock
                .split_once(&format!("\"{field}\""))
                .map(|(_, rest)| rest)
            {
                if let Some(list) = rest
                    .split_once('[')
                    .and_then(|(_, rest)| rest.split_once(']'))
                {
                    for name in list.0.split('"').filter(|piece| piece.contains('/')) {
                        println!("cargo:rerun-if-changed=../../{name}");
                    }
                }
            }
        }
    }
    // An offline build of a tree that is already prepared has nothing to do here, and no network to
    // do it with. Verification has already happened for that tree; it is the lock's own record.
    // Tracked before the early return, so clearing it re-runs the fetch and verification.
    println!("cargo:rerun-if-env-changed=MSIME_SKIP_ENGINE_FETCH");
    if std::env::var_os("MSIME_SKIP_ENGINE_FETCH").is_some() {
        return;
    }
    let status = std::process::Command::new("python3")
        .arg(&script)
        .status()
        .unwrap_or_else(|error| panic!("could not run {}: {error}", script.display()));
    assert!(status.success(), "{} failed", script.display());
}

fn main() {
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=native");
    prepare_engine();
    println!("cargo:rerun-if-env-changed=CMAKE_PREFIX_PATH");
    let mut config = cmake::Config::new("native");
    let mut android_include = None;
    let mut ohos_include = None;
    let mut windows_include = None;
    println!("cargo:rerun-if-env-changed=MSIME_BOOST_DIR");
    if let Some(boost_dir) = std::env::var_os("MSIME_BOOST_DIR") {
        let boost_dir = PathBuf::from(boost_dir);
        assert!(
            boost_dir.is_absolute(),
            "MSIME_BOOST_DIR must be an absolute path"
        );
        config.define("Boost_DIR", &boost_dir);
    }
    println!("cargo:rerun-if-env-changed=MSIME_BOOST_HEADERS_DIR");
    if let Some(boost_headers_dir) = std::env::var_os("MSIME_BOOST_HEADERS_DIR") {
        let boost_headers_dir = PathBuf::from(boost_headers_dir);
        assert!(
            boost_headers_dir.is_absolute(),
            "MSIME_BOOST_HEADERS_DIR must be an absolute path"
        );
        config.define("boost_headers_DIR", &boost_headers_dir);
    }
    // fmt and spdlog ship config packages the same way Boost does, and a cross build has to be told
    // where they are for the same reason: the toolchain's find root hides the host-side ones.
    for (variable, define) in [
        ("MSIME_FMT_DIR", "fmt_DIR"),
        ("MSIME_SPDLOG_DIR", "spdlog_DIR"),
    ] {
        println!("cargo:rerun-if-env-changed={variable}");
        if let Some(directory) = std::env::var_os(variable) {
            let directory = PathBuf::from(directory);
            assert!(
                directory.is_absolute(),
                "{variable} must be an absolute path"
            );
            config.define(define, &directory);
        }
    }
    let android = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android");
    let ios = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios");
    // OpenHarmony reports target_os = "linux", so only target_env separates it from an ordinary
    // Linux desktop build.
    let ohos = std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("ohos");
    if ios || ohos {
        // Both the iOS and the OpenHarmony CMake platform default package lookup to their SDK root, which hides the host-side config packages used for header-only dependencies.
        config.define("CMAKE_FIND_ROOT_PATH_MODE_PACKAGE", "BOTH");
    }
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
        windows_include = Some(prefix.join("include"));
    }
    let windows_msvc = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows")
        && std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc");
    // Build-Client.ps1 hands MSVC builds their dependencies through CMAKE_PREFIX_PATH. CMake reads it from the environment, but the bridge below is compiled by cc and includes the Engine headers that include sqlite3.h, so it needs the prefix's headers too.
    let msvc_includes: Vec<PathBuf> = if windows_msvc {
        std::env::var_os("CMAKE_PREFIX_PATH")
            .map(|paths| {
                std::env::split_paths(&paths)
                    .map(|prefix| prefix.join("include"))
                    .filter(|include| include.is_dir())
                    .collect()
            })
            .unwrap_or_default()
    } else {
        Vec::new()
    };
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
            .define("MSIME_ENGINE_BRIDGE_HANDWRITING", "OFF")
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
    for name in ["MSIME_OHOS_NDK", "MSIME_OHOS_DEPS"] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    if ohos {
        let ndk =
            PathBuf::from(std::env::var_os("MSIME_OHOS_NDK").expect("MSIME_OHOS_NDK is required"));
        let prefix = PathBuf::from(
            std::env::var_os("MSIME_OHOS_DEPS").expect("MSIME_OHOS_DEPS is required"),
        );
        assert!(
            ndk.is_absolute() && prefix.is_absolute(),
            "OpenHarmony build paths must be absolute"
        );
        ohos_include = Some(prefix.join("include"));
        let arch = match std::env::var("TARGET").unwrap().as_str() {
            "aarch64-unknown-linux-ohos" => "arm64-v8a",
            "armv7-unknown-linux-ohos" => "armeabi-v7a",
            "x86_64-unknown-linux-ohos" => "x86_64",
            target => panic!("OpenHarmony arch not configured: {target}"),
        };
        config
            // Native dependency roots can move; don't retain stale FindPackage paths.
            .configure_arg("--fresh")
            // Handwriting is deliberately absent on HarmonyOS. The engine expects the host to inject
            // a platform recognizer, as Android does, and HarmonyOS has no equivalent to inject; the
            // vendored zinnia implementation would ship unreachable either way.
            .define("MSIME_ENGINE_BRIDGE_HANDWRITING", "OFF")
            .define(
                "CMAKE_TOOLCHAIN_FILE",
                ndk.join("build/cmake/ohos.toolchain.cmake"),
            )
            .define("OHOS_ARCH", arch)
            .define("CMAKE_PREFIX_PATH", &prefix)
            .define("CMAKE_FIND_ROOT_PATH", &prefix);
    }
    // Rust links the release CRT on MSVC even for debug profiles, while CMake
    // selects the debug CRT for a Debug build. Mixing them makes the Engine
    // objects unlinkable into any Rust test binary ("RuntimeLibrary mismatch:
    // MDd_DynamicDebug vs MD_DynamicRelease"), which is why host-api tests could
    // not run on Windows. Exceptions must also stay enabled or Boost compiles
    // against BOOST_NO_EXCEPTIONS and leaves boost::throw_exception undefined.
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        config.define("CMAKE_MSVC_RUNTIME_LIBRARY", "MultiThreadedDLL");
        config.cxxflag("/EHsc");
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
        .include("../../vendor/MSIME-Engine/voice/include")
        .include("../../vendor/MSIME-Engine/voice/third_party/miniaudio")
        .include("native")
        .include(&engine)
        .include(engine.join("include"));
    if ios || ohos {
        // The iOS app records through AVAudioEngine in Swift. Keyboard
        // extensions cannot use this desktop capture path, and compiling the
        // Engine's miniaudio source as C++ also pulls Objective-C declarations
        // into a non-Objective-C translation unit.
        //
        // OpenHarmony is the same shape from the other side: miniaudio has no backend for it, and an
        // InputMethodExtensionAbility records through the platform's own audio kit.
        bridge.define("MSIME_ENGINE_BRIDGE_AUDIO_CAPTURE", Some("0"));
    } else {
        // capture_audio() in bridge.cpp calls the Engine's AudioCapture, which
        // lives in a voice target the bridge does not build: enabling that
        // target would drag CURL and nlohmann_json into every platform's bridge
        // just to reach one file. Compile the one file instead. It needs only
        // miniaudio, which is header-only, and ole32, which is linked below.
        let capture = engine.join("voice/src/audio_capture.cpp");
        let miniaudio = engine.join("voice/third_party/miniaudio/miniaudio.h");
        if capture.is_file() && miniaudio.is_file() {
            bridge
                .file(&capture)
                .include(engine.join("voice/include/msime/voice"))
                .include(engine.join("voice/third_party/miniaudio"));
        } else {
            // A prepared Engine archive without miniaudio cannot capture audio.
            // Say so at build time rather than failing to link a symbol whose
            // name explains nothing.
            panic!(
                "voice/third_party/miniaudio is required for audio capture; \
                 run scripts/fetch_engine.py to prepare the locked sources"
            );
        }
    }
    if let Some(include) = android_include {
        bridge.include(include);
    }
    if let Some(include) = ohos_include {
        bridge.include(include);
    }
    if let Some(include) = windows_include {
        bridge.include(include);
    }
    for include in msvc_includes {
        bridge.include(include);
    }
    bridge.std("c++17").compile("msime-engine-cxx");
    println!(
        "cargo:rustc-link-search=native={}/lib",
        destination.display()
    );
    println!("cargo:rustc-link-lib=static=MetasequoiaImeEngine");
    if !android && !ohos {
        println!("cargo:rustc-link-lib=static=MetasequoiaHandwriting");
    }
    let sqlite = std::fs::read_to_string(destination.join("build/sqlite-path.txt"))
        .expect("CMake SQLite path");
    let sqlite = PathBuf::from(sqlite.trim());
    println!(
        "cargo:rustc-link-search=native={}",
        sqlite.parent().unwrap().display()
    );
    println!(
        "cargo:rustc-link-lib={}sqlite3",
        if android || ohos || windows_gnu {
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
