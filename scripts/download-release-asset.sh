#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/download-release-asset.sh <platform> [version] [output-file]

Examples:
  scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
  scripts/download-release-asset.sh linux-x64-odbc latest /tmp/swoole-cli-odbc
  scripts/download-release-asset.sh linux-a64 latest /tmp/swoole-cli-arm64
  scripts/download-release-asset.sh macos-a64-odbc v0.1.0 ./swoole-cli-odbc
  scripts/download-release-asset.sh macos-a64 v0.1.0 ./swoole-cli

Environment:
  PHPSFX_RELEASE_REPO       GitHub repo, default: zoujingli/phpsfx
  PHPSFX_PHP_VERSION        PHP version line, default: 8.4
  PHPSFX_ASSET_PREFIX       Release asset prefix, default: swoole-cli
USAGE
  exit 2
fi

PLATFORM=$1
VERSION=${2:-latest}
OUTPUT=${3:-}
REPO=${PHPSFX_RELEASE_REPO:-zoujingli/phpsfx}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.4}
ASSET_PREFIX=${PHPSFX_ASSET_PREFIX:-swoole-cli}

case "${PLATFORM}" in
  linux-x64|linux-x64-odbc|linux-a64|linux-a64-odbc|macos-x64|macos-x64-odbc|macos-a64|macos-a64-odbc) ;;
  *) echo "Unsupported platform: ${PLATFORM}" >&2; exit 2 ;;
esac

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
