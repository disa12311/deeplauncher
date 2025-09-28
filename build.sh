#!/usr/bin/env bash
# build.sh — robust for Vercel: avoid HOME/euid mismatch by isolating homes
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
echo "[$(ts)] build.sh (robust HOME fix) OUT_DIR=${OUT_DIR} PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}"

# auto-detect crate
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

# isolate home directories inside the repo workspace to avoid rustup complaining
# use a dedicated folder for cargo/rustup and set HOME to that folder during install
WORKSPACE_HOME="${PWD}/.cargo_home"
export RUSTUP_HOME="${PWD}/.rustup"
export CARGO_HOME="${PWD}/.cargo"

mkdir -p "${WORKSPACE_HOME}" "${RUSTUP_HOME}" "${CARGO_HOME}"
# Temporarily set HOME to workspace-local folder so rustup-init won't complain about /root vs /vercel
export HOME="${WORKSPACE_HOME}"
export PATH="${CARGO_HOME}/bin:${PATH}"

echo "[$(ts)] Using HOME=${HOME}"
echo "[$(ts)] RUSTUP_HOME=${RUSTUP_HOME}"
echo "[$(ts)] CARGO_HOME=${CARGO_HOME}"

# Install rustup if rustc not present (installer will use our RUSTUP_HOME/CARGO_HOME because we exported them)
if ! command -v rustc >/dev/null 2>&1; then
  echo "[$(ts)] rustc not found. Installing rustup into isolated home..."
  if command -v curl >/dev/null 2>&1; then
    # use --no-modify-path so installer doesn't try to update profile files
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # source cargo env if exists under our CARGO_HOME
    if [ -f "${CARGO_HOME}/env" ]; then
      # shellcheck disable=SC1090
      . "${CARGO_HOME}/env"
    fi
    export PATH="${CARGO_HOME}/bin:${PATH}"
    echo "[$(ts)] rustup installed. rustc: $(rustc --version || true)"
  else
    echo "[$(ts)] ERROR: curl not available to install rustup. Please preinstall toolchain or enable network."
    exit 1
  fi
else
  echo "[$(ts)] rustc present: $(rustc --version)"
fi

# add wasm target (idempotent)
echo "[$(ts)] Adding wasm32 target..."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# install wasm-pack into isolated cargo if missing
if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] wasm-pack not found — installing into ${CARGO_HOME} ..."
  if command -v curl >/dev/null 2>&1; then
    curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
    export PATH="${CARGO_HOME}/bin:${PATH}"
    if command -v wasm-pack >/dev/null 2>&1; then
      echo "[$(ts)] wasm-pack installed: $(wasm-pack --version)"
    else
      echo "[$(ts)] wasm-pack installer didn't produce binary — continuing to fallback later."
    fi
  else
    echo "[$(ts)] ERROR: curl not available to install wasm-pack."
  fi
else
  echo "[$(ts)] wasm-pack present: $(wasm-pack --version || true)"
fi

# clean previous outputs
rm -rf "${OUT_DIR}" "${PUBLIC_WASM_DIR}"

# build with wasm-pack if available
if command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] Building with wasm-pack (crate dir ${CRATE_DIR})..."
  set -x
  wasm-pack build "${CRATE_DIR}" --target web --out-dir "${OUT_DIR}" --release
  set +x
  echo "[$(ts)] wasm-pack build finished."
else
  echo "[$(ts)] wasm-pack not available — falling back to cargo+wasm-bindgen."
  if ! command -v wasm-bindgen >/dev/null 2>&1; then
    echo "[$(ts)] Installing wasm-bindgen-cli via cargo install..."
    cargo install -f wasm-bindgen-cli || true
  fi

  echo "[$(ts)] Building crate with cargo (release) ..."
  cargo build --manifest-path "${CRATE_TOML}" --target wasm32-unknown-unknown --release
  BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/release"
  WASM_FILE=$(find "${BUILD_ARTIFACT_PATH}" -maxdepth 1 -type f -name "*.wasm" | sed -n '1p' || true)
  if [ -z "${WASM_FILE}" ]; then
    echo "[$(ts)] ERROR: no wasm artifact found in ${BUILD_ARTIFACT_PATH}"
    exit 1
  fi
  mkdir -p "${OUT_DIR}"
  wasm-bindgen "${WASM_FILE}" --out-dir "${OUT_DIR}" --target web
  echo "[$(ts)] wasm-bindgen output in ${OUT_DIR}"
fi

# copy artifacts to public for Vercel
echo "[$(ts)] Copying artifacts to ${PUBLIC_WASM_DIR}"
mkdir -p "${PUBLIC_WASM_DIR}"
rsync -av --delete "${OUT_DIR}/" "${PUBLIC_WASM_DIR}/" || true
echo "[$(ts)] Done. Artifacts available at ${PUBLIC_WASM_DIR}"
