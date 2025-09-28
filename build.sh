#!/usr/bin/env bash
# build.sh — robust: isolate homes, ensure wasm-pack writes to absolute out dir,
# detect fallback pkg locations, and copy portable without rsync.
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-wasm/pkg}"  # Changed: output to root/wasm/pkg

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
echo "[$(ts)] build.sh (robust) OUT_DIR=${OUT_DIR} PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}"

# find crate
CRATE_TOML=$(find . -type f -name Cargo.toml \
  -not -path "./public/wasm/*" \
  -not -path "./wasm/*" \
  -not -path "./target/*" \
  -not -path "./node_modules/*" | sed -n '1p' || true)

if [ -z "$CRATE_TOML" ]; then
  echo "[$(ts)] No Cargo.toml found — SKIPPING wasm build."
  mkdir -p "${PUBLIC_WASM_DIR}"
  exit 0
fi

CRATE_DIR=$(dirname "${CRATE_TOML}")
echo "[$(ts)] Found crate at: ${CRATE_TOML} (dir: ${CRATE_DIR})"

# isolate home dirs - but keep original HOME for rustup
ORIGINAL_HOME="${HOME}"
export RUSTUP_HOME="${PWD}/.rustup"
export CARGO_HOME="${PWD}/.cargo"
mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"
export PATH="${CARGO_HOME}/bin:${PATH}"

echo "[$(ts)] HOME=${HOME}"
echo "[$(ts)] RUSTUP_HOME=${RUSTUP_HOME}"
echo "[$(ts)] CARGO_HOME=${CARGO_HOME}"

# install rustup if needed
if ! command -v rustc >/dev/null 2>&1; then
  echo "[$(ts)] rustc not found. Installing rustup..."
  if command -v curl >/dev/null 2>&1; then
    # Use original HOME for rustup installation, but set custom RUSTUP_HOME and CARGO_HOME
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable
    if [ -f "${CARGO_HOME}/env" ]; then
      # shellcheck disable=SC1090
      . "${CARGO_HOME}/env"
    fi
    export PATH="${CARGO_HOME}/bin:${PATH}"
    echo "[$(ts)] rustup installed. rustc: $(rustc --version || true)"
  else
    echo "[$(ts)] ERROR: curl not available to install rustup."
    exit 1
  fi
else
  echo "[$(ts)] rustc present: $(rustc --version)"
fi

# add wasm target
echo "[$(ts)] Adding wasm32 target..."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# install wasm-pack if missing
if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] wasm-pack not found — installing..."
  if command -v curl >/dev/null 2>&1; then
    curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh -s -- --force
    export PATH="${CARGO_HOME}/bin:${PATH}"
    echo "[$(ts)] wasm-pack: $(wasm-p