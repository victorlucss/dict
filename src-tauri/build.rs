use std::path::{Path, PathBuf};

fn main() {
    // sherpa-rs (Parakeet, macOS-only) ships sherpa-onnx + ONNX Runtime as dynamic
    // libraries referenced via @rpath. Add a runtime search path so they resolve
    // both in dev (dylibs next to the binary in target/<profile>) and in the
    // bundled .app (Tauri copies them into Contents/Frameworks). Whisper compiles
    // into the binary, so non-macOS builds need none of this.
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path");
        println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path/../Frameworks");
        println!("cargo:rustc-link-arg=-Wl,-rpath,@loader_path");
        stage_macos_native_libs();
    }

    tauri_build::build();
}

/// Copy the sherpa-onnx + ONNX Runtime dylibs from the sherpa-rs download cache
/// into `src-tauri/native-libs/`, so Tauri's `bundle.macOS.frameworks` can bundle
/// them by a fixed, target-independent path. Sourcing from the cache (populated by
/// sherpa-rs-sys's build script, which runs before this one) works for both a
/// native build (target/release) and the universal build (target/universal-…),
/// where the dylibs otherwise live under different directories.
#[cfg(target_os = "macos")]
fn stage_macos_native_libs() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let dest = manifest.join("native-libs");
    let _ = std::fs::create_dir_all(&dest);

    let Some(home) = std::env::var_os("HOME") else {
        println!("cargo:warning=HOME unset; cannot stage sherpa native libs");
        return;
    };
    let cache = PathBuf::from(home).join("Library/Caches/sherpa-rs");

    // Library basename -> staged. The bundled binary needs exactly these two
    // (the c-api dylib itself depends on the versioned onnxruntime via @rpath).
    let wanted = ["libonnxruntime.1.17.1.dylib", "libsherpa-onnx-c-api.dylib"];
    let mut staged = 0usize;
    for name in wanted {
        if let Some(src) = find_in_dir(&cache, name, 8) {
            match std::fs::copy(&src, dest.join(name)) {
                Ok(_) => staged += 1,
                Err(e) => println!("cargo:warning=failed to stage {name}: {e}"),
            }
        } else {
            println!("cargo:warning=sherpa native lib {name} not found under {}", cache.display());
        }
    }
    println!("cargo:warning=staged {staged}/{} sherpa native libs into native-libs/", wanted.len());
}

/// Depth-limited recursive search for a file named `name` under `dir`.
#[cfg(target_os = "macos")]
fn find_in_dir(dir: &Path, name: &str, depth: u32) -> Option<PathBuf> {
    if depth == 0 {
        return None;
    }
    let entries = std::fs::read_dir(dir).ok()?;
    let mut subdirs = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            subdirs.push(path);
        } else if path.file_name().and_then(|n| n.to_str()) == Some(name) {
            return Some(path);
        }
    }
    for sub in subdirs {
        if let Some(found) = find_in_dir(&sub, name, depth - 1) {
            return Some(found);
        }
    }
    None
}
