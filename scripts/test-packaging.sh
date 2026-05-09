#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/test-packaging.sh <micro.sfx>" >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MICRO_SFX=$1
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/hello.php" <<'PHP'
<?php
echo "php:" . PHP_VERSION . ":" . PHP_SAPI . PHP_EOL;
PHP

bash "${ROOT_DIR}/scripts/pack-php.sh" "${MICRO_SFX}" "${TMP_DIR}/hello.php" "${TMP_DIR}/hello-php"
"${TMP_DIR}/hello-php" | grep -E '^php:8\.4\..*:cli$'

cat > "${TMP_DIR}/make-phar.php" <<'PHP'
<?php
$target = $argv[1];
@unlink($target);
$phar = new Phar($target);
$phar->startBuffering();
$phar->addFromString('index.php', '<?php echo "phar:" . PHP_VERSION . ":" . PHP_SAPI . PHP_EOL;');
$phar->setStub("<?php Phar::mapPhar('hello.phar'); require 'phar://hello.phar/index.php'; __HALT_COMPILER();");
$phar->stopBuffering();
PHP
php -d phar.readonly=0 "${TMP_DIR}/make-phar.php" "${TMP_DIR}/hello.phar"

bash "${ROOT_DIR}/scripts/pack-phar.sh" "${MICRO_SFX}" "${TMP_DIR}/hello.phar" "${TMP_DIR}/hello-phar"
"${TMP_DIR}/hello-phar" | grep -E '^phar:8\.4\..*:cli$'

printf 'PHP and Phar packaging tests passed for %s\n' "${MICRO_SFX}"
