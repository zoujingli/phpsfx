#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLATFORM=${1:-${PHPSFX_PLATFORM:-}}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.4}
SPC_REPO=${PHPSFX_SPC_REPO:-https://github.com/crazywhalecc/static-php-cli.git}
SPC_REF=${PHPSFX_SPC_REF:-main}
SPC_DIR=${PHPSFX_SPC_DIR:-"${ROOT_DIR}/.build/static-php-cli"}
DIST_DIR=${PHPSFX_DIST_DIR:-"${ROOT_DIR}/dist"}
EXTENSIONS=${PHPSFX_EXTENSIONS:-bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,openssl,pcntl,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zlib}
EXPECTED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS:-swoole,redis,pdo_mysql,openssl,curl,mbstring,phar,zlib}

usage() {
  cat <<'USAGE'
Usage: scripts/build-micro-sfx.sh [platform]

Platforms:
  linux-x64, linux-a64, macos-x64, macos-a64

Important environment variables:
  PHPSFX_PHP_VERSION       PHP version line, default: 8.4
  PHPSFX_SPC_REF           static-php-cli ref, default: main
  PHPSFX_EXTENSIONS        comma-separated static extensions
  PHPSFX_DIST_DIR          output directory, default: ./dist
  PHPSFX_SPC_DIR           static-php-cli checkout dir, default: ./.build/static-php-cli
USAGE
}

detect_platform() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "${os}:${arch}" in
    Linux:x86_64|Linux:amd64) echo linux-x64 ;;
    Linux:aarch64|Linux:arm64) echo linux-a64 ;;
    Darwin:x86_64|Darwin:amd64) echo macos-x64 ;;
    Darwin:arm64|Darwin:aarch64) echo macos-a64 ;;
    *)
      echo "Unsupported host platform: ${os}/${arch}" >&2
      return 1
      ;;
  esac
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 127
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Required command not found: sha256sum or shasum" >&2
    exit 127
  fi
}

if [[ -z "${PLATFORM}" ]]; then
  PLATFORM=$(detect_platform)
fi

case "${PLATFORM}" in
  linux-x64|linux-a64|macos-x64|macos-a64) ;;
  -h|--help) usage; exit 0 ;;
  *)
    usage >&2
    echo "Unsupported platform: ${PLATFORM}" >&2
    exit 2
    ;;
esac

require_command git
require_command php
require_command composer
require_command tar

mkdir -p "${DIST_DIR}" "$(dirname "${SPC_DIR}")"

if [[ ! -d "${SPC_DIR}/.git" ]]; then
  rm -rf "${SPC_DIR}"
  git clone --filter=blob:none "${SPC_REPO}" "${SPC_DIR}"
fi

cd "${SPC_DIR}"
if git fetch --force --depth=1 origin "${SPC_REF}"; then
  git checkout --force FETCH_HEAD
else
  git fetch --force --tags origin
  git checkout --force "${SPC_REF}"
fi
SPC_COMMIT=$(git rev-parse HEAD)

composer install --no-dev --classmap-authoritative --no-interaction --no-progress --prefer-dist
rm -rf buildroot

case "${PLATFORM}" in
  linux-x64|linux-a64)
    require_command docker
    docker version
    ./bin/spc-alpine-docker download --with-php="${PHP_VERSION}" --for-extensions="${EXTENSIONS}" --prefer-pre-built --ignore-cache-sources=php-src
    ./bin/spc-alpine-docker build "${EXTENSIONS}" --build-micro --with-micro-fake-cli
    ;;
  macos-x64|macos-a64)
    ./bin/spc doctor --auto-fix
    ./bin/spc download --with-php="${PHP_VERSION}" --for-extensions="${EXTENSIONS}" --prefer-pre-built --ignore-cache-sources=php-src
    ./bin/spc build "${EXTENSIONS}" --build-micro --with-micro-fake-cli
    ;;
esac

MICRO_SFX="${SPC_DIR}/buildroot/bin/micro.sfx"
if [[ ! -s "${MICRO_SFX}" ]]; then
  echo "micro.sfx was not generated: ${MICRO_SFX}" >&2
  exit 1
fi

ASSET_NAME="micro.sfx-php${PHP_VERSION}-${PLATFORM}"
cp "${MICRO_SFX}" "${DIST_DIR}/${ASSET_NAME}"
chmod +x "${DIST_DIR}/${ASSET_NAME}"

PHPSFX_EXPECTED_PHP_PREFIX="${PHP_VERSION}." \
PHPSFX_REQUIRED_EXTENSIONS="${EXPECTED_EXTENSIONS}" \
  bash "${ROOT_DIR}/scripts/validate-micro-sfx.sh" "${DIST_DIR}/${ASSET_NAME}"

SHA256=$(sha256_file "${DIST_DIR}/${ASSET_NAME}")
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "${DIST_DIR}/build-meta-${PLATFORM}.json" <<META
{
  "platform": "${PLATFORM}",
  "asset": "${ASSET_NAME}",
  "php_version": "${PHP_VERSION}",
  "spc_repo": "${SPC_REPO}",
  "spc_ref": "${SPC_REF}",
  "spc_commit": "${SPC_COMMIT}",
  "extensions": "${EXTENSIONS}",
  "required_extensions": "${EXPECTED_EXTENSIONS}",
  "sha256": "${SHA256}",
  "built_at": "${BUILT_AT}"
}
META

printf 'Built %s\n' "${DIST_DIR}/${ASSET_NAME}"
printf 'SHA256 %s  %s\n' "${SHA256}" "${ASSET_NAME}"
