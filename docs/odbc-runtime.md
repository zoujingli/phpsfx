# Linux ODBC 环境与常见数据库配置

本文说明 `phpsfx` Linux 标准 Release 的 ODBC 能力、部署依赖和常见数据库配置方式。适用于：

- `swoole-cli-php8.4-linux-x64`
- `swoole-cli-php8.4-linux-a64`

macOS x86_64、ARM64 产物当前不包含 PDO ODBC 和 Swoole ODBC 协程能力。

## 1. Release 能力边界

Linux 标准产物保证：

- `PDO::getAvailableDrivers()` 包含 `odbc`。
- `SWOOLE_HOOK_PDO_ODBC` 已定义并包含在 `SWOOLE_HOOK_ALL` 中。
- `php --ri swoole` 显示 `coroutine_odbc => enabled`。
- ELF 动态依赖中存在 `libodbc.so.2`。

Release 不包含：

- unixODBC 运行库和命令行工具。
- MySQL、SQLite、达梦、PostgreSQL、SQL Server、Oracle 等厂商驱动。
- `odbcinst.ini`、`odbc.ini`、证书、DSN、账号或密码。
- 数据库 SQL 方言、DDL、分页、迁移、字段类型、大小写和字符集兼容层。

即使业务只使用 MySQL 或 SQLite，Linux 标准运行时也会在进程启动时加载 `libodbc.so.2`，因此部署机必须安装 unixODBC。具体数据库能否使用取决于同架构的厂商驱动、驱动自身依赖、DSN、网络、凭据和真实连库验收。

MySQL 和 SQLite 已分别内置 `pdo_mysql`、`pdo_sqlite`/`sqlite3`。没有统一接入要求时优先使用原生 PDO 驱动；ODBC 主要用于必须通过厂商 ODBC 客户端接入的数据库。

## 2. 安装 Driver Manager

### Debian / Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y unixodbc
```

源码构建运行时还需要头文件：

```bash
sudo apt-get install -y unixodbc-dev
```

### RHEL / Rocky Linux / 麒麟常见仓库

```bash
sudo dnf install -y unixODBC
```

源码构建运行时再安装：

```bash
sudo dnf install -y unixODBC-devel
```

部分系统使用 `yum`，包名也可能随仓库变化。安装后检查：

```bash
ldconfig -p | grep 'libodbc\.so\.2'
odbcinst -j
odbcinst -q -d
```

`odbcinst -j` 会显示当前用户实际读取的驱动和 DSN 配置位置。常见系统级文件是：

```text
/etc/odbcinst.ini
/etc/odbc.ini
```

systemd 服务、容器和交互式 Shell 可能使用不同用户或配置目录。所有检查都应以实际应用服务用户执行。

## 3. 安装厂商驱动

从操作系统仓库或数据库厂商官方渠道安装与 Linux 架构、发行版 ABI 和数据库版本匹配的 ODBC 驱动。不要把驱动、客户端许可证文件或内部安装包复制进 `phpsfx` Release。

对于手动安装的 `.so` 文件，至少检查：

```bash
file /absolute/path/to/vendor-driver.so
ldd /absolute/path/to/vendor-driver.so
```

通过标准：

- 驱动架构与 `uname -m`、运行时和 unixODBC 一致。
- `ldd` 没有 `not found`。
- 应用服务用户对驱动及其依赖目录有读取和执行权限。
- 驱动需要的动态库目录已经进入系统动态库缓存，或只为服务进程配置了必要的 `LD_LIBRARY_PATH`。

## 4. 注册驱动和 DSN

`odbcinst.ini` 注册驱动名称和动态库路径；`odbc.ini` 用驱动名称定义数据源。账号和密码不要写进这两个文件。

注册后检查：

```bash
odbcinst -q -d
odbcinst -q -s
odbcinst -q -d -n '驱动节名'
odbcinst -q -s -n 'DSN 节名'
```

PHP 使用命名 DSN：

```text
odbc:<odbc.ini 节名>
```

例如 `odbc:app-prod`。连接参数名和默认值由厂商驱动定义，下列配置是结构示例，驱动名称、路径和关键字必须以目标版本官方文档及 `odbcinst -q -d` 的实际输出为准。

## 5. 常见数据库示例

### MySQL / MariaDB

优先选择内置的 `pdo_mysql`。只有统一 ODBC 接入或厂商兼容认证要求时，才安装 MySQL Connector/ODBC 或 MariaDB Connector/ODBC。

```ini
# /etc/odbcinst.ini
[MySQL Unicode]
Description=MySQL Connector ODBC Unicode driver
Driver=/absolute/path/to/libmyodbc8w.so
```

```ini
# /etc/odbc.ini
[mysql-prod]
Driver=MySQL Unicode
SERVER=db.example.internal
PORT=3306
DATABASE=app
```

PDO DSN 为 `odbc:mysql-prod`。TLS CA、证书校验和连接参数应按 Connector/ODBC 对应版本配置，不要因为内网地址而默认关闭证书验证。

### SQLite

应用内 SQLite 优先选择内置的 `pdo_sqlite` 或 `sqlite3`。SQLite ODBC 主要用于验证 ODBC 链路，公共 CI 使用发行版提供的 SQLite ODBC 驱动执行连接、预处理、事务和协程并发测试。

Debian/Ubuntu 常用安装方式：

```bash
sudo apt-get install -y libsqliteodbc
odbcinst -q -d
```

如果安装包已经注册 `SQLite3` 驱动，只需配置 DSN：

```ini
# /etc/odbc.ini
[sqlite-local]
Driver=SQLite3
Database=/var/lib/app/app.sqlite
```

PDO DSN 为 `odbc:sqlite-local`。应用服务用户必须对数据库文件有正确权限；需要写入时还必须能在其目录中创建 SQLite 日志或 WAL 文件。

### 达梦 DM8

安装同架构的达梦官方客户端后注册驱动：

```ini
# /etc/odbcinst.ini
[DM8 ODBC DRIVER]
Description=Dameng DM8 Official ODBC Driver
Driver=/opt/dmdbms/bin/libdodbc.so
Threading=0
```

```ini
# /etc/odbc.ini
[dm-prod]
Driver=DM8 ODBC DRIVER
SERVER=10.0.0.10
TCP_PORT=5236
```

PDO DSN 为 `odbc:dm-prod`。达梦客户端通常还需要设置 `DM_HOME`，并让服务进程能够加载客户端目录中的其它动态库。完整安装、真实只读/写入验收和智慧厨房业务兼容边界见 [达梦 ODBC 环境与真实验收](dameng-odbc-runtime.md)。

### PostgreSQL

安装官方或发行版提供的 psqlODBC 驱动。Debian/Ubuntu 常见包名为 `odbc-postgresql`，安装后以 `odbcinst -q -d` 返回的 Unicode 驱动名称为准。

```ini
# /etc/odbc.ini
[postgres-prod]
Driver=PostgreSQL Unicode
Servername=db.example.internal
Port=5432
Database=app
SSLmode=verify-full
```

PDO DSN 为 `odbc:postgres-prod`。使用 `verify-full` 时还需按 psqlODBC 文档部署受信任 CA，并确保连接主机名与证书匹配。

### Microsoft SQL Server

按微软对应 Linux 发行版的官方步骤安装 Microsoft ODBC Driver 18 for SQL Server。安装程序通常会自动注册驱动：

```bash
odbcinst -q -d -n 'ODBC Driver 18 for SQL Server'
```

```ini
# /etc/odbc.ini
[sqlserver-prod]
Driver=ODBC Driver 18 for SQL Server
Server=tcp:db.example.internal,1433
Database=app
Encrypt=yes
TrustServerCertificate=no
```

PDO DSN 为 `odbc:sqlserver-prod`。Driver 18 默认强调加密连接；应部署可信 CA 并保持证书校验，不要把 `TrustServerCertificate=yes` 当作生产环境的长期处理方式。

### Oracle Database

安装同架构、相互兼容的 Oracle Instant Client Basic 和 ODBC 包。动态库文件名包含客户端版本，以下驱动名和路径只是占位示例：

```ini
# /etc/odbcinst.ini
[Oracle Instant Client ODBC]
Description=Oracle Instant Client ODBC driver
Driver=/opt/oracle/instantclient/libsqora.so.VERSION
```

使用 Easy Connect：

```ini
# /etc/odbc.ini
[oracle-prod]
Driver=Oracle Instant Client ODBC
DBQ=//db.example.internal:1521/APP_SERVICE
```

PDO DSN 为 `odbc:oracle-prod`。如果使用 `tnsnames.ora` 或 Wallet，还需为服务进程配置正确的 `TNS_ADMIN`，并验证 Instant Client 的全部动态依赖。

## 6. 应用环境和 PDO 接口

建议为应用统一使用三个密钥配置项：

```text
APP_ODBC_DSN=odbc:app-prod
APP_ODBC_USER=<由密钥系统注入>
APP_ODBC_PASSWORD=<由密钥系统注入>
```

不要把真实凭据写入仓库、Release、镜像 Dockerfile、`odbc.ini`、systemd unit 或普通日志。排障时不要使用会打印环境变量的 `set -x`。

在创建协程和连接池之前启用 ODBC hook：

```php
<?php

Swoole\Runtime::enableCoroutine(
    Swoole\Runtime::getHookFlags() | SWOOLE_HOOK_PDO_ODBC
);

$dsn = getenv('APP_ODBC_DSN');
$user = getenv('APP_ODBC_USER');
$password = getenv('APP_ODBC_PASSWORD');

if ($dsn === false || $dsn === '' || $user === false || $password === false) {
    throw new RuntimeException('ODBC environment is incomplete');
}

$pdo = new PDO(
    $dsn,
    $user,
    $password,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
```

连接池应为每个连接使用同一套工厂配置，不要在多个并发协程之间同时操作同一个 PDO 对象。日志可以记录不含凭据的驱动类型和错误类别，但应对 DSN、用户名、密码及驱动返回的连接串做脱敏。

## 7. systemd 和容器

systemd unit 可以保存非敏感路径和 DSN 名，账号密码继续通过部署平台的凭据机制注入：

```ini
[Service]
Environment=APP_ODBC_DSN=odbc:app-prod
Environment=LD_LIBRARY_PATH=/opt/vendor/client/lib
ExecStart=/opt/app/app --self
```

修改后执行 `systemctl daemon-reload` 并重启服务。不要只在管理员 Shell 中 `export`，systemd 不会自动继承该 Shell 环境。

容器镜像必须显式安装 unixODBC 和获准分发的厂商驱动；或者通过受控卷挂载厂商客户端和只读配置。主机安装了驱动不代表容器内可见。镜像架构、基础系统 ABI、驱动架构和运行时必须一致。

## 8. 部署预检

假设运行时位于 `/opt/phpsfx/swoole-cli`：

```bash
RUNTIME=/opt/phpsfx/swoole-cli

test -x "$RUNTIME"
file "$RUNTIME"
ldd "$RUNTIME"
readelf -d "$RUNTIME" | grep 'libodbc\.so\.2'

"$RUNTIME" -r 'var_export(PDO::getAvailableDrivers()); echo PHP_EOL;'
"$RUNTIME" -r 'var_dump(defined("SWOOLE_HOOK_PDO_ODBC"));'
"$RUNTIME" --ri swoole | grep 'coroutine_odbc => enabled'

odbcinst -j
odbcinst -q -d
odbcinst -q -s
```

预检通过只证明运行时和配置可见。目标数据库至少还要在隔离验收环境验证：

- 实际服务器身份，防止 DSN 指向错误实例。
- 中文、Unicode、`DECIMAL`、日期和时间字段。
- 位置参数绑定、空值和大字段。
- 提交、回滚、超时和错误传播。
- 连接池回收、断线恢复和多个协程并发连接。
- 业务查询、分页、DDL、迁移、索引和标识符大小写。

公共 CI 的 SQLite ODBC 测试只证明 PDO/unixODBC/Swoole 协程链路，不证明其它厂商数据库现场兼容。真实数据库验收结果也只对当次操作系统、CPU 架构、驱动版本、数据库版本和配置组合有效。

## 9. 常见故障

| 现象 | 检查方向 |
|------|----------|
| `libodbc.so.2: cannot open shared object file` | unixODBC 未安装，或动态库缓存不可见 |
| `Data source name not found` | DSN 拼写、配置文件位置、服务用户或容器内配置不同 |
| `Can't open lib ...` | 驱动路径错误、权限不足、架构不一致或驱动依赖缺失 |
| `wrong ELF class` / `Exec format error` | x86_64 与 ARM64 文件混用 |
| `GLIBC_x.y not found` | Release 或驱动的 ABI 高于目标系统；在兼容基线重建或换用匹配驱动 |
| TLS/证书失败 | CA、主机名、协议版本或厂商驱动加密参数不匹配 |
| 中文乱码或截断 | 数据库、驱动、客户端和字段字符集/长度需要联合验收 |
| SQL 语法或类型错误 | ODBC 不转换 SQL 方言；调整 ORM 方言、迁移和业务 SQL |
| 协程并发异常 | 确认 hook 在建连前启用，并检查连接池是否错误共享同一 PDO 连接 |
