#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/test-hyperf-smoke.sh <swoole-cli>" >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_DIR="${ROOT_DIR}/tests/hyperf-smoke"
SWOOLE_CLI=$1
PORT=${PHPSFX_HYPERF_SMOKE_PORT:-$((20000 + RANDOM % 20000))}
EXPECTED_SWOOLE_VERSION=${PHPSFX_EXPECTED_SWOOLE_VERSION:-}
if [[ -z "${EXPECTED_SWOOLE_VERSION}" && "${PHPSFX_SWOOLE_SRC_REF:-}" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  EXPECTED_SWOOLE_VERSION=${BASH_REMATCH[1]}
fi

if [[ ! -s "${SWOOLE_CLI}" ]]; then
  echo "swoole-cli does not exist or is empty: ${SWOOLE_CLI}" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Required command not found: curl" >&2
  exit 127
fi
if [[ ! -f "${FIXTURE_DIR}/vendor/autoload.php" ]]; then
  echo "Hyperf smoke dependencies are not installed; run composer install --working-dir=${FIXTURE_DIR}" >&2
  exit 1
fi

LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/phpsfx-hyperf-smoke-log.XXXXXX")
RESPONSE_FILE=$(mktemp "${TMPDIR:-/tmp}/phpsfx-hyperf-smoke-response.XXXXXX")
SERVER_PID=

cleanup() {
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -f "${LOG_FILE}" "${RESPONSE_FILE}"
}
trap cleanup EXIT INT TERM

mkdir -p "${FIXTURE_DIR}/runtime"
PHPSFX_HYPERF_SMOKE_PORT="${PORT}" \
  "${SWOOLE_CLI}" "${FIXTURE_DIR}/bin/hyperf.php" start >"${LOG_FILE}" 2>&1 &
SERVER_PID=$!

for ((attempt = 1; attempt <= 60; attempt++)); do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Hyperf smoke server exited before becoming ready" >&2
    cat "${LOG_FILE}" >&2
    exit 1
  fi
  if curl --fail --silent --show-error --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${PORT}/health" --output "${RESPONSE_FILE}" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [[ ! -s "${RESPONSE_FILE}" ]]; then
  echo "Hyperf smoke server did not become ready on port ${PORT}" >&2
  cat "${LOG_FILE}" >&2
  exit 1
fi

PHPSFX_EXPECTED_SWOOLE_VERSION="${EXPECTED_SWOOLE_VERSION}" \
  "${SWOOLE_CLI}" -r '
$response = json_decode(file_get_contents($argv[1]), true, flags: JSON_THROW_ON_ERROR);
$expectedVersion = ltrim(trim(getenv("PHPSFX_EXPECTED_SWOOLE_VERSION") ?: ""), "vV");
$errors = [];
if (($response["status"] ?? null) !== "ok") {
    $errors[] = "health status is not ok";
}
if ($expectedVersion !== "" && ($response["swoole_version"] ?? null) !== $expectedVersion) {
    $errors[] = sprintf("Swoole version %s does not match %s", $response["swoole_version"] ?? "missing", $expectedVersion);
}
if (($response["coroutine_id"] ?? -1) <= 0) {
    $errors[] = "request did not run in a coroutine";
}
if (($response["pdo_sqlite"] ?? null) !== "ok") {
    $errors[] = "PDO SQLite smoke query failed";
}
echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
if ($errors !== []) {
    fwrite(STDERR, implode(PHP_EOL, $errors) . PHP_EOL);
    exit(1);
}
' "${RESPONSE_FILE}"

printf 'Hyperf 3.2 runtime smoke passed for %s\n' "${SWOOLE_CLI}"
