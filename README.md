# 自维护 Swoole CLI

本仓库是自维护的 `swoole-cli` 发行源码和构建仓库，当前构建版本为 `v6.2.3.4`。Release 同时发布 PHP `8.4.27`、`8.5.12` 两条版本线，Swoole 均为 `6.2.3`，并保留把 PHP 入口或 Phar 追加进运行时的单文件能力。两条 PHP 版本线均包含 CVE-2026-109618、CVE-2026-109619 的安全修复；已打包的单文件应用需要使用新运行时重新打包。官方仓库只作为固定基线和实现参考；同步记录见 [docs/upstream-sync.md](docs/upstream-sync.md)。

每条 PHP 版本线在 Linux x86_64、Linux ARM64、macOS ARM64 三个平台分别提供 `mysql`、`pgsql`、`odbc` 三种线上包，以及 `sqlite-mysql-pgsql-odbc` 开发全量包，共 24 个二进制。MySQL、PostgreSQL 线上包不依赖 ODBC 环境；ODBC 线上包和开发包提供 PDO ODBC 与 Swoole 协程 ODBC，动态依赖部署机的 unixODBC。厂商驱动、DSN、客户端依赖和凭据由部署环境提供。

运行时使用 Swoole CLI 官方 SFX 格式：

```text
swoole-cli + payload.php|app.phar + pack('J', payloadSize)
```

其中 `pack('J', payloadSize)` 是 Swoole CLI 官方 SFX 读取逻辑需要的 8 字节长度尾部（与官方 `pack-sfx.php` 保持一致）。

运行已打包产物时需要传入 `--self`，例如 `./app --self list`。这是 Swoole CLI 官方 SFX 模式的入口开关。

## Release 产物

PHP 8.4.27 和 8.5.12 均覆盖 `linux-x64`、`linux-a64`、`macos-a64`。每个 PHP 版本、平台提供以下四种包：

| 用途 | 文件名后缀 | 精确 PDO 驱动集合 |
|------|--------------|----------------|
| 线上 MySQL | `-mysql` | `mysql` |
| 线上 PostgreSQL | `-pgsql` | `pgsql` |
| 线上 ODBC | `-odbc` | `odbc` |
| 开发全量 | `-sqlite-mysql-pgsql-odbc` | `sqlite,mysql,pgsql,odbc` |

文件名为 `swoole-cli-php<8.4或8.5>-<平台><后缀>`，例如 `swoole-cli-php8.4-linux-x64-mysql` 和 `swoole-cli-php8.5-macos-a64-sqlite-mysql-pgsql-odbc`。旧 tag 与 Release 保持不变；macOS Intel 和旧数据库组合可通过指定旧版本下载。

ODBC 产物不绑定达梦或任何数据库厂商，也不发布厂商专用命名的重复产物。

同时发布：

- `SHA256SUMS`
- `build-meta.json`

Release 合计 26 个资产，不再逐包上传 JSON。各构建仍在 Actions artifact 中保留独立元数据，以供汇总和审计。

汇总元数据中，`variant` 表示平台和包后缀；唯一构建身份为 `php_version + variant`，`metadata_asset` 统一指向 `build-meta.json`。

当前不发布 Windows 产物。

## 内置扩展与裁剪

MySQL、PostgreSQL 线上包使用 `scripts/profiles/hyperfadmin-slim.env`，ODBC 线上包和开发全量包使用 `scripts/profiles/hyperfadmin-odbc.env`。通过 `PHPSFX_DB_VARIANT` 选择 `mysql`（默认）、`pgsql`、`odbc` 或 `sqlite-mysql-pgsql`；后两者必须配合 ODBC Profile。共同保留 SFX、Swoole 服务、Phar 发布、基础网络、图片处理、二维码压缩和 OPcache 常用扩展：

```text
bcmath,bz2,ctype,curl,dom,fileinfo,filter,gd,iconv,mbstring,opcache,
openssl,pcntl,phar,posix,redis,simplexml,sockets,
sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib
```

默认裁剪未使用或体积较大的扩展：

```text
exif,gettext,gmp,imagick,intl,mongodb,mysqli,pgsql,readline,session,soap,
sqlite3,xlswriter,xsl,yaml
```

说明：Swoole CLI 的 `+xml` 构建项会同时启用 `dom/simplexml/xmlreader/xmlwriter`；`json/hash/pcre/reflection/PDO/libxml` 等属于 PHP core 或依赖扩展带出的基础能力，不作为独立 `prepare.php +xxx` 参数传入。`intl` 默认不打包，`bz2/gd/opcache` 作为标准能力保留。数据库只提供所选组合的 PDO 驱动；不含 SQLite 的组合不构建 SQLite 客户端库或 `pdo_sqlite`，含 SQLite 的组合也不加载 `SQLite3`。不含 PostgreSQL 的组合不构建 libpq。Swoole 的 mysqlnd 能力不随 PDO MySQL 的选择改变。

构建脚本还会把 Swoole CLI 上游默认的 full profile 收敛为 `PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS`，并进一步裁剪底层依赖：

- Swoole 扩展：保留 server/coroutine/curl hook/mysqlnd/c-ares DNS；ODBC Profile 额外通过 `--with-swoole-odbc=unixODBC,<prefix>` 启用 PDO ODBC 协程支持。默认不启用原生 `pgsql`、Swoole SQLite hook 及 ssh2/ftp/thread/brotli/zstd 等未使用功能。
- libcurl：保留 HTTP(S)、OpenSSL、zlib、c-ares，默认不启用 HTTP3、SSH2、IDN、PSL、Brotli、Zstd。
- libzip：保留 Zip + zlib + OpenSSL，默认不启用 LZMA、Zstd。
- zlib：移除上游模板中与 zlib 构建无关的额外依赖。
- redis：默认关闭 redis session 支持，因为本运行时不打包 PHP `session` 扩展。
- oniguruma：使用 6.9.10 release tarball，并在 macOS 构建时兼容新版 clang 对旧版函数指针告警的严格处理。

依赖库安装前缀默认放在 `.build/swoole-cli/.global-prefix/<platform>`，不会写入 `/usr/local/swoole-cli`，适合 GitHub Actions 和 WSL 普通权限构建。

## 自动发布

GitHub Actions workflow：`.github/workflows/release.yml`。

触发方式：

- 推送 `v*` 标签：自动构建两条 PHP 版本线的全部 24 个二进制并创建 GitHub Release。
- 手动运行 `Release swoole-cli`：`php_version` 默认为 `both`，也可选择 `8.4` 或 `8.5`；`php84_full_version`、`php85_full_version` 分别指定两条线的精确版本。原 `php_full_version` 作为单版本构建的可选覆盖保留。还可输入 `version`、`swoole_cli_ref`、`swoole_src_ref`、`prepare_flags`。默认只构建、校验并上传 workflow artifact；仅当 `publish=true` 时创建 GitHub Release。

示例：

```bash
git tag v6.2.3.4
git push origin swoole-cli v6.2.3.4
```

默认上游源码：

```text
https://github.com/swoole/swoole-cli.git
https://github.com/swoole/swoole-src.git
```

默认基线为 `swoole-cli` commit `f7903840c3e959612dac7d413205e1bdb0067029`，目标为 PHP 8.4.27 / 8.5.12 和 `swoole-src v6.2.3`。官方没有 `swoole-cli v6.2.3` 标签；构建脚本会按目标版本切换基线的 `PHP-VERSION.conf`，同步 PHP 源码并校验最终二进制的精确版本。PHP 8.5 专用的 OPcache、lexbor/uri 补丁仅在 8.5 构建中应用；Swoole 6.2.3 的睡眠函数兼容补丁两条线共用。每次参考官方优化后的变更记录在 [docs/upstream-sync.md](docs/upstream-sync.md)。

## 本地 / WSL 调试

WSL 或 Linux x86_64 本地构建 ODBC 产物前，先安装 unixODBC 开发包，然后指定通用 ODBC Profile：

```bash
cd /mnt/d/WebRoot/phpsfx
sudo apt-get install -y unixodbc unixodbc-dev
PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=odbc \
PHPSFX_PHP_VERSION=8.5 \
PHPSFX_PHP_FULL_VERSION=8.5.12 \
PHPSFX_SWOOLE_CLI_REF=f7903840c3e959612dac7d413205e1bdb0067029 \
PHPSFX_SWOOLE_SRC_REF=v6.2.3 \
  bash scripts/build-swoole-cli.sh
```

构建完成后输出到 `dist/`。本地单次构建默认 PHP 8.5.12；设置 `PHPSFX_PHP_VERSION=8.4` 即使用 8.4.27，手动设置 `PHPSFX_PHP_FULL_VERSION` 时必须与版本线一致。例如：

```bash
PHPSFX_PHP_VERSION=8.4 PHPSFX_DB_VARIANT=mysql \
  bash scripts/build-swoole-cli.sh macos-a64
```

macOS 使用 Homebrew unixODBC：

```bash
brew install unixodbc sqliteodbc
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=sqlite-mysql-pgsql \
  bash scripts/build-swoole-cli.sh macos-a64
```

如果本地已经安装了 PHP 8.4.27 或 8.5.12 / Swoole 6.2.3 CLI，可以先导入为标准命名产物，通过 `PHPSFX_PHP_VERSION` 选择相应版本线，用于快速验证下游打包链路。额外的非数据库扩展可在本地调试时允许，但 PDO 驱动仍必须与所选组合完全一致；正式发布仍应使用源码构建的 slim 产物：

```bash
PHPSFX_ALLOW_EXTRA_EXTENSIONS=1 \
PHPSFX_SWOOLE_CLI_REF=f7903840c3e959612dac7d413205e1bdb0067029 \
PHPSFX_SWOOLE_SRC_REF=v6.2.3 \
  bash scripts/import-swoole-cli.sh linux-x64 /usr/local/bin/php
```

常用覆盖项：

```bash
# 使用依赖镜像，适合网络不稳定时。
PHPSFX_DOWNLOAD_MIRROR_URL=https://example.com \
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=odbc \
  bash scripts/build-swoole-cli.sh linux-x64

# 临时调整扩展裁剪。
PHPSFX_SWOOLE_CLI_PREPARE_FLAGS='+redis +swoole +pdo_mysql +pdo_pgsql +pdo_sqlite +xml -mongodb -mysqli -pgsql -sqlite3' \
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=sqlite-mysql-pgsql \
  bash scripts/build-swoole-cli.sh linux-x64
```

> Linux/macOS 构建均依赖本机编译工具链。默认构建 MySQL 线上包；ODBC 线上包指定 `PHPSFX_DB_VARIANT=odbc`，开发包指定 `PHPSFX_DB_VARIANT=sqlite-mysql-pgsql`，并使用 ODBC Profile。旧数据库组合仍可用于本地自定义构建，但不进入新发布矩阵。

直接使用 ODBC Profile 且未设置 `PHPSFX_DB_VARIANT` 时，默认生成 ODBC-only 线上包。

## 通用 ODBC 运行时

两条 PHP 版本线、三个平台的 `-odbc` 线上包和 `-sqlite-mysql-pgsql-odbc` 开发包均使用 Swoole 6.2.3 的协程 PDO ODBC 驱动。它只提供统一连接接口，不包含 unixODBC、任何数据库厂商客户端、DSN、账号或密码，也不代表 SQL 方言、迁移、分页、标识符、字段类型和字符集已经兼容目标数据库。

通用安装、PHP 接口、服务环境和 MySQL、SQLite、PostgreSQL、SQL Server、Oracle，以及达梦、人大金仓、openGauss/GaussDB、OceanBase、GBase、神通、瀚高、Vastbase、TiDB、GoldenDB 等国产数据库接入路径见 [ODBC 环境与常见数据库接入](docs/odbc-runtime.md)。达梦的官方客户端安装、真实连库脚本和生产验收边界见 [达梦 ODBC 环境与真实验收](docs/dameng-odbc-runtime.md)。

ODBC 构建机需要 unixODBC 开发头文件，运行机需要 Linux `libodbc.so.2` 或 macOS `libodbc.2.dylib`。只有实际连接某个数据库时才需要安装与平台、架构匹配的厂商 ODBC 驱动；但 `-odbc` 运行时本身启动时就需要 unixODBC Driver Manager。

```bash
# 在已有本项目 Linux 构建工具链的主机上增加 ODBC 构建依赖。
# 达梦客户端仍需按官方文档在部署机另行安装。
sudo apt-get install -y unixodbc unixodbc-dev binutils

PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=odbc \
  bash scripts/build-swoole-cli.sh linux-x64

PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=odbc \
  bash scripts/build-swoole-cli.sh linux-a64

brew install unixodbc sqliteodbc
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=sqlite-mysql-pgsql \
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
  dist/swoole-cli-php8.5-linux-x64-odbc

bash scripts/test-dameng-odbc.sh \
  dist/swoole-cli-php8.5-linux-a64-odbc
```

在隔离的验收账号和测试 schema 中设置 `PHPSFX_DM_ODBC_ALLOW_WRITE=1`，可进一步验证参数绑定、中文、数值、时间、事务、错误传播和并发连接。脚本创建唯一测试表并在 `finally` 中精确删除；不要对未授权的生产账号启用写入验收。

## 运行时校验

构建脚本会直接执行生成的 `swoole-cli`，并校验：

- `PHP_VERSION` 以目标版本前缀开头。
- `PHP_SAPI === "cli"`。
- `SWOOLE_CLI` 常量存在。
- 数字版本的 `PHPSFX_SWOOLE_SRC_REF` 与运行时 `SWOOLE_VERSION` 完全一致。
- `swoole`、`redis`、所选组合的 PDO 扩展，以及 `openssl`、`curl`、`mbstring`、`phar`、`zlib`、`zip`、`dom`、`simplexml`、`xmlreader`、`xmlwriter`、`bz2`、`gd`、`opcache` 等必需扩展已加载。
- `PDO::getAvailableDrivers()` 恰好等于所选驱动集合，未选 PDO 扩展未加载；含 SQLite 的组合执行本地 PDO SQLite 读写，无 SQLite 的组合检查该驱动缺席；`SQLite3` 类始终不存在。
- ODBC 产物额外校验 PDO ODBC 驱动、Swoole ODBC 协程 hook 和平台对应的动态 unixODBC 依赖。
- `mysqli`、原生 `pgsql`、`sqlite3` 和 `exif/gettext/gmp/imagick/intl/mongodb/readline/session/soap/xlswriter/xsl/yaml` 等未使用扩展未被打包。

发布矩阵还会使用 `tests/hyperf-smoke` 中固定版本的 Hyperf 3.2 最小应用启动 HTTP 服务，验证请求协程、Swoole 版本和所选 SQLite 能力。ODBC 版通过 CI 另行安装的 SQLite ODBC 驱动验证事务和并发，不要求内置 `pdo_sqlite`：

`bash tests/test-release-variants.sh` 可先快速检查两条 PHP 版本线的八种 Profile、24 个文件名、默认精确版本与新旧下载命名。汇总阶段使用 `scripts/verify-release-assets.py --local <tag> dist` 检查完整矩阵、元数据字段及每个二进制的 SHA-256；发布后再分页核验远端全部 26 个资产，并抽查两条版本线、三个平台的公开下载链接。

```bash
composer install --working-dir=tests/hyperf-smoke --no-dev
PHPSFX_EXPECTED_SWOOLE_VERSION=6.2.3 \
PHPSFX_DB_VARIANT=mysql \
  bash scripts/test-hyperf-smoke.sh dist/swoole-cli-php8.5-linux-x64-mysql
```

手动校验已有产物：

```bash
PHPSFX_EXPECTED_PHP_PREFIX=8.5. \
PHPSFX_EXPECTED_PHP_VERSION=8.5.12 \
PHPSFX_EXPECTED_SWOOLE_VERSION=6.2.3 \
PHPSFX_EXPECT_SWOOLE_ODBC=1 \
PHPSFX_REQUIRED_PDO_DRIVERS=sqlite,mysql,pgsql,odbc \
PHPSFX_REQUIRED_EXTENSIONS=swoole,redis,pdo_mysql,pdo_pgsql,pdo_sqlite,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,bz2,gd,opcache \
PHPSFX_FORBIDDEN_EXTENSIONS=exif,gettext,gmp,imagick,intl,mongodb,mysqli,pgsql,readline,session,soap,sqlite3,xlswriter,xsl,yaml \
  bash scripts/validate-swoole-cli.sh dist/swoole-cli-php8.5-linux-x64-sqlite-mysql-pgsql-odbc
```

## 下载 Release 运行时

```bash
bash scripts/download-release-asset.sh linux-x64-mysql latest /tmp/swoole-cli
```

下载默认选择 PHP 8.5；从 `v6.2.3.3` 起可显式选择 PHP 8.4：

```bash
PHPSFX_PHP_VERSION=8.4 bash scripts/download-release-asset.sh \
  linux-x64-mysql latest /tmp/swoole-cli-php84
```

也可指定版本：

```bash
bash scripts/download-release-asset.sh linux-x64-pgsql-sqlite v6.2.3.1 /tmp/swoole-cli
```

下载不同组合或 ODBC 产物：

```bash
bash scripts/download-release-asset.sh linux-x64-mysql v6.2.3.4 /tmp/swoole-cli-mysql
bash scripts/download-release-asset.sh linux-a64-pgsql latest /tmp/swoole-cli-pgsql
bash scripts/download-release-asset.sh linux-x64-odbc latest /tmp/swoole-cli-odbc
bash scripts/download-release-asset.sh macos-a64-sqlite-mysql-pgsql-odbc latest /tmp/swoole-cli-dev
```

新版本推荐显式指定四种包后缀；`latest` 或 `v6.2.3.4` 起，不带后缀的 `linux-x64` 等参数默认下载 `mysql` 线上包，`linux-x64-odbc` 下载 ODBC-only 线上包。旧版本仍保留原规则：`v6.2.3.0` 使用旧文件名；`v6.2.3.1` 支持原三种含 SQLite 组合；`v6.2.3.2`、`v6.2.3.3` 支持七种组合和 ODBC 叠加，不带组合名时仍映射到旧全量组合。新版本不再发布的组合及 macOS Intel 会在下载前明确拒绝；需要这些文件时请指定旧 tag。

## PHP 源码打包

单个 PHP 入口文件可直接追加到 `swoole-cli`：

```bash
bash scripts/download-release-asset.sh linux-x64-mysql latest /tmp/swoole-cli

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
bash scripts/download-release-asset.sh linux-x64-mysql latest /tmp/swoole-cli

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
bash scripts/test-packaging.sh swoole-cli-php8.5-linux-x64-mysql
```


## 参考

- [swoole/swoole-cli](https://github.com/swoole/swoole-cli)
- [Swoole CLI 构建选项](https://github.com/swoole/swoole-cli/blob/main/docs/options.md)
- [Swoole CLI SFX 打包说明](https://github.com/swoole/swoole-cli/blob/main/sapi/samples/sfx/README.md)
- [Swoole CLI 官方 pack-sfx.php](https://github.com/swoole/swoole-cli/blob/main/sapi/scripts/pack-sfx.php)
