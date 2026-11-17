# micro.sfx + Phar 作为并行实验链

当前发行继续使用 Swoole CLI SFX。为评估 dmskc2 的单文件运行方式，实验分支增加独立的 micro.sfx + Phar 链路，第一阶段只生成 Actions artifact，不创建 Release，也不改变现有 24 个 Swoole CLI 资产。

## 格式与运行

micro 的文件结构为：

```text
micro.sfx + [0xfd 0xf6 0x69 0xe6 + big-endian INI length + INI data] + app.phar
```

没有 Swoole CLI 使用的 `pack('J', payloadSize)` 尾部，运行时直接执行：

```bash
./app
```

`--with-micro-fake-cli` 使 `PHP_SAPI` 保持为 `cli`，但 micro 运行时不提供 `SWOOLE_CLI` 常量和 `--self` 入口。Phar 内的只读资源可通过 `phar://` 和 `micro_get_self_filename()` 读取；日志、配置、上传、缓存和数据库文件必须放在 Phar 外部。

`scripts/pack-micro-phar.sh` 复现 static-php-cli `micro:combine` 的拼接和 INI 注入行为，并独立校验 Phar stub。现有 `scripts/pack-phar.sh` 不复用、不修改。

## 组件与验证范围

实验构建沿用当前 PHP 8.4.27、8.5.12、Swoole 6.2.5、Redis、Phar、PDO 和裁剪扩展集合。static-php-cli 默认会把 `pgsql`、`sqlite3` 作为 PDO 扩展依赖带入，实验构建显式移除这两条依赖，以保持当前 Swoole CLI 的 PDO 合同。`pdo_pgsql` 同时改用无路径的 `--with-pdo-pgsql`，让 PHP 通过静态 `pkg-config` 带入 PostgreSQL 的 `libpgcommon` 与 `libpgport`；直接传 prefix 会退回 `pg_config` 并在 macOS 静态链接时漏掉这两个库。代表矩阵为：

| PHP | 平台 | 变体 | 目的 |
|------|------|------|------|
| 8.4 / 8.5 | macOS ARM64 | `sqlite-mysql-pgsql` | slim、SQLite、本地 Phar |
| 8.4 / 8.5 | Linux x86_64 | `odbc` | ODBC hook、动态 unixODBC、事务并发 |

Linux ODBC 必须保留 `libodbc.so.2` 动态依赖。如果 static-php-cli 默认静态 musl 链路无法满足该合同，workflow 保留失败日志并停止扩展，不通过放宽验证来掩盖差异。

## 当前 macOS ARM64 体积实测

以下比较使用同一个 `sqlite-mysql-pgsql` 变体：micro 由本分支本地构建，Swoole CLI 取已发布的 `v6.2.5.1` 对应资产。数值是可执行文件字节数，未包含 Phar 应用本身。

| PHP | Swoole CLI | micro.sfx | 差值 | 相对变化 |
|------|-----------:|----------:|-----:|---------:|
| 8.4.27 | 36,792,928 | 34,600,848 | -2,192,080 | -5.96% |
| 8.5.12 | 39,721,536 | 43,217,024 | +3,495,488 | +8.80% |

因此 micro.sfx 的体积收益取决于 PHP 版本和构建器输入，不能按历史 micro 产物推断统一收益；8.5 代表包当前反而更大。

用同一个最小测试 Phar 追加到两种 SFX 后，结论一致：8.4.27 的 micro 文件为 34,601,168 bytes，Swoole CLI 为 36,793,256 bytes，减少 2,192,088 bytes（-5.96%）；8.5.12 的 micro 文件为 43,217,344 bytes，Swoole CLI 为 39,721,864 bytes，增加 3,495,480 bytes（+8.80%）。两种生成文件分别以直接执行和 `--self` 执行，均输出预期的 PHP 版本、`cli` SAPI、Phar 内容和对应运行时标识。

## PHP 能力裁剪记录

当前 dmskc2 的 `composer.json` 明确要求 bcmath、bz2、curl、DOM、fileinfo、GD、mbstring、OpenSSL、OPcache、pcntl、PDO/MySQL、posix、Redis、SimpleXML、sockets、sodium、tokenizer、XML、XMLReader、XMLWriter、Zip 和 zlib；源码还实际使用 ctype、filter、iconv、Phar、Sodium、ZipArchive、GD、pcntl 与 posix。这些能力继续保留。phpdbg、PHP debug build、Xdebug、原生 pgsql、SQLite3、mysqli、session、soap、readline、intl、imagick、gmp 和 mongodb 已经排除。

生产 dmskc2 只声明 `pdo_mysql`；`pdo_pgsql` 和 `pdo_sqlite` 仍保留在开发代表包中，后续可用 `PHPSFX_DB_VARIANT=mysql` 单独构建生产包。当前 static-php-cli 默认编译 OPcache JIT，但 dmskc2 的 SFX 打包配置把 CLI OPcache 关闭，因此实验链从本次起默认传入 `--disable-opcache-jit`。JIT 关闭后的实际字节差异必须以同一版本重建和 Phar smoke 结果为准。

## 体积与兼容性边界

micro 与 Swoole CLI 的运行时基线、SFX 格式和组件构建器不同。历史约 31 MB 的 micro 产物使用的是旧 PHP/Swoole 和旧扩展集，不能直接作为当前体积预估。实验必须使用同一测试 Phar，分别记录运行时和打包后文件大小，再与当前 Swoole CLI 代表产物比较。

Hyperf 3.2 smoke 使用 Phar 内的 vendor 代码，外置可写配置和 runtime 目录，验证真实 dmskc2 风格的启动、协程请求、SQLite/ODBC 能力。

Swoole worker fork 前，smoke stub 会按 Composer classmap 预加载 Phar 内类。实测 micro + Phar 在 worker 首次懒加载类时可能出现 classmap 路径不可用，因此该预加载步骤是当前实验的兼容性护栏；若 dmskc2 采用同一方式，需把它纳入正式启动入口或改为验证新 Swoole/micro 版本的 worker Phar 行为。
