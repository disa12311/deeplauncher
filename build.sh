#!/usr/bin/env bash
# build.sh — safe auto-detect wasm build with rustup install (suitable for Vercel)
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
echo "[$(ts)] build.sh (safe mode with rustup) OUT_DIR=${OUT_DIR} PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}"

# find Cargo.toml (exclude typical artifact dirs)
CRATE_TOML=$(find . -type f -name Cargo.toml \
  -not -path "./public/wasm/*" \
  -not -path "./wasm/*" \
  -not -path "./target/*" \
  -not -path "./node_modules/*" | sed -n '1p' || true)

if [ -z "$CRATE_TOML" ]; then
  echo "[$(ts)] No Cargo.toml found — SKIPPING wasm build (intentional)."
  mkdir -p "${PUBLIC_WASM_DIR}"
  exit 0
fi

CRATE_DIR=$(dirname "${CRATE_TOML}")
echo "[$(ts)] Found Rust crate at: ${CRATE_TOML} (dir: ${CRATE_DIR})"

# Ensure rustup / rustc available (install non-interactive if missing)
if ! command -v rustc >/dev/null 2>&1; then
  echo "[$(ts)] rustc not found — installing rustup (non-interactive)..."
  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "[$(ts)] rustup installed. rustc: $(rustc --version || true)"
  else
    echo "[$(ts)] ERROR: curl not available to install rustup. Please enable install or preinstall rust toolchain."
    exit 1
  fi
else
  echo "[$(ts)] rustc present: $(rustc --version)"
fi

# ensure wasm target
echo "[$(ts)] Ensuring wasm32 target..."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# Ensure wasm-pack available (install if missing)
if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] wasm-pack not found — installing wasm-pack (installer requires rustup)..."
  if command -v curl >/dev/null 2>&1; then
    curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
    export PATH="$HOME/.cargo/bin:$PATH"
    if command -v wasm-pack >/dev/null 2>&1; then
      echo "[$(ts)] wasm-pack installed: $(wasm-pack --version)"
    else
      echo "[$(ts)] WARNING: wasm-pack installer did not produce a binary. Will try fallback to wasm-bindgen later."
    fi
  else
    echo "[$(ts)] ERROR: curl not available to install wasm-pack."
  fi
else
  echo "[$(ts)] wasm-pack present: $(wasm-pack --version || true)"
fi

# Clean previous outputs
rm -rf "${OUT_DIR}" "${PUBLIC_WASM_DIR}"

# If wasm-pack exists, use it; else fallback to cargo+wasm-bindgen
if command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] Building with wasm-pack (using crate dir)..."
  set -x
  # use crate directory argument (more robust than --manifest-path in some envs)
  wasm-pack build "${CRATE_DIR}" --target web --out-dir "${OUT_DIR}" --release
  set +x
  echo "[$(ts)] wasm-pack build finished."
else
  echo "[$(ts)] wasm-pack not available — trying cargo build + wasm-bindgen fallback..."
  if ! command -v wasm-bindgen >/dev/null 2>&1; then
    echo "[$(ts)] Installing wasm-bindgen-cli via cargo install (may take some time)..."
    cargo install -f wasm-bindgen-cli || true
  fi

  if [ -f "${CRATE_TOML}" ]; then
    if cargo build --manifest-path "${CRATE_TOML}" --target wasm32-unknown-unknown --release; then
      BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/release"
      WASM_FILE=$(find "${BUILD_ARTIFACT_PATH}" -maxdepth 1 -type f -name "*.wasm" | sed -n '1p' || true)
      if [ -z "${WASM_FILE}" ]; then
        echo "[$(ts)] ERROR: no wasm artifact found in ${BUILD_ARTIFACT_PATH}"
        exit 1
      fi
      mkdir -p "${OUT_DIR}"
      wasm-bindgen "${WASM_FILE}" --out-dir "${OUT_DIR}" --target web
      echo "[$(ts)] wasm-bindgen output in ${OUT_DIR}"
    else
      echo "[$(ts)] cargo build failed"
      exit 1
    fi
  else
    echo "[$(ts)] ERROR: manifest not found at ${CRATE_TOML}"
    exit 1
  fi
fi

# Copy to public for Vercel
echo "[$(ts)] Copying artifacts to ${PUBLIC_WASM_DIR}"
mkdir -p "${PUBLIC_WASM_DIR}"
rsync -av --delete "${OUT_DIR}/" "${PUBLIC_WASM_DIR}/" || true
echo "[$(ts)] Done. Artifacts in ${PUBLIC_WASM_DIR}"
