#!/usr/bin/env bash
# build.sh — robust: isolate homes, ensure wasm-pack writes to absolute out dir,
# detect fallback pkg locations, and copy portable without rsync.
set -euo pipefail

OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"

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
    echo "[$(ts)] wasm-pack: $(wasm-pack --version || 'not found')"
  else
    echo "[$(ts)] ERROR: curl not available to install wasm-pack."
    exit 1
  fi
else
  echo "[$(ts)] wasm-pack present: $(wasm-pack --version || true)"
fi

# clean
rm -rf "${OUT_DIR}" "${PUBLIC_WASM_DIR}"

# compute absolute out dir (so wasm-pack doesn't create inside crate dir)
ABS_OUT_DIR="${PWD%/}/${OUT_DIR#./}"
mkdir -p "${ABS_OUT_DIR}"

# build
if command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] Building with wasm-pack (crate: ${CRATE_DIR}) -> ${ABS_OUT_DIR}"
  set -x
  wasm-pack build "${CRATE_DIR}" --target web --out-dir "${ABS_OUT_DIR}" --release
  set +x
  echo "[$(ts)] wasm-pack build finished."
else
  echo "[$(ts)] wasm-pack not available — fallback cargo+wasm-bindgen..."
  if ! command -v wasm-bindgen >/dev/null 2>&1; then
    cargo install -f wasm-bindgen-cli || true
  fi

  cargo build --manifest-path "${CRATE_TOML}" --target wasm32-unknown-unknown --release
  BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/release"
  WASM_FILE=$(find "${BUILD_ARTIFACT_PATH}" -maxdepth 1 -type f -name "*.wasm" | sed -n '1p' || true)
  if [ -z "${WASM_FILE}" ]; then
    echo "[$(ts)] ERROR: no wasm artifact in ${BUILD_ARTIFACT_PATH}"
    exit 1
  fi
  mkdir -p "${ABS_OUT_DIR}"
  wasm-bindgen "${WASM_FILE}" --out-dir "${ABS_OUT_DIR}" --target web
  echo "[$(ts)] wasm-bindgen output in ${ABS_OUT_DIR}"
fi

# ensure we have a pkg directory - sometimes old wasm-pack writes into crate_dir/wasm/pkg
# check common alternate locations
POSSIBLE_PKG_LOCATIONS=(
  "${ABS_OUT_DIR}"
  "${CRATE_DIR}/wasm/pkg"
  "${CRATE_DIR}/pkg"
  "${CRATE_DIR}/target/wasm32-unknown-unknown/pkg"
)
ACTUAL_PKG=""
for p in "${POSSIBLE_PKG_LOCATIONS[@]}"; do
  if [ -d "${p}" ] && [ -n "$(ls -A "${p}" 2>/dev/null || true)" ]; then
    ACTUAL_PKG="${p}"
    break
  fi
done

if [ -z "${ACTUAL_PKG}" ]; then
  echo "[$(ts)] Warning: no wasm pkg found in expected locations. Listing ${ABS_OUT_DIR}:"
  ls -la "${ABS_OUT_DIR}" || true
  # still try to continue, create public dir
  mkdir -p "${PUBLIC_WASM_DIR}"
else
  echo "[$(ts)] Found wasm pkg at: ${ACTUAL_PKG}"
  # copy to public
  mkdir -p "${PUBLIC_WASM_DIR}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -av --delete "${ACTUAL_PKG}/" "${PUBLIC_WASM_DIR}/"
  else
    # cp fallback
    if [ -d "${PUBLIC_WASM_DIR}" ]; then rm -rf "${PUBLIC_WASM_DIR:?}/"* || true; fi
    mkdir -p "${PUBLIC_WASM_DIR}"
    if command -v cp >/dev/null 2>&1; then
      cp -a "${ACTUAL_PKG}/." "${PUBLIC_WASM_DIR}/" || (cd "${ACTUAL_PKG}" && tar cf - .) | (cd "${PUBLIC_WASM_DIR}" && tar xf -)
    else
      (cd "${ACTUAL_PKG}" && tar cf - .) | (cd "${PUBLIC_WASM_DIR}" && tar xf -)
    fi
  fi
  echo "[$(ts)] Artifacts copied to ${PUBLIC_WASM_DIR}"
fi

echo "[$(ts)] Done."