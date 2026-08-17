# 达梦 ODBC 环境与真实验收

本文说明如何使用 `phpsfx` Linux 标准 ODBC 运行时连接和验收达梦数据库。适用于：

- `swoole-cli-php8.4-linux-x64`
- `swoole-cli-php8.4-linux-a64`

运行时只提供 PHP PDO ODBC 和 Swoole 协程 ODBC 能力。它不包含达梦客户端、许可证、数据库配置、DSN、账号或密码，也不证明智慧厨房业务 SQL、分页、迁移和 MySQL 方言已经兼容达梦。unixODBC 基础环境和其它厂商配置见 [Linux ODBC 环境与常见数据库配置](odbc-runtime.md)。

首次部署按以下顺序执行：

1. 确认部署机架构和 glibc 版本。
2. 安装 unixODBC 运行库和预检工具。
3. 从 Release 下载对应 Linux 标准产物，或在同架构 Linux 主机源码构建。
4. 单独安装同架构的达梦官方客户端。
5. 注册达梦 ODBC 驱动和命名 DSN，并向服务进程注入环境变量。
6. 完成运行时预检，再执行真实达梦只读和写入验收。

## 1. 环境分层

| 环境 | 必需内容 | 用途 |
|------|----------|------|
| 构建机 | Linux、编译工具链、`unixODBC` 开发包 | 从源码生成标准 ODBC 运行时 |
| 部署机 | Linux 标准运行时、`libodbc.so.2`、同架构达梦官方客户端、ODBC 配置 | 运行应用 |
| 验收环境 | 部署机全部内容、可访问的达梦实例、隔离验收账号 | 执行真实连接测试 |

Linux x86_64、ARM64 标准产物需要 unixODBC；macOS x86_64、ARM64 产物当前不包含 ODBC。

## 2. 选择正确架构

先在目标机确认架构：

```bash
uname -m
```

| `uname -m` 结果 | 运行时 | 达梦客户端要求 |
|-----------------|--------|----------------|
| `x86_64` | `linux-x64` | Linux x86_64 官方客户端 |
| `aarch64` 或 `arm64` | `linux-a64` | Linux ARM64 官方客户端 |

运行时、unixODBC 和 `libdodbc.so` 必须是同一架构。macOS 产物仍可用于不依赖 ODBC 的应用，但当前不承诺达梦 ODBC 能力。

当前 GitHub Actions Linux 构建基线是 Ubuntu 24.04。Linux 标准产物为了动态加载 unixODBC，不是全静态 ELF，因此还会依赖构建基线的 glibc、libstdc++ 和 libgcc ABI。达梦客户端安装包标注“麒麟 10”不代表本项目的 Ubuntu 24.04 产物一定能在麒麟 10 上运行。

部署前必须执行：

```bash
getconf GNU_LIBC_VERSION
file ./swoole-cli-php8.4-linux-a64
ldd ./swoole-cli-php8.4-linux-a64
```

如果出现 `GLIBC_x.y not found`，应在与目标系统 ABI 兼容的构建环境重新源码构建，不要通过替换系统 glibc 处理。

## 3. 安装系统依赖

### Debian / Ubuntu

部署机：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl file unixodbc binutils netcat-openbsd
```

其中 `binutils` 提供 `readelf`，`netcat-openbsd` 提供后续网络预检使用的 `nc`。

在已经具备本项目 Linux 构建工具链的主机上，额外安装 ODBC 开发头文件：

```bash
sudo apt-get install -y unixodbc-dev
```

全新 Ubuntu 构建机还必须安装 PHP 8.4 CLI、Composer 2，以及 `.github/workflows/release.yml` 中列出的编译工具链。仅安装 `unixodbc-dev` 不能完成源码构建。

### RHEL / Rocky Linux / 麒麟常见仓库

部署机：

```bash
sudo dnf install unixODBC binutils nmap-ncat file curl
```

在已有项目构建工具链的构建机上额外安装：

```bash
sudo dnf install unixODBC-devel
```

部分麒麟版本使用 `yum`，且 `nmap-ncat` 等软件包名称可能不同，以目标系统启用的仓库为准。`libsqliteodbc` 只用于公共 CI 的 SQLite ODBC 链路测试，生产连接达梦不需要安装它。

安装后必须确认 unixODBC 动态库和配置工具实际可用：

```bash
ldconfig -p | grep 'libodbc\.so\.2'
odbcinst -j
```

## 4. 从源码构建标准 ODBC 运行时

源码构建必须在与目标产物相同架构的 Linux 主机上原生执行；当前脚本不提供 x86_64 与 ARM64 之间的交叉编译。先在仓库根目录确认环境：

```bash
uname -m
php -v
composer --version
command -v git make tar readelf
test -f scripts/profiles/hyperfadmin-odbc.env
```

系统 PHP 必须是 8.4，unixODBC 头文件默认必须位于 `/usr/include/sql.h` 和 `/usr/include/sqlext.h`。如果开发包安装在其它前缀，可通过 `PHPSFX_SWOOLE_ODBC_PREFIX` 指定绝对路径。

x86_64 构建机执行：

```bash
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh linux-x64
```

ARM64 构建机执行：

```bash
PHPSFX_PROFILE_FILE=scripts/profiles/hyperfadmin-odbc.env \
  bash scripts/build-swoole-cli.sh linux-a64
```

成功后输出分别为：

```text
dist/swoole-cli-php8.4-linux-x64
dist/build-meta-linux-x64.json

dist/swoole-cli-php8.4-linux-a64
dist/build-meta-linux-a64.json
```

构建脚本会执行运行时能力校验，并要求元数据中的 `swoole_odbc` 为 `true`、`odbc_dynamic_dependency` 为 `libodbc.so.2`。构建过程中使用 `.build/swoole-cli` 工作目录；可用 `PHPSFX_DIST_DIR` 修改输出目录，但不要在 x86_64 和 ARM64 之间复用构建工作目录。

## 5. 安装达梦官方客户端

按达梦官方文档安装与目标机架构一致的客户端，并记录安装目录。下文统一使用：

```bash
export DM_HOME=/opt/dmdbms
```

实际目录可以不同，但必须能找到：

```text
$DM_HOME/bin/libdodbc.so
```

先检查官方驱动本身：

```bash
file "$DM_HOME/bin/libdodbc.so"
LD_LIBRARY_PATH="$DM_HOME/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  ldd "$DM_HOME/bin/libdodbc.so"
```

输出中不能有 `not found`，架构必须与运行时一致。运行应用的服务进程还必须能够读取达梦客户端目录。

达梦客户端及其许可证受达梦授权约束。不要把客户端文件复制进本项目 Release，也不要把内部授权镜像公开发布。

## 6. 下载和校验 Release 运行时

下载脚本的第三个参数是最终输出文件名。为了能直接使用 Release 的 `SHA256SUMS`，必须先保留 Release 原文件名完成校验，再安装为服务使用的短文件名。

以下示例用于 ARM64；x86_64 只需把前两行的平台和文件名改为 `linux-x64` 和 `swoole-cli-php8.4-linux-x64`：

```bash
PHPSFX_RELEASE_PLATFORM=linux-a64
PHPSFX_RELEASE_ASSET=swoole-cli-php8.4-linux-a64
PHPSFX_RELEASE_STAGE=$(mktemp -d)

bash scripts/download-release-asset.sh \
  "$PHPSFX_RELEASE_PLATFORM" latest \
  "$PHPSFX_RELEASE_STAGE/$PHPSFX_RELEASE_ASSET"

curl -fL --retry 3 \
  -o "$PHPSFX_RELEASE_STAGE/SHA256SUMS" \
  https://github.com/zoujingli/phpsfx/releases/latest/download/SHA256SUMS

(
  cd "$PHPSFX_RELEASE_STAGE"
  grep -F "  $PHPSFX_RELEASE_ASSET" SHA256SUMS \
    > "$PHPSFX_RELEASE_ASSET.sha256"
  test -s "$PHPSFX_RELEASE_ASSET.sha256"
  sha256sum --check --strict "$PHPSFX_RELEASE_ASSET.sha256"
)

sudo install -d -m 0755 /opt/phpsfx
sudo install -m 0755 \
  "$PHPSFX_RELEASE_STAGE/$PHPSFX_RELEASE_ASSET" \
  /opt/phpsfx/swoole-cli
```

校验必须输出 `<Release 原文件名>: OK` 后才能安装。固定版本部署时，把下载脚本的 `latest` 改为标签（例如 `v0.1.0`），同时把 `SHA256SUMS` URL 改为 `/releases/download/v0.1.0/SHA256SUMS`，两者必须来自同一 Release。

## 7. 配置 unixODBC

先用 `odbcinst -j` 确认当前服务用户读取的配置位置。常见系统级位置是：

```text
/etc/odbcinst.ini
/etc/odbc.ini
```

### 注册达梦驱动

在 `odbcinst.ini` 中添加驱动。路径必须使用目标机的真实绝对路径：

```ini
[DM8 ODBC DRIVER]
Description=Dameng DM8 Official ODBC Driver
Driver=/opt/dmdbms/bin/libdodbc.so
Threading=0
```

### 配置命名 DSN

在 `odbc.ini` 中添加数据源：

```ini
[dm-prod]
Description=Dameng production database
Driver=DM8 ODBC DRIVER
SERVER=10.0.0.10
TCP_PORT=5236
```

要求：

- `Driver` 必须与 `odbcinst.ini` 的节名完全一致。
- `SERVER` 和 `TCP_PORT` 由达梦管理员提供。
- 不要在 `odbc.ini` 中写用户名、密码或业务密钥。
- systemd、容器和交互式 Shell 可能使用不同用户，必须以实际服务用户执行 `odbcinst -j`、`odbcinst -q -d` 和 `odbcinst -q -s`。

验证配置是否可见：

```bash
odbcinst -q -d
odbcinst -q -s
```

## 8. 配置进程环境

达梦官方 ODBC 驱动还会加载同目录下的客户端动态库。应用进程至少需要：

```bash
export DM_HOME=/opt/dmdbms
export LD_LIBRARY_PATH="$DM_HOME/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DM_ODBC_DSN='odbc:dm-prod'
```

应用账号和密码必须由部署平台的密钥管理能力注入：

```text
DM_ODBC_USER
DM_ODBC_PASSWORD
```

不要把真实值写入仓库、Release、镜像 Dockerfile、systemd unit、`odbc.ini` 或普通日志。排查问题时不要启用会输出环境变量的 `set -x`。

systemd 服务至少要为进程提供以下非敏感环境；账号和密码继续通过部署平台的凭据机制注入：

```ini
[Service]
Environment=DM_HOME=/opt/dmdbms
Environment=LD_LIBRARY_PATH=/opt/dmdbms/bin
Environment=DM_ODBC_DSN=odbc:dm-prod
ExecStart=/opt/app/app --self
```

修改 unit 后执行 `systemctl daemon-reload` 并重启服务。不要只在管理员 Shell 中设置环境变量，因为 systemd 服务不会自动继承该 Shell 的环境。

## 9. 部署前预检

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
```

通过标准：

- `ldd` 没有 `not found`。
- `PDO::getAvailableDrivers()` 包含 `odbc`。
- `SWOOLE_HOOK_PDO_ODBC` 为 `true`。
- `coroutine_odbc => enabled`。

数据库网络也必须从应用所在主机或容器连通：

```bash
nc -vz 10.0.0.10 5236
```

网络探测成功只证明 TCP 可达，不证明账号、权限、字符集或 SQL 兼容。

## 10. PHP / Hyperf 连接方式

在创建协程和数据库连接前启用 ODBC hook：

```php
<?php

Swoole\Runtime::enableCoroutine(
    Swoole\Runtime::getHookFlags() | SWOOLE_HOOK_PDO_ODBC
);

$dsn = getenv('DM_ODBC_DSN');
$user = getenv('DM_ODBC_USER');
$password = getenv('DM_ODBC_PASSWORD');

if ($dsn === false || $dsn === '' || $user === false || $password === false) {
    throw new RuntimeException('Dameng ODBC environment is incomplete');
}

$pdo = new PDO(
    $dsn,
    $user,
    $password,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
```

DSN 必须是 `odbc:<odbc.ini 节名>`，例如 `odbc:dm-prod`，不要把密码拼进 DSN。连接池中的每个连接都应由同一套环境配置创建。

本项目只提供运行时能力。接入 HyperfAdmin 时还需要单独处理数据库连接工厂、连接池、达梦 SQL 方言、分页、标识符大小写、migration、索引和字段类型兼容。

## 11. 真实达梦验收

公共 CI 使用 SQLite ODBC 驱动验证 PDO、事务和 Hyperf 协程链路，只能证明 Linux 标准运行时的 ODBC 能力。下面的脚本连接实际达梦实例后，才能形成该架构、该版达梦客户端和该数据库环境的真实验收证据；结果不能自动外推到另一种 CPU 架构或其它客户环境。

验收脚本使用以下专用变量，与业务应用的 `DM_ODBC_*` 变量分开：

| 变量 | 必需 | 说明 |
|------|------|------|
| `PHPSFX_DM_ODBC_DSN` | 是 | 例如 `odbc:dm-prod` |
| `PHPSFX_DM_ODBC_USER` | 是 | 验收账号，可为空但必须设置 |
| `PHPSFX_DM_ODBC_PASSWORD` | 是 | 验收密码，可为空但必须设置 |
| `PHPSFX_DM_ODBC_ALLOW_WRITE` | 否 | 默认 `0`；设置 `1` 才执行写入验收 |

可以由部署系统把业务连接变量映射给验收脚本：

```bash
export PHPSFX_DM_ODBC_DSN="$DM_ODBC_DSN"
export PHPSFX_DM_ODBC_USER="$DM_ODBC_USER"
export PHPSFX_DM_ODBC_PASSWORD="$DM_ODBC_PASSWORD"

bash scripts/test-dameng-odbc.sh /opt/phpsfx/swoole-cli
```

默认只读验收检查：

- PDO ODBC 驱动可用。
- Swoole ODBC 协程 hook 可用。
- `SELECT 1` 成功。
- 达梦专属 `ID_CODE()` 返回有效结果，防止误连到其它 ODBC 数据库。

只有在隔离验收 schema 且账号已获授权时才能运行写入验收：

```bash
export PHPSFX_DM_ODBC_ALLOW_WRITE=1
bash scripts/test-dameng-odbc.sh /opt/phpsfx/swoole-cli
```

写入验收还会检查中文字符串、`DECIMAL`、`TIMESTAMP`、参数绑定、事务提交、事务回滚、SQL 错误传播和两个协程并发连接。脚本创建唯一测试表，并在 `finally` 中按表名精确删除。

生产账号没有 `CREATE TABLE` / `DROP TABLE` 权限时，应保持只读模式，并由数据库管理员在隔离验收账号和 schema 中完成写入验收。不要为了跑测试扩大生产应用账号权限。

## 12. 常见故障

| 现象 | 原因和处理 |
|------|------------|
| `libodbc.so.2: cannot open shared object file` | unixODBC 运行库未安装，或动态库缓存未更新 |
| `Can't open lib ... libdodbc.so` | 驱动路径错误、服务用户无读取权限、`LD_LIBRARY_PATH` 缺失，或客户端依赖有 `not found` |
| `Exec format error` / `wrong ELF class` | x86_64、ARM64 文件混用 |
| `GLIBC_x.y not found` | 目标系统 ABI 低于 Release 构建基线；在兼容环境重建运行时 |
| `Data source name not found` | DSN 名不一致，或服务用户读取了另一套 `odbc.ini`；先运行 `odbcinst -j` |
| 连接超时或拒绝 | 数据库监听、端口、防火墙、容器网络或安全组问题 |
| `SWOOLE_HOOK_PDO_ODBC` 未定义 | 下载了 macOS 或旧版 ODBC-disabled 产物；检查平台和 Release 版本 |
| 中文不一致 | 核对数据库字符集、客户端字符集和字段类型；以真实中文验收结果为准 |
| 写入验收权限错误 | 使用隔离验收账号/schema，或改用默认只读验收，不要扩大生产账号权限 |

## 13. 生产启用检查单

上线前逐项确认：

- 运行时、操作系统、unixODBC 和达梦客户端架构一致。
- `ldd` 对运行时和 `libdodbc.so` 均无 `not found`。
- 目标系统 glibc 满足 Release ABI，或已在兼容环境重新构建。
- 服务用户能读取相同的驱动和 DSN 配置。
- DSN 中没有账号或密码，凭据由密钥管理系统注入。
- 只读真实达梦验收通过。
- 隔离 schema 的写入、事务和并发验收通过。
- 测试表清理完成，日志中没有 DSN、用户名或密码。
- 智慧厨房业务 SQL、迁移、分页和字段类型已另行完成达梦兼容验收。

只有运行时验收通过，不能单独证明完整业务系统已具备达梦生产兼容性。
