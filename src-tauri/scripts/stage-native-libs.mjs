// Stage the sherpa-onnx + ONNX Runtime native libraries that `sherpa-rs`'s
// `download-binaries` feature drops into the cargo target/<profile> directory
// into src-tauri/native-libs/, so Tauri's bundler picks them up (referenced from
// bundle.macOS.frameworks). Run as a `beforeBundleCommand` — after the Rust build
// (libs exist) and before bundling. Cross-platform: matches the right extension
// per OS and prefers the release build.
import { readdirSync, mkdirSync, copyFileSync, existsSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..'); // src-tauri/
const dest = join(root, 'native-libs');
mkdirSync(dest, { recursive: true });

const matchers =
  process.platform === 'darwin'
    ? [/^libonnxruntime.*\.dylib$/, /^libsherpa-onnx-c-api\.dylib$/]
    : process.platform === 'win32'
    ? [/^onnxruntime.*\.dll$/, /^sherpa-onnx-c-api\.dll$/]
    : [/^libonnxruntime\.so.*$/, /^libsherpa-onnx-c-api\.so.*$/];

const targetDir = process.env.CARGO_TARGET_DIR || join(root, 'target');

function* walk(dir, depth) {
  if (depth < 0 || !existsSync(dir)) return;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    let s;
    try { s = statSync(p); } catch { continue; }
    if (s.isDirectory()) yield* walk(p, depth - 1);
    else yield p;
  }
}

// For each matching lib, prefer a copy whose path is under a `release` dir.
const picks = new Map();
for (const f of walk(targetDir, 4)) {
  const base = f.split(/[\\/]/).pop();
  if (!matchers.some((re) => re.test(base))) continue;
  const prev = picks.get(base);
  const isRelease = f.includes(`${'release'}`);
  if (!prev || (isRelease && !prev.includes('release'))) picks.set(base, f);
}

if (picks.size === 0) {
  console.error(`[stage-native-libs] no native libs found under ${targetDir}`);
  process.exit(1);
}
for (const [base, src] of picks) {
  copyFileSync(src, join(dest, base));
  console.log(`[stage-native-libs] staged ${base}`);
}
