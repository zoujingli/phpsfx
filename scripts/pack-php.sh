#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/pack-php.sh <swoole-cli> <entry.php> <output-binary>

将单个 PHP 入口文件追加到 swoole-cli 后生成单文件可执行程序。
Swoole CLI SFX 格式固定为：swoole-cli + entry.php + pack('J', phpFileSize)。
适合小型命令行脚本或自包含入口文件；复杂项目建议先打 Phar，再用 pack-phar.sh。
运行生成的二进制时需要使用 --self，例如：./output --self list。
USAGE
  exit 2
fi

SWOOLE_CLI=$1
ENTRY_PHP=$2
OUTPUT=$3

if [[ ! -s "${SWOOLE_CLI}" ]]; then
  echo "swoole-cli does not exist or is empty: ${SWOOLE_CLI}" >&2
  exit 1
fi

if [[ ! -s "${ENTRY_PHP}" ]]; then
  echo "PHP entry file does not exist or is empty: ${ENTRY_PHP}" >&2
  exit 1
fi

case "${ENTRY_PHP}" in
  *.php) ;;
  *) echo "PHP entry file should use .php suffix: ${ENTRY_PHP}" >&2; exit 1 ;;
esac

chmod +x "${SWOOLE_CLI}"
"${SWOOLE_CLI}" -r 'exit(defined("SWOOLE_CLI") ? 0 : 1);'
php -l "${ENTRY_PHP}" >/dev/null

mkdir -p "$(dirname "${OUTPUT}")"
cat "${SWOOLE_CLI}" "${ENTRY_PHP}" > "${OUTPUT}"
php -r '
$target = $argv[1];
$payload = $argv[2];
$size = filesize($payload);
if ($size === false) {
    fwrite(STDERR, "Cannot stat payload: {$payload}\n");
    exit(1);
}
$fp = fopen($target, "ab");
if ($fp === false || fwrite($fp, pack("J", $size)) === false || fclose($fp) === false) {
    fwrite(STDERR, "Cannot append SFX payload length to: {$target}\n");
    exit(1);
}
' "${OUTPUT}" "${ENTRY_PHP}"
chmod +x "${OUTPUT}"
printf 'Packed PHP binary: %s\n' "${OUTPUT}"
