#!/usr/bin/env bash
# build.sh — robust for Vercel: isolate homes, build wasm, fallback copy if rsync missing
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
echo "[$(ts)] build.sh (robust) OUT_DIR=${OUT_DIR} PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}"

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

# isolate rustup / cargo homes to avoid HOME mismatch
WORKSPACE_HOME="${PWD}/.cargo_home"
export RUSTUP_HOME="${PWD}/.rustup"
export CARGO_HOME="${PWD}/.cargo"

mkdir -p "${WORKSPACE_HOME}" "${RUSTUP_HOME}" "${CARGO_HOME}"
export HOME="${WORKSPACE_HOME}"
export PATH="${CARGO_HOME}/bin:${PATH}"

echo "[$(ts)] Using HOME=${HOME}"
echo "[$(ts)] RUSTUP_HOME=${RUSTUP_HOME}"
echo "[$(ts)] CARGO_HOME=${CARGO_HOME}"

# install rustup if rustc missing
if ! command -v rustc >/dev/null 2>&1; then
  echo "[$(ts)] rustc not found. Installing rustup into isolated home..."
  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
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

# ensure wasm target
echo "[$(ts)] Adding wasm32 target..."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# install wasm-pack if missing
if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] wasm-pack not found — installing..."
  if command -v curl >/dev/null 2>&1; then
    curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
    export PATH="${CARGO_HOME}/bin:${PATH}"
    if command -v wasm-pack >/dev/null 2>&1; then
      echo "[$(ts)] wasm-pack installed: $(wasm-pack --version)"
    else
      echo "[$(ts)] WARNING: wasm-pack installer didn't produce binary, will fallback to wasm-bindgen."
    fi
  else
    echo "[$(ts)] ERROR: curl not available to install wasm-pack."
  fi
else
  echo "[$(ts)] wasm-pack present: $(wasm-pack --version || true)"
fi

# clean output
rm -rf "${OUT_DIR}" "${PUBLIC_WASM_DIR}"

# build wasm
if command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] Building with wasm-pack (crate dir: ${CRATE_DIR})..."
  set -x
  wasm-pack build "${CRATE_DIR}" --target web --out-dir "${OUT_DIR}" --release
  set +x
  echo "[$(ts)] wasm-pack build finished."
else
  echo "[$(ts)] wasm-pack not available — fallback cargo+wasm-bindgen..."
  if ! command -v wasm-bindgen >/dev/null 2>&1; then
    echo "[$(ts)] Installing wasm-bindgen-cli..."
    cargo install -f wasm-bindgen-cli || true
  fi

  echo "[$(ts)] Cargo build ..."
  cargo build --manifest-path "${CRATE_TOML}" --target wasm32-unknown-unknown --release
  BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/release"
  WASM_FILE=$(find "${BUILD_ARTIFACT_PATH}" -maxdepth 1 -type f -name "*.wasm" | sed -n '1p' || true)
  if [ -z "${WASM_FILE}" ]; then
    echo "[$(ts)] ERROR: no wasm artifact in ${BUILD_ARTIFACT_PATH}"
    exit 1
  fi
  mkdir -p "${OUT_DIR}"
  wasm-bindgen "${WASM_FILE}" --out-dir "${OUT_DIR}" --target web
  echo "[$(ts)] wasm-bindgen output in ${OUT_DIR}"
fi

# copy artifacts to public dir — prefer rsync; fallback to cp -a
echo "[$(ts)] Copying artifacts to ${PUBLIC_WASM_DIR}"
mkdir -p "${PUBLIC_WASM_DIR}"

if command -v rsync >/dev/null 2>&1; then
  echo "[$(ts)] Using rsync to copy files..."
  rsync -av --delete "${OUT_DIR}/" "${PUBLIC_WASM_DIR}/"
else
  echo "[$(ts)] rsync not found — using cp fallback..."
  # Use POSIX-safe cp recursion; preserve attributes when possible
  # remove destination contents first (like rsync --delete)
  if [ -d "${PUBLIC_WASM_DIR}" ]; then
    rm -rf "${PUBLIC_WASM_DIR:?}/"*
  fi
  mkdir -p "${PUBLIC_WASM_DIR}"
  # copy files (preserve mode and timestamps if possible)
  if command -v cp >/dev/null 2>&1; then
    cp -a "${OUT_DIR}/." "${PUBLIC_WASM_DIR}/" || {
      # fallback portable copy
      (cd "${OUT_DIR}" && tar cf - .) | (cd "${PUBLIC_WASM_DIR}" && tar xf -)
    }
  else
    echo "[$(ts)] ERROR: neither rsync nor cp available to copy files."
    exit 1
  fi
fi

echo "[$(ts)] Done. Artifacts available at ${PUBLIC_WASM_DIR}"
