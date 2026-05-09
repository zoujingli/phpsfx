#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/pack-phar.sh <micro.sfx> <app.phar> <output-binary>

将 Phar 包直接追加到 micro.sfx 后生成可执行文件。
Phar 必须自带可执行 stub；HyperfAdmin 通过 xadmin:build:phar 生成的 system.bin 属于此类。
USAGE
  exit 2
fi

MICRO_SFX=$1
APP_PHAR=$2
OUTPUT=$3

if [[ ! -s "${MICRO_SFX}" ]]; then
  echo "micro.sfx does not exist or is empty: ${MICRO_SFX}" >&2
  exit 1
fi

if [[ ! -s "${APP_PHAR}" ]]; then
  echo "Phar file does not exist or is empty: ${APP_PHAR}" >&2
  exit 1
fi

# 用 PHP Phar 元数据做轻量校验，避免把普通文件误当 Phar 追加。
# Phar API 依赖文件后缀识别，因此对 HyperfAdmin system.bin 这类自定义后缀先复制为临时 .phar 再校验。
TMP_PHAR=""
VALIDATE_PHAR="${APP_PHAR}"
case "${APP_PHAR}" in
  *.phar) ;;
  *)
    TMP_PHAR=$(mktemp --suffix=.phar 2>/dev/null || mktemp -t phpsfx-phar)
    cp "${APP_PHAR}" "${TMP_PHAR}"
    VALIDATE_PHAR="${TMP_PHAR}"
    ;;
esac
trap '[[ -z "${TMP_PHAR}" ]] || rm -f "${TMP_PHAR}"' EXIT
php -r '
$path = $argv[1];
try {
    new Phar($path);
} catch (Throwable $exception) {
    fwrite(STDERR, "Invalid Phar: {$path}\n{$exception->getMessage()}\n");
    exit(1);
}
' "${VALIDATE_PHAR}"

mkdir -p "$(dirname "${OUTPUT}")"
cat "${MICRO_SFX}" "${APP_PHAR}" > "${OUTPUT}"
chmod +x "${OUTPUT}"
printf 'Packed Phar binary: %s\n' "${OUTPUT}"
