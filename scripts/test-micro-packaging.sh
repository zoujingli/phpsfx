#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/test-micro-packaging.sh <micro.sfx>" >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MICRO_SFX=$1
[[ -s "${MICRO_SFX}" ]] || { echo "micro.sfx does not exist or is empty: ${MICRO_SFX}" >&2; exit 1; }

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/phpsfx-micro-packaging.XXXXXX")
trap 'rm -rf "${TMP_DIR}"' EXIT
PLATFORM=${PHPSFX_PLATFORM:-}
if [[ "${PLATFORM}" == windows-* ]]; then
  EXECUTABLE_SUFFIX=.exe
else
  EXECUTABLE_SUFFIX=
fi

cat > "${TMP_DIR}/plain.php" <<'PHP'
<?php
echo 'plain:' . PHP_VERSION . ':' . PHP_SAPI . ':' . (function_exists('micro_get_self_filename') ? 'micro' : 'missing') . PHP_EOL;
PHP

cat > "${TMP_DIR}/make-ini-phar.php" <<'PHP'
<?php
$target = $argv[1];
@unlink($target);
$phar = new Phar($target);
$phar->addFromString('index.php', "<?php echo 'ini:' . (string) ini_get('memory_limit') . PHP_EOL;");
$phar->setDefaultStub('index.php');
PHP

cat > "${TMP_DIR}/make-phar.php" <<'PHP'
<?php
$target = $argv[1];
$compression = $argv[2] ?? 'none';
@unlink($target);
$phar = new Phar($target);
$phar->startBuffering();
$phar->addFromString('resource.txt', 'micro-resource-ok');
$phar->addFromString('index.php', <<<'APP'
<?php
$self = function_exists('micro_get_self_filename') ? micro_get_self_filename() : __FILE__;
$resource = file_get_contents('phar://' . $self . '/resource.txt');
echo 'phar:' . PHP_VERSION . ':' . PHP_SAPI . ':' . $resource . ':' . (str_starts_with(__FILE__, 'phar://') ? 'self' : 'external') . PHP_EOL;
APP
);
$phar->setDefaultStub('index.php');
if ($compression === 'gz') {
    $phar->compressFiles(Phar::GZ);
} elseif ($compression === 'bz2') {
    $phar->compressFiles(Phar::BZ2);
}
$phar->stopBuffering();
PHP

cat "${MICRO_SFX}" "${TMP_DIR}/plain.php" > "${TMP_DIR}/plain${EXECUTABLE_SUFFIX}"
chmod +x "${TMP_DIR}/plain${EXECUTABLE_SUFFIX}"
plain_output=$("${TMP_DIR}/plain${EXECUTABLE_SUFFIX}")
echo "${plain_output}"
case "${plain_output}" in
  plain:*:cli:micro) ;;
  *) echo "Unexpected plain micro output: ${plain_output}" >&2; exit 1 ;;
esac

php -d phar.readonly=0 "${TMP_DIR}/make-ini-phar.php" "${TMP_DIR}/ini.phar"
ini_output_path="${TMP_DIR}/ini-app${EXECUTABLE_SUFFIX}"
bash "${ROOT_DIR}/scripts/pack-micro-phar.sh" "${MICRO_SFX}" "${TMP_DIR}/ini.phar" "${ini_output_path}" --ini memory_limit=512M
ini_output=$("${ini_output_path}")
echo "${ini_output}"
[[ "${ini_output}" == 'ini:512M' ]] || { echo "INI injection failed: ${ini_output}" >&2; exit 1; }

IFS=',' read -r -a compressions <<< "${PHPSFX_MICRO_TEST_COMPRESSIONS:-none,gz,bz2}"
for compression in "${compressions[@]}"; do
  phar_path="${TMP_DIR}/app-${compression}.phar"
  output_path="${TMP_DIR}/app-${compression}${EXECUTABLE_SUFFIX}"
  php -d phar.readonly=0 "${TMP_DIR}/make-phar.php" "${phar_path}" "${compression}"
  bash "${ROOT_DIR}/scripts/pack-micro-phar.sh" "${MICRO_SFX}" "${phar_path}" "${output_path}"
  phar_output=$("${output_path}")
  echo "${phar_output}"
  case "${phar_output}" in
    phar:*:cli:micro-resource-ok:self) ;;
    *) echo "Unexpected ${compression} Phar output: ${phar_output}" >&2; exit 1 ;;
  esac
done

printf 'micro.sfx PHP and Phar packaging tests passed for %s\n' "${MICRO_SFX}"
