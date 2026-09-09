use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=native");
    println!("cargo:rerun-if-changed=../../vendor/MSIME-Engine");
    println!("cargo:rerun-if-env-changed=CMAKE_PREFIX_PATH");
    let mut config = cmake::Config::new("native");
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
    println!("cargo:rustc-link-lib=sqlite3");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rustc-link-lib=ole32");
        println!("cargo:rustc-link-lib=shell32");
    }
}
