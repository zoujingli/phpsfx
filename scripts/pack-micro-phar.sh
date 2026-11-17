#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -lt 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/pack-micro-phar.sh <micro.sfx> <app.phar> <output-binary> [options]

将可执行 Phar 追加到 micro.sfx 后生成单文件程序。
格式固定为：micro.sfx + [INI magic/length/data] + app.phar。

Options:
  -I, --ini <key=value>       注入一项运行时 INI，可重复
  -N, --ini-file <path>       注入一个多行 INI 文件
USAGE
  exit 2
fi

MICRO_SFX=$1
APP_PHAR=$2
OUTPUT=$3
shift 3

if [[ ! -s "${MICRO_SFX}" ]]; then
  echo "micro.sfx does not exist or is empty: ${MICRO_SFX}" >&2
  exit 1
fi
if [[ ! -s "${APP_PHAR}" ]]; then
  echo "Phar file does not exist or is empty: ${APP_PHAR}" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/phpsfx-micro-pack.XXXXXX")
trap 'rm -rf "${TMP_DIR}"' EXIT

INI_FILE="${TMP_DIR}/injected.ini"
: > "${INI_FILE}"
HAS_INI=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -I|--ini|--with-ini-set)
      [[ $# -ge 2 ]] || { echo "$1 requires key=value" >&2; exit 2; }
      printf '%s\n' "$2" >> "${INI_FILE}"
      HAS_INI=1
      shift 2
      ;;
    -N|--ini-file|--with-ini-file)
      [[ $# -ge 2 ]] || { echo "$1 requires a file path" >&2; exit 2; }
      [[ -f "$2" ]] || { echo "INI file does not exist: $2" >&2; exit 1; }
      cat "$2" >> "${INI_FILE}"
      printf '\n' >> "${INI_FILE}"
      HAS_INI=1
      shift 2
      ;;
    -h|--help)
      sed -n '1,24p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# Phar API uses the filename suffix for archive detection. Validate custom
# suffixes through a temporary .phar copy, while preserving the original bytes
# for the final payload.
VALIDATE_PHAR=${APP_PHAR}
TMP_PHAR=""
case "${APP_PHAR}" in
  *.phar) ;;
  *)
    TMP_PHAR="${TMP_DIR}/validate.phar"
    cp "${APP_PHAR}" "${TMP_PHAR}"
    VALIDATE_PHAR=${TMP_PHAR}
    ;;
esac

php -d phar.readonly=0 -r '
$path = $argv[1];
try {
    $phar = new Phar($path);
    $stub = $phar->getStub();
    if (!is_string($stub) || !str_contains($stub, "__HALT_COMPILER")) {
        throw new RuntimeException("Phar does not contain an executable stub");
    }
} catch (Throwable $exception) {
    fwrite(STDERR, "Invalid executable Phar: {$path}\n{$exception->getMessage()}\n");
    exit(1);
}
' "${VALIDATE_PHAR}"

INI_PART="${TMP_DIR}/ini.part"
if [[ "${HAS_INI}" == 1 ]]; then
  php -r '
$path = $argv[1];
$ini = file_get_contents($path);
if ($ini === false || parse_ini_string($ini) === false) {
    fwrite(STDERR, "Cannot parse injected INI\n");
    exit(1);
}
$part = "\xfd\xf6\x69\xe6" . pack("N", strlen($ini)) . $ini;
if (file_put_contents($argv[2], $part) === false) {
    fwrite(STDERR, "Cannot write INI block\n");
    exit(1);
}
' "${INI_FILE}" "${INI_PART}"
else
  : > "${INI_PART}"
fi

mkdir -p "$(dirname "${OUTPUT}")"
cat "${MICRO_SFX}" "${INI_PART}" "${APP_PHAR}" > "${OUTPUT}"
chmod +x "${OUTPUT}"
printf 'Packed micro Phar binary: %s\n' "${OUTPUT}"
