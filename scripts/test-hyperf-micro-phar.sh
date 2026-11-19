#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/test-hyperf-micro-phar.sh <micro.sfx>" >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MICRO_SFX=$1
FIXTURE_DIR=${PHPSFX_HYPERF_FIXTURE_DIR:-"${ROOT_DIR}/tests/hyperf-smoke"}
EXPECTED_SWOOLE_VERSION=${PHPSFX_EXPECTED_SWOOLE_VERSION:-}
PORT=${PHPSFX_HYPERF_SMOKE_PORT:-$((20000 + RANDOM % 20000))}

[[ -s "${MICRO_SFX}" ]] || { echo "micro.sfx does not exist or is empty: ${MICRO_SFX}" >&2; exit 1; }
[[ -f "${FIXTURE_DIR}/vendor/autoload.php" ]] || {
  echo "Hyperf smoke dependencies are not installed; run composer install --working-dir=${FIXTURE_DIR}" >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || { echo 'Required command not found: curl' >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo 'Required command not found: python3' >&2; exit 127; }

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/phpsfx-hyperf-micro.XXXXXX")
LOG_FILE="${TMP_DIR}/server.log"
RESPONSE_FILE="${TMP_DIR}/response.json"
BASE_PATH="${TMP_DIR}/app"
PHAR_PATH="${TMP_DIR}/hyperf.phar"
if [[ "${PHPSFX_PLATFORM:-}" == windows-* ]]; then
  APP_PATH="${TMP_DIR}/hyperf.exe"
else
  APP_PATH="${TMP_DIR}/hyperf"
fi
SERVER_PID=
ODBC_DB_FILE=

cleanup() {
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT INT TERM

mkdir -p "${BASE_PATH}/config" "${BASE_PATH}/runtime"
cp -R "${FIXTURE_DIR}/config/." "${BASE_PATH}/config/"
cp "${FIXTURE_DIR}/composer.json" "${BASE_PATH}/composer.json"
cp "${FIXTURE_DIR}/composer.lock" "${BASE_PATH}/composer.lock"

cat > "${TMP_DIR}/make-phar.php" <<'PHP'
<?php
$source = $argv[1];
$target = $argv[2];
@unlink($target);
$phar = new Phar($target);
$phar->startBuffering();
$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($source, FilesystemIterator::SKIP_DOTS),
);
foreach ($iterator as $file) {
    if (!$file->isFile()) {
        continue;
    }
    $relative = substr($file->getPathname(), strlen($source) + 1);
    if ($relative === '' || str_starts_with($relative, 'runtime/') || str_starts_with($relative, '.git/')) {
        continue;
    }
    $phar->addFile($file->getPathname(), $relative);
}
$phar->setStub(<<<'STUB'
<?php
$self = function_exists('micro_get_self_filename') ? micro_get_self_filename() : __FILE__;
$basePath = getenv('PHPSFX_HYPERF_BASE_PATH') ?: dirname($self);
defined('BASE_PATH') || define('BASE_PATH', $basePath);
defined('SWOOLE_HOOK_FLAGS') || define('SWOOLE_HOOK_FLAGS', SWOOLE_HOOK_ALL);
Phar::mapPhar('micro-hyperf.phar');
require 'phar://micro-hyperf.phar/vendor/autoload.php';

\Hyperf\Di\ClassLoader::init();
$container = require BASE_PATH . '/config/container.php';
$pending = array_keys(require 'phar://micro-hyperf.phar/vendor/composer/autoload_classmap.php');
for ($round = 0; $round < 20 && $pending !== []; ++$round) {
    $next = [];
    foreach ($pending as $className) {
        try {
            class_exists($className);
        } catch (Throwable) {
            $next[] = $className;
        }
    }
    if (count($next) === count($pending)) {
        break;
    }
    $pending = $next;
}
$container->get(\Hyperf\Contract\ApplicationInterface::class)->run();
__HALT_COMPILER();
STUB
);
$phar->stopBuffering();
PHP

php -d phar.readonly=0 "${TMP_DIR}/make-phar.php" "${FIXTURE_DIR}" "${PHAR_PATH}"
bash "${ROOT_DIR}/scripts/pack-micro-phar.sh" "${MICRO_SFX}" "${PHAR_PATH}" "${APP_PATH}"

ODBC_DSN=${PHPSFX_ODBC_SMOKE_DSN:-}
if [[ -z "${ODBC_DSN}" && -n "${PHPSFX_ODBC_SMOKE_DRIVER:-}" ]]; then
  ODBC_DB_FILE="${TMP_DIR}/odbc.sqlite"
  ODBC_DSN="odbc:Driver=${PHPSFX_ODBC_SMOKE_DRIVER};Database=${ODBC_DB_FILE}"
fi

PHPSFX_HYPERF_BASE_PATH="${BASE_PATH}" \
PHPSFX_HYPERF_SMOKE_PORT="${PORT}" \
PHPSFX_ODBC_SMOKE_DSN="${ODBC_DSN}" \
PHPSFX_ODBC_SMOKE_USER="${PHPSFX_ODBC_SMOKE_USER:-}" \
PHPSFX_ODBC_SMOKE_PASSWORD="${PHPSFX_ODBC_SMOKE_PASSWORD:-}" \
  "${APP_PATH}" start >"${LOG_FILE}" 2>&1 &
SERVER_PID=$!

for ((attempt = 1; attempt <= 60; attempt++)); do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo 'Hyperf micro Phar server exited before becoming ready' >&2
    tail -240 "${LOG_FILE}" | strings | tail -120 >&2 || true
    exit 1
  fi
  if curl --fail --silent --show-error --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${PORT}/health" --output "${RESPONSE_FILE}" 2>/dev/null; then
    break
  fi
  sleep 1
done

[[ -s "${RESPONSE_FILE}" ]] || {
  echo "Hyperf micro Phar server did not become ready on port ${PORT}" >&2
  tail -240 "${LOG_FILE}" | strings | tail -120 >&2 || true
  exit 1
}

PHPSFX_EXPECTED_SWOOLE_VERSION="${EXPECTED_SWOOLE_VERSION}" \
PHPSFX_EXPECT_ODBC_SMOKE="$([[ -n "${ODBC_DSN}" ]] && printf 1 || printf 0)" \
PHPSFX_EXPECT_SQLITE_SMOKE="$([[ "${PHPSFX_DB_VARIANT:-mysql}" == *sqlite* ]] && printf 1 || printf 0)" \
  python3 - "${RESPONSE_FILE}" <<'PY'
import json
import os
import sys

payload = json.load(open(sys.argv[1], encoding='utf-8'))
errors = []
expected_version = os.environ.get('PHPSFX_EXPECTED_SWOOLE_VERSION', '').lstrip('vV')
if payload.get('status') != 'ok':
    errors.append('health status is not ok')
if expected_version and payload.get('swoole_version') != expected_version:
    errors.append(f"Swoole version {payload.get('swoole_version')} does not match {expected_version}")
if (payload.get('coroutine_id') or -1) <= 0:
    errors.append('request did not run in a coroutine')
if os.environ.get('PHPSFX_EXPECT_SQLITE_SMOKE') == '1' and payload.get('pdo_sqlite') != 'ok':
    errors.append('PDO SQLite smoke query failed')
if os.environ.get('PHPSFX_EXPECT_ODBC_SMOKE') == '1':
    odbc = payload.get('pdo_odbc') or {}
    if odbc.get('driver') != 'odbc':
        errors.append('PDO ODBC driver name is invalid')
    if odbc.get('value') != '标准-ODBC':
        errors.append('PDO ODBC Unicode query failed')
    if odbc.get('rollback_count') != 1:
        errors.append('PDO ODBC rollback check failed')
    if odbc.get('commit_count') != 2:
        errors.append('PDO ODBC commit check failed')
    if odbc.get('concurrent_values') != ['标准-ODBC', '标准-ODBC']:
        errors.append('PDO ODBC concurrent query check failed')
print(json.dumps(payload, ensure_ascii=False, indent=2))
if errors:
    raise SystemExit('\n'.join(errors))
PY

printf 'Hyperf 3.2 micro Phar smoke passed for %s\n' "${MICRO_SFX}"
