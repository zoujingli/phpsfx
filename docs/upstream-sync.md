# 上游同步记录

本仓库把官方 `swoole-cli` 当作构建基线，而不是把发布流程绑定到官方 CLI 标签。所有 PHP 版本适配、扩展选择、builder 覆盖、ODBC 修补和发行元数据都在当前仓库审计。

## v6.2.3.0 基线

| 输入 | 固定值 | 用途 |
| --- | --- | --- |
| 官方 `swoole-cli` | `f7903840c3e959612dac7d413205e1bdb0067029` (`v6.2.2.2`) | 构建脚本、SFX、Profile 和依赖 builder 基线 |
| 官方 `swoole-src` | `8b20cd39f8c19da7aaf70290037e04f616db5ff7` (`v6.2.3`) | Swoole 扩展源码 |
| PHP | `d6bbf3ed631eea9763a2b790653fc91b69f0af7a` (`php-8.5.9`) | PHP release source archive 对应源码 |
| 本地发行版本 | `v6.2.3.0` | 本仓库定义的 CLI 版本，不是官方标签 |

官方目前没有 `swoole-cli v6.2.3` 标签。`PHPSFX_SWOOLE_CLI_REF` 默认使用上面的 commit，`PHPSFX_SWOOLE_SRC_REF` 默认使用 `v6.2.3`；构建时由 `prime_swoole_extension_archive` 固定和展开 Swoole 源码。

## v6.2.3.1 数据库分包

继续使用上表固定的 `swoole-cli`、`swoole-src` 和 PHP 8.5.9 源码，不同步或移动上游 commit。仓库的 Profile 根据 `PHPSFX_DB_VARIANT` 分别启用 `pgsql-sqlite`、`mysql-sqlite`、`mysql-pgsql-sqlite`；每种组合再提供独立的 ODBC 版，四平台共 24 个产物。未选中的 PDO 驱动必须在运行时缺席，`mysql-sqlite` 版不构建 libpq；SFX/Phar 格式、PHP 与 Swoole 版本不变。`v6.2.3.0` 原 Release 和标签不改动。每次发布的实际运行结果、SHA256 和校验记录以对应的 Release 元数据及工作流为准。

本地 macOS ARM64 已完成六种组合的完整构建，均通过 PHP 8.5.9、Swoole 6.2.3、精确 PDO 驱动集合、PDO SQLite、PHP/Phar SFX 和 Hyperf 3.2 smoke。三种 ODBC 版另通过 SQLite ODBC 事务、中文和并发查询，动态依赖为 `libodbc.2.dylib`；`mysql-sqlite` 两版的构建日志不含 libpq。四平台结果以 `v6.2.3.1` 发布工作流为准。

## v6.2.3.2 SQLite 独立拆包

继续使用相同的官方基线、PHP 8.5.9 和 Swoole 6.2.3，保留 `v6.2.3.0`、`v6.2.3.1` 的 tag 与 Release。新增 `sqlite`、`mysql`、`pgsql`、`mysql-pgsql` 四种 PDO 组合，原三种含 SQLite 组合不变；四平台各有七种普通版和七种 ODBC 版，共 56 个二进制、56 份平台元数据、汇总元数据与 `SHA256SUMS`，合计 114 个 Release 资产。默认组合与无组合名下载别名仍为 `mysql-pgsql-sqlite`。未选 SQLite 时不补入 `pdo_sqlite` 源码、不注入 builder、不构建 SQLite 客户端库；未选 PostgreSQL 时同样不构建 libpq。ODBC 版通过 CI 单独安装的 SQLite ODBC 驱动验收事务与并发，不依赖该二进制包含 `pdo_sqlite`。本地 macOS ARM64 的 14 个组合均已完整构建，并通过精确 PDO 驱动、未选库构建目标缺席、PHP/Phar SFX 和 Hyperf 3.2 smoke；七个 ODBC 版还通过外部 SQLite ODBC 事务与并发测试。`bash -n`、ShellCheck、actionlint、Composer、Profile/下载测试、发布核验单测和 `git diff --check` 均通过。四平台发布结果以本版本的 Release 元数据和工作流为准。

## v6.2.3.3 双 PHP 版本线与安全更新

同一 Release 同时发布 PHP `8.4.27`、`8.5.12`，两条线均修复 [CVE-2026-109618 和 CVE-2026-109619](https://www.php.net/archive/2026.php#2026-10-21-5)，涉及 Zend OOM 和请求状态清理。源码输入来自 [PHP 8.4 官方 release API](https://www.php.net/releases/index.php?json&version=8.4.27) 和 [PHP 8.5 官方 release API](https://www.php.net/releases/index.php?json&version=8.5.12)：

| PHP 版本 | 官方 tag commit | 官方 tar.gz SHA-256 |
| --- | --- | --- |
| 8.4.27 | `00d8bae801541db0d95a698e108bb4b1b273fe6e` | `5bafed9994c1a49796b25b5f61c22c9183bfe046b6acc7b363842d03c77f972f` |
| 8.5.12 | `136e049ac10b032c83018e65b63b6df858943750` | `81a0f450349e84b08eb43faa85f8a4c835684f3cc1c50471775d1317a046c525` |

两份本地源码压缩包均已按上表核验 SHA-256。Swoole CLI 基线、Swoole 6.2.3、七种 PDO 组合、ODBC 叠加和 SFX 格式继续沿用；每条 PHP 版本线覆盖四平台、十四组合，共 112 个二进制、112 份独立元数据和两个汇总文件，合计 226 个 Release 资产。二进制和独立元数据均包含 `php8.4` 或 `php8.5`；`variant` 的语义不变，汇总唯一键改为 `php_version + variant`。发布前后复用同一完整矩阵核验，发布后分页读取全部资产并抽查两条 PHP 线的公开下载链接。下载默认仍选择 PHP 8.5，通过 `PHPSFX_PHP_VERSION=8.4` 选择另一条线；旧 tag 不移动、旧 Release 不修改。已有单文件应用必须使用新运行时重新打包才能更新内嵌 PHP。

本地 macOS ARM64 已验证两条 PHP 线的普通/ODBC 全量组合，共四份代表包；精确 PHP/Swoole 版本、PDO 集合、SQLite 本地读写、PHP/Phar SFX 和 Hyperf 3.2 均通过。两个 ODBC 包另通过外部 SQLite ODBC 事务、中文、并发查询及 `libodbc.2.dylib` 动态依赖检查。两条 PHP 线的 OPcache 编译/缓存检查均通过；官方 OOM/Fiber 定向用例每条线 7 通过、1 因未打包 `zend_test` 跳过，不代表覆盖所有安全漏洞利用路径。28 种 Profile/下载兼容测试、7 项发布核验单测、`bash -n`、ShellCheck、actionlint、Composer 和 `git diff --check` 均通过。其余数据库组合和四平台的完整 112 项验收由本版本发布 CI 执行；未进行外部 MySQL、PostgreSQL 或厂商数据库连接验收。

## v6.2.3.4 按线上与开发用途收敛

固定源码和两条 PHP 精确版本沿用 v6.2.3.3。发布平台收敛为 Linux x86_64、Linux ARM64、macOS ARM64；每个平台、PHP 版本只发 `mysql`、`pgsql`、`odbc` 三种线上包和 `sqlite-mysql-pgsql-odbc` 开发全量包，共 24 个二进制。ODBC-only 线上包不包含 MySQL、PostgreSQL、SQLite PDO 驱动，不构建 libpq 或 SQLite 客户端库；开发包包含四种 PDO 驱动。Swoole mysqlnd、SFX/Phar、图片处理及 OPcache 能力沿用。

所有平台元数据汇入 `build-meta.json`，Release 只上传 24 个二进制、汇总元数据、24 条记录的 `SHA256SUMS`，共 26 个资产。独立元数据仍保留在 Actions artifact；汇总中的 `metadata_asset` 统一指向 `build-meta.json`。发布前后严格检查两条 PHP 线各 12 个唯一身份、精确 PDO 集合、平台动态依赖及全部 SHA-256。新版本默认构建和无后缀下载选择 MySQL 线上包，生产下载推荐显式指定后缀；v6.2.3.0 至 v6.2.3.3 的下载规则仍按原布局处理，旧 tag 不移动。macOS Intel 和旧组合不进入新矩阵。

本地 macOS ARM64 已完整构建两条 PHP 线的四种包，共八份；精确 PHP/Swoole 版本、PDO 驱动集合、未选扩展和依赖构建目标缺席、PHP/Phar SFX、Hyperf 3.2 均通过。两个开发包另通过本地 PDO SQLite 读写；四个 ODBC 线上及开发包另通过外部 SQLite ODBC 事务、中文、并发查询和 `libodbc.2.dylib` 动态依赖检查。八种 Profile、24 个文件名及旧版本下载兼容测试、10 项发布核验单测、`bash -n`、ShellCheck、actionlint、Composer 严格校验和 `git diff --check` 均通过。Linux 两个架构与完整 24 包的发布验收由本版本 CI 执行，跨平台发布结果以对应工作流、Release 元数据与分页资产核验为准；未进行外部 MySQL、PostgreSQL 或厂商数据库连接验收。

## v6.2.3.5 开发包名称与平台 ODBC 边界修正

沿用固定上游输入、PHP 8.4.27 / 8.5.12 和 Swoole 6.2.3。开发包统一改名为 `sqlite-mysql-pgsql`，Linux 保留 PDO ODBC 和 Swoole 协程 ODBC，macOS 开发包只提供三个 PDO 驱动且不依赖 unixODBC；用户已确认三个平台的独立 `odbc` 线上包均保留，因此仍为 24 个二进制、26 个 Release 资产。元数据和下载规则按版本区分，v6.2.3.4 tag 不移动，尚未发布的旧流水线因方案被替代而取消。术语见根目录 `CONTEXT.md`，平台差异依据见 [ADR](adr/0001-development-package-odbc-by-platform.md)。

截至 2026-10-22，PHP 官方发布接口确认两条线最新版本仍为 8.4.27 和 8.5.12。本次在 macOS ARM64 完整重建这两条 PHP 线的开发包，均通过精确版本、三种 PDO 驱动、无 unixODBC 动态依赖、SQLite 本地读写、PHP/Phar SFX 和 Hyperf 3.2 检查。24 项发行配置与旧版本下载兼容、12 项发布核验单测、`bash -n`、ShellCheck、actionlint、Composer 严格校验和 `git diff --check` 均通过；平台 ODBC 新回归已先观察旧实现失败，再验证修正后通过。三个线上包能力沿用前次验证，本次未重复完整构建全部八个 macOS 包；Linux 开发包及完整 24 包的实际发布结果以新版本 CI 和 Release 核验为准，未验收外部 MySQL、PostgreSQL 或厂商数据库连接。

## v6.2.3.6 发行检查隔离 ODBC 作业环境

v6.2.3.5 的 ODBC 作业在运行全部发行配置检查时，将当前作业的 `PHPSFX_SWOOLE_ODBC=1` 传入普通 Profile 用例，导致测试在构建前误失败。单变量复现命令 `PHPSFX_SWOOLE_ODBC=1 bash tests/test-release-variants.sh` 已观察失败；每个配置用例先显式关闭 ODBC，再由所选 ODBC Profile 启用，修正后同一命令通过。该修复只涉及测试隔离和发行版本默认值，24 包矩阵、平台能力边界、PHP/Swoole 与固定依赖输入沿用 v6.2.3.5，旧 tag 不移动。

另一个 Linux ARM64 PostgreSQL 作业在下载 giflib 时连续三次 SSL 连接超时，原 SourceForge 链接随后已恢复 HTTP 200；保留原依赖 URL 和内容校验，不将该瞬时失败归因于源码或包配置。新 tag 的 CI 重新验证完整矩阵，实际发布与资产结果以该运行及分页核验为准。

普通环境及 ODBC 作业环境下的 24 项发行配置/旧下载兼容检查均通过，12 项发布核验单测、`bash -n`、ShellCheck、actionlint、Composer 严格校验和 `git diff --check` 通过。运行时构建输入没有改动，本次未重复本地编译，复用前述 v6.2.3.4 线上包及 v6.2.3.5 macOS 开发包的实际验证；完整 24 包仍须由新版本 CI 和 Release 核验验收，未验收外部 MySQL、PostgreSQL 或厂商数据库。

## v6.2.4.0 同步 Swoole 6.2.4

2026-10-31 核对官方发布：最新稳定扩展为 [Swoole v6.2.4](https://github.com/swoole/swoole-src/releases/tag/v6.2.4)，对应 commit `c7e514509451beafd4d70ce5b78943d51e76381c`；`v6.3.0-rc1` 为候选版。官方 PHP release API 确认两条线最新版本仍为 8.4.27、8.5.12，继续沿用上表归档和校验值。Swoole v6.2.4 的 codeload 归档 SHA-256 为 `92624681feb1b1311a4ee0fc40080e747b63fc5d0ed988f8e6aa148aac55987f`。

CLI 构建基线同步为官方 v6.2.4.0 commit `f70344b0b40231347504c995c6ce3f26ccce26a7`，扩展源码目标为 v6.2.4。按用户确认，未使用的 `-U/--self-update` 随上游删除，SFX 格式继续沿用；原 `sw_usleep` 兼容和 libiconv 下载 URL 补丁已由上游修复，删除本地重复实现。新版修复 WebSocket 控制帧与握手校验、HTTP 请求边界、流超时、信号及协程状态等问题；PHP 8.5 与 ODBC configure probe 等仍需要的本地适配继续保留。

本地发行目标改为 v6.2.4.0，仍为双 PHP、三平台四包，共 24 个二进制、26 个 Release 资产。下载参数和旧 tag 布局沿用；发布核验根据发行版本推导默认 Swoole 精确版本，并保留显式源码 ref 覆盖。新增“新版发行拒绝旧 Swoole 版本”回归已观察修正前失败、修正后通过，旧发行校验继续覆盖。

本地 macOS ARM64 完整构建两条 PHP 线的开发包和独立 ODBC 包，共四份，均通过精确 PHP/Swoole 版本、PDO 集合、禁止扩展、PHP/Phar SFX 和 Hyperf 3.2 检查。两个开发包通过 PDO SQLite 读写且不依赖 unixODBC；两个 ODBC 包通过外部 SQLite ODBC 事务、中文和并发查询，动态依赖为 `libodbc.2.dylib`。四份均通过 WebSocket 控制帧 125/126 字节边界和 FIN 规范化检查，帮助信息中已无 `-U/--self-update`；产物元数据的固定基线和 SHA-256 与实际文件一致。

24 项发行配置/旧下载兼容、14 项发布核验单测、`bash -n`、ShellCheck、actionlint、Composer 严格校验及 `git diff --check` 均通过。日志保留在 `.build/logs-v6240`，本地产物在 `dist/v6.2.4.0/macos-a64`，一次性检查脚本已清理。其余组合、Linux 两架构和完整 24 包的实际发布结果以新版本 CI 与分页资产核验为准；未验收外部 MySQL、PostgreSQL 或厂商数据库连接。

## v6.2.5.0 同步 Swoole 6.2.5

2026-11-11 核对官方发布：最新稳定扩展为 [Swoole v6.2.5](https://github.com/swoole/swoole-src/releases/tag/v6.2.5)，对应 commit `76c657d88be39b7af6bf85e46bcbac0da7387760`；官方 CLI 基线为 [v6.2.5.0](https://github.com/swoole/swoole-cli/releases/tag/v6.2.5.0)，对应 commit `e891b2b38720c5879c9a2c7894384b9af7228de0`。Swoole 6.2.5 修复 cURL 句柄生命周期、信号继承与恢复、进程池调度和超时、HTTP/2 数据帧、HTTP body 边界、100 Continue、请求 trailer、上传头校验、PDO pgsql 查询取消与连接超时，以及 TLS 正常关闭状态上报等问题，并包含 HTTP 上传文件标记安全修复。

官方归档校验值如下：

| 输入 | 固定值 | SHA-256 |
| --- | --- | --- |
| PHP 8.4 | `8.4.27`，2026-10-21 发布 | `5bafed9994c1a49796b25b5f61c22c9183bfe046b6acc7b363842d03c77f972f` |
| PHP 8.5 | `8.5.12`，2026-10-21 发布 | `81a0f450349e84b08eb43faa85f8a4c835684f3cc1c50471775d1317a046c525` |
| Swoole 源码 | `v6.2.5` | `8b8261162375a04a1fc58775824ca146ac1d1905c178fbb548381c27f2c343f5` |
| Swoole CLI 基线 | `v6.2.5.0` | `c3b47304ab4126774211f9104acca3956295d4c03262bc301247af763993a6ae` |

PHP 两条版本线没有新的 patch 版本，仍固定为 8.4.27 和 8.5.12。构建默认值、workflow 输入、导入元数据和发行校验同步到 CLI v6.2.5.0 / Swoole v6.2.5；PHP 8.5 OPcache、lexbor/uri 和 ODBC configure probe 等本地必要适配继续保留，未因版本更新恢复未使用能力或移动历史 tag。

本次同步后的 Profile/发布核验覆盖新默认版本和旧 Release 下载兼容；v6.2.5.0 CI 运行 `42971808577` 的 25 个 job 全部成功，生成双 PHP、三平台四用途的 24 个二进制。合并 workflow artifact 为 50 个文件，归档 SHA-256 为 `6b71840c582165003d8f5febc2dbce6ef67ae564730d1f17809d84503770c99a`；分页 Release API 核对 26 个资产的名称、大小和 SHA-256 全部一致，24 个 `php_version + variant` 身份、PHP 8.4.27/8.5.12、Swoole 6.2.5 及新上游 ref 均一致，抽查两条 PHP 线三个平台公开下载链接通过。仍未验收外部 MySQL、PostgreSQL 或厂商数据库连接。

## v6.2.5.1 剥离调试符号

v6.2.5.0 的 dmskc2 代表运行时仍包含调试符号。对同一份可执行文件做平台对应的 `strip --strip-debug`（macOS 使用 `strip -S`）后，Linux ARM64 从 44.5 MB 降至 39.4 MB，macOS ARM64 从 35.1 MB 降至 34.8 MB；PHP、Swoole、PDO 驱动、SFX/Phar 行为均保持通过。v6.2.5.1 在构建产物复制到 `dist/` 后、动态依赖和运行时校验前统一剥离调试符号，导入脚本同步采用相同规则；扩展集合、编译选项和 ODBC 动态链接合同不变。旧 v6.2.5.0 tag 与 Release 保留不变。

v6.2.5.1 CI 运行 `43008772159` 的 25 个 job 全部成功，24 个二进制总大小由 v6.2.5.0 的 1,103,076,376 bytes 降至 1,016,801,832 bytes，减少 86,274,544 bytes（7.82%）。合并 artifact 为 50 个文件，归档 SHA-256 为 `5003777229c179a824829c67b94041930e10468e6fccd03835e496033b5e44c1`；分页 Release API 核对 26 个资产的名称、大小和 SHA-256 全部一致，6 个代表下载链接通过 HTTP 206 探针。

## 当前本地适配

1. `scripts/build-swoole-cli.sh` 按 `PHPSFX_PHP_VERSION` 将基线的 `sapi/PHP-VERSION.conf` 切换为 `8.4.27` 或 `8.5.12`，调用基线的 `sync-source-code.php`，并确认 `main/php_version.h` 报告精确版本。同一版本线的 patch 更新也必须同步，不能只比较 `8.4` / `8.5` 前缀。
2. PHP 同步后，仅对选中的 PDO 驱动从对应 PHP release 源码补入 `ext/pdo_sqlite` 和/或 `ext/pdo_pgsql`。上游同步脚本没有把 `pdo_pgsql` 列入固定扩展清单，因此该步骤由本仓库显式维护。
3. 构建阶段按组合写入本仓库的 `pdo_sqlite` 和/或 `pdo_pgsql` builder。`pdo_pgsql` 依赖本地精简的 `sapi/src/builder/library/pgsql.php` 生成 `libpq`，通过 `LIBPQ_CFLAGS` / `LIBPQ_LIBS` 配置 PHP 的 `--with-pdo-pgsql`。
4. Profile 根据数据库组合选择 `pdo_mysql`、`pdo_pgsql`、`pdo_sqlite`，不启用 `mysqli`、原生 `pgsql`、`SQLite3` 或 Swoole SQLite hook。
5. Swoole builder 保留 server、coroutine、curl hook、mysqlnd、DNS 和 ODBC 能力；ODBC 版的 unixODBC 动态链接和 configure probe 修补仍由当前仓库维护。
6. phpredis 固定为 6.3.0（PHP 8.5 的 smart-string 头文件已从 `ext/standard` 移至 Zend）。仅 PHP 8.5 构建移除旧 OPcache 注册/stub、补入 lexbor/uri，8.4 保留基线注册方式。Swoole 6.2.5 和新 CLI 基线已包含睡眠函数及 libiconv URL 修复，本地不再重复应用。
7. `scripts/validate-swoole-cli.sh` 强制检查目标 PHP 精确版本、Swoole 6.2.5、所选 PDO driver 集合（含未选驱动缺席）、含 SQLite 包的 PDO SQLite 本地读写，以及禁止扩展集合；显式指定旧源码 ref 时按该版本验证。

## 参考官方更新的流程

在需要吸收官方优化时：

```bash
git ls-remote --tags https://github.com/swoole/swoole-cli.git
git ls-remote --tags https://github.com/swoole/swoole-src.git
curl -fsSL https://www.php.net/releases/ | head
```

然后按以下顺序更新：

1. 选择并记录可复现的官方 commit，不把浮动的 `main` 直接作为发布输入。
2. 检查 `PHP-VERSION.conf`、`SWOOLE-VERSION.conf`、`sync-source-code.php`、builder API 和 SFX 读取逻辑的变化。
3. 在当前仓库修改构建脚本、Profile 或补丁；不要把完整 PHP/Swoole 源码树提交进仓库。
4. 更新本表的 commit、适配说明和验证结果，并在 `build-meta.json` 中保留实际 commit。
5. 先执行静态检查，再在 macOS ARM64 完整构建；随后验证 SFX、Phar、Hyperf 3.2、PDO SQLite、PDO driver 集合和 ODBC 动态依赖。
6. 通过后再创建新的本地版本标签。已发布标签不移动、不覆盖；失败修复使用新的递增版本。

## 验证记录模板

每次同步应在变更说明或 Release 中记录：

- 上游 `swoole-cli` commit 与 `swoole-src` tag/commit；
- PHP 完整版本与 source archive 校验结果；
- 本地 builder/profile/patch 的文件和原因；
- `bash -n`、ShellCheck、actionlint、Composer、`git diff --check` 结果；
- 至少一个原生构建平台的完整构建、SFX/Phar、PDO 和 Hyperf smoke 结果；
- 两条 PHP 线、三平台四种用途 CI、`build-meta.json`、`SHA256SUMS` 和 24 个 Release 二进制、26 个资产的分页核对结果。
