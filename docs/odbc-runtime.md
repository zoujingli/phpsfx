# ODBC 环境与常见数据库接入

本文说明 `phpsfx` 通用 ODBC 运行时的选择、安装、配置、开发和验收方法，覆盖常见国际数据库以及达梦、人大金仓、openGauss/GaussDB、OceanBase、GBase、神通、瀚高、Vastbase、TiDB、GoldenDB 等国产数据库接入路线。

适用 Release 文件：

- `swoole-cli-php8.4-linux-x64-odbc`
- `swoole-cli-php8.4-linux-a64-odbc`
- `swoole-cli-php8.4-macos-x64-odbc`
- `swoole-cli-php8.4-macos-a64-odbc`

不使用 ODBC 时请选择不带 `-odbc` 的默认产物。默认产物仍包含 `pdo_mysql`、`pdo_sqlite` 和 `sqlite3`，进程启动不依赖 unixODBC。

## 1. 能力与责任边界

`-odbc` 产物保证：

- `PDO::getAvailableDrivers()` 包含 `odbc`。
- `SWOOLE_HOOK_PDO_ODBC` 已定义并包含在 `SWOOLE_HOOK_ALL` 中。
- `php --ri swoole` 显示 `coroutine_odbc => enabled`。
- Linux 动态依赖中存在 `libodbc.so.2`。
- macOS 动态依赖中存在 `libodbc.2.dylib`。

Release 不包含：

- unixODBC Driver Manager、配置工具或 SQLite ODBC 测试驱动。
- 任何数据库厂商客户端、ODBC 驱动、许可证或证书。
- `odbcinst.ini`、`odbc.ini`、DSN、账号、密码或业务配置。
- SQL 方言、DDL、分页、迁移、字段类型、标识符大小写或字符集兼容层。

依赖分为三层：

| 层级 | 何时需要 | 由谁提供 |
|------|----------|----------|
| phpsfx ODBC 运行时 | 使用 `-odbc` 产物时 | 本项目 Release |
| unixODBC Driver Manager | `-odbc` 进程启动时 | 部署系统或 Homebrew |
| 数据库厂商 ODBC 驱动 | 实际连接对应数据库时 | 数据库厂商或操作系统仓库 |

因此，厂商驱动是按数据库可选的，但 unixODBC 对 `-odbc` 产物不是延迟依赖。只使用 MySQL/SQLite 且不希望安装 unixODBC 时，应下载默认产物。

## 2. 选择平台和架构

运行时、unixODBC、厂商驱动及其客户端依赖必须属于同一操作系统和 CPU 架构：

| 目标环境 | Release 平台 | Driver Manager 动态库 | 厂商驱动格式 |
|----------|--------------|------------------------|--------------|
| Linux x86_64 | `linux-x64-odbc` | `libodbc.so.2` | x86_64 ELF `.so` |
| Linux ARM64 | `linux-a64-odbc` | `libodbc.so.2` | ARM64 ELF `.so` |
| macOS Intel | `macos-x64-odbc` | `libodbc.2.dylib` | Intel Mach-O `.dylib` |
| macOS Apple Silicon | `macos-a64-odbc` | `libodbc.2.dylib` | ARM64 Mach-O `.dylib` |

Linux 厂商驱动不能复制到 macOS 使用，x86_64 驱动也不能由 ARM64 进程直接加载。macOS 运行时具备 ODBC 能力，不代表每个数据库厂商都提供 macOS 驱动；没有对应平台的厂商驱动就不能在该平台连接该数据库。

## 3. 安装 unixODBC

### Debian / Ubuntu

部署机：

```bash
sudo apt-get update
sudo apt-get install -y unixodbc
```

源码构建机再安装：

```bash
sudo apt-get install -y unixodbc-dev
```

### RHEL / Rocky Linux / 麒麟常见仓库

部署机：

```bash
sudo dnf install -y unixODBC
```

源码构建机再安装：

```bash
sudo dnf install -y unixODBC-devel
```

部分发行版使用 `yum`，具体包名以目标系统仓库为准。

### macOS

```bash
brew install unixodbc
```

公共 SQLite ODBC 链路测试还需要：

```bash
brew install sqliteodbc
```

确认 Homebrew 前缀和动态库：

```bash
ODBC_PREFIX=$(brew --prefix unixodbc)
test -f "$ODBC_PREFIX/include/sql.h"
ls -l "$ODBC_PREFIX/lib/libodbc.2.dylib"
```

## 4. 配置文件位置

先以实际应用用户执行：

```bash
odbcinst -j
```

常见位置：

| 环境 | 驱动注册 | 系统 DSN |
|------|----------|----------|
| Linux | `/etc/odbcinst.ini` | `/etc/odbc.ini` |
| Homebrew Apple Silicon | `/opt/homebrew/etc/odbcinst.ini` | `/opt/homebrew/etc/odbc.ini` |
| Homebrew Intel | `/usr/local/etc/odbcinst.ini` | `/usr/local/etc/odbc.ini` |

不要根据表格硬编码路径，`odbcinst -j` 的当前输出才是准确信息。systemd、launchd、容器和交互式 Shell 可能使用不同用户或配置目录。

注册后检查：

```bash
odbcinst -q -d
odbcinst -q -s
odbcinst -q -d -n '驱动节名'
odbcinst -q -s -n 'DSN 节名'
```

## 5. 安装和检查厂商驱动

只从数据库厂商官方渠道、获授权的软件仓库或操作系统仓库安装驱动。不要把厂商驱动、客户端许可证、内部镜像或账号配置复制进 phpsfx Release。

Linux 检查：

```bash
file /absolute/path/to/vendor-driver.so
ldd /absolute/path/to/vendor-driver.so
```

macOS 检查：

```bash
file /absolute/path/to/vendor-driver.dylib
otool -L /absolute/path/to/vendor-driver.dylib
codesign -dv /absolute/path/to/vendor-driver.dylib 2>&1 || true
```

通过标准：

- 文件平台和 CPU 架构与运行时一致。
- 动态依赖中没有 `not found`。
- 服务用户能够读取驱动、客户端目录、配置和证书。
- 驱动版本与数据库服务端、操作系统版本和授权范围匹配。
- macOS 驱动满足目标机器的签名、公证和安全策略。

## 6. 注册驱动和 DSN

`odbcinst.ini` 注册驱动名称和动态库路径：

```ini
[VENDOR ODBC DRIVER]
Description=Vendor supplied ODBC driver
Driver=/absolute/path/to/vendor-driver
```

`odbc.ini` 使用已注册名称定义数据源：

```ini
[app-prod]
Driver=VENDOR ODBC DRIVER
SERVER=db.example.internal
PORT=PORT_FROM_DBA
DATABASE=app
```

上例中的 `Driver`、`SERVER`、`PORT`、`DATABASE` 只是结构示例。不同驱动可能使用 `Servername`、`Host`、`TCP_PORT`、`DBQ`、`ServiceName` 等不同关键字，必须以目标驱动版本的官方文档为准。

PDO 使用命名 DSN：

```text
odbc:<odbc.ini 节名>
```

例如 `odbc:app-prod`。不要在 `odbc.ini` 或 DSN 中保存账号、密码和业务密钥。

## 7. 数据库接入路线总表

下表用于选择接入路线，不是对厂商驱动存在、免费授权或现场兼容的承诺。

| 数据库 | 优先接入路线 | ODBC 驱动来源 | 关键确认项 |
|--------|--------------|---------------|------------|
| MySQL / MariaDB | 优先内置 `pdo_mysql`；需要统一 ODBC 时再使用 Connector/ODBC | MySQL 或 MariaDB 官方 | TLS、字符集、认证插件 |
| SQLite | 优先内置 `pdo_sqlite`/`sqlite3`；ODBC 主要用于链路测试 | 系统仓库或 Homebrew `sqliteodbc` | 文件与目录写权限、WAL |
| PostgreSQL | psqlODBC | PostgreSQL 社区或系统仓库 | TLS、Unicode 驱动、时区 |
| Microsoft SQL Server | Microsoft ODBC Driver 18 | 微软官方 | TLS CA、加密、认证方式 |
| Oracle Database | Oracle Instant Client Basic + ODBC | Oracle 官方 | 客户端版本、服务名、Wallet/TNS |
| IBM Db2 | IBM Data Server Driver for ODBC and CLI | IBM 官方 | 许可证、catalog、代码页 |
| ClickHouse | ClickHouse ODBC | ClickHouse 官方或认证发行渠道 | HTTP/native 模式、TLS、类型映射 |
| 达梦 DM8 | 达梦官方 ODBC | 达梦官方客户端 | 架构、字符集、`libdodbc` 依赖 |
| 人大金仓 KingbaseES | KingbaseES 官方 ODBC；经厂商确认后也可评估兼容驱动 | 人大金仓官方 | 产品版本、端口、大小写、Oracle/PG 模式 |
| openGauss | 官方/认证 ODBC 或经兼容认证的 psqlODBC | openGauss 发行渠道或厂商 | 驱动认证、SSL、兼容模式 |
| GaussDB | 对应 GaussDB 产品形态的官方驱动 | 华为云或产品交付渠道 | 产品形态不能仅按 openGauss 推断 |
| OceanBase | MySQL 模式优先 `pdo_mysql`；ODBC 需使用厂商认可路线 | OceanBase 或兼容驱动厂商 | 租户名、兼容模式、连接串格式 |
| GBase 8a / 8s | 对应产品官方 ODBC | 南大通用官方 | 8a 与 8s 驱动不可混用、字符集 |
| 神通数据库 | 神通官方 ODBC | 神通官方 | 驱动版本、服务名、字符集 |
| 瀚高 HighGo | 官方 ODBC 或厂商认证的 PostgreSQL 路线 | 瀚高官方 | 安全版差异、SSL、兼容认证 |
| Vastbase | 官方 ODBC 或厂商认证的 PostgreSQL 路线 | 海量数据官方 | 产品版本、兼容模式、SSL |
| TiDB | 优先 `pdo_mysql`；ODBC 使用经验证的 MySQL Connector/ODBC | MySQL/MariaDB 驱动渠道 | TiDB 版本、MySQL 兼容差异 |
| GoldenDB | 优先产品官方建议；MySQL 兼容路线必须经厂商确认 | GoldenDB 交付渠道 | 分布式事务、路由、兼容模式 |

## 8. 常见国际数据库配置

### MySQL / MariaDB

优先使用默认产物中的 `pdo_mysql`。ODBC 配置示例：

```ini
[MySQL Unicode]
Description=MySQL Connector ODBC Unicode driver
Driver=/absolute/path/to/libmyodbc-unicode

[mysql-prod]
Driver=MySQL Unicode
SERVER=db.example.internal
PORT=3306
DATABASE=app
```

PDO DSN 为 `odbc:mysql-prod`。驱动文件名随操作系统和版本变化，应从实际安装清单获取。

### SQLite

Debian/Ubuntu：

```bash
sudo apt-get install -y libsqliteodbc
```

macOS：

```bash
brew install sqliteodbc
```

安装包通常会注册 `SQLite3` 驱动：

```ini
[sqlite-local]
Driver=SQLite3
Database=/var/lib/app/app.sqlite
```

PDO DSN 为 `odbc:sqlite-local`。需要写入时，服务用户必须能在数据库所在目录创建日志或 WAL 文件。

### PostgreSQL

```ini
[postgres-prod]
Driver=PostgreSQL Unicode
Servername=db.example.internal
Port=5432
Database=app
SSLmode=verify-full
```

PDO DSN 为 `odbc:postgres-prod`。驱动名称以 `odbcinst -q -d` 为准。

### Microsoft SQL Server

```ini
[sqlserver-prod]
Driver=ODBC Driver 18 for SQL Server
Server=tcp:db.example.internal,1433
Database=app
Encrypt=yes
TrustServerCertificate=no
```

PDO DSN 为 `odbc:sqlserver-prod`。生产环境应部署可信 CA，不要长期使用 `TrustServerCertificate=yes` 绕过证书校验。

### Oracle Database

```ini
[Oracle Instant Client ODBC]
Description=Oracle Instant Client ODBC driver
Driver=/absolute/path/to/libsqora

[oracle-prod]
Driver=Oracle Instant Client ODBC
DBQ=//db.example.internal:1521/APP_SERVICE
```

PDO DSN 为 `odbc:oracle-prod`。使用 `tnsnames.ora` 或 Wallet 时，还需为服务进程设置 `TNS_ADMIN`。

### IBM Db2

Db2 CLI/ODBC 的驱动注册、许可证和 catalog 方式随客户端包变化。建议先使用厂商工具验证连接，再注册 unixODBC DSN：

```ini
[db2-prod]
Driver=IBM DB2 ODBC DRIVER
Database=APPDB
Hostname=db.example.internal
Port=50000
Protocol=TCPIP
```

PDO DSN 为 `odbc:db2-prod`。节名和关键字必须以当前 Db2 驱动文档为准。

## 9. 国产数据库配置

### 达梦 DM8

```ini
[DM8 ODBC DRIVER]
Description=Dameng DM8 Official ODBC Driver
Driver=/opt/dmdbms/bin/libdodbc.so
Threading=0

[dm-prod]
Driver=DM8 ODBC DRIVER
SERVER=10.0.0.10
TCP_PORT=5236
```

PDO DSN 为 `odbc:dm-prod`。Linux 客户端通常还需要 `DM_HOME` 和客户端动态库路径。完整的真实达梦读写、事务和并发验收见 [达梦 ODBC 环境与真实验收](dameng-odbc-runtime.md)。macOS 必须先确认达梦是否为目标版本提供同架构官方驱动，不能使用 Linux `libdodbc.so`。

### 人大金仓 KingbaseES

优先安装与 KingbaseES 产品版本和兼容模式对应的官方 ODBC 包。注册时不要猜测驱动文件名：

```ini
[KingbaseES ODBC DRIVER]
Description=KingbaseES vendor ODBC driver
Driver=/absolute/path/from-kingbase-installation

[kingbase-prod]
Driver=KingbaseES ODBC DRIVER
Servername=db.example.internal
Port=PORT_FROM_DBA
Database=app
```

PDO DSN 为 `odbc:kingbase-prod`。必须验收 Oracle/PG 兼容模式、标识符大小写、序列、分页和时间类型；不能仅凭 PostgreSQL 协议兼容就认定 psqlODBC 可用于生产。

### openGauss / GaussDB

openGauss 可评估官方或发行渠道提供的 ODBC，也可在厂商明确认证时使用 psqlODBC。GaussDB 包含不同产品形态，驱动和连接方式必须以购买或云服务文档为准，不能直接套用 openGauss 配置。

```ini
[opengauss-prod]
Driver=REGISTERED OPENGAUSS ODBC DRIVER
Servername=db.example.internal
Port=PORT_FROM_DBA
Database=app
SSLmode=verify-full
```

PDO DSN 为 `odbc:opengauss-prod`。重点验收认证算法、SSL、字符集、分布式事务和 PostgreSQL 方言差异。

### OceanBase

OceanBase MySQL 模式优先使用 `pdo_mysql`。只有统一 ODBC 接口或项目认证需要时，才使用 OceanBase 官方认可的 ODBC 路线。租户名可能属于账号或连接属性的一部分，必须按目标版本文档配置，不能将密码或完整账号写入 DSN。

```ini
[oceanbase-prod]
Driver=REGISTERED OCEANBASE OR COMPATIBLE ODBC DRIVER
SERVER=db.example.internal
PORT=2881
DATABASE=app
```

PDO DSN 为 `odbc:oceanbase-prod`。MySQL 模式与 Oracle 模式需要分别验收，不可共用一套 SQL 兼容结论。

### GBase 8a / GBase 8s

GBase 8a 和 GBase 8s 是不同产品，必须安装各自版本的官方 ODBC 驱动，不能混用动态库或配置模板：

```ini
[gbase-prod]
Driver=REGISTERED GBASE PRODUCT ODBC DRIVER
SERVER=db.example.internal
PORT=PORT_FROM_DBA
DATABASE=app
```

PDO DSN 为 `odbc:gbase-prod`。重点验收集群路由、字符集、批量写入、事务行为和日期数值类型。

### 神通数据库

安装与神通数据库服务端版本、操作系统和架构匹配的官方 ODBC 驱动：

```ini
[shentong-prod]
Driver=REGISTERED SHENTONG ODBC DRIVER
SERVER=db.example.internal
PORT=PORT_FROM_DBA
DATABASE=app
```

PDO DSN 为 `odbc:shentong-prod`。驱动节名、服务名和连接关键字以交付文档为准。

### 瀚高 HighGo / Vastbase

两者均可能提供官方 ODBC 或经厂商认证的 PostgreSQL 兼容路线，但不能只根据协议兼容自行替换驱动：

```ini
[domestic-pg-prod]
Driver=REGISTERED VENDOR ODBC DRIVER
Servername=db.example.internal
Port=PORT_FROM_DBA
Database=app
SSLmode=verify-full
```

分别为瀚高和 Vastbase 创建独立驱动名和 DSN。重点验收安全版认证、密码策略、SSL、扩展类型、分页和序列。

### TiDB / GoldenDB

TiDB 通常优先使用 `pdo_mysql`。需要 ODBC 时，可在目标版本兼容认证范围内评估 MySQL/MariaDB Connector/ODBC。GoldenDB 应优先采用厂商交付的连接建议；即使支持 MySQL 协议，也必须确认分布式事务、路由和故障切换语义。

```ini
[mysql-compatible-prod]
Driver=REGISTERED MYSQL COMPATIBLE ODBC DRIVER
SERVER=db.example.internal
PORT=PORT_FROM_DBA
DATABASE=app
```

为每种产品建立独立 DSN，不要让一个名称在不同环境指向不同厂商数据库。

## 10. PHP / Hyperf 接口

推荐环境变量：

```text
APP_ODBC_DSN=odbc:app-prod
APP_ODBC_USER=<由密钥系统注入>
APP_ODBC_PASSWORD=<由密钥系统注入>
```

在创建协程和连接池前启用 hook：

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

不要在多个并发协程之间同时操作同一个 PDO 对象。连接池中的每个连接应由同一套工厂配置创建，并设置明确的获取、连接、查询和事务超时。

不要把真实凭据写入仓库、Release、镜像 Dockerfile、`odbc.ini`、systemd/launchd 配置或普通日志。错误日志应对 DSN、用户名、密码和驱动返回的完整连接串脱敏。

## 11. 服务和容器环境

systemd 可以保存非敏感 DSN 名和客户端路径，账号密码继续通过凭据机制注入：

```ini
[Service]
Environment=APP_ODBC_DSN=odbc:app-prod
Environment=LD_LIBRARY_PATH=/opt/vendor/client/lib
ExecStart=/opt/app/app --self
```

macOS launchd 不会自动继承交互式 Shell 的 Homebrew 路径和环境变量，应在服务配置中提供所需路径。容器镜像必须显式安装 unixODBC 和获准分发的厂商驱动；主机安装的驱动不会自动出现在容器内。

## 12. 部署预检

通用能力：

```bash
RUNTIME=/opt/phpsfx/swoole-cli-odbc

test -x "$RUNTIME"
"$RUNTIME" -r 'var_export(PDO::getAvailableDrivers()); echo PHP_EOL;'
"$RUNTIME" -r 'var_dump(defined("SWOOLE_HOOK_PDO_ODBC"));'
"$RUNTIME" --ri swoole | grep 'coroutine_odbc => enabled'

odbcinst -j
odbcinst -q -d
odbcinst -q -s
```

Linux 动态依赖：

```bash
ldd "$RUNTIME"
readelf -d "$RUNTIME" | grep 'libodbc\.so\.2'
```

macOS 动态依赖：

```bash
otool -L "$RUNTIME" | grep 'libodbc\.2\.dylib'
```

预检通过只证明运行时和配置可见。每种真实数据库至少还要在隔离验收环境验证：

- 服务器身份和数据库版本，防止 DSN 指向错误实例。
- 中文/Unicode、空值、`DECIMAL`、日期时间、大字段和二进制字段。
- 参数绑定、批量执行、受影响行数和主键返回。
- 提交、回滚、隔离级别、死锁、超时和错误传播。
- 连接池回收、断线恢复、多个协程并发连接和资源上限。
- 业务查询、分页、DDL、迁移、索引、序列及标识符大小写。

公共 CI 的 SQLite ODBC 测试只证明 PDO/unixODBC/Swoole 协程链路，不证明任何其它厂商数据库现场兼容。真实数据库结果也只对当次操作系统、架构、驱动版本、数据库版本和配置组合有效。

## 13. 常见故障

| 现象 | 检查方向 |
|------|----------|
| `libodbc.so.2` / `libodbc.2.dylib` 无法加载 | 下载了 `-odbc` 产物但未安装 unixODBC，或动态库路径不可见 |
| `Data source name not found` | DSN 拼写、配置文件位置、服务用户或容器配置不同 |
| `Can't open lib ...` | 驱动路径错误、权限不足、架构不一致或驱动依赖缺失 |
| `wrong ELF class` / `Exec format error` | 操作系统或 x86_64/ARM64 文件混用 |
| macOS 拒绝加载驱动 | 驱动签名、公证、隔离属性或安全策略不满足 |
| `GLIBC_x.y not found` | Release 或驱动 ABI 高于 Linux 目标系统 |
| TLS/证书失败 | CA、主机名、协议版本或厂商加密参数不匹配 |
| 中文乱码或截断 | 数据库、驱动、客户端和字段字符集/长度需联合验收 |
| SQL 语法或类型错误 | ODBC 不转换 SQL 方言；调整 ORM 方言、迁移和业务 SQL |
| 协程并发异常 | 确认 hook 在建连前启用，并检查连接池是否共享同一 PDO 对象 |
