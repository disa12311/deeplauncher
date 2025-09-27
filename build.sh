#!/usr/bin/env bash
# build.sh (improved)
# - auto-detect Cargo.toml
# - prefer wasm-pack, fallback to cargo+wasm-bindgen
# - copy output to public/wasm/pkg (configurable)
# - suitable for local dev or CI (Vercel)
#
# Usage:
#   ./build.sh                  # auto-detect crate, release build
#   ./build.sh --debug          # debug build (no --release)
#   ./build.sh --crate engine   # use crate in ./engine
#   OUT_DIR=wasm/pkg PUBLIC_WASM_DIR=public/wasm/pkg ./build.sh
#   ./build.sh --force          # fail if no crate found
#
set -euo pipefail

# --- defaults (can be overridden by env or args)
OUT_DIR="${OUT_DIR:-wasm/pkg}"
PUBLIC_WASM_DIR="${PUBLIC_WASM_DIR:-public/wasm/pkg}"
BUILD_MODE="release"   # "release" or "debug"
CRATE_PATH=""          # explicit crate path (directory)
SKIP_INSTALL="false"   # if true, won't attempt to auto-install wasm-pack/rustup
FORCE_FAIL="false"     # if true, exit non-zero when no Cargo.toml found

# --- parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) BUILD_MODE="debug"; shift ;;
    --crate) CRATE_PATH="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --public) PUBLIC_WASM_DIR="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL="true"; shift ;;
    --force) FORCE_FAIL="true"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--debug] [--crate <path>] [--out <out_dir>] [--public <public_dir>] [--skip-install] [--force]
  --debug         Build debug (no --release)
  --crate <path>  Path to crate directory (where Cargo.toml is)
  --out <dir>     wasm-pack out dir (default: ${OUT_DIR})
  --public <dir>  copy artifacts to this public dir (default: ${PUBLIC_WASM_DIR})
  --skip-install  don't auto-install rustup/wasm-pack
  --force         exit with error if no Cargo.toml found
EOF
      exit 0
      ;;
    *)
      echo "Unknown arg: $1"
      exit 1
      ;;
  esac
done

# timestamp helper
ts() { date +"%Y-%m-%d %H:%M:%S"; }

echo "[$(ts)] Starting build.sh"
echo "[$(ts)] OUT_DIR=${OUT_DIR}, PUBLIC_WASM_DIR=${PUBLIC_WASM_DIR}, BUILD_MODE=${BUILD_MODE}"
if [[ -n "${CRATE_PATH}" ]]; then echo "[$(ts)] Explicit crate path: ${CRATE_PATH}"; fi
if [[ "${SKIP_INSTALL}" == "true" ]]; then echo "[$(ts)] SKIP_INSTALL=true (will not auto-install tools)"; fi
if [[ "${FORCE_FAIL}" == "true" ]]; then echo "[$(ts)] FORCE_FAIL=true (will fail if no crate)"; fi

# --- find Cargo.toml
if [[ -n "${CRATE_PATH}" ]]; then
  if [[ -f "${CRATE_PATH}/Cargo.toml" ]]; then
    CRATE_TOML="${CRATE_PATH}/Cargo.toml"
  else
    echo "[$(ts)] ERROR: Provided crate path '${CRATE_PATH}' does not contain Cargo.toml"
    exit 1
  fi
else
  # search for first Cargo.toml, exclude typical build artifact folders
  CRATE_TOML=$(find . -type f -name Cargo.toml \
    -not -path "./public/wasm/*" \
    -not -path "./wasm/*" \
    -not -path "./target/*" \
    -not -path "./node_modules/*" | sed -n '1p' || true)
fi

if [[ -z "${CRATE_TOML}" ]]; then
  echo "[$(ts)] No Cargo.toml found in repo."
  if [[ "${FORCE_FAIL}" == "true" ]]; then
    echo "[$(ts)] Exiting due to --force."
    exit 1
  fi
  # ensure public dir exists for consistent deployment
  mkdir -p "${PUBLIC_WASM_DIR}"
  echo "[$(ts)] Skipping wasm build. Created ${PUBLIC_WASM_DIR} (empty)."
  echo "[$(ts)] Done."
  exit 0
fi

CRATE_DIR=$(dirname "${CRATE_TOML}")
echo "[$(ts)] Found Cargo.toml at: ${CRATE_TOML} (crate dir: ${CRATE_DIR})"

# --- ensure rust toolchain and wasm target (optionally auto-install)
if ! command -v rustc >/dev/null 2>&1; then
  if [[ "${SKIP_INSTALL}" == "true" ]]; then
    echo "[$(ts)] ERROR: rustc not found and auto-install disabled (--skip-install)."
    exit 1
  fi
  echo "[$(ts)] rustc not found — installing rustup (non-interactive)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# add wasm target (no-op if already added)
echo "[$(ts)] Ensuring wasm32-unknown-unknown target..."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

# --- ensure wasm-pack or wasm-bindgen available
USE_WASM_PACK="false"
if command -v wasm-pack >/dev/null 2>&1; then
  echo "[$(ts)] wasm-pack found: $(wasm-pack --version || true)"
  USE_WASM_PACK="true"
else
  if [[ "${SKIP_INSTALL}" == "true" ]]; then
    echo "[$(ts)] wasm-pack not found and --skip-install set; will attempt wasm-bindgen fallback."
    USE_WASM_PACK="false"
  else
    echo "[$(ts)] wasm-pack not found — installing wasm-pack (this may take some time)..."
    if command -v curl >/dev/null 2>&1; then
      curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
      export PATH="$HOME/.cargo/bin:$PATH"
      if command -v wasm-pack >/dev/null 2>&1; then
        echo "[$(ts)] wasm-pack installed: $(wasm-pack --version)"
        USE_WASM_PACK="true"
      else
        echo "[$(ts)] wasm-pack installer did not produce binary; will try fallback."
        USE_WASM_PACK="false"
      fi
    else
      echo "[$(ts)] curl not available — cannot auto-install wasm-pack. Will try fallback."
      USE_WASM_PACK="false"
    fi
  fi
fi

# if wasm-pack available use it
if [[ "${USE_WASM_PACK}" == "true" ]]; then
  echo "[$(ts)] Building with wasm-pack..."
  # choose release or not
  if [[ "${BUILD_MODE}" == "release" ]]; then
    WP_FLAGS="--release"
  else
    WP_FLAGS=""
  fi

  set -x
  if [[ "${CRATE_DIR}" != "." ]]; then
    wasm-pack build --manifest-path "${CRATE_TOML}" --target web --out-dir "${OUT_DIR}" ${WP_FLAGS}
  else
    wasm-pack build --target web --out-dir "${OUT_DIR}" ${WP_FLAGS}
  fi
  set +x
  echo "[$(ts)] wasm-pack build finished."
else
  # fallback: try cargo build + wasm-bindgen
  echo "[$(ts)] wasm-pack not available — attempting cargo build + wasm-bindgen fallback."
  if ! command -v wasm-bindgen >/dev/null 2>&1; then
    if [[ "${SKIP_INSTALL}" == "true" ]]; then
      echo "[$(ts)] ERROR: wasm-bindgen not found and auto-install disabled. Cannot build."
      exit 1
    fi
    echo "[$(ts)] Installing wasm-bindgen-cli..."
    cargo install -f wasm-bindgen-cli || true
  fi

  # build with cargo
  if [[ "${BUILD_MODE}" == "release" ]]; then
    cargo build --target wasm32-unknown-unknown --manifest-path "${CRATE_TOML}" --release
    BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/release"
  else
    cargo build --target wasm32-unknown-unknown --manifest-path "${CRATE_TOML}"
    BUILD_ARTIFACT_PATH="target/wasm32-unknown-unknown/debug"
  fi

  # find wasm file
  WASM_FILE=$(find "${BUILD_ARTIFACT_PATH}" -maxdepth 1 -type f -name "*.wasm" | sed -n '1p' || true)
  if [[ -z "${WASM_FILE}" ]]; then
    echo "[$(ts)] ERROR: no .wasm artifact found in ${BUILD_ARTIFACT_PATH}"
    exit 1
  fi
  echo "[$(ts)] Found wasm artifact: ${WASM_FILE}"

  # run wasm-bindgen
  mkdir -p "${OUT_DIR}"
  wasm-bindgen "${WASM_FILE}" --out-dir "${OUT_DIR}" --target web
  echo "[$(ts)] wasm-bindgen output in ${OUT_DIR}"
fi

# --- copy/sync into public folder for Vercel
echo "[$(ts)] Preparing ${PUBLIC_WASM_DIR}"
mkdir -p "${PUBLIC_WASM_DIR}"
rsync -av --delete "${OUT_DIR}/" "${PUBLIC_WASM_DIR}/"

echo "[$(ts)] Files copied to ${PUBLIC_WASM_DIR}:"
ls -la "${PUBLIC_WASM_DIR}" || true

echo "[$(ts)] Build finished successfully."
exit 0
