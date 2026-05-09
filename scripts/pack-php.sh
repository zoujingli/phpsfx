#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  cat >&2 <<'USAGE'
Usage: scripts/pack-php.sh <micro.sfx> <entry.php> <output-binary>

将单个 PHP 入口文件直接追加到 micro.sfx 后生成可执行文件。
适合小型命令行脚本或自包含入口文件；复杂项目建议先打 Phar，再用 pack-phar.sh。
USAGE
  exit 2
fi

MICRO_SFX=$1
ENTRY_PHP=$2
OUTPUT=$3

if [[ ! -s "${MICRO_SFX}" ]]; then
  echo "micro.sfx does not exist or is empty: ${MICRO_SFX}" >&2
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

mkdir -p "$(dirname "${OUTPUT}")"
cat "${MICRO_SFX}" "${ENTRY_PHP}" > "${OUTPUT}"
chmod +x "${OUTPUT}"
printf 'Packed PHP binary: %s\n' "${OUTPUT}"
