#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/import-swoole-cli.sh [platform] <swoole-cli-binary>

Import an already built Swoole CLI runtime into dist/ using the same phpsfx asset naming,
then validate it and generate build-meta-<platform>-<combination>.json. This is intended for local smoke
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
DB_VARIANT=${PHPSFX_DB_VARIANT:-mysql-pgsql-sqlite}
ASSET_SUFFIX=${PHPSFX_ASSET_SUFFIX:-${DB_VARIANT}}
SWOOLE_ODBC_ENABLED=${PHPSFX_SWOOLE_ODBC:-0}
EXPECTED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS:-swoole,redis,pdo_mysql,pdo_pgsql,pdo_sqlite,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,fileinfo,bcmath,bz2,gd,opcache,sodium,sockets}
FORBIDDEN_EXTENSIONS=${PHPSFX_FORBIDDEN_EXTENSIONS:-exif,gettext,gmp,imagick,intl,mongodb,mysqli,pgsql,readline,session,soap,sqlite3,xlswriter,xsl,yaml}
REQUIRED_PDO_DRIVERS=${PHPSFX_REQUIRED_PDO_DRIVERS:-mysql,pgsql,sqlite}
DEFAULT_EXTENSIONS='bcmath,bz2,ctype,curl,dom,fileinfo,filter,gd,iconv,mbstring,opcache,openssl,pcntl,pdo_mysql,pdo_pgsql,pdo_sqlite,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib'

case "${PLATFORM}" in
  linux-x64|linux-a64|macos-x64|macos-a64) ;;
  *) echo "Unsupported platform: ${PLATFORM}" >&2; exit 2 ;;
esac
if [[ ! "${ASSET_SUFFIX}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "PHPSFX_ASSET_SUFFIX must contain only lowercase letters, digits, and hyphens" >&2
  exit 2
fi
case "${SWOOLE_ODBC_ENABLED}" in
  0|1) ;;
  *) echo "PHPSFX_SWOOLE_ODBC must be 0 or 1" >&2; exit 2 ;;
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
VARIANT="${PLATFORM}-${ASSET_SUFFIX}"
ASSET_NAME="swoole-cli-php${PHP_VERSION}-${VARIANT}"
cp "${SOURCE_BIN}" "${DIST_DIR}/${ASSET_NAME}"
chmod +x "${DIST_DIR}/${ASSET_NAME}"

PHPSFX_EXPECTED_PHP_PREFIX="${PHP_VERSION}." \
PHPSFX_EXPECTED_PHP_VERSION="${PHP_FULL_VERSION}" \
PHPSFX_EXPECTED_SWOOLE_VERSION="${EXPECTED_SWOOLE_VERSION}" \
PHPSFX_REQUIRED_EXTENSIONS="${EXPECTED_EXTENSIONS}" \
PHPSFX_FORBIDDEN_EXTENSIONS="${FORBIDDEN_EXTENSIONS}" \
PHPSFX_REQUIRED_PDO_DRIVERS="${REQUIRED_PDO_DRIVERS}" \
PHPSFX_EXPECT_SWOOLE_ODBC="${SWOOLE_ODBC_ENABLED}" \
  bash "${ROOT_DIR}/scripts/validate-swoole-cli.sh" "${DIST_DIR}/${ASSET_NAME}"

ODBC_DYNAMIC_DEPENDENCY=
if [[ "${PLATFORM}" == linux-* ]]; then
  ODBC_DYNAMIC_DEPENDENCY=$(readelf -d "${DIST_DIR}/${ASSET_NAME}" \
    | sed -n 's/.*Shared library: \[\(libodbc\.so[^]]*\)\].*/\1/p' | head -1)
  expected_odbc_dependency=libodbc.so.2
else
  ODBC_DYNAMIC_DEPENDENCY=$(otool -L "${DIST_DIR}/${ASSET_NAME}" \
    | awk '/libodbc(\.[0-9]+)*\.dylib/ { dependency = $1; sub(/^.*\//, "", dependency); print dependency; exit }')
  expected_odbc_dependency=libodbc.2.dylib
fi
if [[ "${SWOOLE_ODBC_ENABLED}" == 1 && "${ODBC_DYNAMIC_DEPENDENCY}" != "${expected_odbc_dependency}" ]] ||
   [[ "${SWOOLE_ODBC_ENABLED}" == 0 && -n "${ODBC_DYNAMIC_DEPENDENCY}" ]]; then
  echo "Unexpected unixODBC runtime dependency: ${ODBC_DYNAMIC_DEPENDENCY:-none}" >&2
  exit 1
fi

PHP_FULL_VERSION=$("${DIST_DIR}/${ASSET_NAME}" -r 'echo PHP_VERSION;')
SWOOLE_VERSION=$("${DIST_DIR}/${ASSET_NAME}" -r 'echo defined("SWOOLE_VERSION") ? SWOOLE_VERSION : "";')
SHA256=$(sha256_file "${DIST_DIR}/${ASSET_NAME}")
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ "${SWOOLE_ODBC_ENABLED}" == 1 ]]; then
  SWOOLE_ODBC_JSON=true
else
  SWOOLE_ODBC_JSON=false
fi
cat > "${DIST_DIR}/build-meta-${VARIANT}.json" <<META
{
  "platform": "${PLATFORM}",
  "variant": "${VARIANT}",
  "asset": "${ASSET_NAME}",
  "profile": "${PROFILE_NAME}",
  "database_variant": "${DB_VARIANT}",
  "cli_version": "${PHPSFX_RELEASE_VERSION:-v6.2.3.1}",
  "php_version": "${PHP_VERSION}",
  "php_full_version": "${PHP_FULL_VERSION}",
  "swoole_version": "${SWOOLE_VERSION}",
  "extensions": "${PHPSFX_EXTENSIONS:-${DEFAULT_EXTENSIONS}}",
  "required_extensions": "${EXPECTED_EXTENSIONS}",
  "required_pdo_drivers": "${REQUIRED_PDO_DRIVERS}",
  "forbidden_extensions": "${FORBIDDEN_EXTENSIONS}",
  "swoole_odbc": ${SWOOLE_ODBC_JSON},
  "odbc_dynamic_dependency": "${ODBC_DYNAMIC_DEPENDENCY}",
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
