#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/test-dameng-odbc.sh <swoole-cli-dm-odbc>" >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SWOOLE_CLI=$1

if [[ ! -s "${SWOOLE_CLI}" ]]; then
  echo "Swoole CLI runtime does not exist or is empty" >&2
  exit 1
fi
if [[ -z "${PHPSFX_DM_ODBC_DSN:-}" ]]; then
  echo "PHPSFX_DM_ODBC_DSN is required" >&2
  exit 2
fi
if [[ "${PHPSFX_DM_ODBC_USER+x}" != x ]]; then
  echo "PHPSFX_DM_ODBC_USER must be set, even when the account name is empty" >&2
  exit 2
fi
if [[ "${PHPSFX_DM_ODBC_PASSWORD+x}" != x ]]; then
  echo "PHPSFX_DM_ODBC_PASSWORD must be set, even when the password is empty" >&2
  exit 2
fi
case "${PHPSFX_DM_ODBC_ALLOW_WRITE:-0}" in
  0|1) ;;
  *) echo "PHPSFX_DM_ODBC_ALLOW_WRITE must be 0 or 1" >&2; exit 2 ;;
esac

"${SWOOLE_CLI}" "${ROOT_DIR}/tests/dameng-odbc-smoke.php"
