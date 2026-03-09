#!/bin/bash
# Build the Swift speech bridge as a static library
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$SCRIPT_DIR/lib}"

mkdir -p "$OUT_DIR"

swiftc \
    -emit-library -static \
    -module-name DictSpeechBridge \
    -o "$OUT_DIR/libdict_speech_bridge.a" \
    "$SCRIPT_DIR/DictSpeechBridge.swift" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target "$(uname -m)-apple-macosx14.0" \
    -O

echo "Built: $OUT_DIR/libdict_speech_bridge.a"
