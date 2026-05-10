#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/test-packaging.sh <swoole-cli>" >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SWOOLE_CLI=$1
EXPECTED_PREFIX=${PHPSFX_EXPECTED_PHP_PREFIX:-${PHPSFX_PHP_VERSION:-8.4}.}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/hello.php" <<'PHP'
<?php
echo "php:" . PHP_VERSION . ":" . PHP_SAPI . ":" . (defined('SWOOLE_CLI') ? 'swoole-cli' : 'plain') . PHP_EOL;
PHP

bash "${ROOT_DIR}/scripts/pack-php.sh" "${SWOOLE_CLI}" "${TMP_DIR}/hello.php" "${TMP_DIR}/hello-php"
PHP_OUTPUT=$("${TMP_DIR}/hello-php" --self)
echo "${PHP_OUTPUT}"
case "${PHP_OUTPUT}" in
  php:${EXPECTED_PREFIX}*:cli:swoole-cli) ;;
  *) echo "Unexpected PHP SFX output: ${PHP_OUTPUT}" >&2; exit 1 ;;
esac

cat > "${TMP_DIR}/make-phar.php" <<'PHP'
<?php
$target = $argv[1];
@unlink($target);
$phar = new Phar($target);
$phar->startBuffering();
$phar->addFromString('index.php', '<?php echo "phar:" . PHP_VERSION . ":" . PHP_SAPI . ":" . (defined("SWOOLE_CLI") ? "swoole-cli" : "plain") . PHP_EOL;');
$phar->setStub("<?php Phar::mapPhar('hello.phar'); require 'phar://hello.phar/index.php'; __HALT_COMPILER();");
$phar->stopBuffering();
PHP
php -d phar.readonly=0 "${TMP_DIR}/make-phar.php" "${TMP_DIR}/hello.phar"

bash "${ROOT_DIR}/scripts/pack-phar.sh" "${SWOOLE_CLI}" "${TMP_DIR}/hello.phar" "${TMP_DIR}/hello-phar"
PHAR_OUTPUT=$("${TMP_DIR}/hello-phar" --self)
echo "${PHAR_OUTPUT}"
case "${PHAR_OUTPUT}" in
  phar:${EXPECTED_PREFIX}*:cli:swoole-cli) ;;
  *) echo "Unexpected Phar SFX output: ${PHAR_OUTPUT}" >&2; exit 1 ;;
esac

printf 'PHP and Phar Swoole CLI SFX packaging tests passed for %s\n' "${SWOOLE_CLI}"
