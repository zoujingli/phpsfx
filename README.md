# micro.sfx + Phar 实验链

这是 `micro.sfx` 远程分支的独立实验说明。目标是用 PHP micro SAPI 承载当前 dmskc2 所需的 Swoole、PDO、Redis、Phar 和基础 PHP 能力，再把应用 Phar 追加为可直接执行的单文件程序。实验链与正式 `swoole-cli` 发行链并行，现有 Swoole CLI 分支、tag、Release 和生产部署文件保持不变。

当前实验固定 PHP `8.4.27`、`8.5.12` 和 Swoole `6.2.5`，默认关闭 dmskc2 不使用的 OPcache JIT，同时保留 Swoole server、coroutine、curl hook、mysqlnd、c-ares DNS、Phar 和必要 PHP 扩展。代表构建覆盖 Linux x86_64、Linux ARM64 的 `mysql`、`pgsql`、`odbc` 生产包，以及 macOS ARM64 的 `mysql`、`pgsql` 生产包；不构建混合开发包，micro.sfx 不作为独立 PHP 开发环境。

micro 的运行格式是：

```text
micro.sfx + [可选 INI magic/length/data] + app.phar
```

生成文件直接执行 `./app`，不使用 Swoole CLI 的 `--self` 参数。micro 提供 `micro_get_self_filename()` 和 `phar://` 只读资源访问；应用配置、日志、上传、缓存和数据库文件放在 Phar 外部。

## Swoole CLI 基线参考

以下章节记录本仓库原有的 Swoole CLI 发布矩阵，仅作为 micro.sfx 的组件和兼容性基线；micro.sfx 实验不会创建这些 Release 资产。

Swoole CLI 基线的格式是：

```text
swoole-cli + payload.php|app.phar + pack('J', payloadSize)
```

该格式需要使用 `--self` 入口，例如 `./app --self list`。这套格式只适用于下面的 Swoole CLI 基线章节，不适用于 micro.sfx。

## Release 产物

PHP 8.4.27 和 8.5.12 均覆盖 `linux-x64`、`linux-a64`、`macos-a64`。每个 PHP 版本、平台提供以下四种包：

| 用途 | 文件名后缀 | Linux PDO 驱动 | macOS PDO 驱动 |
|------|--------------|----------------|----------------|
| 线上 MySQL | `-mysql` | `mysql` | `mysql` |
| 线上 PostgreSQL | `-pgsql` | `pgsql` | `pgsql` |
| 线上 ODBC | `-odbc` | `odbc` | `odbc` |
| 开发 | `-sqlite-mysql-pgsql` | `sqlite,mysql,pgsql,odbc` | `sqlite,mysql,pgsql` |

文件名为 `swoole-cli-php<8.4或8.5>-<平台><后缀>`，例如 `swoole-cli-php8.4-linux-x64-mysql` 和 `swoole-cli-php8.5-macos-a64-sqlite-mysql-pgsql`。开发包的 ODBC 能力由平台决定，须结合上表或元数据选择；决策依据见 [开发包 ODBC 平台差异](docs/adr/0001-development-package-odbc-by-platform.md)。旧 tag 与 Release 保持不变；macOS Intel 和旧数据库组合可通过指定旧版本下载。

ODBC 产物不绑定达梦或任何数据库厂商，也不发布厂商专用命名的重复产物。

同时发布：

- `SHA256SUMS`
- `build-meta.json`

Release 合计 26 个资产，不再逐包上传 JSON。各构建仍在 Actions artifact 中保留独立元数据，以供汇总和审计。

汇总元数据中，`variant` 表示平台和包后缀；唯一构建身份为 `php_version + variant`，`metadata_asset` 统一指向 `build-meta.json`。

当前不发布 Windows 产物。

## 内置扩展与裁剪

MySQL、PostgreSQL 线上包和 macOS 开发包使用 `scripts/profiles/hyperfadmin-slim.env`；ODBC 线上包和 Linux 开发包使用 `scripts/profiles/hyperfadmin-odbc.env`。通过 `PHPSFX_DB_VARIANT` 选择 `mysql`（默认）、`pgsql`、`odbc` 或 `sqlite-mysql-pgsql`。共同保留 SFX、Swoole 服务、Phar 发布、基础网络、图片处理、二维码压缩和 OPcache 常用扩展：

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
git tag v6.2.5.1
git push origin swoole-cli v6.2.5.1
```

默认上游源码：

```text
https://github.com/swoole/swoole-cli.git
https://github.com/swoole/swoole-src.git
```

默认基线为官方 `swoole-cli v6.2.5.0` commit `e891b2b38720c5879c9a2c7894384b9af7228de0`，目标为 PHP 8.4.27 / 8.5.12 和 `swoole-src v6.2.5`。SFX 格式和裁剪机制沿用，`-U/--self-update` 随上游删除，更新运行时使用本仓库下载脚本。构建脚本会按目标版本切换基线的 `PHP-VERSION.conf`，同步 PHP 源码并校验最终二进制的精确版本。PHP 8.5 专用的 OPcache、lexbor/uri 补丁仅在 8.5 构建中应用；原睡眠函数兼容和 libiconv 下载 URL 补丁已由上游修复，删除本地重复实现。每次参考官方优化后的变更记录在 [docs/upstream-sync.md](docs/upstream-sync.md)。

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
PHPSFX_SWOOLE_CLI_REF=e891b2b38720c5879c9a2c7894384b9af7228de0 \
PHPSFX_SWOOLE_SRC_REF=v6.2.5 \
  bash scripts/build-swoole-cli.sh
```

构建完成后输出到 `dist/`。本地单次构建默认 PHP 8.5.12；设置 `PHPSFX_PHP_VERSION=8.4` 即使用 8.4.27，手动设置 `PHPSFX_PHP_FULL_VERSION` 时必须与版本线一致。例如：

```bash
PHPSFX_PHP_VERSION=8.4 PHPSFX_DB_VARIANT=mysql \
  bash scripts/build-swoole-cli.sh macos-a64
```

macOS 的独立 ODBC 线上包使用 Homebrew unixODBC：

```bash
brew install unixodbc sqliteodbc
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_DB_VARIANT=odbc \
  bash scripts/build-swoole-cli.sh macos-a64
```

macOS 开发包不需要 unixODBC，使用默认 slim Profile：

```bash
PHPSFX_DB_VARIANT=sqlite-mysql-pgsql \
  bash scripts/build-swoole-cli.sh macos-a64
```

如果本地已经安装了 PHP 8.4.27 或 8.5.12 / Swoole 6.2.5 CLI，可以先导入为标准命名产物，通过 `PHPSFX_PHP_VERSION` 选择相应版本线，用于快速验证下游打包链路。额外的非数据库扩展可在本地调试时允许，但 PDO 驱动仍必须与所选组合完全一致；正式发布仍应使用源码构建的 slim 产物：

```bash
PHPSFX_ALLOW_EXTRA_EXTENSIONS=1 \
PHPSFX_SWOOLE_CLI_REF=e891b2b38720c5879c9a2c7894384b9af7228de0 \
PHPSFX_SWOOLE_SRC_REF=v6.2.5 \
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

> Linux/macOS 构建均依赖本机编译工具链。默认构建 MySQL 线上包；ODBC 线上包指定 `PHPSFX_DB_VARIANT=odbc`，并使用 ODBC Profile。开发包指定 `PHPSFX_DB_VARIANT=sqlite-mysql-pgsql`，Linux 使用 ODBC Profile，macOS 使用默认 slim Profile。旧数据库组合仍可用于本地自定义构建，但不进入新发布矩阵。

直接使用 ODBC Profile 且未设置 `PHPSFX_DB_VARIANT` 时，默认生成 ODBC-only 线上包。

## 通用 ODBC 运行时

两条 PHP 版本线、三个平台的 `-odbc` 线上包，以及 Linux 的 `-sqlite-mysql-pgsql` 开发包，使用 Swoole 6.2.5 的协程 PDO ODBC 驱动。macOS 开发包不提供 ODBC，也不依赖 unixODBC。ODBC 只提供统一连接接口，不包含 unixODBC、任何数据库厂商客户端、DSN、账号或密码，也不代表 SQL 方言、迁移、分页、标识符、字段类型和字符集已经兼容目标数据库。

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
PHPSFX_DB_VARIANT=odbc \
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

`bash tests/test-release-variants.sh` 可先快速检查 24 项发行配置、平台对应的 ODBC 能力、默认精确版本与新旧下载命名。汇总阶段使用 `scripts/verify-release-assets.py --local <tag> dist` 检查完整矩阵、元数据字段及每个二进制的 SHA-256；发布后再分页核验远端全部 26 个资产，并抽查两条版本线、三个平台的公开下载链接。

```bash
composer install --working-dir=tests/hyperf-smoke --no-dev
PHPSFX_EXPECTED_SWOOLE_VERSION=6.2.5 \
PHPSFX_DB_VARIANT=mysql \
  bash scripts/test-hyperf-smoke.sh dist/swoole-cli-php8.5-linux-x64-mysql
```

手动校验已有产物：

```bash
PHPSFX_EXPECTED_PHP_PREFIX=8.5. \
PHPSFX_EXPECTED_PHP_VERSION=8.5.12 \
PHPSFX_EXPECTED_SWOOLE_VERSION=6.2.5 \
PHPSFX_EXPECT_SWOOLE_ODBC=1 \
PHPSFX_REQUIRED_PDO_DRIVERS=sqlite,mysql,pgsql,odbc \
PHPSFX_REQUIRED_EXTENSIONS=swoole,redis,pdo_mysql,pdo_pgsql,pdo_sqlite,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,bz2,gd,opcache \
PHPSFX_FORBIDDEN_EXTENSIONS=exif,gettext,gmp,imagick,intl,mongodb,mysqli,pgsql,readline,session,soap,sqlite3,xlswriter,xsl,yaml \
  bash scripts/validate-swoole-cli.sh dist/swoole-cli-php8.5-linux-x64-sqlite-mysql-pgsql
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
bash scripts/download-release-asset.sh linux-x64-mysql v6.2.5.1 /tmp/swoole-cli-mysql
bash scripts/download-release-asset.sh linux-a64-pgsql latest /tmp/swoole-cli-pgsql
bash scripts/download-release-asset.sh linux-x64-odbc latest /tmp/swoole-cli-odbc
bash scripts/download-release-asset.sh macos-a64-sqlite-mysql-pgsql latest /tmp/swoole-cli-dev
```

新版本推荐显式指定四种包后缀；不带后缀的 `linux-x64` 等参数默认下载 `mysql` 线上包，`linux-x64-odbc` 下载 ODBC-only 线上包。`latest` 或 `v6.2.3.5` 起，开发包使用 `sqlite-mysql-pgsql`；`v6.2.3.4` tag 对应旧 `sqlite-mysql-pgsql-odbc` 命名，其发布流水线已取消。更早版本保留原规则：`v6.2.3.0` 使用旧文件名；`v6.2.3.1` 支持原三种含 SQLite 组合；`v6.2.3.2`、`v6.2.3.3` 支持七种组合和 ODBC 叠加，不带组合名时仍映射到旧全量组合。新版本不再发布的组合及 macOS Intel 会在下载前明确拒绝；需要这些文件时请指定已发布的旧 tag。

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

## micro.sfx 快速使用

从远程分支获取并查看完整构建、打包和验证命令：

```bash
git clone --branch micro.sfx --single-branch https://github.com/zoujingli/phpsfx.git
cd phpsfx
```

构建后用 `scripts/pack-micro-phar.sh` 生成文件，直接执行 `./build/app`；micro 不使用 Swoole CLI 的 `--self` 参数。完整变体、环境变量、INI 注入、Phar 可写目录和验证入口见下方 [micro.sfx + Phar 实验链](#microsfx--phar-实验链) 与 [micro.sfx + Phar ADR](docs/adr/0002-micro-sfx-phar-experiment.md)。

## micro.sfx + Phar 实验链

`micro.sfx` 远程分支提供并行实验链，不改变当前 Swoole CLI Release。micro 的格式是 `micro.sfx + 可选 INI 块 + app.phar`，运行时直接执行生成文件，不使用 `--self`：

```bash
bash scripts/pack-micro-phar.sh \
  micro.sfx \
  app.phar \
  build/micro-app \
  --ini memory_limit=512M

./build/micro-app
```

实验分支为 `micro.sfx`，固定验证 PHP 8.4.27/8.5.12、Swoole 6.2.5 和当前 dmskc2 扩展集合；保留 Swoole server/coroutine/curl hook/DNS/Phar 基础能力；仅 mysql 变体启用 mysqlnd hook，默认关闭未使用的 OPcache JIT。代表矩阵为 Linux x86_64、Linux ARM64 的 `mysql`、`pgsql`、`odbc`，以及 macOS ARM64、macOS x86_64、Windows x86_64 的 `mysql`、`pgsql`；每条 PHP 线共十二种产物，不构建混合开发包。micro 运行时通过 `--with-micro-fake-cli` 暴露 `PHP_SAPI=cli`，不提供 `SWOOLE_CLI` 或 Swoole CLI `--self` 行为；Phar 内的可写数据必须放在外部目录。Linux ODBC 代表包在静态 PHP/Swoole 基础上使用 glibc 2.17 目标，并把构建机的 unixODBC `libodbc.so.2` 映射为运行时动态依赖。推送 `micro.sfx` 会运行实验 workflow；workflow 只上传 Actions artifact，不创建 Release，也不进入现有 24 个 Swoole CLI 资产。详情见 [micro.sfx + Phar ADR](docs/adr/0002-micro-sfx-phar-experiment.md)。

### micro.sfx 使用方法

下面的命令只在需要实验时使用，命令执行目录是本仓库根目录。实验分支只保留远程分支，直接拉取即可：

```bash
git clone --branch micro.sfx --single-branch https://github.com/zoujingli/phpsfx.git
cd phpsfx
```

构建 macOS ARM64 MySQL 生产代表包（PHP 8.5.12）：

```bash
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-slim.env \
PHPSFX_PHP_VERSION=8.5 PHPSFX_PHP_FULL_VERSION=8.5.12 \
PHPSFX_DB_VARIANT=mysql \
PHPSFX_MICRO_DISABLE_OPCACHE_JIT=1 \
bash scripts/build-micro-sfx.sh macos-a64
```

构建 macOS ARM64 PostgreSQL 生产代表包：

```bash
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-slim.env \
PHPSFX_PHP_VERSION=8.5 PHPSFX_PHP_FULL_VERSION=8.5.12 \
PHPSFX_DB_VARIANT=pgsql \
PHPSFX_MICRO_DISABLE_OPCACHE_JIT=1 \
bash scripts/build-micro-sfx.sh macos-a64
```

构建生产 MySQL 代表包时只选择 `pdo_mysql`：

```bash
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-slim.env \
PHPSFX_PHP_VERSION=8.5 PHPSFX_PHP_FULL_VERSION=8.5.12 \
PHPSFX_DB_VARIANT=mysql \
PHPSFX_REQUIRED_PDO_DRIVERS=mysql \
PHPSFX_MICRO_DISABLE_OPCACHE_JIT=1 \
bash scripts/build-micro-sfx.sh macos-a64
```

Linux x86_64、Linux ARM64 ODBC 代表包必须使用 ODBC Profile，并要求构建机有 unixODBC 开发头文件：

```bash
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
PHPSFX_PHP_VERSION=8.5 PHPSFX_PHP_FULL_VERSION=8.5.12 \
PHPSFX_DB_VARIANT=odbc PHPSFX_SWOOLE_ODBC=1 \
PHPSFX_MICRO_DISABLE_OPCACHE_JIT=1 \
bash scripts/build-micro-sfx.sh linux-x64
# Linux ARM64 使用：bash scripts/build-micro-sfx.sh linux-a64
```

构建产物位于 `dist/micro-<php>-<platform>-<variant>/`。PHP 8.4 和 8.5 各自使用独立目录，每条线固定以下十个文件名：

```text
linux.x64.mysql.sfx
linux.x64.pgsql.sfx
linux.x64.odbc.sfx
linux.a64.mysql.sfx
linux.a64.pgsql.sfx
linux.a64.odbc.sfx
macos.x64.mysql.sfx
macos.x64.pgsql.sfx
macos.a64.mysql.sfx
macos.a64.pgsql.sfx
windows.x64.mysql.sfx
windows.x64.pgsql.sfx
```

构建脚本写入独立元数据和 `SHA256SUMS`，并执行版本、扩展、单 PDO 集合和 ODBC 动态依赖校验；workflow 继续验证 Phar 打包与 Hyperf。合并 artifact 保留 PHP 版本目录，汇总元数据的 `asset_path` 和根目录 `SHA256SUMS` 使用相对路径，避免两条 PHP 线同名覆盖。汇总必须验证全部 24 个唯一构建及实际文件的大小、SHA-256；任何缺项均失败。从 Actions 下载后，先为所选 `.sfx` 执行 `chmod +x` 再打包。Windows x64 的 `.sfx` 是 PE 可执行文件，组合 Phar 后输出文件使用 `.exe` 后缀。

把应用 Phar 打包为可直接执行文件：

```bash
MICRO=dist/micro-8.5-macos-a64-mysql/macos.a64.mysql.sfx
bash scripts/pack-micro-phar.sh \
  "$MICRO" app.phar build/micro-app \
  --ini memory_limit=512M \
  --ini opcache.enable_cli=0
chmod +x build/micro-app
./build/micro-app
```

`--ini` 可以重复使用，`--ini-file path/to/app.ini` 可以注入多行配置。`app.phar` 必须包含可执行 Phar stub；生成文件的格式是 `micro.sfx + 可选 INI 块 + app.phar`，运行时直接执行 `./build/micro-app`。使用 `micro_get_self_filename()` 或 `phar://` 读取包内只读资源；日志、配置、上传、缓存、数据库文件和其他运行时写入内容放到 Phar 外部。

当前按 CLI OPcache 关闭的配置验收，与 dmskc2 的打包配置一致。macOS ARM64 / PHP 8.4.27 / PostgreSQL 产物实测注入 `opcache.enable_cli=1` 后，最小 Phar 在执行时触发 SIGBUS；同一 Phar 注入 `opcache.enable_cli=0` 正常，根因尚未定位。OPcache 扩展仍保留，使用时应在注入的 INI 中保持 `opcache.enable_cli=0`；其他平台及版本开启 CLI OPcache 的行为未验收。

构建后可分别运行：

```bash
bash scripts/validate-micro-sfx.sh "$MICRO"
bash scripts/test-micro-packaging.sh "$MICRO"
bash scripts/test-hyperf-micro-phar.sh "$MICRO"
```

这些脚本覆盖普通 PHP、默认/GZ/BZ2 Phar、INI 注入、`micro_get_self_filename()`、`phar://` 资源、PHP/Swoole/PDO 校验和 Hyperf 3.2 smoke。Linux ODBC 代表包还必须检查 `libodbc.so.2`；外部数据库厂商驱动、DSN、账号和密码不随 micro.sfx 提供。


## 参考

- [swoole/swoole-cli](https://github.com/swoole/swoole-cli)
- [Swoole CLI 构建选项](https://github.com/swoole/swoole-cli/blob/main/docs/options.md)
- [Swoole CLI SFX 打包说明](https://github.com/swoole/swoole-cli/blob/main/sapi/samples/sfx/README.md)
- [Swoole CLI 官方 pack-sfx.php](https://github.com/swoole/swoole-cli/blob/main/sapi/scripts/pack-sfx.php)
