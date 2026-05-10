#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE=${PHPSFX_PROFILE:-${PHPSFX_PROFILE_NAME:-min}}
PROFILE_FILE=${PHPSFX_PROFILE_FILE:-"${ROOT_DIR}/scripts/profiles/${PROFILE}.env"}
if [[ -n "${PROFILE_FILE}" && "${PROFILE_FILE}" != "none" ]]; then
  [[ "${PROFILE_FILE}" = /* ]] || PROFILE_FILE="${ROOT_DIR}/${PROFILE_FILE}"
  if [[ ! -f "${PROFILE_FILE}" ]]; then
    echo "Profile file does not exist: ${PROFILE_FILE}" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${PROFILE_FILE}"
fi

PLATFORM=${1:-${PHPSFX_PLATFORM:-}}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.4}
SWOOLE_CLI_REPO=${PHPSFX_SWOOLE_CLI_REPO:-https://github.com/swoole/swoole-cli.git}
SWOOLE_CLI_CHECKOUT_MODE=${PHPSFX_SWOOLE_CLI_CHECKOUT_MODE:-auto}
default_swoole_cli_ref() {
  case "$1" in
    8.1) echo "v6.0.2.0" ;;
    8.4) echo "v6.2.0.0" ;;
    *)
      echo "Unsupported PHP version line for default Swoole CLI ref: $1" >&2
      echo "Set PHPSFX_SWOOLE_CLI_REF explicitly if you want to build this PHP line." >&2
      return 2
      ;;
  esac
}
SWOOLE_CLI_REF=${PHPSFX_SWOOLE_CLI_REF:-$(default_swoole_cli_ref "${PHP_VERSION}")}
SWOOLE_CLI_DIR=${PHPSFX_SWOOLE_CLI_DIR:-"${ROOT_DIR}/.build/swoole-cli"}
DIST_DIR=${PHPSFX_DIST_DIR:-"${ROOT_DIR}/dist"}
HOST_JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
DEFAULT_JOBS=${HOST_JOBS}
if [[ "${GITHUB_ACTIONS:-}" == "true" && -z "${PHPSFX_BUILD_JOBS:-}" ]]; then
  # GitHub hosted runner 在 OpenSSL 静态构建阶段容易因并行过高触发 OOM 或随机编译失败，发布构建默认保守一些。
  DEFAULT_JOBS=2
fi
JOBS=${PHPSFX_BUILD_JOBS:-${DEFAULT_JOBS}}
PROFILE_NAME=${PHPSFX_PROFILE_NAME:-${PHPSFX_PROFILE:-min}}
DEFAULT_EXTENSIONS='bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,mysqlnd,openssl,pcntl,pdo,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib'
DEFAULT_PREPARE_FLAGS='+bcmath +ctype +curl +fileinfo +filter +iconv +mbstring +mysqlnd +openssl +pcntl +pdo +pdo_mysql +phar +posix +redis +sockets +sodium +swoole +tokenizer +xml +zip +zlib -bz2 -exif -gd -gettext -gmp -imagick -intl -mongodb -mysqli -opcache -readline -session -soap -sqlite3 -xlswriter -xsl -yaml'
# PHPSFX_SWOOLE_CLI_PREPARE_FLAGS 允许显式设置为空字符串：
# - min profile 会提供裁剪后的 +extension/-extension 参数；
# - max profile 需要空参数以保留 Swoole CLI 上游默认组件集合。
PREPARE_FLAGS=${PHPSFX_SWOOLE_CLI_PREPARE_FLAGS-${DEFAULT_PREPARE_FLAGS}}
EXPECTED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS-swoole,redis,pdo,pdo_mysql,mysqlnd,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,fileinfo,bcmath,sodium,sockets,posix,pcntl}
FORBIDDEN_EXTENSIONS=${PHPSFX_FORBIDDEN_EXTENSIONS-bz2,exif,gd,gettext,gmp,imagick,intl,mongodb,mysqli,readline,session,soap,sqlite3,xlswriter,xsl,yaml,opcache}
DOWNLOAD_MIRROR_URL=${PHPSFX_DOWNLOAD_MIRROR_URL:-}
SWOOLE_SRC_REF=${PHPSFX_SWOOLE_SRC_REF:-}
STRIP_BINARY=${PHPSFX_STRIP_BINARY:-1}

usage() {
  cat <<'USAGE'
Usage: scripts/build-swoole-cli.sh [platform]

Platforms:
  linux-x64, linux-a64, macos-x64, macos-a64

Important environment variables:
  PHPSFX_PHP_VERSION                 PHP version prefix used for asset name and validation, default: 8.4
  PHPSFX_SWOOLE_CLI_REPO             Swoole CLI git repository, default: https://github.com/swoole/swoole-cli.git
  PHPSFX_SWOOLE_CLI_REF              Swoole CLI branch, tag, or commit, default: v6.0.2.0 for PHP 8.1, v6.2.0.0 for PHP 8.4
  PHPSFX_SWOOLE_CLI_CHECKOUT_MODE    auto, git, or archive. git uses a shallow tag/ref checkout; archive uses GitHub API tarball, default: auto
  PHPSFX_SWOOLE_CLI_PREPARE_FLAGS    Space-separated prepare.php flags, e.g. '+redis -mongodb'
  PHPSFX_SWOOLE_SRC_REF              Optional swoole-src tag/ref when upstream ref lacks sapi/SWOOLE-VERSION.conf
  PHPSFX_REQUIRED_EXTENSIONS         Comma-separated runtime extensions checked after build
  PHPSFX_FORBIDDEN_EXTENSIONS        Comma-separated extensions that must not be loaded
  PHPSFX_ALLOW_EXTRA_EXTENSIONS      Set to 1 to skip forbidden-extension checks for local full-runtime smoke
  PHPSFX_PROFILE                     Runtime component profile: min or max, default: min
  PHPSFX_PROFILE_FILE                Profile env file, default: scripts/profiles/${PHPSFX_PROFILE}.env
  PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS Comma-separated prepare.php default extension list override
  PHPSFX_SWOOLE_SLIM_EXTENSION       Set to 1 to trim optional Swoole extension features, default from profile: 1
  PHPSFX_CURL_SLIM_LIBRARY           Set to 1 to trim optional libcurl features, default from profile: 1
  PHPSFX_LIBZIP_SLIM_LIBRARY         Set to 1 to trim optional libzip codecs, default from profile: 1
  PHPSFX_ZLIB_SLIM_LIBRARY           Set to 1 to remove unrelated zlib library deps, default from profile: 1
  PHPSFX_REDIS_DISABLE_SESSION       Set to 1 to build redis without session hooks, default from profile: 1
  PHPSFX_ONIGURUMA_CLANG_COMPAT      Set to 1 to relax macOS clang oniguruma warnings, default from profile: 1
  PHPSFX_LIBSODIUM_STABLE_LIBRARY    Set to 1 to patch old Swoole CLI refs to libsodium 1.0.21, default from profile: 1
  PHPSFX_DISABLE_FPM_RUNTIME         Set to 1 to remove php-fpm sources/entry while keeping CLI web server, default from profile: 1
  PHPSFX_STRIP_BINARY                Set to 1 to strip debug symbols from release binary, default: 1
  PHPSFX_GLOBAL_PREFIX               Dependency install prefix, default: .build/swoole-cli/.global-prefix/<platform>
  PHPSFX_DOWNLOAD_MIRROR_URL         Optional Swoole CLI dependency mirror URL passed to prepare.php
  PHPSFX_DIST_DIR                    Output directory, default: ./dist
  PHPSFX_SWOOLE_CLI_DIR              Swoole CLI checkout dir, default: ./.build/swoole-cli
USAGE
}

detect_platform() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "${os}:${arch}" in
    Linux:x86_64|Linux:amd64) echo linux-x64 ;;
    Linux:aarch64|Linux:arm64) echo linux-a64 ;;
    Darwin:x86_64|Darwin:amd64) echo macos-x64 ;;
    Darwin:arm64|Darwin:aarch64) echo macos-a64 ;;
    *)
      echo "Unsupported host platform: ${os}/${arch}" >&2
      return 1
      ;;
  esac
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 127
  fi
}

retry_command() {
  local max=${PHPSFX_RETRY_TIMES:-3}
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= max )); then
      return 1
    fi
    echo "Command failed, retry ${attempt}/${max}: $*" >&2
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
  done
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Required command not found: sha256sum or shasum" >&2
    exit 127
  fi
}

strip_output_binary() {
  local binary=$1 before after
  if [[ "${STRIP_BINARY}" != "1" && "${STRIP_BINARY}" != "true" && "${STRIP_BINARY}" != "yes" ]]; then
    return 0
  fi
  if ! command -v strip >/dev/null 2>&1; then
    echo "strip command not found, keep unstripped binary: ${binary}" >&2
    return 0
  fi

  before=$(wc -c < "${binary}" | tr -d '[:space:]')
  case "${PLATFORM}" in
    macos-*) strip -x "${binary}" 2>/dev/null || strip "${binary}" 2>/dev/null || true ;;
    *) strip --strip-all "${binary}" 2>/dev/null || strip "${binary}" 2>/dev/null || true ;;
  esac
  after=$(wc -c < "${binary}" | tr -d '[:space:]')
  if [[ "${before}" != "${after}" ]]; then
    echo "Stripped ${binary}: ${before} -> ${after} bytes" >&2
  fi
}

download_swoole_cli_archive() {
  local tmp_dir archive_url archive_file curl_headers
  tmp_dir="${SWOOLE_CLI_DIR}.archive.$$"
  archive_file="${ROOT_DIR}/.build/swoole-cli-${SWOOLE_CLI_REF//[^A-Za-z0-9._-]/_}.tar.gz"
  archive_url="${PHPSFX_SWOOLE_CLI_ARCHIVE_URL:-https://api.github.com/repos/swoole/swoole-cli/tarball/${SWOOLE_CLI_REF}}"

  require_command curl
  rm -rf "${tmp_dir}"
  mkdir -p "${tmp_dir}" "$(dirname "${archive_file}")"
  echo "Downloading Swoole CLI archive: ${archive_url}" >&2
  # 读取公开上游源码包不使用当前仓库 GITHUB_TOKEN，避免 token 作用域/跨仓库策略导致 API tarball 302/403 异常。
  curl_headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: phpsfx")
  if ! retry_command curl --http1.1 -fsSL --retry 5 --retry-delay 2 --connect-timeout 30 --max-time 900 "${curl_headers[@]}" -o "${archive_file}" "${archive_url}"; then
    require_command php
    echo "curl archive download failed, fallback to PHP stream downloader" >&2
    retry_command php -r '
      $url = $argv[1];
      $out = $argv[2];
      $context = stream_context_create([
          "http" => [
              "method" => "GET",
              "follow_location" => 1,
              "max_redirects" => 10,
              "timeout" => 900,
              "header" => "Accept: application/vnd.github+json\r\nUser-Agent: phpsfx\r\n",
          ],
      ]);
      $data = file_get_contents($url, false, $context);
      if ($data === false || $data === "") {
          fwrite(STDERR, "Unable to download archive: {$url}\n");
          exit(1);
      }
      file_put_contents($out, $data);
    ' "${archive_url}" "${archive_file}"
  fi
  if [[ ! -s "${archive_file}" ]]; then
    echo "Downloaded archive is empty: ${archive_file}" >&2
    exit 1
  fi
  tar -xzf "${archive_file}" -C "${tmp_dir}" --strip-components=1
  rm -rf "${SWOOLE_CLI_DIR}"
  mv "${tmp_dir}" "${SWOOLE_CLI_DIR}"
}

clone_swoole_cli_git() {
  local tmp_dir
  require_command git
  tmp_dir="${SWOOLE_CLI_DIR}.git.$$"
  rm -rf "${tmp_dir}"

  # 默认发布 ref 都是 tag；先走 --branch + --depth=1，可避免完整仓库 checkout 在 macOS runner 上长时间卡住。
  if retry_command git clone --depth=1 --single-branch --branch "${SWOOLE_CLI_REF}" "${SWOOLE_CLI_REPO}" "${tmp_dir}"; then
    rm -rf "${SWOOLE_CLI_DIR}"
    mv "${tmp_dir}" "${SWOOLE_CLI_DIR}"
    return 0
  fi

  rm -rf "${tmp_dir}"
  if retry_command git clone --filter=blob:none --no-checkout "${SWOOLE_CLI_REPO}" "${tmp_dir}"; then
    cd "${tmp_dir}"
    if retry_command git fetch --force --depth=1 origin "${SWOOLE_CLI_REF}"; then
      git checkout --force FETCH_HEAD
    else
      retry_command git fetch --force --tags origin
      git checkout --force "${SWOOLE_CLI_REF}"
    fi
    cd "${ROOT_DIR}"
    rm -rf "${SWOOLE_CLI_DIR}"
    mv "${tmp_dir}" "${SWOOLE_CLI_DIR}"
    return 0
  fi

  rm -rf "${tmp_dir}"
  return 1
}

checkout_swoole_cli() {
  local preserved_pool origin_url need_checkout
  mkdir -p "${DIST_DIR}" "$(dirname "${SWOOLE_CLI_DIR}")"

  if [[ "${SWOOLE_CLI_CHECKOUT_MODE}" == "archive" ]]; then
    preserved_pool=""
    if [[ -d "${SWOOLE_CLI_DIR}/pool" ]]; then
      preserved_pool=$(mktemp -d)
      mv "${SWOOLE_CLI_DIR}/pool" "${preserved_pool}/pool"
    fi
    download_swoole_cli_archive
    if [[ -n "${preserved_pool}" && -d "${preserved_pool}/pool" ]]; then
      rm -rf "${SWOOLE_CLI_DIR}/pool"
      mv "${preserved_pool}/pool" "${SWOOLE_CLI_DIR}/pool"
      rmdir "${preserved_pool}" 2>/dev/null || true
    fi
    cd "${SWOOLE_CLI_DIR}"
    rm -f make.sh
    rm -rf bin/swoole-cli bin/dist thirdparty var/php-* modules libs libphp.la
    return 0
  fi

  need_checkout=0
  if [[ -d "${SWOOLE_CLI_DIR}/.git" ]]; then
    origin_url=$(git -C "${SWOOLE_CLI_DIR}" remote get-url origin 2>/dev/null || true)
    if [[ "${origin_url}" != "${SWOOLE_CLI_REPO}" ]]; then
      echo "Existing checkout remote does not match Swoole CLI repo, recreating: ${origin_url:-<none>}" >&2
      need_checkout=1
    fi
  elif [[ ! -f "${SWOOLE_CLI_DIR}/prepare.php" ]]; then
    need_checkout=1
  fi

  if [[ "${need_checkout}" == "1" ]]; then
    preserved_pool=""
    if [[ -d "${SWOOLE_CLI_DIR}/pool" ]]; then
      preserved_pool=$(mktemp -d)
      mv "${SWOOLE_CLI_DIR}/pool" "${preserved_pool}/pool"
    fi
    rm -rf "${SWOOLE_CLI_DIR}"
    if ! clone_swoole_cli_git; then
      download_swoole_cli_archive
    fi
    if [[ -n "${preserved_pool}" && -d "${preserved_pool}/pool" ]]; then
      rm -rf "${SWOOLE_CLI_DIR}/pool"
      mv "${preserved_pool}/pool" "${SWOOLE_CLI_DIR}/pool"
      rmdir "${preserved_pool}" 2>/dev/null || true
    fi
  fi

  cd "${SWOOLE_CLI_DIR}"
  if [[ -d .git ]]; then
    if retry_command git fetch --force --depth=1 origin "${SWOOLE_CLI_REF}"; then
      git checkout --force FETCH_HEAD
    else
      retry_command git fetch --force --tags origin
      git checkout --force "${SWOOLE_CLI_REF}"
    fi
  fi

  # 清理上一次构建输出，但保留 pool/ 下载缓存，方便本地和 CI cache 复用依赖源码。
  rm -f make.sh
  rm -rf bin/swoole-cli bin/dist thirdparty var/php-* modules libs libphp.la
}

assert_target_php_version() {
  local upstream_php_version
  upstream_php_version=$(tr -d '[:space:]' < sapi/PHP-VERSION.conf)
  if [[ "${upstream_php_version}" != "${PHP_VERSION}."* ]]; then
    cat >&2 <<ERROR
Swoole CLI ref ${SWOOLE_CLI_REF} targets PHP ${upstream_php_version}, not PHP ${PHP_VERSION}.x.
Please choose a matching PHPSFX_SWOOLE_CLI_REF or set PHPSFX_PHP_VERSION=${upstream_php_version%.*}.
ERROR
    exit 1
  fi
}

prime_swoole_extension_archive() {
  local swoole_version tgz_file archive_url tmp_file first_entry helper_script helper_tmp
  if [[ -n "${SWOOLE_SRC_REF}" ]]; then
    swoole_version="${SWOOLE_SRC_REF}"
  elif [[ -f sapi/SWOOLE-VERSION.conf ]]; then
    swoole_version=$(tr -d '[:space:]' < sapi/SWOOLE-VERSION.conf)
  else
    swoole_version="${SWOOLE_CLI_REF%.0}"
  fi
  tgz_file="${SWOOLE_CLI_DIR}/pool/ext/swoole-${swoole_version}.tgz"

  # 上游 download-swoole-src-archive.sh 在部分 runner 上会被 sh 执行，导致 [[ 语法失败后重新 clone swoole-src。
  # 这里提前生成 prepare.php 期望的 tgz，并主动展开 ext/swoole，避免 archive checkout 的空子模块目录
  # 让 prepare.php 误判“源码目录已存在”而跳过下载，最终在 PHP 扩展编译阶段才失败。
  helper_script="${SWOOLE_CLI_DIR}/sapi/scripts/download-swoole-src-archive.sh"
  if [[ -f "${helper_script}" ]] && ! head -1 "${helper_script}" | grep -q '^#!'; then
    helper_tmp="${helper_script}.tmp.$$"
    {
      printf '%s\n' '#!/usr/bin/env bash'
      cat "${helper_script}"
    } > "${helper_tmp}"
    mv "${helper_tmp}" "${helper_script}"
    chmod +x "${helper_script}"
  fi

  mkdir -p "$(dirname "${tgz_file}")"
  if [[ ! -s "${tgz_file}" && -f "${SWOOLE_CLI_DIR}/ext/swoole/CMakeLists.txt" ]]; then
    echo "Priming swoole-src archive from checked-out submodule: ${tgz_file}" >&2
    tar -czf "${tgz_file}" -C "${SWOOLE_CLI_DIR}/ext/swoole" .
  fi

  if [[ ! -s "${tgz_file}" ]]; then
    archive_url="https://codeload.github.com/swoole/swoole-src/tar.gz/${swoole_version}"
    tmp_file="${tgz_file}.tmp.$$"
    echo "Bundled ext/swoole is empty, downloading swoole-src archive: ${archive_url}" >&2
    require_command curl
    retry_command curl -fL --retry 3 --retry-delay 2 -o "${tmp_file}" "${archive_url}"
    gzip -t "${tmp_file}"
    mv "${tmp_file}" "${tgz_file}"
  fi

  # git archive fallback 场景下 ext/swoole 常是空目录；Swoole CLI prepare.php 只判断目录是否存在，
  # 因此这里强制确保源码已经展开。codeload 归档包含顶层目录，官方脚本也使用 strip-components=1。
  if [[ ! -f "${SWOOLE_CLI_DIR}/ext/swoole/CMakeLists.txt" ]]; then
    echo "Expanding swoole-src ${swoole_version} into ${SWOOLE_CLI_DIR}/ext/swoole" >&2
    rm -rf "${SWOOLE_CLI_DIR}/ext/swoole"
    mkdir -p "${SWOOLE_CLI_DIR}/ext/swoole"
    first_entry=$(tar -tzf "${tgz_file}" | awk 'NR == 1 { print; found = 1 } END { exit found ? 0 : 1 }')
    if [[ "${first_entry}" == */* ]]; then
      tar --strip-components=1 -C "${SWOOLE_CLI_DIR}/ext/swoole" -xzf "${tgz_file}"
    else
      tar -C "${SWOOLE_CLI_DIR}/ext/swoole" -xzf "${tgz_file}"
    fi
  fi

  if [[ ! -f "${SWOOLE_CLI_DIR}/ext/swoole/CMakeLists.txt" ]]; then
    echo "swoole-src archive is invalid or incomplete: ${tgz_file}" >&2
    tar -tzf "${tgz_file}" | head -20 >&2 || true
    exit 1
  fi
  echo "Prepared swoole-src ${swoole_version}: ${tgz_file}" >&2
}

apply_profile_patches() {
  local enabled_file swoole_file curl_file libzip_file zlib_file redis_file oniguruma_file libsodium_file ext

  if [[ "${PHPSFX_DISABLE_FPM_RUNTIME:-${PHPSFX_SFX_ONLY_RUNTIME:-0}}" == "1" ]]; then
    python3 - "${SWOOLE_CLI_DIR}/sapi/cli/config.m4" "${SWOOLE_CLI_DIR}/sapi/cli/php_cli.c" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
cli_path = Path(sys.argv[2])

config = config_path.read_text(encoding="utf-8")
config = config.replace(
    "  PHP_ADD_BUILD_DIR(sapi/cli/fpm)\n  PHP_ADD_BUILD_DIR(sapi/cli/fpm/events)\n",
    "",
)
config = re.sub(
    r'  PHP_FPM_FILES="fpm/fpm\.c \\\n.*?\n  "\n',
    '  PHP_FPM_FILES=""\n',
    config,
    flags=re.S,
)
config = config.replace(
    "PHP_SELECT_CLI_SAPI(cli, program, $PHP_CLI_FILES $PHP_FPM_FILES $PHP_SFX_FILES $PHP_FPM_TRACE_FILES, -DZEND_ENABLE_STATIC_TSRMLS_CACHE=1, '$(SAPI_CLI_PATH)')",
    "PHP_SELECT_CLI_SAPI(cli, program, $PHP_CLI_FILES $PHP_SFX_FILES, -DZEND_ENABLE_STATIC_TSRMLS_CACHE=1 -DSWOOLE_CLI_NO_FPM=1, '$(SAPI_CLI_PATH)')",
)
config_path.write_text(config, encoding="utf-8")

cli = cli_path.read_text(encoding="utf-8")
cli, fpm_case_count = re.subn(
    r"case 'P':\s*return fpm_main\(argc, argv\);\s*default:",
    "case 'P':\n#ifndef SWOOLE_CLI_NO_FPM\n\t\t\treturn fpm_main(argc, argv);\n#else\n\t\t\tphp_cli_usage(argv[0]);\n\t\t\treturn FAILURE;\n#endif\n\t\tdefault:",
    cli,
    count=1,
)
if fpm_case_count != 1:
    raise RuntimeError("Unable to patch php-fpm -P entry in sapi/cli/php_cli.c")
cli_path.write_text(cli, encoding="utf-8")
PY
    echo "Applied php-fpm disabled runtime profile" >&2
  fi

  # Swoole CLI 上游默认启用 full profile；这里将默认启用列表改为 profile 明确声明的最小集合，
  # 防止 prepare.php 在解析依赖时下载 sqlite/intl/gd/imagick/mongodb 等未使用组件。
  if [[ -n "${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS:-}" ]]; then
    enabled_file="${SWOOLE_CLI_DIR}/sapi/src/builder/enabled_extensions.php"
    {
      printf '%s\n' '<?php'
      printf '%s\n' 'return ['
      IFS=',' read -r -a enabled_extensions <<< "${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS}"
      for ext in "${enabled_extensions[@]}"; do
        ext=$(echo "${ext}" | xargs)
        [[ -z "${ext}" ]] && continue
        printf "    '%s',\n" "${ext}"
      done
      printf '%s\n' '];'
    } > "${enabled_file}"
    echo "Applied enabled extension profile: ${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS}" >&2
  fi

  if [[ "${PHPSFX_SWOOLE_SLIM_EXTENSION:-0}" == "1" ]]; then
    swoole_file="${SWOOLE_CLI_DIR}/sapi/src/builder/extension/swoole.php"
    cat > "${swoole_file}" <<'PHP'
<?php

use SwooleCli\Extension;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    // slim profile:
    // 保留 Swoole HTTP/TCP/WebSocket server、coroutine、mysqlnd、curl hook 和 c-ares DNS 能力；
    // 不启用 pgsql/sqlite/odbc/ssh2/ftp/thread/brotli/zstd 等可选功能，减少依赖库和二进制体积。
    $dependentLibraries = ['curl', 'openssl', 'cares', 'zlib'];
    $dependentExtensions = ['curl', 'openssl', 'sockets', 'mysqlnd', 'pdo'];

    $options = [
        '--enable-swoole',
        '--enable-sockets',
        '--enable-mysqlnd',
        '--enable-swoole-curl',
        '--enable-cares',
    ];

    $p->addExtension((new Extension('swoole'))
        ->withHomePage('https://github.com/swoole/swoole-src')
        ->withLicense('https://github.com/swoole/swoole-src/blob/master/LICENSE', Extension::LICENSE_APACHE2)
        ->withManual('https://wiki.swoole.com/#/')
        ->withOptions(implode(' ', $options))
        ->withBuildCached(false)
        ->withDependentLibraries(...$dependentLibraries)
        ->withDependentExtensions(...$dependentExtensions));

    $p->withVariable('LIBS', '$LIBS ' . ($p->isMacos() ? '-lc++' : '-lstdc++'));
    $p->withExportVariable('CARES_CFLAGS', '$(pkg-config  --cflags --static  libcares)');
    $p->withExportVariable('CARES_LIBS', '$(pkg-config    --libs   --static  libcares)');
};
PHP
    echo "Applied slim Swoole extension profile" >&2
  fi

  if [[ "${PHPSFX_CURL_SLIM_LIBRARY:-0}" == "1" ]]; then
    curl_file="${SWOOLE_CLI_DIR}/sapi/src/builder/library/curl.php"
    cat > "${curl_file}" <<'PHP'
<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    $curl_prefix = CURL_PREFIX;
    $openssl_prefix = OPENSSL_PREFIX;
    $zlib_prefix = ZLIB_PREFIX;
    $cares_prefix = CARES_PREFIX;

    $p->addLibrary(
        (new Library('curl'))
            ->withHomePage('https://curl.se/')
            ->withManual('https://curl.se/docs/install.html')
            ->withLicense('https://github.com/curl/curl/blob/master/COPYING', Library::LICENSE_SPEC)
            ->withUrl('https://github.com/curl/curl/releases/download/curl-8_16_0/curl-8.16.0.tar.gz')
            ->withFileHash('md5', '3db9de72cc8f04166fa02d3173ac78bb')
            ->withPrefix($curl_prefix)
            ->withConfigure(
                <<<EOF
            ./configure --help

            PACKAGES='zlib openssl libcares'
            CPPFLAGS="$(pkg-config  --cflags-only-I  --static \$PACKAGES) -I{$openssl_prefix}/include/openssl/" \
            LDFLAGS="$(pkg-config   --libs-only-L    --static \$PACKAGES)" \
            LIBS="$(pkg-config      --libs-only-l    --static \$PACKAGES)" \
            ./configure --prefix={$curl_prefix}  \
            --enable-static \
            --disable-shared \
            --without-librtmp \
            --disable-ldap \
            --disable-ldaps \
            --disable-rtsp \
            --enable-http \
            --enable-alt-svc \
            --enable-hsts \
            --enable-http-auth \
            --enable-mime \
            --enable-cookies \
            --enable-doh \
            --enable-ipv6 \
            --enable-proxy  \
            --enable-websockets \
            --enable-get-easy-options \
            --enable-file \
            --enable-unix-sockets  \
            --enable-progress-meter \
            --enable-optimize \
            --with-zlib={$zlib_prefix} \
            --enable-ares={$cares_prefix} \
            --with-openssl  \
            --with-default-ssl-backend=openssl \
            --without-brotli \
            --without-zstd \
            --without-nghttp2 \
            --without-nghttp3 \
            --without-ngtcp2 \
            --without-libidn2 \
            --without-libpsl \
            --without-libssh2 \
            --without-gnutls \
            --without-mbedtls \
            --without-wolfssl \
            --without-libressl \
            --without-rustls

EOF
            )
            ->withPkgName('libcurl')
            ->withBinPath($curl_prefix . '/bin/')
            ->withDependentLibraries('openssl', 'cares', 'zlib')
    );
};
PHP
    echo "Applied slim curl library profile" >&2
  fi

  if [[ "${PHPSFX_LIBZIP_SLIM_LIBRARY:-0}" == "1" ]]; then
    libzip_file="${SWOOLE_CLI_DIR}/sapi/src/builder/library/libzip.php"
    cat > "${libzip_file}" <<'PHP'
<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    $openssl_prefix = OPENSSL_PREFIX;
    $libzip_prefix = ZIP_PREFIX;
    $zlib_prefix = ZLIB_PREFIX;

    $p->addLibrary(
        (new Library('libzip'))
            ->withHomePage('https://libzip.org/')
            ->withLicense('https://libzip.org/license/', Library::LICENSE_BSD)
            ->withUrl('https://libzip.org/download/libzip-1.9.2.tar.gz')
            ->withFileHash('md5', '345a88add7e9dd58aa029ac5b5b361ad')
            ->withManual('https://libzip.org')
            ->withPrefix($libzip_prefix)
            ->withConfigure(
                <<<EOF
            mkdir -p build
            cd build
            cmake .. \
            -DCMAKE_INSTALL_PREFIX={$libzip_prefix} \
            -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_TOOLS=OFF \
            -DBUILD_EXAMPLES=OFF \
            -DBUILD_DOC=OFF \
            -DLIBZIP_DO_INSTALL=ON \
            -DENABLE_GNUTLS=OFF  \
            -DENABLE_MBEDTLS=OFF \
            -DENABLE_OPENSSL=ON \
            -DOPENSSL_USE_STATIC_LIBS=TRUE \
            -DENABLE_BZIP2=OFF \
            -DENABLE_COMMONCRYPTO=OFF \
            -DENABLE_LZMA=OFF \
            -DENABLE_ZSTD=OFF \
            -DOpenSSL_ROOT={$openssl_prefix} \
            -DZLIB_ROOT={$zlib_prefix} \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5

EOF
            )
            ->withMakeOptions('VERBOSE=1')
            ->withPkgName('libzip')
            ->withBinPath($libzip_prefix . '/bin/')
            ->withDependentLibraries('openssl', 'zlib')
    );
};
PHP
    echo "Applied slim libzip library profile" >&2
  fi

  if [[ "${PHPSFX_ZLIB_SLIM_LIBRARY:-0}" == "1" ]]; then
    zlib_file="${SWOOLE_CLI_DIR}/sapi/src/builder/library/zlib.php"
    cat > "${zlib_file}" <<'PHP'
<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    $p->addLibrary(
        (new Library('zlib'))
            ->withHomePage('https://zlib.net/')
            ->withLicense('https://zlib.net/zlib_license.html', Library::LICENSE_SPEC)
            ->withUrl('https://github.com/madler/zlib/archive/refs/tags/v1.3.1.tar.gz')
            ->withFile('zlib-v1.3.1.tar.gz')
            ->withFileHash('md5', 'ddb17dbbf2178807384e57ba0d81e6a1')
            ->withPrefix(ZLIB_PREFIX)
            ->withConfigure('./configure --prefix=' . ZLIB_PREFIX . ' --static')
            ->withPkgName('zlib')
    );
};
PHP
    echo "Applied slim zlib library profile" >&2
  fi

  if [[ "${PHPSFX_REDIS_DISABLE_SESSION:-0}" == "1" ]]; then
    redis_file="${SWOOLE_CLI_DIR}/sapi/src/builder/extension/redis.php"
    cat > "${redis_file}" <<'PHP'
<?php

use SwooleCli\Extension;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    $p->addExtension(
        (new Extension('redis'))
            ->withOptions('--enable-redis --disable-redis-session')
            ->withPeclVersion('6.2.0')
            ->withFileHash('md5', 'b713b42a7ad2eb6638de739fffd62c3a')
            ->withHomePage('https://github.com/phpredis/phpredis')
            ->withLicense('https://github.com/phpredis/phpredis/blob/develop/COPYING', Extension::LICENSE_PHP)
    );
};
PHP
    echo "Applied redis without session profile" >&2
  fi

  if [[ "${PHPSFX_ONIGURUMA_CLANG_COMPAT:-0}" == "1" ]]; then
    oniguruma_file="${SWOOLE_CLI_DIR}/sapi/src/builder/library/oniguruma.php"
    cat > "${oniguruma_file}" <<'PHP'
<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    $oniguruma_prefix = ONIGURUMA_PREFIX;
    $cflags = $p->isMacos() ? 'CFLAGS="$CFLAGS -Wno-error=incompatible-function-pointer-types" ' : '';
    $p->addLibrary(
        (new Library('oniguruma'))
            ->withHomePage('https://github.com/kkos/oniguruma.git')
            ->withUrl('https://github.com/kkos/oniguruma/releases/download/v6.9.10/onig-6.9.10.tar.gz')
            ->withFile('onig-6.9.10.tar.gz')
            ->withFileHash('sha256', '2a5cfc5ae259e4e97f86b68dfffc152cdaffe94e2060b770cb827238d769fc05')
            ->withPrefix($oniguruma_prefix)
            ->withConfigure(
                $cflags . './configure --prefix=' . $oniguruma_prefix . ' --enable-static --disable-shared'
            )
            ->withLicense('https://github.com/kkos/oniguruma/blob/master/COPYING', Library::LICENSE_SPEC)
            ->withPkgName('oniguruma')
            ->withBinPath($oniguruma_prefix . '/bin/')
    );
};
PHP
    echo "Applied oniguruma clang compatibility profile" >&2
  fi

  if [[ "${PHPSFX_LIBSODIUM_STABLE_LIBRARY:-0}" == "1" ]]; then
    libsodium_file="${SWOOLE_CLI_DIR}/sapi/src/builder/library/libsodium.php"
    cat > "${libsodium_file}" <<'PHP'
<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;

return function (Preprocessor $p) {
    $p->addLibrary(
        (new Library('libsodium'))
            // 老版本 Swoole CLI 引用的 libsodium 1.0.18 上游下载地址已经不可用；
            // 统一使用 1.0.21 release tarball，保持 sodium 扩展能力不变并避免 CI 下载 404。
            ->withLicense('https://en.wikipedia.org/wiki/ISC_license', Library::LICENSE_SPEC)
            ->withHomePage('https://doc.libsodium.org/')
            ->withUrl('https://download.libsodium.org/libsodium/releases/libsodium-1.0.21.tar.gz')
            ->withFileHash('md5', 'ecd60ebc2c916133db2f6b3b2e9e775d')
            ->withPrefix(LIBSODIUM_PREFIX)
            ->withConfigure('./configure --prefix=' . LIBSODIUM_PREFIX . ' --enable-static --disable-shared')
            ->withPkgName('libsodium')
    );
};
PHP
    echo "Applied stable libsodium library profile" >&2
  fi
}

if [[ -z "${PLATFORM}" ]]; then
  PLATFORM=$(detect_platform)
fi

case "${PLATFORM}" in
  linux-x64|linux-a64|macos-x64|macos-a64) ;;
  -h|--help) usage; exit 0 ;;
  *)
    usage >&2
    echo "Unsupported platform: ${PLATFORM}" >&2
    exit 2
    ;;
esac
GLOBAL_PREFIX=${PHPSFX_GLOBAL_PREFIX:-"${SWOOLE_CLI_DIR}/.global-prefix/${PLATFORM}"}

require_command git
require_command php
require_command composer
require_command make
require_command tar

checkout_swoole_cli
if [[ -d .git ]]; then
  SWOOLE_CLI_COMMIT=$(git rev-parse HEAD)
else
  SWOOLE_CLI_COMMIT="${SWOOLE_CLI_REF} (archive)"
fi
assert_target_php_version
prime_swoole_extension_archive
apply_profile_patches
mkdir -p "${GLOBAL_PREFIX}"

export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-interaction --no-progress --prefer-dist --no-dev --no-scripts --optimize-autoloader

# Swoole CLI 官方构建链路：prepare.php 生成 make.sh，随后依次构建依赖库、configure、build。
# prepare.php 支持 +extension/-extension 裁剪扩展；--without-docker 让工作目录固定为当前 checkout，适合 GitHub runner/WSL/macOS。
PREPARE_ARGS=()
if [[ -n "${PREPARE_FLAGS}" ]]; then
  read -r -a PREPARE_ARGS <<< "${PREPARE_FLAGS}"
fi
if [[ -n "${DOWNLOAD_MIRROR_URL}" ]]; then
  PREPARE_ARGS+=("--with-download-mirror-url=${DOWNLOAD_MIRROR_URL}")
fi
php prepare.php --without-docker=1 --with-parallel-jobs="${JOBS}" --with-global-prefix="${GLOBAL_PREFIX}" "${PREPARE_ARGS[@]}"

bash ./make.sh all-library
bash ./make.sh config
bash ./make.sh build

SWOOLE_CLI_BIN="${SWOOLE_CLI_DIR}/bin/swoole-cli"
if [[ ! -s "${SWOOLE_CLI_BIN}" ]]; then
  echo "swoole-cli was not generated: ${SWOOLE_CLI_BIN}" >&2
  exit 1
fi

ASSET_NAME="swoole-cli-php${PHP_VERSION}-${PROFILE_NAME}-${PLATFORM}"
cp "${SWOOLE_CLI_BIN}" "${DIST_DIR}/${ASSET_NAME}"
chmod +x "${DIST_DIR}/${ASSET_NAME}"
strip_output_binary "${DIST_DIR}/${ASSET_NAME}"
chmod +x "${DIST_DIR}/${ASSET_NAME}"

PHPSFX_EXPECTED_PHP_PREFIX="${PHP_VERSION}." \
PHPSFX_REQUIRED_EXTENSIONS="${EXPECTED_EXTENSIONS}" \
PHPSFX_FORBIDDEN_EXTENSIONS="${FORBIDDEN_EXTENSIONS}" \
  bash "${ROOT_DIR}/scripts/validate-swoole-cli.sh" "${DIST_DIR}/${ASSET_NAME}"

SHA256=$(sha256_file "${DIST_DIR}/${ASSET_NAME}")
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META_NAME="build-meta-php${PHP_VERSION}-${PROFILE_NAME}-${PLATFORM}.json"
cat > "${DIST_DIR}/${META_NAME}" <<META
{
  "platform": "${PLATFORM}",
  "asset": "${ASSET_NAME}",
  "profile": "${PROFILE_NAME}",
  "php_version": "${PHP_VERSION}",
  "extensions": "${PHPSFX_EXTENSIONS:-${DEFAULT_EXTENSIONS}}",
  "required_extensions": "${EXPECTED_EXTENSIONS}",
  "forbidden_extensions": "${FORBIDDEN_EXTENSIONS}",
  "prepare_enabled_extensions": "${PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS:-}",
  "swoole_slim_extension": "${PHPSFX_SWOOLE_SLIM_EXTENSION:-0}",
  "curl_slim_library": "${PHPSFX_CURL_SLIM_LIBRARY:-0}",
  "libzip_slim_library": "${PHPSFX_LIBZIP_SLIM_LIBRARY:-0}",
  "zlib_slim_library": "${PHPSFX_ZLIB_SLIM_LIBRARY:-0}",
  "redis_disable_session": "${PHPSFX_REDIS_DISABLE_SESSION:-0}",
  "oniguruma_clang_compat": "${PHPSFX_ONIGURUMA_CLANG_COMPAT:-0}",
  "libsodium_stable_library": "${PHPSFX_LIBSODIUM_STABLE_LIBRARY:-0}",
  "disable_fpm_runtime": "${PHPSFX_DISABLE_FPM_RUNTIME:-${PHPSFX_SFX_ONLY_RUNTIME:-0}}",
  "strip_binary": "${STRIP_BINARY}",
  "swoole_cli_repo": "${SWOOLE_CLI_REPO}",
  "swoole_cli_ref": "${SWOOLE_CLI_REF}",
  "swoole_cli_checkout_mode": "${SWOOLE_CLI_CHECKOUT_MODE}",
  "swoole_src_ref": "${SWOOLE_SRC_REF}",
  "swoole_cli_commit": "${SWOOLE_CLI_COMMIT}",
  "prepare_flags": "${PREPARE_FLAGS}",
  "global_prefix": "${GLOBAL_PREFIX}",
  "sha256": "${SHA256}",
  "built_at": "${BUILT_AT}"
}
META

printf 'Built %s\n' "${DIST_DIR}/${ASSET_NAME}"
printf 'SHA256 %s  %s\n' "${SHA256}" "${ASSET_NAME}"
