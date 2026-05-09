#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/validate-micro-sfx.sh /path/to/micro.sfx" >&2
  exit 2
fi

MICRO_SFX=$1
if [[ ! -s "${MICRO_SFX}" ]]; then
  echo "micro.sfx does not exist or is empty: ${MICRO_SFX}" >&2
  exit 1
fi

chmod +x "${MICRO_SFX}"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

PAYLOAD="${TMP_DIR}/probe.php"
PROBE="${TMP_DIR}/probe"
cat > "${PAYLOAD}" <<'PHP'
<?php
$expectedPrefix = getenv('PHPSFX_EXPECTED_PHP_PREFIX') ?: '8.4.';
$required = array_values(array_filter(array_map('trim', explode(',', getenv('PHPSFX_REQUIRED_EXTENSIONS') ?: ''))));
$errors = [];

if (!str_starts_with(PHP_VERSION, $expectedPrefix)) {
    $errors[] = sprintf('PHP_VERSION %s does not start with %s', PHP_VERSION, $expectedPrefix);
}

if (PHP_SAPI !== 'cli') {
    $errors[] = sprintf('PHP_SAPI should be cli, got %s', PHP_SAPI);
}

$missing = [];
foreach ($required as $extension) {
    if (!extension_loaded($extension)) {
        $missing[] = $extension;
    }
}
if ($missing !== []) {
    $errors[] = 'Missing extensions: ' . implode(', ', $missing);
}

if (extension_loaded('swoole') && !defined('SWOOLE_VERSION')) {
    $errors[] = 'swoole extension is loaded but SWOOLE_VERSION is not defined';
}

$result = [
    'php_version' => PHP_VERSION,
    'php_sapi' => PHP_SAPI,
    'swoole_version' => defined('SWOOLE_VERSION') ? SWOOLE_VERSION : null,
    'required_extensions' => $required,
    'errors' => $errors,
];

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
exit($errors === [] ? 0 : 1);
PHP

cat "${MICRO_SFX}" "${PAYLOAD}" > "${PROBE}"
chmod +x "${PROBE}"
"${PROBE}"
