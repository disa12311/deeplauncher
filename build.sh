#!/usr/bin/env bash
# build.sh — build Rust -> WASM (wasm-pack preferred, fallback to wasm-bindgen)
# Usage:
#   ./build.sh            # build release into ./wasm/pkg
#   ./build.sh --debug    # build debug (non-release)
#   ./build.sh --out dir  # set output dir
#   ./build.sh --crate name  # optional crate name for wasm-bindgen fallback
#
set -euo pipefail

# defaults
OUT_DIR="./wasm/pkg"
BUILD_MODE="release"   # or "debug"
CRATE_NAME=""           # optional, used for wasm-bindgen fallback if needed

print_usage() {
  cat <<EOF
Usage: $0 [--debug] [--out <dir>] [--crate <name>]
  --debug        Build non-release (faster, not optimized)
  --out <dir>    Output directory (default: ./wasm/pkg)
  --crate <name> Crate name for wasm-bindgen fallback (optional)
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) BUILD_MODE="debug"; shift ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --crate) CRATE_NAME="$2"; shift 2 ;;
    -h|--help) print_usage ;;
    *) echo "Unknown arg: $1"; print_usage ;;
  esac
done

echo "=== Build script for game_engine WASM ==="
echo "Build mode : $BUILD_MODE"
echo "Output dir : $OUT_DIR"
if [[ -n "$CRATE_NAME" ]]; then
  echo "Crate name : $CRATE_NAME"
fi
echo

# ensure target exists
if ! rustup target list --installed | grep -q "^wasm32-unknown-unknown\$"; then
  echo "[*] Installing wasm32-unknown-unknown target..."
  rustup target add wasm32-unknown-unknown
fi

# create output dir
mkdir -p "$OUT_DIR"

# prefer wasm-pack
if command -v wasm-pack >/dev/null 2>&1; then
  echo "[*] Using wasm-pack to build..."
  # choose release or dev
  if [[ "$BUILD_MODE" == "release" ]]; then
    wasm-pack build --target web --out-dir "$OUT_DIR" --release
  else
    wasm-pack build --target web --out-dir "$OUT_DIR"
  fi
  echo "[+] wasm-pack build finished. Output in: $OUT_DIR"
  exit 0
fi

# fallback: use cargo + wasm-bindgen-cli (needs wasm-bindgen-cli installed)
if command -v wasm-bindgen >/dev/null 2>&1; then
  echo "[*] wasm-pack not found — using cargo + wasm-bindgen (fallback)."

  # build with cargo
  if [[ "$BUILD_MODE" == "release" ]]; then
    cargo build --target wasm32-unknown-unknown --release
    BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/release"
  else
    cargo build --target wasm32-unknown-unknown
    BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/debug"
  fi

  # try to guess wasm file name
  if [[ -n "$CRATE_NAME" ]]; then
    WASM_FILE="$BUILD_ARTIFACT_PATH/$CRATE_NAME.wasm"
  else
    # attempt to auto-detect a single .wasm in build dir
    WASM_COUNT=$(ls "$BUILD_ARTIFACT_PATH"/*.wasm 2>/dev/null | wc -l || true)
    if [[ "$WASM_COUNT" -eq 1 ]]; then
      WASM_FILE=$(ls "$BUILD_ARTIFACT_PATH"/*.wasm)
    else
      echo "[-] Can't auto-detect wasm file. Provide --crate <name> to build.sh"
      echo "    Candidate files in $BUILD_ARTIFACT_PATH:"
      ls -la "$BUILD_ARTIFACT_PATH" | sed -n '1,200p'
      exit 1
    fi
  fi

  if [[ ! -f "$WASM_FILE" ]]; then
    echo "[-] wasm file not found at: $WASM_FILE"
    exit 1
  fi

  echo "[*] Found wasm: $WASM_FILE"
  echo "[*] Running wasm-bindgen to generate JS glue (target web) ..."
  # output should be $OUT_DIR
  mkdir -p "$OUT_DIR"
  wasm-bindgen "$WASM_FILE" --out-dir "$OUT_DIR" --target web

  echo "[+] wasm-bindgen finished. Output in: $OUT_DIR"
  exit 0
fi

# If we reach here, neither wasm-pack nor wasm-bindgen available
cat <<EOF
[-] Neither 'wasm-pack' nor 'wasm-bindgen' found in PATH.
    Install wasm-pack (recommended):
      https://rustwasm.github.io/wasm-pack/installer/
    or install wasm-bindgen-cli:
      cargo install wasm-bindgen-cli
EOF
exit 2
