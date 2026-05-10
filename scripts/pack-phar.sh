#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/pack-phar.sh <swoole-cli> <app.phar> <output-binary>

将可执行 Phar 追加到 swoole-cli 后生成单文件可执行程序。
Swoole CLI SFX 格式固定为：swoole-cli + app.phar + pack('J', pharSize)。
脚本兼容 .bin 等自定义 Phar 后缀，会先复制为临时 .phar 做轻量校验。
运行生成的二进制时需要使用 --self，例如：./output --self list。
USAGE
  exit 2
fi

SWOOLE_CLI=$1
APP_PHAR=$2
OUTPUT=$3

if [[ ! -s "${SWOOLE_CLI}" ]]; then
  echo "swoole-cli does not exist or is empty: ${SWOOLE_CLI}" >&2
  exit 1
fi

if [[ ! -s "${APP_PHAR}" ]]; then
  echo "Phar file does not exist or is empty: ${APP_PHAR}" >&2
  exit 1
fi

chmod +x "${SWOOLE_CLI}"
"${SWOOLE_CLI}" -r 'exit(defined("SWOOLE_CLI") ? 0 : 1);'

# 用 PHP Phar 元数据做轻量校验，避免把普通文件误当 Phar 追加。
# Phar API 依赖文件后缀识别，因此对 .bin 等自定义后缀先复制为临时 .phar 再校验。
TMP_PHAR=""
VALIDATE_PHAR="${APP_PHAR}"
case "${APP_PHAR}" in
  *.phar) ;;
  *)
    if TMP_PHAR=$(mktemp --suffix=.phar 2>/dev/null); then
      :
    else
      TMP_BASE=$(mktemp -t phpsfx-phar.XXXXXX)
      TMP_PHAR="${TMP_BASE}.phar"
      mv "${TMP_BASE}" "${TMP_PHAR}"
    fi
    cp "${APP_PHAR}" "${TMP_PHAR}"
    VALIDATE_PHAR="${TMP_PHAR}"
    ;;
esac
trap '[[ -z "${TMP_PHAR}" ]] || rm -f "${TMP_PHAR}"' EXIT
php -d phar.readonly=0 -r '
$path = $argv[1];
try {
    new Phar($path);
} catch (Throwable $exception) {
    fwrite(STDERR, "Invalid Phar: {$path}\n{$exception->getMessage()}\n");
    exit(1);
}
' "${VALIDATE_PHAR}"

mkdir -p "$(dirname "${OUTPUT}")"
cat "${SWOOLE_CLI}" "${APP_PHAR}" > "${OUTPUT}"
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
' "${OUTPUT}" "${APP_PHAR}"
chmod +x "${OUTPUT}"
printf 'Packed Phar binary: %s\n' "${OUTPUT}"
