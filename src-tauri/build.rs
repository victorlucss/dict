fn main() {
    // sherpa-rs's `download-binaries` ships sherpa-onnx + ONNX Runtime as dynamic
    // libraries that the binary references via @rpath. Add runtime search paths so
    // they resolve both in dev (dylibs sit next to the binary in target/<profile>)
    // and in the bundled app (Tauri copies them into Contents/Frameworks on macOS;
    // alongside the executable on Linux/Windows).
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path");
        println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path/../Frameworks");
        println!("cargo:rustc-link-arg=-Wl,-rpath,@loader_path");
    }
    #[cfg(target_os = "linux")]
    {
        // $ORIGIN = the directory of the binary at runtime.
        println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN");
        println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN/../lib");
    }
    // Windows resolves DLLs from the executable's directory automatically; the
    // bundling step places them next to dict.exe, so no link arg is needed.

    tauri_build::build();
}
