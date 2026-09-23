#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/download-release-asset.sh <platform>[-<database-combination>][-odbc] [version] [output-file]

Examples:
  scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
  scripts/download-release-asset.sh linux-x64-pgsql-sqlite-odbc latest /tmp/swoole-cli-odbc
  scripts/download-release-asset.sh linux-a64-mysql-sqlite v6.2.3.1 /tmp/swoole-cli-arm64
  scripts/download-release-asset.sh linux-a64-sqlite v6.2.3.2 /tmp/swoole-cli-sqlite
  scripts/download-release-asset.sh macos-a64-odbc v6.2.3.0 ./swoole-cli-old-odbc

Environment:
  PHPSFX_RELEASE_REPO       GitHub repo, default: zoujingli/phpsfx
  PHPSFX_PHP_VERSION        PHP version line, default: 8.5
  PHPSFX_ASSET_PREFIX       Release asset prefix, default: swoole-cli
USAGE
  exit 2
fi

PLATFORM=$1
VERSION=${2:-latest}
OUTPUT=${3:-}
REPO=${PHPSFX_RELEASE_REPO:-zoujingli/phpsfx}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.5}
ASSET_PREFIX=${PHPSFX_ASSET_PREFIX:-swoole-cli}

if [[ "${PLATFORM}" =~ ^(linux-x64|linux-a64|macos-x64|macos-a64)(-(mysql-pgsql-sqlite|mysql-sqlite|pgsql-sqlite|mysql-pgsql|mysql|pgsql|sqlite))?(-odbc)?$ ]]; then
  database=${BASH_REMATCH[3]:-}
else
  echo "Unsupported platform or database combination: ${PLATFORM}" >&2
  exit 2
fi

asset_generation=0
if [[ "${VERSION}" == latest ]]; then
  asset_generation=2
elif [[ "${VERSION}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  patch=${BASH_REMATCH[3]}
  revision=${BASH_REMATCH[4]}
  if (( 10#${major} > 6 ||
        (10#${major} == 6 && 10#${minor} > 2) ||
        (10#${major} == 6 && 10#${minor} == 2 && 10#${patch} > 3) )); then
    asset_generation=2
  elif (( 10#${major} == 6 && 10#${minor} == 2 && 10#${patch} == 3 )); then
    if (( 10#${revision} >= 2 )); then
      asset_generation=2
    elif (( 10#${revision} == 1 )); then
      asset_generation=1
    fi
  fi
fi

if [[ "${asset_generation}" -eq 0 && -n "${database}" ]]; then
  echo "Version ${VERSION} does not have database-combination assets" >&2
  exit 2
fi
if [[ "${asset_generation}" -eq 1 ]]; then
  case "${database}" in
    sqlite|mysql|pgsql|mysql-pgsql)
      echo "Version ${VERSION} does not have the ${database} combination" >&2
      exit 2
      ;;
  esac
fi

if [[ "${asset_generation}" -gt 0 && -z "${database}" ]]; then
  if [[ "${PLATFORM}" == *-odbc ]]; then
    PLATFORM="${PLATFORM%-odbc}-mysql-pgsql-sqlite-odbc"
  else
    PLATFORM="${PLATFORM}-mysql-pgsql-sqlite"
  fi
fi

ASSET="${ASSET_PREFIX}-php${PHP_VERSION}-${PLATFORM}"
if [[ -z "${OUTPUT}" ]]; then
  OUTPUT="${ASSET}"
fi

if [[ "${VERSION}" == "latest" ]]; then
  URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
else
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
fi

mkdir -p "$(dirname "${OUTPUT}")"
curl -fL --retry 3 --retry-delay 2 -o "${OUTPUT}" "${URL}"
chmod +x "${OUTPUT}"
printf 'Downloaded %s -> %s\n' "${URL}" "${OUTPUT}"
