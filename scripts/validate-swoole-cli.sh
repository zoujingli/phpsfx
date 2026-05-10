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
$required = array_values(array_filter(array_map("trim", explode(",", getenv("PHPSFX_REQUIRED_EXTENSIONS") ?: ""))));
$forbidden = array_values(array_filter(array_map("trim", explode(",", getenv("PHPSFX_FORBIDDEN_EXTENSIONS") ?: ""))));
$allowExtra = filter_var(getenv("PHPSFX_ALLOW_EXTRA_EXTENSIONS") ?: "0", FILTER_VALIDATE_BOOL);
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
}

$result = [
    "php_version" => PHP_VERSION,
    "php_sapi" => PHP_SAPI,
    "swoole_cli" => defined("SWOOLE_CLI"),
    "swoole_version" => defined("SWOOLE_VERSION") ? SWOOLE_VERSION : null,
    "required_extensions" => $required,
    "forbidden_extensions" => $forbidden,
    "allow_extra_extensions" => $allowExtra,
    "errors" => $errors,
];

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
exit($errors === [] ? 0 : 1);
'
