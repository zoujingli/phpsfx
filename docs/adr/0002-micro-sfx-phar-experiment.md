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

实验构建沿用当前 PHP 8.4.27、8.5.12、Swoole 6.2.5、Redis、Phar、PDO 和裁剪扩展集合。static-php-cli 默认会把 `pgsql`、`sqlite3` 作为 PDO 扩展依赖带入，实验构建显式移除这两条依赖，以保持当前 Swoole CLI 的 PDO 合同。代表矩阵为：

| PHP | 平台 | 变体 | 目的 |
|------|------|------|------|
| 8.4 / 8.5 | macOS ARM64 | `sqlite-mysql-pgsql` | slim、SQLite、本地 Phar |
| 8.4 / 8.5 | Linux x86_64 | `odbc` | ODBC hook、动态 unixODBC、事务并发 |

Linux ODBC 必须保留 `libodbc.so.2` 动态依赖。如果 static-php-cli 默认静态 musl 链路无法满足该合同，workflow 保留失败日志并停止扩展，不通过放宽验证来掩盖差异。

## 体积与兼容性边界

micro 与 Swoole CLI 的运行时基线、SFX 格式和组件构建器不同。历史约 31 MB 的 micro 产物使用的是旧 PHP/Swoole 和旧扩展集，不能直接作为当前体积预估。实验必须使用同一测试 Phar，分别记录运行时和打包后文件大小，再与当前 Swoole CLI 代表产物比较。

Hyperf 3.2 smoke 使用 Phar 内的 vendor 代码，外置可写配置和 runtime 目录，验证真实 dmskc2 风格的启动、协程请求、SQLite/ODBC 能力。

Swoole worker fork 前，smoke stub 会按 Composer classmap 预加载 Phar 内类。实测 micro + Phar 在 worker 首次懒加载类时可能出现 classmap 路径不可用，因此该预加载步骤是当前实验的兼容性护栏；若 dmskc2 采用同一方式，需把它纳入正式启动入口或改为验证新 Swoole/micro 版本的 worker Phar 行为。
