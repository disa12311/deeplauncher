#!/usr/bin/env bash
# build.sh — robust for Vercel: isolate rustup/cargo homes to avoid $HOME/euid mismatch
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
echo "[$(ts)] build.sh (robust) OUT_DIR=${OUT_DIR} PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}"

# locate crate (first Cargo.toml)
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

# Use isolated directories inside workspace so rustup doesn't complain about HOME mismatch
# (Vercel build can run as root while $HOME points to /vercel -> rustup checks mismatch)
export RUSTUP_HOME="${PWD}/.rustup"
export CARGO_HOME="${PWD}/.cargo"
export PATH="${CARGO_HOME}/bin:${PATH}"

echo "[$(ts)] Using RUSTUP_HOME=${RUSTUP_HOME} CARGO_HOME=${CARGO_HOME}"

# install rustup toolchain if rustc not present
if ! command -v rustc >/dev/null 2>&1; then
  echo "[$(ts)] rustc not found. Installing rustup into isolated home..."
  if command -v curl >/dev/null 2>&1; then
    # Use rustup-init non-interactive. piping to sh is standard installer.
    # Installer will write into RUSTUP_HOME/CARGO_HOME because we exported them above.
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # source cargo env if exists
    if [ -f "${CARGO_HOME}/env" ]; then
      # older installers may create $CARGO_HOME/env
      # source it if shell supports
      # shellcheck disable=SC1090
      . "${CARGO_HOME}/env"
    fi
    # ensure PATH updated
    export PATH="${CARGO_HOME}/bin:${PATH}"
    echo "[$(ts)] rustup installed. rustc: $(rustc --version || true)"
  else
    echo "[$(ts)] ERROR: curl not available to install rustup. Please preinstall toolchain or enable network."
    exit 1
  fi
else
  echo "[$(ts)] rustc present: $(rustc --version)"
fi

# ensure wasm target
echo "[$(ts)] Adding wasm32 target (idempotent)..."
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
