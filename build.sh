#!/usr/bin/env bash
# build.sh — safe auto-detect wasm build (won't fail if no Cargo.toml)
# Usage: ./build.sh
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"

echo "=> build.sh (safe mode)"
echo "   OUT_DIR=${OUT_DIR}"
echo "   PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}"

# find Cargo.toml (exclude typical artifact dirs)
CRATE_TOML=$(find . -type f -name Cargo.toml \
  -not -path "./public/wasm/*" \
  -not -path "./wasm/*" \
  -not -path "./target/*" \
  -not -path "./node_modules/*" | sed -n '1p' || true)

if [ -z "$CRATE_TOML" ]; then
  echo "[!] No Cargo.toml found — SKIPPING wasm build (this is intentional)."
  echo "[i] Creating empty public wasm dir so deploy won't fail."
  mkdir -p "${PUBLIC_WASM_DIR}"
  echo "[i] Done. If you add a Rust crate later, this script will build it automatically."
  exit 0
fi

CRATE_DIR=$(dirname "$CRATE_TOML")
echo "[+] Found Rust crate at: $CRATE_TOML (dir: $CRATE_DIR)"

# ensure wasm-pack available (try to install if missing)
if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "[*] wasm-pack not found — attempting install (may take time)..."
  if command -v curl >/dev/null 2>&1; then
    curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
    export PATH="$HOME/.cargo/bin:$PATH"
  else
    echo "[-] curl not available and wasm-pack missing. Please install wasm-pack or add to PATH."
    exit 1
  fi
else
  echo "[*] wasm-pack found: $(wasm-pack --version || true)"
fi

# clean previous outputs
rm -rf "${OUT_DIR}" "${PUBLIC_WASM_DIR}"

# build using wasm-pack
echo "[*] Building wasm-pack..."
if [ "$CRATE_DIR" != "." ]; then
  wasm-pack build --manifest-path "${CRATE_TOML}" --target web --out-dir "${OUT_DIR}" --release
else
  wasm-pack build --target web --out-dir "${OUT_DIR}" --release
fi
echo "[*] wasm-pack build finished."

# copy to public for Vercel
echo "[*] Copying artifacts to ${PUBLIC_WASM_DIR}"
mkdir -p "${PUBLIC_WASM_DIR}"
rsync -av --delete "${OUT_DIR}/" "${PUBLIC_WASM_DIR}/"

echo "[*] Done. Artifacts available at ${PUBLIC_WASM_DIR}"
