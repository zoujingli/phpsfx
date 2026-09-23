#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

for database in sqlite mysql pgsql mysql-pgsql pgsql-sqlite mysql-sqlite mysql-pgsql-sqlite; do
  case "${database}" in
    sqlite) expected=sqlite ;;
    mysql) expected=mysql ;;
    pgsql) expected=pgsql ;;
    mysql-pgsql) expected=mysql,pgsql ;;
    pgsql-sqlite) expected=pgsql,sqlite ;;
    mysql-sqlite) expected=mysql,sqlite ;;
    mysql-pgsql-sqlite) expected=mysql,pgsql,sqlite ;;
  esac
  for mode in slim odbc; do
    PHPSFX_DB_VARIANT="${database}" bash -c '
      set -Eeuo pipefail
      source "scripts/profiles/$1.env"
      expected=$2
      [[ "${PHPSFX_ASSET_SUFFIX}" == "${PHPSFX_DB_VARIANT}$3" ]]
      [[ "${PHPSFX_REQUIRED_PDO_DRIVERS}" == "${expected}$4" ]]
      [[ "${PHPSFX_RELEASE_VERSION}" == v6.2.3.2 ]]
      for driver in mysql pgsql sqlite; do
        extension="pdo_${driver}"
        if [[ ",${expected}," == *",${driver},"* ]]; then
          [[ ",${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS}," == *",${extension},"* ]]
          [[ ",${PHPSFX_REQUIRED_EXTENSIONS}," == *",${extension},"* ]]
          [[ ",${PHPSFX_EXTENSIONS}," == *",${extension},"* ]]
          [[ " ${PHPSFX_SWOOLE_CLI_PREPARE_FLAGS} " == *" +${extension} "* ]]
          [[ ",${PHPSFX_FORBIDDEN_EXTENSIONS}," != *",${extension},"* ]]
        else
          [[ ",${PHPSFX_FORBIDDEN_EXTENSIONS}," == *",${extension},"* ]]
          [[ ",${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS}," != *",${extension},"* ]]
          [[ ",${PHPSFX_EXTENSIONS}," != *",${extension},"* ]]
          [[ " ${PHPSFX_SWOOLE_CLI_PREPARE_FLAGS} " == *" -${extension} "* ]]
        fi
      done
    ' _ "hyperfadmin-${mode}" "${expected}" \
      "$([[ "${mode}" == odbc ]] && printf '%s' -odbc)" \
      "$([[ "${mode}" == odbc ]] && printf '%s' ,odbc)"
  done
done

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
export TEST_RELEASE_URL="${TMP_DIR}/url"

curl() {
  local output='' url='' previous='' argument
  for argument in "$@"; do
    if [[ "${previous}" == -o ]]; then
      output=${argument}
    fi
    previous=${argument}
    url=${argument}
  done
  printf 'test-binary' > "${output}"
  printf '%s' "${url}" > "${TEST_RELEASE_URL}"
}
export -f curl

check_download() {
  local platform=$1 version=$2 expected=$3
  bash scripts/download-release-asset.sh "${platform}" "${version}" "${TMP_DIR}/binary" >/dev/null
  [[ "$(< "${TEST_RELEASE_URL}")" == \
    "https://github.com/zoujingli/phpsfx/releases/${expected}" ]]
}

check_download linux-x64 v6.2.3.0 download/v6.2.3.0/swoole-cli-php8.5-linux-x64
check_download linux-x64-odbc v6.2.3.0 download/v6.2.3.0/swoole-cli-php8.5-linux-x64-odbc
check_download linux-x64 latest latest/download/swoole-cli-php8.5-linux-x64-mysql-pgsql-sqlite
check_download linux-x64-odbc v6.2.3.1 download/v6.2.3.1/swoole-cli-php8.5-linux-x64-mysql-pgsql-sqlite-odbc
check_download linux-x64 v6.2.3.2 download/v6.2.3.2/swoole-cli-php8.5-linux-x64-mysql-pgsql-sqlite
for database in sqlite mysql pgsql mysql-pgsql pgsql-sqlite mysql-sqlite mysql-pgsql-sqlite; do
  check_download macos-a64-${database} latest latest/download/swoole-cli-php8.5-macos-a64-${database}
  check_download macos-a64-${database}-odbc v6.2.3.2 download/v6.2.3.2/swoole-cli-php8.5-macos-a64-${database}-odbc
done
for database in pgsql-sqlite mysql-sqlite mysql-pgsql-sqlite; do
  check_download linux-a64-${database} v6.2.3.1 download/v6.2.3.1/swoole-cli-php8.5-linux-a64-${database}
done
for database in sqlite mysql pgsql mysql-pgsql; do
  if bash scripts/download-release-asset.sh "linux-x64-${database}" v6.2.3.1 "${TMP_DIR}/binary" >/dev/null 2>&1; then
    echo "Old release unexpectedly accepted ${database}" >&2
    exit 1
  fi
done
if bash scripts/download-release-asset.sh linux-x64-pgsql-sqlite v6.2.3.0 "${TMP_DIR}/binary" >/dev/null 2>&1; then
  echo 'Old release unexpectedly accepted a database-combination asset' >&2
  exit 1
fi

printf '%s\n' 'Fourteen release profiles and download asset names passed'
