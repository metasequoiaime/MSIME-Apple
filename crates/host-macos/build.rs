fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    println!("cargo:rerun-if-changed=native/keyboard.mm");
    println!("cargo:rerun-if-changed=native/keyboard.h");
    cc::Build::new()
        .cpp(true)
        .file("native/keyboard.mm")
        .flag("-fobjc-arc")
        .std("c++17")
        .compile("msime_macos_keyboard");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=CoreGraphics");
}
