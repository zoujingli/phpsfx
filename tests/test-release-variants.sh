#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

for php_version in 8.4 8.5; do
  case "${php_version}" in
    8.4) php_full_version=8.4.27 ;;
    8.5) php_full_version=8.5.12 ;;
  esac
  for platform in linux-x64 linux-a64 macos-a64; do
    for package in mysql pgsql odbc sqlite-mysql-pgsql; do
      database=${package}
      mode=slim
      case "${package}" in
        mysql) expected=mysql ;;
        pgsql) expected=pgsql ;;
        odbc) expected=odbc; mode=odbc ;;
        sqlite-mysql-pgsql)
          expected=sqlite,mysql,pgsql
          if [[ "${platform}" == linux-* ]]; then
            expected+=,odbc
            mode=odbc
          fi
          ;;
      esac
      # Check profile defaults independently of the current CI job's build settings.
      PHPSFX_SWOOLE_ODBC=0 PHPSFX_SWOOLE_CLI_REF='' PHPSFX_SWOOLE_SRC_REF='' PHPSFX_PHP_VERSION="${php_version}" PHPSFX_PHP_FULL_VERSION='' PHPSFX_RELEASE_VERSION='' PHPSFX_DB_VARIANT="${database}" bash -c '
        set -Eeuo pipefail
        source "scripts/profiles/$1.env"
        expected=$2
        [[ "${PHPSFX_ASSET_SUFFIX}" == "$3" ]] || exit 1
        [[ "${PHPSFX_REQUIRED_PDO_DRIVERS}" == "${expected}" ]] || exit 1
        [[ "${PHPSFX_RELEASE_VERSION}" == v6.2.5.1 ]] || exit 1
        [[ "${PHPSFX_SWOOLE_CLI_REF}" == e891b2b38720c5879c9a2c7894384b9af7228de0 ]] || exit 1
        [[ "${PHPSFX_SWOOLE_SRC_REF}" == v6.2.5 ]] || exit 1
        [[ "${PHPSFX_PHP_FULL_VERSION}" == "$4" ]] || exit 1
        [[ "${PHPSFX_SWOOLE_ODBC:-0}" == "$5" ]] || exit 1
        for driver in mysql pgsql sqlite; do
          extension="pdo_${driver}"
          if [[ ",${expected}," == *",${driver},"* ]]; then
            [[ ",${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS}," == *",${extension},"* ]] || exit 1
            [[ ",${PHPSFX_REQUIRED_EXTENSIONS}," == *",${extension},"* ]] || exit 1
            [[ ",${PHPSFX_EXTENSIONS}," == *",${extension},"* ]] || exit 1
            [[ " ${PHPSFX_SWOOLE_CLI_PREPARE_FLAGS} " == *" +${extension} "* ]] || exit 1
            [[ ",${PHPSFX_FORBIDDEN_EXTENSIONS}," != *",${extension},"* ]] || exit 1
          else
            [[ ",${PHPSFX_FORBIDDEN_EXTENSIONS}," == *",${extension},"* ]] || exit 1
            [[ ",${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS}," != *",${extension},"* ]] || exit 1
            [[ ",${PHPSFX_EXTENSIONS}," != *",${extension},"* ]] || exit 1
            [[ " ${PHPSFX_SWOOLE_CLI_PREPARE_FLAGS} " == *" -${extension} "* ]] || exit 1
          fi
        done
      ' _ "hyperfadmin-${mode}" "${expected}" "${package}" "${php_full_version}" "$([[ "${mode}" == odbc ]] && printf 1 || printf 0)"
    done
  done
done

for mode in slim odbc; do
  expected=mysql
  [[ "${mode}" != odbc ]] || expected=odbc
  PHPSFX_DB_VARIANT='' PHPSFX_REQUIRED_PDO_DRIVERS='' PHPSFX_ASSET_SUFFIX='' PHPSFX_SWOOLE_ODBC=0 bash -c '
    set -Eeuo pipefail
    source "scripts/profiles/hyperfadmin-$1.env"
    [[ "${PHPSFX_DB_VARIANT}" == "$2" ]] || exit 1
    [[ "${PHPSFX_ASSET_SUFFIX}" == "$2" ]] || exit 1
    [[ "${PHPSFX_REQUIRED_PDO_DRIVERS}" == "$2" ]] || exit 1
  ' _ "${mode}" "${expected}"
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
  local platform=$1 version=$2 expected=$3 php_version=${4:-8.5}
  PHPSFX_PHP_VERSION="${php_version}" bash scripts/download-release-asset.sh "${platform}" "${version}" "${TMP_DIR}/binary" >/dev/null
  [[ "$(< "${TEST_RELEASE_URL}")" == \
    "https://github.com/zoujingli/phpsfx/releases/${expected}" ]]
}

check_download linux-x64 v6.2.3.0 download/v6.2.3.0/swoole-cli-php8.5-linux-x64
check_download linux-x64-odbc v6.2.3.0 download/v6.2.3.0/swoole-cli-php8.5-linux-x64-odbc
check_download linux-x64 v6.2.3.3 download/v6.2.3.3/swoole-cli-php8.5-linux-x64-mysql-pgsql-sqlite
check_download linux-x64-odbc v6.2.3.1 download/v6.2.3.1/swoole-cli-php8.5-linux-x64-mysql-pgsql-sqlite-odbc
check_download linux-x64 v6.2.3.2 download/v6.2.3.2/swoole-cli-php8.5-linux-x64-mysql-pgsql-sqlite
check_download linux-x64 v6.2.3.3 download/v6.2.3.3/swoole-cli-php8.4-linux-x64-mysql-pgsql-sqlite 8.4
check_download linux-x64 latest latest/download/swoole-cli-php8.5-linux-x64-mysql
check_download linux-x64-odbc latest latest/download/swoole-cli-php8.5-linux-x64-odbc
check_download macos-a64-sqlite-odbc v6.2.3.3 download/v6.2.3.3/swoole-cli-php8.4-macos-a64-sqlite-odbc 8.4
for database in sqlite mysql pgsql mysql-pgsql pgsql-sqlite mysql-sqlite mysql-pgsql-sqlite; do
  check_download macos-x64-${database} v6.2.3.3 download/v6.2.3.3/swoole-cli-php8.5-macos-x64-${database}
  check_download macos-a64-${database}-odbc v6.2.3.2 download/v6.2.3.2/swoole-cli-php8.5-macos-a64-${database}-odbc
done
for version in v6.2.3.0 v6.2.3.1 v6.2.3.2 v6.2.3.3; do
  if bash scripts/download-release-asset.sh linux-x64-sqlite-mysql-pgsql-odbc "${version}" "${TMP_DIR}/binary" >/dev/null 2>&1; then
    echo "Old release unexpectedly accepted the new development package: ${version}" >&2
    exit 1
  fi
done

for php_version in 8.4 8.5; do
  for platform in linux-x64 linux-a64 macos-a64; do
    for package in mysql pgsql odbc sqlite-mysql-pgsql; do
      check_download "${platform}-${package}" latest "latest/download/swoole-cli-php${php_version}-${platform}-${package}" "${php_version}"
      for version in v6.2.3.5 v6.2.3.6 v6.2.4.0 v6.2.5.0 v6.2.5.1; do
        check_download "${platform}-${package}" "${version}" "download/${version}/swoole-cli-php${php_version}-${platform}-${package}" "${php_version}"
      done
    done
    for package in mysql pgsql odbc sqlite-mysql-pgsql-odbc; do
      check_download "${platform}-${package}" v6.2.3.4 "download/v6.2.3.4/swoole-cli-php${php_version}-${platform}-${package}" "${php_version}"
    done
  done
done
for unavailable in macos-x64-mysql linux-x64-sqlite linux-x64-mysql-odbc linux-x64-mysql-pgsql-sqlite macos-a64-sqlite-mysql-pgsql-odbc; do
  if bash scripts/download-release-asset.sh "${unavailable}" latest "${TMP_DIR}/binary" >/dev/null 2>&1; then
    echo "New release unexpectedly accepted ${unavailable}" >&2
    exit 1
  fi
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

printf '%s\n' '24 release configurations, platform-specific ODBC and legacy downloads passed'
