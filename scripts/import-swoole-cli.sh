#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/import-swoole-cli.sh [platform] <swoole-cli-binary>

Import an already built Swoole CLI runtime into dist/ using the same phpsfx asset naming,
then validate it and generate build-meta-<platform>.json. This is intended for local smoke
tests against the recommended upstream release when the runtime is already installed.

Environment:
  PHPSFX_SWOOLE_CLI_REF     Swoole CLI baseline commit recorded in metadata, default: f7903840c3e959612dac7d413205e1bdb0067029
  PHPSFX_SWOOLE_SRC_REF     swoole-src ref recorded in metadata, default: v6.2.3
  PHPSFX_EXPECTED_SWOOLE_VERSION Exact runtime Swoole version; inferred from numeric source tags
USAGE
  exit 2
fi

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

if [[ $# -eq 1 ]]; then
  PLATFORM=${PHPSFX_PLATFORM:-linux-x64}
  SOURCE_BIN=$1
else
  PLATFORM=$1
  SOURCE_BIN=$2
fi

PHP_VERSION=${PHPSFX_PHP_VERSION:-8.5}
PHP_FULL_VERSION=${PHPSFX_PHP_FULL_VERSION:-8.5.9}
SWOOLE_CLI_REF=${PHPSFX_SWOOLE_CLI_REF:-f7903840c3e959612dac7d413205e1bdb0067029}
SWOOLE_SRC_REF=${PHPSFX_SWOOLE_SRC_REF:-v6.2.3}
if [[ "${SWOOLE_SRC_REF}" =~ ^[0-9]+(\.[0-9]+)+([._-].*)?$ ]]; then
  SWOOLE_SRC_REF="v${SWOOLE_SRC_REF}"
fi
EXPECTED_SWOOLE_VERSION=${PHPSFX_EXPECTED_SWOOLE_VERSION:-}
if [[ -z "${EXPECTED_SWOOLE_VERSION}" && "${SWOOLE_SRC_REF}" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  EXPECTED_SWOOLE_VERSION=${BASH_REMATCH[1]}
fi
DIST_DIR=${PHPSFX_DIST_DIR:-"${ROOT_DIR}/dist"}
PROFILE_NAME=${PHPSFX_PROFILE_NAME:-hyperfadmin-slim}
EXPECTED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS:-swoole,redis,pdo_mysql,pdo_pgsql,pdo_sqlite,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,fileinfo,bcmath,bz2,gd,opcache,sodium,sockets}
FORBIDDEN_EXTENSIONS=${PHPSFX_FORBIDDEN_EXTENSIONS:-exif,gettext,gmp,imagick,intl,mongodb,mysqli,pgsql,readline,session,soap,sqlite3,xlswriter,xsl,yaml}
REQUIRED_PDO_DRIVERS=${PHPSFX_REQUIRED_PDO_DRIVERS:-mysql,pgsql,sqlite}
DEFAULT_EXTENSIONS='bcmath,bz2,ctype,curl,dom,fileinfo,filter,gd,iconv,mbstring,opcache,openssl,pcntl,pdo_mysql,pdo_pgsql,pdo_sqlite,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib'

case "${PLATFORM}" in
  linux-x64|linux-a64|macos-x64|macos-a64) ;;
  *) echo "Unsupported platform: ${PLATFORM}" >&2; exit 2 ;;
esac

if [[ ! -s "${SOURCE_BIN}" ]]; then
  echo "Swoole CLI binary does not exist or is empty: ${SOURCE_BIN}" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
else
  sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

mkdir -p "${DIST_DIR}"
ASSET_NAME="swoole-cli-php${PHP_VERSION}-${PLATFORM}"
cp "${SOURCE_BIN}" "${DIST_DIR}/${ASSET_NAME}"
chmod +x "${DIST_DIR}/${ASSET_NAME}"

PHPSFX_EXPECTED_PHP_PREFIX="${PHP_VERSION}." \
PHPSFX_EXPECTED_PHP_VERSION="${PHP_FULL_VERSION}" \
PHPSFX_EXPECTED_SWOOLE_VERSION="${EXPECTED_SWOOLE_VERSION}" \
PHPSFX_REQUIRED_EXTENSIONS="${EXPECTED_EXTENSIONS}" \
PHPSFX_FORBIDDEN_EXTENSIONS="${FORBIDDEN_EXTENSIONS}" \
PHPSFX_REQUIRED_PDO_DRIVERS="${REQUIRED_PDO_DRIVERS}" \
  bash "${ROOT_DIR}/scripts/validate-swoole-cli.sh" "${DIST_DIR}/${ASSET_NAME}"

PHP_FULL_VERSION=$("${DIST_DIR}/${ASSET_NAME}" -r 'echo PHP_VERSION;')
SWOOLE_VERSION=$("${DIST_DIR}/${ASSET_NAME}" -r 'echo defined("SWOOLE_VERSION") ? SWOOLE_VERSION : "";')
SHA256=$(sha256_file "${DIST_DIR}/${ASSET_NAME}")
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "${DIST_DIR}/build-meta-${PLATFORM}.json" <<META
{
  "platform": "${PLATFORM}",
  "asset": "${ASSET_NAME}",
  "profile": "${PROFILE_NAME}",
  "cli_version": "${PHPSFX_RELEASE_VERSION:-v6.2.3.0}",
  "php_version": "${PHP_VERSION}",
  "php_full_version": "${PHP_FULL_VERSION}",
  "swoole_version": "${SWOOLE_VERSION}",
  "extensions": "${PHPSFX_EXTENSIONS:-${DEFAULT_EXTENSIONS}}",
  "required_extensions": "${EXPECTED_EXTENSIONS}",
  "required_pdo_drivers": "${REQUIRED_PDO_DRIVERS}",
  "forbidden_extensions": "${FORBIDDEN_EXTENSIONS}",
  "swoole_cli_repo": "https://github.com/swoole/swoole-cli.git",
  "swoole_cli_ref": "${SWOOLE_CLI_REF}",
  "swoole_src_ref": "${SWOOLE_SRC_REF}",
  "swoole_cli_commit": "prebuilt-local",
  "upstream_baseline_commit": "${SWOOLE_CLI_REF}",
  "prepare_flags": "prebuilt-local",
  "source_binary": "${SOURCE_BIN}",
  "sha256": "${SHA256}",
  "built_at": "${BUILT_AT}"
}
META

(
  cd "${DIST_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum swoole-cli-php"${PHP_VERSION}"-* > SHA256SUMS
  else
    shasum -a 256 swoole-cli-php"${PHP_VERSION}"-* > SHA256SUMS
  fi
)
PHPSFX_RELEASE_VERSION=${PHPSFX_RELEASE_VERSION:-local-smoke} \
PHPSFX_PHP_VERSION="${PHP_VERSION}" \
PHPSFX_SWOOLE_CLI_REF="${SWOOLE_CLI_REF}" \
  python3 "${ROOT_DIR}/scripts/merge-build-meta.py" "${DIST_DIR}" "${DIST_DIR}/build-meta.json"

printf 'Imported %s -> %s\n' "${SOURCE_BIN}" "${DIST_DIR}/${ASSET_NAME}"
