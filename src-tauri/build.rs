fn main() {
    tauri_build::build();

    #[cfg(target_os = "macos")]
    {
        use std::process::Command;

        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let swift_dir = format!("{}/swift-bridge", manifest_dir);
        let out_dir = std::env::var("OUT_DIR").unwrap();

        // Build the Swift static library
        let status = Command::new("swiftc")
            .args([
                "-emit-library",
                "-static",
                "-module-name",
                "DictSpeechBridge",
                "-o",
                &format!("{}/libdict_speech_bridge.a", out_dir),
                &format!("{}/DictSpeechBridge.swift", swift_dir),
                "-sdk",
            ])
            .arg(
                String::from_utf8(
                    Command::new("xcrun")
                        .args(["--sdk", "macosx", "--show-sdk-path"])
                        .output()
                        .expect("xcrun failed")
                        .stdout,
                )
                .unwrap()
                .trim()
                .to_string(),
            )
            .args([
                "-target",
                &format!(
                    "{}-apple-macosx14.0",
                    std::env::consts::ARCH
                ),
                "-O",
            ])
            .status()
            .expect("Failed to run swiftc");

        assert!(status.success(), "Swift compilation failed");

        // Tell cargo to link the static library
        println!("cargo:rustc-link-search=native={}", out_dir);
        println!("cargo:rustc-link-lib=static=dict_speech_bridge");

        // Link required Swift runtime and macOS frameworks
        println!("cargo:rustc-link-lib=dylib=swiftCore");
        println!("cargo:rustc-link-lib=dylib=swiftFoundation");
        println!("cargo:rustc-link-lib=framework=Speech");
        println!("cargo:rustc-link-lib=framework=AVFoundation");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=AppKit");
        println!("cargo:rustc-link-lib=framework=Carbon");

        // Re-run if Swift source changes
        println!("cargo:rerun-if-changed=swift-bridge/DictSpeechBridge.swift");
    }
}
