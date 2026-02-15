#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "Running script tests..."

# --- build.sh syntax check ---
echo ""
echo "build.sh"
if bash -n "$PROJECT_DIR/scripts/build.sh" 2>/dev/null; then
    pass "syntax check passes"
else
    fail "syntax check failed"
fi

# --- Info.plist version is parseable ---
echo ""
echo "Info.plist"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || echo "")
if [[ -n "$VERSION" && "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "version is parseable: $VERSION"
else
    fail "version not parseable: '$VERSION'"
fi

# --- generate-dmg-background.swift produces a valid PNG ---
echo ""
echo "generate-dmg-background.swift"
BACKGROUND="$PROJECT_DIR/Resources/dmg-background.png"
# Generate if not present
if [[ ! -f "$BACKGROUND" ]]; then
    if swift "$PROJECT_DIR/scripts/generate-dmg-background.swift" 2>/dev/null; then
        pass "script executes successfully"
    else
        fail "script execution failed"
    fi
else
    pass "background already exists (skipping generation)"
fi

if [[ -f "$BACKGROUND" ]]; then
    # Check it's a valid PNG (file magic)
    FILE_TYPE=$(file -b "$BACKGROUND")
    if echo "$FILE_TYPE" | grep -qi "png"; then
        pass "output is a valid PNG"
    else
        fail "output is not a PNG: $FILE_TYPE"
    fi

    # Check dimensions via sips
    DIMS=$(sips -g pixelWidth -g pixelHeight "$BACKGROUND" 2>/dev/null)
    WIDTH=$(echo "$DIMS" | grep pixelWidth | awk '{print $2}')
    HEIGHT=$(echo "$DIMS" | grep pixelHeight | awk '{print $2}')
    # Accept both 1x (800x450) and 2x Retina (1600x900)
    if [[ "$WIDTH" == "800" && "$HEIGHT" == "450" ]] || [[ "$WIDTH" == "1600" && "$HEIGHT" == "900" ]]; then
        pass "dimensions are ${WIDTH}x${HEIGHT}"
    else
        fail "dimensions are ${WIDTH}x${HEIGHT}, expected 800x450 or 1600x900"
    fi
else
    fail "background PNG not found"
    fail "cannot check dimensions"
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
