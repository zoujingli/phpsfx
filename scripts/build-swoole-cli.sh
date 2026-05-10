#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE_FILE=${PHPSFX_PROFILE_FILE:-"${ROOT_DIR}/scripts/profiles/hyperfadmin-slim.env"}
if [[ -n "${PROFILE_FILE}" && "${PROFILE_FILE}" != "none" ]]; then
  [[ "${PROFILE_FILE}" = /* ]] || PROFILE_FILE="${ROOT_DIR}/${PROFILE_FILE}"
  if [[ ! -f "${PROFILE_FILE}" ]]; then
    echo "Profile file does not exist: ${PROFILE_FILE}" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${PROFILE_FILE}"
fi

PLATFORM=${1:-${PHPSFX_PLATFORM:-}}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.4}
SWOOLE_CLI_REPO=${PHPSFX_SWOOLE_CLI_REPO:-https://github.com/swoole/swoole-cli.git}
SWOOLE_CLI_REF=${PHPSFX_SWOOLE_CLI_REF:-v6.2.0.0}
SWOOLE_CLI_DIR=${PHPSFX_SWOOLE_CLI_DIR:-"${ROOT_DIR}/.build/swoole-cli"}
DIST_DIR=${PHPSFX_DIST_DIR:-"${ROOT_DIR}/dist"}
JOBS=${PHPSFX_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}
PROFILE_NAME=${PHPSFX_PROFILE_NAME:-hyperfadmin-slim}
DEFAULT_EXTENSIONS='bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,openssl,pcntl,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib'
DEFAULT_PREPARE_FLAGS='+bcmath +ctype +curl +fileinfo +filter +iconv +mbstring +openssl +pcntl +pdo_mysql +phar +posix +redis +sockets +sodium +swoole +tokenizer +xml +zip +zlib -bz2 -exif -gd -gettext -gmp -imagick -intl -mongodb -mysqli -opcache -readline -session -soap -sqlite3 -xlswriter -xsl -yaml'
PREPARE_FLAGS=${PHPSFX_SWOOLE_CLI_PREPARE_FLAGS:-${DEFAULT_PREPARE_FLAGS}}
EXPECTED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS:-swoole,redis,pdo_mysql,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,fileinfo,bcmath,sodium,sockets}
FORBIDDEN_EXTENSIONS=${PHPSFX_FORBIDDEN_EXTENSIONS:-bz2,exif,gd,gettext,gmp,imagick,intl,mongodb,mysqli,readline,session,soap,sqlite3,xlswriter,xsl,yaml,opcache}
DOWNLOAD_MIRROR_URL=${PHPSFX_DOWNLOAD_MIRROR_URL:-}

usage() {
  cat <<'USAGE'
Usage: scripts/build-swoole-cli.sh [platform]

Platforms:
  linux-x64, linux-a64, macos-x64, macos-a64

Important environment variables:
  PHPSFX_PHP_VERSION                 PHP version prefix used for asset name and validation, default: 8.4
  PHPSFX_SWOOLE_CLI_REPO             Swoole CLI git repository, default: https://github.com/swoole/swoole-cli.git
  PHPSFX_SWOOLE_CLI_REF              Swoole CLI branch, tag, or commit, default: v6.2.0.0
  PHPSFX_SWOOLE_CLI_PREPARE_FLAGS    Space-separated prepare.php flags, e.g. '+redis -mongodb'
  PHPSFX_REQUIRED_EXTENSIONS         Comma-separated runtime extensions checked after build
  PHPSFX_FORBIDDEN_EXTENSIONS        Comma-separated extensions that must not be loaded
  PHPSFX_ALLOW_EXTRA_EXTENSIONS      Set to 1 to skip forbidden-extension checks for local full-runtime smoke
  PHPSFX_PROFILE_FILE                Profile env file, default: scripts/profiles/hyperfadmin-slim.env
  PHPSFX_DOWNLOAD_MIRROR_URL         Optional Swoole CLI dependency mirror URL passed to prepare.php
  PHPSFX_DIST_DIR                    Output directory, default: ./dist
  PHPSFX_SWOOLE_CLI_DIR              Swoole CLI checkout dir, default: ./.build/swoole-cli
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

retry_command() {
  local max=${PHPSFX_RETRY_TIMES:-3}
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= max )); then
      return 1
    fi
    echo "Command failed, retry ${attempt}/${max}: $*" >&2
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
  done
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

download_swoole_cli_archive() {
  local tmp_dir archive_url archive_file
  tmp_dir="${SWOOLE_CLI_DIR}.archive.$$"
  archive_file="${ROOT_DIR}/.build/swoole-cli-${SWOOLE_CLI_REF//[^A-Za-z0-9._-]/_}.tar.gz"
  archive_url="https://codeload.github.com/swoole/swoole-cli/tar.gz/${SWOOLE_CLI_REF}"

  require_command curl
  rm -rf "${tmp_dir}"
  mkdir -p "${tmp_dir}" "$(dirname "${archive_file}")"
  echo "Git clone failed or unavailable, fallback to archive: ${archive_url}" >&2
  retry_command curl -fL --retry 3 --retry-delay 2 -o "${archive_file}" "${archive_url}"
  tar -xzf "${archive_file}" -C "${tmp_dir}" --strip-components=1
  rm -rf "${SWOOLE_CLI_DIR}"
  mv "${tmp_dir}" "${SWOOLE_CLI_DIR}"
}

checkout_swoole_cli() {
  mkdir -p "${DIST_DIR}" "$(dirname "${SWOOLE_CLI_DIR}")"
  if [[ ! -d "${SWOOLE_CLI_DIR}/.git" && ! -f "${SWOOLE_CLI_DIR}/prepare.php" ]]; then
    rm -rf "${SWOOLE_CLI_DIR}"
    if ! retry_command git clone --filter=blob:none "${SWOOLE_CLI_REPO}" "${SWOOLE_CLI_DIR}"; then
      download_swoole_cli_archive
    fi
  fi

  cd "${SWOOLE_CLI_DIR}"
  if [[ -d .git ]]; then
    if retry_command git fetch --force --depth=1 origin "${SWOOLE_CLI_REF}"; then
      git checkout --force FETCH_HEAD
    else
      retry_command git fetch --force --tags origin
      git checkout --force "${SWOOLE_CLI_REF}"
    fi
  fi

  # 清理上一次构建输出，但保留 pool/ 下载缓存，方便本地和 CI cache 复用依赖源码。
  rm -f make.sh
  rm -rf bin/swoole-cli bin/dist thirdparty var/php-* modules libs libphp.la
}

assert_target_php_version() {
  local upstream_php_version
  upstream_php_version=$(tr -d '[:space:]' < sapi/PHP-VERSION.conf)
  if [[ "${upstream_php_version}" != "${PHP_VERSION}."* ]]; then
    cat >&2 <<ERROR
Swoole CLI ref ${SWOOLE_CLI_REF} targets PHP ${upstream_php_version}, not PHP ${PHP_VERSION}.x.
Please choose a matching PHPSFX_SWOOLE_CLI_REF or set PHPSFX_PHP_VERSION=${upstream_php_version%.*}.
ERROR
    exit 1
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
require_command make
require_command tar

checkout_swoole_cli
if [[ -d .git ]]; then
  SWOOLE_CLI_COMMIT=$(git rev-parse HEAD)
else
  SWOOLE_CLI_COMMIT="${SWOOLE_CLI_REF} (archive)"
fi
assert_target_php_version

export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-interaction --no-progress --prefer-dist --no-dev --no-scripts --optimize-autoloader

# Swoole CLI 官方构建链路：prepare.php 生成 make.sh，随后依次构建依赖库、configure、build。
# prepare.php 支持 +extension/-extension 裁剪扩展；--without-docker 让工作目录固定为当前 checkout，适合 GitHub runner/WSL/macOS。
read -r -a PREPARE_ARGS <<< "${PREPARE_FLAGS}"
if [[ -n "${DOWNLOAD_MIRROR_URL}" ]]; then
  PREPARE_ARGS+=("--with-download-mirror-url=${DOWNLOAD_MIRROR_URL}")
fi
php prepare.php --without-docker=1 --with-parallel-jobs="${JOBS}" "${PREPARE_ARGS[@]}"

bash ./make.sh all-library
bash ./make.sh config
bash ./make.sh build

SWOOLE_CLI_BIN="${SWOOLE_CLI_DIR}/bin/swoole-cli"
if [[ ! -s "${SWOOLE_CLI_BIN}" ]]; then
  echo "swoole-cli was not generated: ${SWOOLE_CLI_BIN}" >&2
  exit 1
fi

ASSET_NAME="swoole-cli-php${PHP_VERSION}-${PLATFORM}"
cp "${SWOOLE_CLI_BIN}" "${DIST_DIR}/${ASSET_NAME}"
chmod +x "${DIST_DIR}/${ASSET_NAME}"

PHPSFX_EXPECTED_PHP_PREFIX="${PHP_VERSION}." \
PHPSFX_REQUIRED_EXTENSIONS="${EXPECTED_EXTENSIONS}" \
PHPSFX_FORBIDDEN_EXTENSIONS="${FORBIDDEN_EXTENSIONS}" \
  bash "${ROOT_DIR}/scripts/validate-swoole-cli.sh" "${DIST_DIR}/${ASSET_NAME}"

SHA256=$(sha256_file "${DIST_DIR}/${ASSET_NAME}")
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "${DIST_DIR}/build-meta-${PLATFORM}.json" <<META
{
  "platform": "${PLATFORM}",
  "asset": "${ASSET_NAME}",
  "profile": "${PROFILE_NAME}",
  "php_version": "${PHP_VERSION}",
  "extensions": "${PHPSFX_EXTENSIONS:-${DEFAULT_EXTENSIONS}}",
  "required_extensions": "${EXPECTED_EXTENSIONS}",
  "forbidden_extensions": "${FORBIDDEN_EXTENSIONS}",
  "swoole_cli_repo": "${SWOOLE_CLI_REPO}",
  "swoole_cli_ref": "${SWOOLE_CLI_REF}",
  "swoole_cli_commit": "${SWOOLE_CLI_COMMIT}",
  "prepare_flags": "${PREPARE_FLAGS}",
  "sha256": "${SHA256}",
  "built_at": "${BUILT_AT}"
}
META

printf 'Built %s\n' "${DIST_DIR}/${ASSET_NAME}"
printf 'SHA256 %s  %s\n' "${SHA256}" "${ASSET_NAME}"
