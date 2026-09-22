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

## 本地适配

1. `scripts/build-swoole-cli.sh` 将基线的 `sapi/PHP-VERSION.conf` 切换为 `8.5.9`，调用基线的 `sync-source-code.php`，并确认 `main/php_version.h` 报告 `8.5.9`。
2. PHP 同步后，从 PHP 8.5.9 源码补入 `ext/pdo_sqlite` 和 `ext/pdo_pgsql`。上游同步脚本没有把 `pdo_pgsql` 列入固定扩展清单，因此该步骤由本仓库显式维护。
3. 构建阶段写入本仓库的 `pdo_sqlite` 和 `pdo_pgsql` builder。`pdo_pgsql` 依赖上游 `sapi/src/builder/library/pgsql.php` 生成的 `libpq`，通过 `LIBPQ_CFLAGS` / `LIBPQ_LIBS` 配置 PHP 的 `--with-pdo-pgsql`。
4. Profile 只启用 `pdo_mysql`、`pdo_pgsql`、`pdo_sqlite`，不启用 `mysqli`、原生 `pgsql`、`SQLite3` 或 Swoole SQLite hook。
5. Swoole builder 保留 server、coroutine、curl hook、mysqlnd、DNS 和 ODBC 能力；ODBC 版的 unixODBC 动态链接和 configure probe 修补仍由当前仓库维护。
6. phpredis 固定为 6.3.0（PHP 8.5 的 smart-string 头文件已从 `ext/standard` 移至 Zend）；Swoole 6.2.3 的 `sw_usleep` 调用由本地补丁改为标准 C++ 睡眠实现。
7. `scripts/validate-swoole-cli.sh` 强制检查 PHP 8.5.9、Swoole 6.2.3、PDO driver `mysql/pgsql/sqlite`、PDO SQLite 本地读写，以及禁止扩展集合。

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
- 八平台 CI、`build-meta.json`、`SHA256SUMS` 和 Release 资产结果。
