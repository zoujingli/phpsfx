# phpsfx

`phpsfx` 用于自动构建和发布多平台 **Swoole CLI PHP 8.4 运行时**。产物用于把 PHP 源码入口或可执行 Phar 追加进运行时后生成单文件可执行程序。

四个平台的默认产物内置 MySQL 和 SQLite，不依赖 ODBC 环境；同一 Release 另外提供通用 `-odbc` 产物，增加 PDO ODBC 和 Swoole 协程 ODBC 能力。ODBC 产物动态依赖部署机的 unixODBC，具体数据库的厂商驱动、DSN、客户端依赖和凭据由部署环境提供。

运行时使用 Swoole CLI 官方 SFX 格式：

```text
swoole-cli + payload.php|app.phar + pack('J', payloadSize)
```

其中 `pack('J', payloadSize)` 是 Swoole CLI 官方 SFX 读取逻辑需要的 8 字节长度尾部（与官方 `pack-sfx.php` 保持一致）。

运行已打包产物时需要传入 `--self`，例如 `./app --self list`。这是 Swoole CLI 官方 SFX 模式的入口开关。

## Release 产物

默认构建 PHP 8.4 运行时，覆盖以下平台：

| 平台 | Release 文件 |
|------|--------------|
| Linux x86_64 | `swoole-cli-php8.4-linux-x64` |
| Linux ARM64 | `swoole-cli-php8.4-linux-a64` |
| macOS x86_64 | `swoole-cli-php8.4-macos-x64` |
| macOS ARM64 | `swoole-cli-php8.4-macos-a64` |
| Linux x86_64 + ODBC | `swoole-cli-php8.4-linux-x64-odbc` |
| Linux ARM64 + ODBC | `swoole-cli-php8.4-linux-a64-odbc` |
| macOS x86_64 + ODBC | `swoole-cli-php8.4-macos-x64-odbc` |
| macOS ARM64 + ODBC | `swoole-cli-php8.4-macos-a64-odbc` |

ODBC 产物不绑定达梦或任何数据库厂商，也不发布厂商专用命名的重复产物。

同时发布：

- `SHA256SUMS`
- `build-meta.json`
- `build-meta-linux-x64.json`
- `build-meta-linux-a64.json`
- `build-meta-macos-x64.json`
- `build-meta-macos-a64.json`
- `build-meta-linux-x64-odbc.json`
- `build-meta-linux-a64-odbc.json`
- `build-meta-macos-x64-odbc.json`
- `build-meta-macos-a64-odbc.json`

首版不发布 Windows 产物。

## 内置扩展与裁剪

四个平台默认产物使用 `scripts/profiles/hyperfadmin-slim.env`，ODBC 产物使用在它之上启用 ODBC 的 `scripts/profiles/hyperfadmin-odbc.env`。两者都只保留 SFX、Swoole 服务、Phar 发布、数据库、基础网络、图片处理、二维码压缩和 OPcache 常用扩展：

```text
bcmath,bz2,ctype,curl,dom,fileinfo,filter,gd,iconv,mbstring,opcache,
openssl,pcntl,pdo_mysql,pdo_sqlite,phar,posix,redis,simplexml,sockets,
sodium,sqlite3,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib
```

默认裁剪未使用或体积较大的扩展：

```text
exif,gettext,gmp,imagick,intl,mongodb,mysqli,readline,session,soap,
xlswriter,xsl,yaml
```

说明：Swoole CLI 的 `+xml` 构建项会同时启用 `dom/simplexml/xmlreader/xmlwriter`；`json/hash/pcre/reflection/PDO/libxml` 等属于 PHP core 或依赖扩展带出的基础能力，不作为独立 `prepare.php +xxx` 参数传入。`intl` 默认不打包，`bz2/gd/opcache` 作为 dmskc 标准能力保留。`sqlite3/pdo_sqlite` 作为 PHP 标准 SQLite 能力保留，预计每个平台运行时增加约 1.6–3 MiB，最终以构建产物字节差值为准。

构建脚本还会把 Swoole CLI 上游默认的 full profile 收敛为 `PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS`，并进一步裁剪底层依赖：

- Swoole 扩展：保留 server/coroutine/curl hook/mysqlnd/c-ares DNS；ODBC Profile 额外通过 `--with-swoole-odbc=unixODBC,<prefix>` 启用 PDO ODBC 协程支持。默认不启用 `pgsql/sqlite/ssh2/ftp/thread/brotli/zstd` 等未使用功能；其中 MySQL 协程化底层条件继续依赖 `mysqlnd`，SQLite 只提供 PHP 标准 `sqlite3/pdo_sqlite`，不默认启用 `--enable-swoole-sqlite`。
- libcurl：保留 HTTP(S)、OpenSSL、zlib、c-ares，默认不启用 HTTP3、SSH2、IDN、PSL、Brotli、Zstd。
- libzip：保留 Zip + zlib + OpenSSL，默认不启用 LZMA、Zstd。
- zlib：移除上游模板中与 zlib 构建无关的额外依赖。
- redis：默认关闭 redis session 支持，因为本运行时不打包 PHP `session` 扩展。
- oniguruma：使用 6.9.10 release tarball，并在 macOS 构建时兼容新版 clang 对旧版函数指针告警的严格处理。

依赖库安装前缀默认放在 `.build/swoole-cli/.global-prefix/<platform>`，不会写入 `/usr/local/swoole-cli`，适合 GitHub Actions 和 WSL 普通权限构建。

## 自动发布

GitHub Actions workflow：`.github/workflows/release.yml`。

触发方式：

- 推送 `v*` 标签：自动构建所有平台并创建 GitHub Release。
- 手动运行 `Release swoole-cli`：可输入 `version`、`php_version`、`swoole_cli_ref`、`swoole_src_ref`、`prepare_flags`。默认只构建、校验并上传 workflow artifact；仅当 `publish=true` 时创建 GitHub Release。

示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

默认上游源码：

```text
https://github.com/swoole/swoole-cli.git
https://github.com/swoole/swoole-src.git
```

默认 `swoole_cli_ref=v6.2.2.0`，目标为 PHP 8.4.25 和 `swoole-src v6.2.2`。构建脚本会按上游 `PHP-VERSION.conf` 同步 PHP 源码，并校验最终二进制的精确版本。如果未来要固定官方 tag 或提交，可设置环境变量 `PHPSFX_SWOOLE_CLI_REF` / `PHPSFX_SWOOLE_SRC_REF`；非数字 ref 可通过 `PHPSFX_EXPECTED_SWOOLE_VERSION` 指定产物必须报告的扩展版本。

## 本地 / WSL 调试

WSL 或 Linux x86_64 本地构建 ODBC 产物前，先安装 unixODBC 开发包，然后指定通用 ODBC Profile：

```bash
cd /mnt/d/WebRoot/phpsfx
sudo apt-get install -y unixodbc unixodbc-dev
PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_PHP_VERSION=8.4 \
PHPSFX_SWOOLE_CLI_REF=v6.2.2.0 \
PHPSFX_SWOOLE_SRC_REF=v6.2.2 \
  bash scripts/build-swoole-cli.sh
```

构建完成后输出到 `dist/`。

macOS 使用 Homebrew unixODBC：

```bash
brew install unixodbc sqliteodbc
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh macos-a64
```

如果本地已经安装了同版本 Swoole CLI（例如 `/usr/local/bin/php` 输出 `Swoole 6.2.2`），可以先导入为 phpsfx 标准命名产物，用于快速验证下游打包链路。注意官方 full runtime 通常包含 `mongodb/imagick/mysqli/intl` 等额外扩展，导入时如只是本地调试可显式允许额外扩展；正式发布仍应使用源码构建的 slim 产物：

```bash
PHPSFX_ALLOW_EXTRA_EXTENSIONS=1 \
PHPSFX_SWOOLE_CLI_REF=v6.2.2.0 \
PHPSFX_SWOOLE_SRC_REF=v6.2.2 \
  bash scripts/import-swoole-cli.sh linux-x64 /usr/local/bin/php
```

常用覆盖项：

```bash
# 使用依赖镜像，适合网络不稳定时。
PHPSFX_DOWNLOAD_MIRROR_URL=https://example.com \
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh linux-x64

# 临时调整扩展裁剪。
PHPSFX_SWOOLE_CLI_PREPARE_FLAGS='+redis +swoole +pdo_mysql +pdo_sqlite +sqlite3 +xml -mongodb' \
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh linux-x64
```

> Linux/macOS 构建均依赖本机编译工具链。默认 Profile 生成无 ODBC 依赖的基础产物；只有显式使用 ODBC Profile 才生成 `-odbc` 产物。

## 通用 ODBC 运行时

四个平台的 `-odbc` 产物使用 Swoole 6.2.2 自带的 PHP 8.4 协程 PDO ODBC 驱动。它只提供统一连接接口，不包含 unixODBC、任何数据库厂商客户端、DSN、账号或密码，也不代表 SQL 方言、迁移、分页、标识符、字段类型和字符集已经兼容目标数据库。

通用安装、PHP 接口、服务环境和 MySQL、SQLite、PostgreSQL、SQL Server、Oracle，以及达梦、人大金仓、openGauss/GaussDB、OceanBase、GBase、神通、瀚高、Vastbase、TiDB、GoldenDB 等国产数据库接入路径见 [ODBC 环境与常见数据库接入](docs/odbc-runtime.md)。达梦的官方客户端安装、真实连库脚本和生产验收边界见 [达梦 ODBC 环境与真实验收](docs/dameng-odbc-runtime.md)。

ODBC 构建机需要 unixODBC 开发头文件，运行机需要 Linux `libodbc.so.2` 或 macOS `libodbc.2.dylib`。只有实际连接某个数据库时才需要安装与平台、架构匹配的厂商 ODBC 驱动；但 `-odbc` 运行时本身启动时就需要 unixODBC Driver Manager。

```bash
# 在已有本项目 Linux 构建工具链的主机上增加 ODBC 构建依赖。
# 达梦客户端仍需按官方文档在部署机另行安装。
sudo apt-get install -y unixodbc unixodbc-dev binutils

PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh linux-x64

PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh linux-a64

brew install unixodbc sqliteodbc
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh macos-a64
```

每个命令都必须在对应操作系统和架构的主机原生执行。源码构建输出、Release 下载校验和生产部署依赖以完整环境手册为准。

构建脚本会拒绝将 unixODBC 静态链接进 ODBC 产物，并校验以下能力：

- `PDO::getAvailableDrivers()` 包含 `odbc`。
- `SWOOLE_HOOK_PDO_ODBC` 已定义并包含在 `SWOOLE_HOOK_ALL` 中。
- `php --ri swoole` 报告 `coroutine_odbc => enabled`。
- Linux ODBC 产物依赖 `libodbc.so.2`，macOS ODBC 产物依赖 `libodbc.2.dylib`；默认产物不得意外出现 ODBC 动态依赖。

部署时按达梦官方 ODBC 文档配置驱动和命名 DSN，`odbc.ini` 中不要保存账号或密码。实测达梦官方 Linux ODBC 驱动时，PDO 的 DSN 应使用 `odbc:<unixODBC DSN 名>`（例如 `odbc:dm-prod`），账号和密码继续通过 `PDO` 的独立参数传入。应用只从环境或密钥管理系统读取连接信息。最小连接示例：

```php
<?php

$pdo = new PDO(
    getenv('DM_ODBC_DSN'),
    getenv('DM_ODBC_USER') ?: '',
    getenv('DM_ODBC_PASSWORD') ?: '',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
```

现场只读验收需要预先设置 `PHPSFX_DM_ODBC_DSN`、`PHPSFX_DM_ODBC_USER` 和 `PHPSFX_DM_ODBC_PASSWORD`，其中 DSN 使用上述 `odbc:<名称>` 格式。脚本不会输出这些值，并会通过达梦专属 `ID_CODE()` 查询确认连接目标是达梦数据库：

```bash
bash scripts/test-dameng-odbc.sh \
  dist/swoole-cli-php8.4-linux-x64-odbc

bash scripts/test-dameng-odbc.sh \
  dist/swoole-cli-php8.4-linux-a64-odbc
```

在隔离的验收账号和测试 schema 中设置 `PHPSFX_DM_ODBC_ALLOW_WRITE=1`，可进一步验证参数绑定、中文、数值、时间、事务、错误传播和并发连接。脚本创建唯一测试表并在 `finally` 中精确删除；不要对未授权的生产账号启用写入验收。

## 运行时校验

构建脚本会直接执行生成的 `swoole-cli`，并校验：

- `PHP_VERSION` 以目标版本前缀开头。
- `PHP_SAPI === "cli"`。
- `SWOOLE_CLI` 常量存在。
- 数字版本的 `PHPSFX_SWOOLE_SRC_REF` 与运行时 `SWOOLE_VERSION` 完全一致。
- `swoole`、`redis`、`pdo_mysql`、`pdo_sqlite`、`sqlite3`、`openssl`、`curl`、`mbstring`、`phar`、`zlib`、`zip`、`dom`、`simplexml`、`xmlreader`、`xmlwriter`、`bz2`、`gd`、`opcache` 等必需扩展已加载。
- `SQLite3` 类、`SQLite3(":memory:")`、`PDO("sqlite::memory:")` 和 `PDO::getAvailableDrivers()` 中的 `sqlite` 驱动可用。
- ODBC 产物额外校验 PDO ODBC 驱动、Swoole ODBC 协程 hook 和平台对应的动态 unixODBC 依赖。
- `exif/gettext/gmp/imagick/intl/mongodb/mysqli/readline/session/soap/xlswriter/xsl/yaml` 等未使用扩展未被打包。

发布矩阵还会使用 `tests/hyperf-smoke` 中固定版本的 Hyperf 3.2 最小应用启动 HTTP 服务，验证请求协程、Swoole 版本和 PDO SQLite 查询：

```bash
composer install --working-dir=tests/hyperf-smoke --no-dev
PHPSFX_EXPECTED_SWOOLE_VERSION=6.2.2 \
  bash scripts/test-hyperf-smoke.sh dist/swoole-cli-php8.4-linux-x64
```

手动校验已有产物：

```bash
PHPSFX_EXPECTED_PHP_PREFIX=8.4. \
PHPSFX_EXPECTED_SWOOLE_VERSION=6.2.2 \
PHPSFX_EXPECT_SWOOLE_ODBC=1 \
PHPSFX_REQUIRED_EXTENSIONS=swoole,redis,pdo_mysql,pdo_sqlite,sqlite3,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,bz2,gd,opcache \
PHPSFX_FORBIDDEN_EXTENSIONS=exif,gettext,gmp,imagick,intl,mongodb,mysqli,readline,session,soap,xlswriter,xsl,yaml \
  bash scripts/validate-swoole-cli.sh dist/swoole-cli-php8.4-linux-x64-odbc
```

## 下载 Release 运行时

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
```

也可指定版本：

```bash
bash scripts/download-release-asset.sh linux-x64 v0.1.0 /tmp/swoole-cli
```

下载默认产物或 ODBC 产物：

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
bash scripts/download-release-asset.sh linux-x64-odbc latest /tmp/swoole-cli-odbc
bash scripts/download-release-asset.sh macos-a64-odbc latest /tmp/swoole-cli-odbc-macos
```

## PHP 源码打包

单个 PHP 入口文件可直接追加到 `swoole-cli`：

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli

bash scripts/pack-php.sh \
  /tmp/swoole-cli \
  examples/hello.php \
  build/hello

./build/hello --self
```

等价原理：

```text
copy swoole-cli -> build/hello
append examples/hello.php
append pack('J', filesize('examples/hello.php'))
chmod +x build/hello
```

该模式适合单文件命令行工具或入口文件已经自包含的场景；多文件应用不要直接追加源码目录。

## Phar 打包

复杂项目推荐先生成可执行 Phar，再追加到 `swoole-cli`：

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli

bash scripts/pack-phar.sh \
  /tmp/swoole-cli \
  app.phar \
  build/app

./build/app --self
```

等价原理：

```text
copy swoole-cli -> build/app
append app.phar
append pack('J', filesize('app.phar'))
chmod +x build/app
```

约束：

- `app.phar` 必须自带可执行 Phar stub。
- 运行时读取外部配置、日志、上传目录、数据库快照等资源时，仍应按应用自己的 Phar 运行规则放在二进制同级或指定路径。
- 脚本兼容 `.bin` 这类自定义 Phar 后缀，会先复制为临时 `.phar` 做轻量校验。

## 打包实现自测

对已有 `swoole-cli` 同时测试 PHP 与 Phar 两种 SFX 打包方式：

```bash
bash scripts/test-packaging.sh swoole-cli-php8.4-linux-x64
```


## 参考

- [swoole/swoole-cli](https://github.com/swoole/swoole-cli)
- [Swoole CLI 构建选项](https://github.com/swoole/swoole-cli/blob/main/docs/options.md)
- [Swoole CLI SFX 打包说明](https://github.com/swoole/swoole-cli/blob/main/sapi/samples/sfx/README.md)
- [Swoole CLI 官方 pack-sfx.php](https://github.com/swoole/swoole-cli/blob/main/sapi/scripts/pack-sfx.php)
