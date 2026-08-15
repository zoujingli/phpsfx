#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/validate-swoole-cli.sh /path/to/swoole-cli" >&2
  exit 2
fi

SWOOLE_CLI=$1
if [[ ! -s "${SWOOLE_CLI}" ]]; then
  echo "swoole-cli does not exist or is empty: ${SWOOLE_CLI}" >&2
  exit 1
fi

chmod +x "${SWOOLE_CLI}"
"${SWOOLE_CLI}" -r '
$expectedPrefix = getenv("PHPSFX_EXPECTED_PHP_PREFIX") ?: "8.4.";
$expectedSwooleVersion = ltrim(trim(getenv("PHPSFX_EXPECTED_SWOOLE_VERSION") ?: ""), "vV");
$required = array_values(array_filter(array_map("trim", explode(",", getenv("PHPSFX_REQUIRED_EXTENSIONS") ?: ""))));
$forbidden = array_values(array_filter(array_map("trim", explode(",", getenv("PHPSFX_FORBIDDEN_EXTENSIONS") ?: ""))));
$allowExtra = filter_var(getenv("PHPSFX_ALLOW_EXTRA_EXTENSIONS") ?: "0", FILTER_VALIDATE_BOOL);
$expectSwooleOdbc = (getenv("PHPSFX_EXPECT_SWOOLE_ODBC") ?: "0") === "1";
$errors = [];

if (!str_starts_with(PHP_VERSION, $expectedPrefix)) {
    $errors[] = sprintf("PHP_VERSION %s does not start with %s", PHP_VERSION, $expectedPrefix);
}

if (PHP_SAPI !== "cli") {
    $errors[] = sprintf("PHP_SAPI should be cli, got %s", PHP_SAPI);
}

if (!defined("SWOOLE_CLI")) {
    $errors[] = "SWOOLE_CLI constant is not defined; this is not a Swoole CLI runtime";
}

$missing = [];
foreach ($required as $extension) {
    if (!extension_loaded($extension)) {
        $missing[] = $extension;
    }
}
if ($missing !== []) {
    $errors[] = "Missing extensions: " . implode(", ", $missing);
}

$unexpected = [];
if (!$allowExtra) {
    foreach ($forbidden as $extension) {
        if (extension_loaded($extension)) {
            $unexpected[] = $extension;
        }
    }
}
if ($unexpected !== []) {
    $errors[] = "Unexpected extensions in slim runtime: " . implode(", ", $unexpected);
}

if (!extension_loaded("swoole") || !defined("SWOOLE_VERSION")) {
    $errors[] = "swoole extension is not available";
} elseif ($expectedSwooleVersion !== "" && SWOOLE_VERSION !== $expectedSwooleVersion) {
    $errors[] = sprintf("SWOOLE_VERSION %s does not match %s", SWOOLE_VERSION, $expectedSwooleVersion);
}

ob_start();
phpinfo(INFO_MODULES);
$moduleInfo = (string) ob_get_clean();
$pdoDrivers = class_exists("PDO") ? PDO::getAvailableDrivers() : [];
$odbcHook = defined("SWOOLE_HOOK_PDO_ODBC") ? constant("SWOOLE_HOOK_PDO_ODBC") : 0;
$allHooks = defined("SWOOLE_HOOK_ALL") ? constant("SWOOLE_HOOK_ALL") : 0;
$odbcSmoke = [
    "expected" => $expectSwooleOdbc,
    "pdo_driver" => in_array("odbc", $pdoDrivers, true),
    "hook_constant" => $odbcHook !== 0,
    "hook_in_all" => $odbcHook !== 0 && ($allHooks & $odbcHook) === $odbcHook,
    "coroutine_feature" => preg_match("/coroutine_odbc\\s*=>\\s*enabled/", $moduleInfo) === 1,
];

if ($expectSwooleOdbc) {
    foreach (["pdo_driver", "hook_constant", "hook_in_all", "coroutine_feature"] as $capability) {
        if (!$odbcSmoke[$capability]) {
            $errors[] = sprintf("Swoole ODBC capability is missing: %s", $capability);
        }
    }
}

$sqliteSmoke = [
    "sqlite3_class" => class_exists("SQLite3"),
    "sqlite3_memory" => null,
    "pdo_sqlite_driver" => class_exists("PDO") ? in_array("sqlite", PDO::getAvailableDrivers(), true) : false,
    "pdo_sqlite_memory" => null,
];

if (in_array("sqlite3", $required, true)) {
    if (!class_exists("SQLite3")) {
        $errors[] = "SQLite3 class is not available";
    } else {
        try {
            $db = new SQLite3(":memory:");
            $db->exec("CREATE TABLE phpsfx_sqlite3_check (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
            $db->exec("INSERT INTO phpsfx_sqlite3_check (name) VALUES (\"ok\")");
            $value = $db->querySingle("SELECT name FROM phpsfx_sqlite3_check WHERE id = 1");
            $db->close();
            $sqliteSmoke["sqlite3_memory"] = ($value === "ok");
            if ($value !== "ok") {
                $errors[] = "SQLite3 memory smoke check returned unexpected value";
            }
        } catch (Throwable $e) {
            $sqliteSmoke["sqlite3_memory"] = false;
            $errors[] = "SQLite3 memory smoke check failed: " . $e->getMessage();
        }
    }
}

if (in_array("pdo_sqlite", $required, true)) {
    if (!class_exists("PDO")) {
        $errors[] = "PDO class is not available";
    } elseif (!in_array("sqlite", PDO::getAvailableDrivers(), true)) {
        $errors[] = "PDO sqlite driver is not available";
    } else {
        try {
            $pdo = new PDO("sqlite::memory:");
            $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $pdo->exec("CREATE TABLE phpsfx_pdo_sqlite_check (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
            $pdo->exec("INSERT INTO phpsfx_pdo_sqlite_check (name) VALUES (\"ok\")");
            $value = $pdo->query("SELECT name FROM phpsfx_pdo_sqlite_check WHERE id = 1")->fetchColumn();
            $sqliteSmoke["pdo_sqlite_memory"] = ($value === "ok");
            if ($value !== "ok") {
                $errors[] = "PDO SQLite memory smoke check returned unexpected value";
            }
        } catch (Throwable $e) {
            $sqliteSmoke["pdo_sqlite_memory"] = false;
            $errors[] = "PDO SQLite memory smoke check failed: " . $e->getMessage();
        }
    }
}

$result = [
    "php_version" => PHP_VERSION,
    "php_sapi" => PHP_SAPI,
    "swoole_cli" => defined("SWOOLE_CLI"),
    "swoole_version" => defined("SWOOLE_VERSION") ? SWOOLE_VERSION : null,
    "expected_swoole_version" => $expectedSwooleVersion !== "" ? $expectedSwooleVersion : null,
    "required_extensions" => $required,
    "forbidden_extensions" => $forbidden,
    "allow_extra_extensions" => $allowExtra,
    "odbc" => $odbcSmoke,
    "sqlite_smoke" => $sqliteSmoke,
    "errors" => $errors,
];

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
exit($errors === [] ? 0 : 1);
'
