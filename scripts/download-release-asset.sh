#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/download-release-asset.sh <platform> [version] [output-file]

Examples:
  scripts/download-release-asset.sh linux-x64 latest /tmp/micro.sfx
  scripts/download-release-asset.sh macos-a64 v0.0.5 ./micro.sfx
USAGE
  exit 2
fi

PLATFORM=$1
VERSION=${2:-latest}
OUTPUT=${3:-}
REPO=${PHPSFX_RELEASE_REPO:-zoujingli/phpsfx}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.4}

case "${PLATFORM}" in
  linux-x64|linux-a64|macos-x64|macos-a64) ;;
  *) echo "Unsupported platform: ${PLATFORM}" >&2; exit 2 ;;
esac

ASSET="micro.sfx-php${PHP_VERSION}-${PLATFORM}"
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
