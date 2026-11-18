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

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/phpsfx-micro-validate.XXXXXX")
trap 'rm -rf "${TMP_DIR}"' EXIT

PROBE="${TMP_DIR}/probe.php"
PROBE_APP="${TMP_DIR}/probe"
cat > "${PROBE}" <<'PHP'
<?php

$expectedPrefix = getenv('PHPSFX_EXPECTED_PHP_PREFIX') ?: '8.5.';
$expectedVersion = trim(getenv('PHPSFX_EXPECTED_PHP_VERSION') ?: '');
$expectedSwooleVersion = ltrim(trim(getenv('PHPSFX_EXPECTED_SWOOLE_VERSION') ?: ''), 'vV');
$required = array_values(array_filter(array_map('trim', explode(',', getenv('PHPSFX_REQUIRED_EXTENSIONS') ?: ''))));
$forbidden = array_values(array_filter(array_map('trim', explode(',', getenv('PHPSFX_FORBIDDEN_EXTENSIONS') ?: ''))));
$requiredPdoDrivers = array_values(array_filter(array_map('trim', explode(',', getenv('PHPSFX_REQUIRED_PDO_DRIVERS') ?: ''))));
$expectSwooleOdbc = (getenv('PHPSFX_EXPECT_SWOOLE_ODBC') ?: '0') === '1';
$errors = [];

$isExtensionLoaded = static function (string $extension): bool {
    if (extension_loaded($extension)) {
        return true;
    }
    return strtolower($extension) === 'opcache' && extension_loaded('Zend OPcache');
};

if (!str_starts_with(PHP_VERSION, $expectedPrefix)) {
    $errors[] = sprintf('PHP_VERSION %s does not start with %s', PHP_VERSION, $expectedPrefix);
}
if ($expectedVersion !== '' && PHP_VERSION !== $expectedVersion) {
    $errors[] = sprintf('PHP_VERSION %s does not match %s', PHP_VERSION, $expectedVersion);
}
if (PHP_SAPI !== 'cli') {
    $errors[] = sprintf('PHP_SAPI should be cli, got %s', PHP_SAPI);
}
if (!function_exists('micro_get_self_filename')) {
    $errors[] = 'micro_get_self_filename is not available';
}
if (!class_exists('Phar')) {
    $errors[] = 'Phar is not available';
}

$missing = [];
foreach ($required as $extension) {
    if (!$isExtensionLoaded($extension)) {
        $missing[] = $extension;
    }
}
if ($missing !== []) {
    $errors[] = 'Missing extensions: ' . implode(',', $missing);
}

$unexpected = [];
foreach ($forbidden as $extension) {
    if ($isExtensionLoaded($extension)) {
        $unexpected[] = $extension;
    }
}
if ($unexpected !== []) {
    $errors[] = 'Unexpected extensions: ' . implode(',', $unexpected);
}

if (!extension_loaded('swoole') || !defined('SWOOLE_VERSION')) {
    $errors[] = 'swoole extension is not available';
} elseif ($expectedSwooleVersion !== '' && SWOOLE_VERSION !== $expectedSwooleVersion) {
    $errors[] = sprintf('SWOOLE_VERSION %s does not match %s', SWOOLE_VERSION, $expectedSwooleVersion);
}

$pdoDrivers = class_exists('PDO') ? PDO::getAvailableDrivers() : [];
sort($pdoDrivers);
$expectedPdoDrivers = $requiredPdoDrivers;
sort($expectedPdoDrivers);
if ($pdoDrivers !== $expectedPdoDrivers) {
    $errors[] = sprintf(
        'PDO drivers [%s] do not match [%s]',
        implode(',', $pdoDrivers),
        implode(',', $expectedPdoDrivers),
    );
}

ob_start();
phpinfo(INFO_MODULES);
$moduleInfo = (string) ob_get_clean();
$odbcHook = defined('SWOOLE_HOOK_PDO_ODBC') ? constant('SWOOLE_HOOK_PDO_ODBC') : 0;
$allHooks = defined('SWOOLE_HOOK_ALL') ? constant('SWOOLE_HOOK_ALL') : 0;
$odbc = [
    'expected' => $expectSwooleOdbc,
    'pdo_driver' => in_array('odbc', $pdoDrivers, true),
    'hook_constant' => $odbcHook !== 0,
    'hook_in_all' => $odbcHook !== 0 && ($allHooks & $odbcHook) === $odbcHook,
    'coroutine_feature' => preg_match('/coroutine_odbc\s*=>\s*enabled/', $moduleInfo) === 1,
];
if ($expectSwooleOdbc) {
    foreach (['pdo_driver', 'hook_constant', 'hook_in_all', 'coroutine_feature'] as $capability) {
        if (!$odbc[$capability]) {
            $errors[] = "Swoole ODBC capability is missing: {$capability}";
        }
    }
} elseif ($odbc['pdo_driver'] || $odbc['hook_constant'] || $odbc['coroutine_feature']) {
    $errors[] = 'ODBC capability is unexpectedly enabled';
}

$sqliteSmoke = null;
if (in_array('sqlite', $requiredPdoDrivers, true)) {
    try {
        $pdo = new PDO('sqlite::memory:');
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->exec('CREATE TABLE phpsfx_micro_check (name TEXT NOT NULL)');
        $pdo->exec("INSERT INTO phpsfx_micro_check (name) VALUES ('ok')");
        $sqliteSmoke = $pdo->query('SELECT name FROM phpsfx_micro_check')->fetchColumn() === 'ok';
        if (!$sqliteSmoke) {
            $errors[] = 'PDO SQLite smoke check returned an unexpected value';
        }
    } catch (Throwable $exception) {
        $sqliteSmoke = false;
        $errors[] = 'PDO SQLite smoke check failed: ' . $exception->getMessage();
    }
}

$result = [
    'php_version' => PHP_VERSION,
    'php_sapi' => PHP_SAPI,
    'micro_version' => function_exists('micro_version') ? micro_version() : null,
    'micro_self' => function_exists('micro_get_self_filename') ? micro_get_self_filename() : null,
    'micro_sfx_size' => function_exists('micro_get_sfxsize') ? micro_get_sfxsize() : null,
    'swoole_version' => defined('SWOOLE_VERSION') ? SWOOLE_VERSION : null,
    'swoole_cli' => defined('SWOOLE_CLI'),
    'required_extensions' => $required,
    'forbidden_extensions' => $forbidden,
    'pdo_drivers' => $pdoDrivers,
    'required_pdo_drivers' => $expectedPdoDrivers,
    'odbc' => $odbc,
    'sqlite_smoke' => $sqliteSmoke,
    'errors' => $errors,
];

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
exit($errors === [] ? 0 : 1);
PHP

cat "${MICRO_SFX}" "${PROBE}" > "${PROBE_APP}"
chmod +x "${PROBE_APP}"
PHPSFX_EXPECTED_PHP_PREFIX=${PHPSFX_EXPECTED_PHP_PREFIX:-8.5.} \
PHPSFX_EXPECTED_PHP_VERSION=${PHPSFX_EXPECTED_PHP_VERSION:-} \
PHPSFX_EXPECTED_SWOOLE_VERSION=${PHPSFX_EXPECTED_SWOOLE_VERSION:-} \
PHPSFX_REQUIRED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS:-swoole,redis,phar} \
PHPSFX_FORBIDDEN_EXTENSIONS=${PHPSFX_FORBIDDEN_EXTENSIONS:-opcache} \
PHPSFX_REQUIRED_PDO_DRIVERS=${PHPSFX_REQUIRED_PDO_DRIVERS:-} \
PHPSFX_EXPECT_SWOOLE_ODBC=${PHPSFX_EXPECT_SWOOLE_ODBC:-0} \
  "${PROBE_APP}"

PLATFORM=${PHPSFX_PLATFORM:-}
EXPECT_ODBC=${PHPSFX_EXPECT_SWOOLE_ODBC:-0}
if [[ "${EXPECT_ODBC}" == 1 ]]; then
  case "${PLATFORM}" in
    linux-*)
      command -v readelf >/dev/null 2>&1 || { echo 'readelf is required for Linux ODBC validation' >&2; exit 127; }
      if ! readelf -d "${MICRO_SFX}" | grep -q 'libodbc\.so'; then
        echo 'Linux micro ODBC binary does not dynamically depend on libodbc.so' >&2
        exit 1
      fi
      ;;
    macos-*)
      command -v otool >/dev/null 2>&1 || { echo 'otool is required for macOS ODBC validation' >&2; exit 127; }
      if ! otool -L "${MICRO_SFX}" | grep -q 'libodbc'; then
        echo 'macOS micro ODBC binary does not dynamically depend on libodbc' >&2
        exit 1
      fi
      ;;
  esac
else
  case "${PLATFORM}" in
    linux-*)
      if command -v readelf >/dev/null 2>&1 && readelf -d "${MICRO_SFX}" | grep -q 'libodbc\.so'; then
        echo 'Non-ODBC micro binary unexpectedly depends on libodbc.so' >&2
        exit 1
      fi
      ;;
    macos-*)
      if command -v otool >/dev/null 2>&1 && otool -L "${MICRO_SFX}" | grep -q 'libodbc'; then
        echo 'Non-ODBC micro binary unexpectedly depends on libodbc' >&2
        exit 1
      fi
      ;;
  esac
fi

printf 'Validated micro.sfx: %s\n' "${MICRO_SFX}"
