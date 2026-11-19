#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE_FILE=${PHPSFX_PROFILE_FILE:-"${ROOT_DIR}/scripts/profiles/hyperfadmin-slim.env"}
if [[ -n "${PROFILE_FILE}" && "${PROFILE_FILE}" != none ]]; then
  [[ "${PROFILE_FILE}" = /* ]] || PROFILE_FILE="${ROOT_DIR}/${PROFILE_FILE}"
  [[ -f "${PROFILE_FILE}" ]] || { echo "Profile file does not exist: ${PROFILE_FILE}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${PROFILE_FILE}"
fi

PLATFORM=${1:-${PHPSFX_PLATFORM:-}}
PHP_VERSION=${PHPSFX_PHP_VERSION:-8.5}
case "${PHP_VERSION}" in
  8.4) PHP_FULL_VERSION=${PHPSFX_PHP_FULL_VERSION:-8.4.27} ;;
  8.5) PHP_FULL_VERSION=${PHPSFX_PHP_FULL_VERSION:-8.5.12} ;;
  *) echo "Unsupported PHPSFX_PHP_VERSION: ${PHP_VERSION}" >&2; exit 2 ;;
esac

case "${PLATFORM}" in
  linux-x64|linux-a64|macos-x64|macos-a64|windows-x64) ;;
  *)
    echo "This experiment currently supports linux-x64, linux-a64, macos-x64, macos-a64 and windows-x64: ${PLATFORM}" >&2
    exit 2
    ;;
esac

PHP_FULL_VERSION=${PHPSFX_PHP_FULL_VERSION:-${PHP_FULL_VERSION}}
DB_VARIANT=${PHPSFX_DB_VARIANT:-mysql}
SWOOLE_ODBC_ENABLED=${PHPSFX_SWOOLE_ODBC:-0}
SWOOLE_SRC_REF=${PHPSFX_SWOOLE_SRC_REF:-v6.2.5}
SWOOLE_SRC_REF="v${SWOOLE_SRC_REF#v}"
EXPECTED_SWOOLE_VERSION=${PHPSFX_EXPECTED_SWOOLE_VERSION:-${SWOOLE_SRC_REF#v}}
SPC_REPO=${PHPSFX_MICRO_SPC_REPO:-https://github.com/crazywhalecc/static-php-cli.git}
SPC_REF=${PHPSFX_MICRO_SPC_REF:-956fa13e7c390e3127cc0343215c00491f13a835}
SPC_DIR=${PHPSFX_MICRO_SPC_DIR:-"${ROOT_DIR}/.build/static-php-cli-micro-${PHP_VERSION}-${PLATFORM}-${DB_VARIANT}"}
DIST_DIR=${PHPSFX_DIST_DIR:-"${ROOT_DIR}/dist/micro-${PHP_VERSION}-${PLATFORM}-${DB_VARIANT}"}
SKIP_DOCTOR=${PHPSFX_MICRO_SKIP_DOCTOR:-0}
PREFER_PREBUILT=${PHPSFX_MICRO_PREFER_PREBUILT:-0}
MICRO_DYNAMIC_ODBC=${PHPSFX_MICRO_DYNAMIC_ODBC:-1}
MICRO_SPC_TARGET=${PHPSFX_MICRO_SPC_TARGET:-}
TRIM_NATIVE_PDO_EXTENSIONS=${PHPSFX_MICRO_TRIM_NATIVE_PDO_EXTENSIONS:-1}
DISABLE_OPCACHE_JIT=${PHPSFX_MICRO_DISABLE_OPCACHE_JIT:-1}
MICRO_EXTENSIONS=${PHPSFX_MICRO_EXTENSIONS:-${PHPSFX_EXTENSIONS:-}}
EXPECTED_EXTENSIONS=${PHPSFX_REQUIRED_EXTENSIONS:-swoole,redis,phar,zlib}
FORBIDDEN_EXTENSIONS=${PHPSFX_FORBIDDEN_EXTENSIONS:-}
REQUIRED_PDO_DRIVERS=${PHPSFX_REQUIRED_PDO_DRIVERS:-}
case "${DB_VARIANT}" in
  mysql|pgsql) ;;
  odbc)
    if [[ "${PLATFORM}" != linux-* ]]; then
      echo "The micro ODBC variant is supported on Linux only: ${PLATFORM}" >&2
      exit 2
    fi
    ;;
  *) echo "Unsupported micro production variant: ${DB_VARIANT}; choose mysql, pgsql or odbc" >&2; exit 2 ;;
esac

usage() {
  cat <<'USAGE'
Usage: scripts/build-micro-sfx.sh [platform]

Platforms:
  linux-x64, linux-a64, macos-x64, macos-a64, windows-x64

Important environment variables:
  PHPSFX_PHP_VERSION             PHP version line, 8.4 or 8.5
  PHPSFX_PHP_FULL_VERSION        Exact PHP version, 8.4.27 or 8.5.12
  PHPSFX_DB_VARIANT              mysql, pgsql or odbc (no mixed development variant)
  PHPSFX_PROFILE_FILE            Current phpsfx profile file
  PHPSFX_MICRO_SPC_REF           Pinned static-php-cli commit
  PHPSFX_MICRO_SPC_TARGET       Linux target override (ODBC defaults to glibc 2.17)
  PHPSFX_MICRO_DYNAMIC_ODBC     Use a dynamically linked unixODBC manager on Linux
  PHPSFX_SWOOLE_SRC_REF          Swoole source tag/commit, default v6.2.5
  PHPSFX_MICRO_SPC_DIR           Per-build static-php-cli checkout directory
  PHPSFX_MICRO_SKIP_DOCTOR      Set to 1 when the host build tools are preinstalled
  PHPSFX_MICRO_PREFER_PREBUILT  Set to 1 to use static-php-cli hosted packages
  PHPSFX_MICRO_TRIM_NATIVE_PDO_EXTENSIONS  Keep PDO drivers without pgsql/sqlite3 extensions
  PHPSFX_MICRO_DISABLE_OPCACHE_JIT         Disable unused OPcache JIT code generation (default: 1)
  PHPSFX_DIST_DIR                Output directory
USAGE
}

if [[ "${PLATFORM}" == -h || "${PLATFORM}" == --help ]]; then
  usage
  exit 0
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 127; }
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

file_size() {
  if stat -c '%s' "$1" >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

append_extension() {
  local name=$1
  case ",${MICRO_EXTENSIONS}," in
    *,"${name}",*) ;;
    *) MICRO_EXTENSIONS="${MICRO_EXTENSIONS:+${MICRO_EXTENSIONS},}${name}" ;;
  esac
}

remove_extension() {
  local remove_name=$1
  local extension_list=$2
  local extension
  local filtered=
  local first=1
  local -a extensions=()
  IFS=',' read -r -a extensions <<< "${extension_list}"
  for extension in "${extensions[@]}"; do
    [[ "${extension}" == "${remove_name}" ]] && continue
    if [[ "${first}" == 1 ]]; then
      filtered="${extension}"
      first=0
    else
      filtered+=",${extension}"
    fi
  done
  printf '%s' "${filtered}"
}

# Only the MySQL production variant carries mysqlnd and the Swoole MySQL hook;
# the pgsql/odbc variants keep a strict single-PDO contract.
case "${DISABLE_OPCACHE_JIT}" in
  0|1) ;;
  *) echo "PHPSFX_MICRO_DISABLE_OPCACHE_JIT must be 0 or 1" >&2; exit 2 ;;
esac

if [[ "${PLATFORM}" == windows-* ]]; then
  # pcntl is unavailable on the native Windows builder. Keep the shared
  # profile unchanged for Linux and macOS builds.
  MICRO_EXTENSIONS=$(remove_extension pcntl "${MICRO_EXTENSIONS}")
fi

if [[ "${DB_VARIANT}" == mysql ]]; then
  append_extension swoole-hook-mysql
fi
if [[ "${SWOOLE_ODBC_ENABLED}" == 1 ]]; then
  append_extension swoole-hook-odbc
fi

patch_native_pdo_dependencies() {
  [[ "${TRIM_NATIVE_PDO_EXTENSIONS}" == 1 ]] || return 0
  local config_path="${SPC_DIR}/config/ext.json"
  php -r '
$path = $argv[1];
$data = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);
foreach (["pdo_pgsql" => "pgsql", "pdo_sqlite" => "sqlite3"] as $extension => $native) {
    if (!isset($data[$extension]["ext-depends"]) || !is_array($data[$extension]["ext-depends"])) {
        throw new RuntimeException("Missing ext-depends for {$extension}");
    }
    $data[$extension]["ext-depends"] = array_values(array_diff($data[$extension]["ext-depends"], [$native]));
}
// Let PHP use static pkg-config for libpq. Passing the PostgreSQL prefix makes
// PHP fall back to pg_config and emits only -lpq, which omits libpgcommon and
// libpgport from static links on current PostgreSQL releases.
if (isset($data["pdo_pgsql"]) && ($data["pdo_pgsql"]["arg-type"] ?? null) === "with-path") {
    $data["pdo_pgsql"]["arg-type"] = "with";
}
$json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
if (file_put_contents($path, $json) === false) {
    throw new RuntimeException("Unable to write {$path}");
}
' "${config_path}"
  echo 'Trimmed native PDO dependencies and selected static pkg-config for pdo_pgsql' >&2
}

patch_windows_swoole_dependencies() {
  [[ "${PLATFORM}" == windows-* ]] || return 0
  local config_path="${SPC_DIR}/config/ext.json"
  php -r '
$path = $argv[1];
$data = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);
if (!isset($data["swoole"]) || !is_array($data["swoole"])) {
    throw new RuntimeException("Missing Swoole extension configuration");
}
foreach (["lib-depends", "lib-depends-windows"] as $key) {
    if (isset($data["swoole"][$key]) && is_array($data["swoole"][$key])) {
        $data["swoole"][$key] = array_values(array_diff($data["swoole"][$key], ["libcares"]));
    }
}
$json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
if (file_put_contents($path, $json) === false) {
    throw new RuntimeException("Unable to write {$path}");
}
' "${config_path}"
  echo 'Removed unsupported Windows Swoole libcares dependency; native DNS remains available' >&2
}

patch_windows_spc_paths() {
  [[ "${PLATFORM}" == windows-* ]] || return 0
  local filesystem_path="${SPC_DIR}/src/SPC/store/FileSystem.php"
  python3 - "${filesystem_path}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = (
    "    private static function extractArchive(string $filename, string $target): void\n"
    "    {\n"
)
replacement = needle + (
    "        $filename = self::convertPath($filename);\n"
    "        $target = self::convertPath($target);\n"
)
if source.count(needle) != 1:
    raise SystemExit("Unexpected static-php-cli extractArchive anchor")
source = source.replace(needle, replacement, 1)
command = (
    """                'xz', 'txz', 'gz', 'tgz', 'bz2' => """
    """cmd()->execWithResult("\\"{$_7z}\\" x -so {$filename} | tar -f - -x -C \\"{$target}\\" --strip-components 1"),"""
)
replacement_command = (
    """                'xz', 'txz' => """
    """cmd()->execWithResult("\\"" . """
    """(getenv('PHPSFX_WINDOWS_TAR') ?: 'tar') . """
    """ "\\" -xf \\"{$filename}\\" -C \\"{$target}\\" --strip-components 1"),"""
    """                'gz', 'tgz', 'bz2' => """
    """cmd()->execWithResult("\\"{$_7z}\\" x -so {$filename} | \\"" . """
    """(getenv('PHPSFX_WINDOWS_TAR') ?: 'tar') . """
    """ "\\" -f - -x -C \\"{$target}\\" --strip-components 1"),"""
)
if source.count(command) != 1:
    raise SystemExit("Unexpected static-php-cli Windows tar command")
path.write_text(source.replace(command, replacement_command, 1), encoding="utf-8")
PY
  echo 'Normalized static-php-cli Windows archive paths and tar command' >&2
}

patch_dynamic_odbc_builder() {
  [[ "${DB_VARIANT}" == odbc && "${PLATFORM}" == linux-* && "${MICRO_DYNAMIC_ODBC}" == 1 ]] || return 0

  # The pinned static-php-cli release defaults Linux to a pure-musl link and
  # builds unixODBC with --disable-shared. Keep PHP/Swoole/extensions static,
  # but let the Linux ODBC experiment use glibc and expose libodbc.so.2.
  local linux_builder="${SPC_DIR}/src/SPC/builder/linux/LinuxBuilder.php"
  local autoconf_executor="${SPC_DIR}/src/SPC/util/executor/UnixAutoconfExecutor.php"
  local zig_toolchain="${SPC_DIR}/src/SPC/toolchain/ZigToolchain.php"
  local unixodbc_builder="${SPC_DIR}/src/SPC/builder/unix/library/unixodbc.php"
  [[ -f "${linux_builder}" && -f "${autoconf_executor}" && -f "${zig_toolchain}" && -f "${unixodbc_builder}" ]] || {
    echo "Pinned static-php-cli layout does not expose the Linux ODBC patch points" >&2
    return 1
  }

  php -r '
$path = $argv[1];
$source = file_get_contents($path);
$search = "            (\$enableMicro ? \x27--enable-micro=all-static \x27 : \x27--disable-micro \x27) .";
$replace = "            (\$enableMicro ? (getenv(\x27PHPSFX_MICRO_DYNAMIC_ODBC\x27) === \x271\x27 ? \x27--enable-micro \x27 : \x27--enable-micro=all-static \x27) : \x27--disable-micro \x27) .";
if (substr_count($source, $search) !== 1) {
    throw new RuntimeException("Unexpected LinuxBuilder micro configure anchor");
}
$source = str_replace($search, $replace, $source);
file_put_contents($path, $source);
' "${linux_builder}"

  php -r '
$path = $argv[1];
$source = file_get_contents($path);
$search = "            \x27--enable-static\x27,\n            \x27--disable-shared\x27,";
$replace = "            getenv(\x27PHPSFX_MICRO_DYNAMIC_ODBC\x27) === \x271\x27 && \$this->library->getName() === \x27unixodbc\x27 ? \x27--enable-shared\x27 : \x27--disable-shared\x27,\n            \x27--enable-static\x27,";
if (substr_count($source, $search) !== 1) {
    throw new RuntimeException("Unexpected UnixAutoconfExecutor configure anchor");
}
$source = str_replace($search, $replace, $source);
file_put_contents($path, $source);
' "${autoconf_executor}"

  php -r '
$path = $argv[1];
$source = file_get_contents($path);
$search = "        \x27EXTRA_LIBS\x27 => \$config[\x27libs\x27],";
$replace = "        \x27EXTRA_LIBS\x27 => getenv(\x27PHPSFX_MICRO_DYNAMIC_ODBC\x27) === \x271\x27\n            ? str_replace(\n                [\x27-Wl,-Bstatic,-lresolv,-Bdynamic\x27, BUILD_LIB_PATH . \x27/libodbc.a\x27, BUILD_LIB_PATH . \x27/libodbccr.a\x27, BUILD_LIB_PATH . \x27/libodbcinst.a\x27],\n                [\x27-lresolv\x27, \x27-lodbc\x27, \x27-Wl,--no-as-needed -lodbccr\x27, \x27-lodbcinst -Wl,--as-needed\x27],\n                \$config[\x27libs\x27],\n            )\n            : \$config[\x27libs\x27],";
if (substr_count($source, $search) !== 1) {
    throw new RuntimeException("Unexpected LinuxBuilder EXTRA_LIBS anchor");
}
$source = str_replace($search, $replace, $source);
file_put_contents($path, $source);
' "${linux_builder}"

  php -r '
$path = $argv[1];
$source = file_get_contents($path);
$search = "        GlobalEnvManager::putenv(\x27SPC_LINUX_DEFAULT_LD=zig-ld.lld\x27);";
$replace = "        GlobalEnvManager::putenv(\x27SPC_LINUX_DEFAULT_LD=\x27 . (getenv(\x27PHPSFX_MICRO_DYNAMIC_ODBC\x27) === \x271\x27 ? \x27zig-cc\x27 : \x27zig-ld.lld\x27));";
if (substr_count($source, $search) !== 1) {
    throw new RuntimeException("Unexpected ZigToolchain LD anchor");
}
file_put_contents($path, str_replace($search, $replace, $source));
' "${zig_toolchain}"

  python3 - "${unixodbc_builder}" "${linux_builder}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
needle = "    protected function build(): void\n    {\n"
insert = r'''        if (getenv('PHPSFX_MICRO_DYNAMIC_ODBC') === '1' && PHP_OS_FAMILY === 'Linux') {
            // Stage the runner's unixODBC Driver Manager. PHP/Swoole and all
            // other libraries remain static; only libodbc.so.2 is dynamic.
            $root = $this->getBuildRootPath();
            $include = $root . '/include';
            $lib = $root . '/lib';
            $pkgconfig = $lib . '/pkgconfig';
            \SPC\util\GlobalEnvManager::putenv('PKG_CONFIG_PATH=' . $pkgconfig . ':' . (getenv('PKG_CONFIG_PATH') ?: ''));
            foreach ([$include, $lib, $pkgconfig] as $directory) {
                if (!is_dir($directory) && !mkdir($directory, 0777, true) && !is_dir($directory)) {
                    throw new \RuntimeException("Unable to create unixODBC staging directory: {$directory}");
                }
            }
            $systemInclude = trim((string) shell_exec('pkg-config --variable=includedir odbc 2>/dev/null')) ?: '/usr/include';
            $systemIncludeCandidates = [$systemInclude];
            $systemIncludeFlags = trim((string) shell_exec('pkg-config --cflags-only-I odbc 2>/dev/null'));
            foreach (preg_split('/\s+/', $systemIncludeFlags) as $flag) {
                if (str_starts_with($flag, '-I') && strlen($flag) > 2) {
                    $systemIncludeCandidates[] = substr($flag, 2);
                }
            }
            foreach (['odbc.h', 'sql.h', 'sqlext.h', 'sqltypes.h', 'sqlucode.h', 'unixodbc.h', 'odbcinst.h'] as $header) {
                $source = '';
                foreach ($systemIncludeCandidates as $candidate) {
                    if (is_file($candidate . '/' . $header)) {
                        $source = $candidate . '/' . $header;
                        break;
                    }
                }
                if ($source === '') {
                    $source = trim((string) shell_exec('find /usr/include /usr/local/include -type f -name ' . escapeshellarg($header) . ' -print -quit 2>/dev/null'));
                }
                if ($source === '' && $header === 'odbc.h') {
                    continue;
                }
                if ($source === '' || !copy($source, $include . '/' . $header)) {
                    throw new \RuntimeException("Missing system unixODBC header: {$header}");
                }
            }
            foreach (['odbc', 'odbccr', 'odbcinst'] as $library) {
                $soname = 'lib' . $library . '.so.2';
                $resolved = trim((string) shell_exec("ldconfig -p 2>/dev/null | awk '/{$soname} / {print \$NF; exit}'"));
                if ($resolved === '' || !is_file($resolved)) {
                    throw new \RuntimeException("Missing system unixODBC shared library: {$soname}");
                }
                foreach ([$soname, 'lib' . $library . '.so'] as $link) {
                    $target = $lib . '/' . $link;
                    @unlink($target);
                    if (!symlink($resolved, $target)) {
                        throw new \RuntimeException("Unable to stage unixODBC shared library: {$target}");
                    }
                }
                $archive = $lib . '/lib' . $library . '.a';
                if (!is_file($archive)) {
                    $status = 0;
                    exec('ar rcs ' . escapeshellarg($archive), $output, $status);
                    if ($status !== 0 || !is_file($archive)) {
                        throw new \RuntimeException("Unable to create unixODBC link placeholder: {$archive}");
                    }
                }
                $pc = "prefix={$root}\nlibdir={$lib}\nincludedir={$include}\nName: unixODBC {$library}\nDescription: unixODBC driver manager\nVersion: 2.3.12\nLibs: -l{$library}\nCflags: -I{$include}\n";
                if (file_put_contents($pkgconfig . '/' . $library . '.pc', $pc) === false) {
                    throw new \RuntimeException("Unable to write unixODBC pkg-config file: {$library}");
                }
            }
            return;
        }
'''
if source.count(needle) != 1:
    raise SystemExit(f'unexpected unixODBC build anchor: {source.count(needle)}')
path.write_text(source.replace(needle, needle + insert, 1))

linux_path = Path(sys.argv[2])
linux_source = linux_path.read_text()
linux_needle = """            shell()->cd(SOURCE_PATH . '/php-src')
                ->exec('sed -i \"s|//lib|/lib|g\" Makefile')
                ->exec(\"make {$concurrency} {$vars} micro\");"""
linux_insert = """            shell()->cd(SOURCE_PATH . '/php-src')
                ->exec('sed -i \"s|//lib|/lib|g\" Makefile')
                ->exec(\"sed -i 's|-Wl,-Bstatic,-lresolv,-Bdynamic|-lresolv|g' Makefile\")
                ->exec(\"make {$concurrency} {$vars} micro\");"""
if linux_source.count(linux_needle) != 1:
    raise SystemExit(f'unexpected LinuxBuilder micro make anchor: {linux_source.count(linux_needle)}')
linux_path.write_text(linux_source.replace(linux_needle, linux_insert, 1))

linux_source = linux_path.read_text()
linux_needle = """            $vars = $this->getMakeExtraVars();

            // patch fake cli"""
linux_insert = """            $vars = $this->getMakeExtraVars();
            if (getenv('PHPSFX_MICRO_UBSAN_LINK') === '1') {
                // PHP 8.5's ODBC bridge can leave UBSan references in the
                // Swoole C++ objects. Ask the Zig driver to link compiler_rt
                // so the final micro.sfx contains the matching handlers.
                $vars['EXTRA_LIBS'] = trim(($vars['EXTRA_LIBS'] ?? '') . ' -fsanitize=undefined');
            }

            // patch fake cli"""
if linux_source.count(linux_needle) != 1:
    raise SystemExit(f'unexpected LinuxBuilder make-vars anchor: {linux_source.count(linux_needle)}')
linux_path.write_text(linux_source.replace(linux_needle, linux_insert, 1))
PY

  echo "Configured dynamic Linux unixODBC for micro ODBC" >&2
}

for command in git php composer tar; do
  require_command "${command}"
done
if [[ "${PLATFORM}" == linux-* ]]; then
  require_command readelf
elif [[ "${PLATFORM}" == macos-* ]]; then
  require_command otool
fi

mkdir -p "${DIST_DIR}" "$(dirname "${SPC_DIR}")"
if [[ ! -f "${SPC_DIR}/bin/spc" ]]; then
  rm -rf "${SPC_DIR}"
  git clone --filter=blob:none "${SPC_REPO}" "${SPC_DIR}"
fi

git -C "${SPC_DIR}" fetch --force --depth=1 origin "${SPC_REF}"
git -C "${SPC_DIR}" checkout --force FETCH_HEAD
SPC_COMMIT=$(git -C "${SPC_DIR}" rev-parse HEAD)

if [[ "${DB_VARIANT}" == odbc && "${PLATFORM}" == linux-* && "${MICRO_DYNAMIC_ODBC}" == 1 ]]; then
  if [[ -z "${MICRO_SPC_TARGET}" ]]; then
    case "${PLATFORM}" in
      linux-x64) MICRO_SPC_TARGET=x86_64-linux-gnu.2.17 ;;
      linux-a64) MICRO_SPC_TARGET=aarch64-linux-gnu.2.17 ;;
    esac
  fi
  export SPC_TARGET="${MICRO_SPC_TARGET}"
  export PHPSFX_MICRO_DYNAMIC_ODBC=1
fi

patch_dynamic_odbc_builder
patch_windows_swoole_dependencies
patch_windows_spc_paths

if [[ "${DB_VARIANT}" == odbc && "${PLATFORM}" == linux-* && "${PHP_VERSION}" == 8.5 ]]; then
  export PHPSFX_MICRO_UBSAN_LINK=1
fi

composer install --working-dir="${SPC_DIR}" --no-dev --no-interaction --no-progress --prefer-dist

cd "${SPC_DIR}"
if [[ "${SKIP_DOCTOR}" != 1 ]]; then
  "${SPC_DIR}/bin/spc" doctor --auto-fix
fi

DOWNLOAD_ARGS=(
  "--with-php=${PHP_FULL_VERSION}"
  "--for-extensions=${MICRO_EXTENSIONS}"
  "--ignore-cache-sources=php-src"
  "-G"
  "swoole:${SWOOLE_SRC_REF}:https://github.com/swoole/swoole-src.git"
)
if [[ "${PREFER_PREBUILT}" == 1 ]]; then
  DOWNLOAD_ARGS+=(--prefer-pre-built)
fi
./bin/spc download "${DOWNLOAD_ARGS[@]}"
patch_native_pdo_dependencies
BUILD_ARGS=("${MICRO_EXTENSIONS}" --build-micro --with-micro-fake-cli)
if [[ "${DISABLE_OPCACHE_JIT}" == 1 ]]; then
  BUILD_ARGS+=(--disable-opcache-jit)
fi
if ! ./bin/spc build "${BUILD_ARGS[@]}"; then
  for build_log in "${SPC_DIR}/log/spc.output.log" "${SPC_DIR}/log/spc.shell.log" "${SPC_DIR}/log/php-src.config.log"; do
    if [[ -f "${build_log}" ]]; then
      echo "--- static-php-cli failure log: ${build_log} ---" >&2
      grep -E -i 'error:|undefined|cannot|not found|ld\.lld|collect2|failed' "${build_log}" | tail -n 120 >&2 || true
      tail -n 240 "${build_log}" >&2 || true
    fi
  done
  exit 1
fi

MICRO_SFX="${SPC_DIR}/buildroot/bin/micro.sfx"
[[ -s "${MICRO_SFX}" ]] || { echo "micro.sfx was not generated: ${MICRO_SFX}" >&2; exit 1; }

case "${PLATFORM}" in
  linux-x64) ASSET_PLATFORM=linux.x64 ;;
  linux-a64) ASSET_PLATFORM=linux.a64 ;;
  macos-x64) ASSET_PLATFORM=macos.x64 ;;
  macos-a64) ASSET_PLATFORM=macos.a64 ;;
  windows-x64) ASSET_PLATFORM=windows.x64 ;;
  *) echo "Unsupported asset platform: ${PLATFORM}" >&2; exit 2 ;;
esac
ASSET_NAME="${ASSET_PLATFORM}.${DB_VARIANT}.sfx"
ASSET_PATH="${DIST_DIR}/${ASSET_NAME}"
cp "${MICRO_SFX}" "${ASSET_PATH}"
chmod +x "${ASSET_PATH}"
case "${PLATFORM}" in
  linux-*) strip --strip-debug "${ASSET_PATH}" ;;
  macos-*) strip -S "${ASSET_PATH}" ;;
  windows-*) ;;
esac

PHPSFX_PLATFORM="${PLATFORM}" \
PHPSFX_EXPECTED_PHP_PREFIX="${PHP_VERSION}." \
PHPSFX_EXPECTED_PHP_VERSION="${PHP_FULL_VERSION}" \
PHPSFX_EXPECTED_SWOOLE_VERSION="${EXPECTED_SWOOLE_VERSION}" \
PHPSFX_REQUIRED_EXTENSIONS="${EXPECTED_EXTENSIONS}" \
PHPSFX_FORBIDDEN_EXTENSIONS="${FORBIDDEN_EXTENSIONS}" \
PHPSFX_REQUIRED_PDO_DRIVERS="${REQUIRED_PDO_DRIVERS}" \
PHPSFX_EXPECT_SWOOLE_ODBC="${SWOOLE_ODBC_ENABLED}" \
  bash "${ROOT_DIR}/scripts/validate-micro-sfx.sh" "${ASSET_PATH}"

ODBC_DYNAMIC_DEPENDENCY=
case "${PLATFORM}" in
  linux-*)
    ODBC_DYNAMIC_DEPENDENCY=$(readelf -d "${ASSET_PATH}" | sed -n 's/.*Shared library: \[\(libodbc\.so[^]]*\)\].*/\1/p' | head -1)
    ;;
  macos-*)
    ODBC_DYNAMIC_DEPENDENCY=$(otool -L "${ASSET_PATH}" | awk '/libodbc(\.[0-9]+)*\.dylib/ { dependency = $1; sub(/^.*\//, "", dependency); print dependency; exit }')
    ;;
  windows-*) ;;
esac

SHA256=$(sha256_file "${ASSET_PATH}")
SFX_SIZE=$(file_size "${ASSET_PATH}")
if [[ "${SWOOLE_ODBC_ENABLED}" == 1 ]]; then
  SWOOLE_ODBC_JSON=true
else
  SWOOLE_ODBC_JSON=false
fi
if [[ "${DISABLE_OPCACHE_JIT}" == 1 ]]; then
  OPCACHE_JIT_JSON=false
else
  OPCACHE_JIT_JSON=true
fi
if [[ "${DB_VARIANT}" == odbc && "${PLATFORM}" == linux-* && "${MICRO_DYNAMIC_ODBC}" == 1 ]]; then
  MICRO_DYNAMIC_ODBC_JSON=true
else
  MICRO_DYNAMIC_ODBC_JSON=false
fi
cat > "${DIST_DIR}/build-meta-${PHP_VERSION}-${PLATFORM}-${DB_VARIANT}.json" <<META
{
  "runtime": "micro",
  "sapi": "micro",
  "sfx_format": "micro.sfx + [INI magic/length/data] + payload",
  "platform": "${PLATFORM}",
  "variant": "${PLATFORM}-${DB_VARIANT}",
  "asset": "${ASSET_NAME}",
  "profile": "${PHPSFX_PROFILE_NAME:-micro-experiment}",
  "database_variant": "${DB_VARIANT}",
  "php_version": "${PHP_VERSION}",
  "php_full_version": "${PHP_FULL_VERSION}",
  "swoole_version": "${EXPECTED_SWOOLE_VERSION}",
  "micro_fake_cli": true,
  "micro_spc_repo": "${SPC_REPO}",
  "micro_spc_ref": "${SPC_REF}",
  "micro_spc_commit": "${SPC_COMMIT}",
  "micro_spc_target": "${SPC_TARGET:-}",
  "micro_dynamic_odbc": ${MICRO_DYNAMIC_ODBC_JSON},
  "swoole_src_ref": "${SWOOLE_SRC_REF}",
  "extensions": "${MICRO_EXTENSIONS}",
  "required_extensions": "${EXPECTED_EXTENSIONS}",
  "forbidden_extensions": "${FORBIDDEN_EXTENSIONS}",
  "required_pdo_drivers": "${REQUIRED_PDO_DRIVERS}",
  "swoole_odbc": ${SWOOLE_ODBC_JSON},
  "opcache": true,
  "opcache_jit": ${OPCACHE_JIT_JSON},
  "odbc_dynamic_dependency": "${ODBC_DYNAMIC_DEPENDENCY}",
  "sfx_size": ${SFX_SIZE},
  "sha256": "${SHA256}",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
META

(
  cd "${DIST_DIR}"
  printf '%s  %s\n' "${SHA256}" "${ASSET_NAME}" > SHA256SUMS
)

printf 'Built %s\n' "${ASSET_PATH}"
printf 'SHA256 %s  %s\n' "${SHA256}" "${ASSET_NAME}"
