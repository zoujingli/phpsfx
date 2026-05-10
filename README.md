# phpsfx

`phpsfx` 是一个面向 PHP 单文件发布的 Swoole CLI 静态运行时构建仓库。它通过 GitHub Actions 自动编译、校验并发布可用于 SFX 打包的 `swoole-cli` 二进制文件，目标是让 PHP 源码入口或可执行 Phar 能与运行时合并为一个可直接分发的二进制程序。

本仓库只维护运行时本身，不绑定具体业务应用；业务项目可以在自己的构建流程中下载指定版本的运行时，再把 `payload.php` 或 `app.phar` 追加进去生成最终程序。

## SFX 打包格式

运行时使用 Swoole CLI 官方 SFX 格式：

```text
swoole-cli + payload.php|app.phar + pack('J', payloadSize)
```

- `swoole-cli`：本仓库发布的静态 PHP 运行时。
- `payload.php`：单文件 PHP 入口，适合脚本、工具或已经自包含的入口文件。
- `app.phar`：可执行 Phar，适合多文件应用和框架项目。
- `pack('J', payloadSize)`：追加在文件末尾的 8 字节 payload 长度，Swoole CLI SFX 入口通过它定位并加载 payload。

执行打包后的程序时需要通过 `--self` 启动内置 payload，例如：

```bash
./app --self
./app --self list
./app --self start
```

## Release 产物

默认发布两个 PHP 版本、两个组件 profile、四个 Linux/macOS 平台，资产命名格式如下：

```text
swoole-cli-php{php_version}-{profile}-{platform}
```

示例：

```text
swoole-cli-php8.4-min-linux-x64
swoole-cli-php8.4-max-linux-x64
swoole-cli-php8.1-min-linux-x64
swoole-cli-php8.1-max-linux-x64
```

同时发布：

- `SHA256SUMS`：所有运行时资产的 SHA-256 校验值。
- `build-meta.json`：构建版本、组件 profile、平台、上游 ref、裁剪开关和构建时间等元数据。

## PHP 与 Swoole CLI 版本

| PHP 版本线 | 默认 Swoole CLI ref | Swoole 源码说明 |
|------------|---------------------|-----------------|
| `8.4.x` | `v6.2.0.0` | 使用上游 ref 内置配置 |
| `8.1.x` | `v6.0.2.0` | 使用 `swoole-src v6.0.2` |

手动运行 workflow 时可以指定单个 PHP 版本并覆盖 `swoole_cli_ref`，用于验证上游新标签或指定提交。

## 组件 profile

### `min`

`min` 是较小的运行时集合，适合只需要 CLI/SFX、Swoole 服务、常见数据库和基础网络能力的应用。包含组件：

```text
bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,mysqlnd,openssl,pcntl,pdo,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib
```

`min` 的依赖裁剪策略：

- Swoole 扩展保留 HTTP/TCP/WebSocket server、coroutine、mysqlnd、curl hook 和 c-ares DNS 能力。
- Swoole 扩展不启用 `pgsql/sqlite/odbc/ssh2/ftp/thread/brotli/zstd` 等可选功能。
- libcurl 保留 HTTP(S)、OpenSSL、zlib、c-ares，不启用 HTTP3、SSH2、IDN、PSL、Brotli、Zstd。
- libzip 保留 Zip + zlib + OpenSSL，不启用 BZip2、LZMA、Zstd。
- zlib 移除上游模板中与 zlib 构建无关的 BZip2 依赖。
- redis 关闭 session 支持，因为该 profile 不包含 PHP `session` 扩展。

### `max`

`max` 使用 Swoole CLI 官方默认组件集合，适合需要更完整扩展覆盖面的场景。包含组件：

```text
opcache,curl,iconv,bz2,bcmath,pcntl,filter,session,tokenizer,mbstring,ctype,zlib,zip,posix,sockets,pdo,sqlite3,phar,mysqlnd,mysqli,intl,fileinfo,pdo_mysql,soap,xsl,gmp,exif,sodium,openssl,readline,xml,gd,redis,swoole,yaml,imagick,mongodb,xlswriter,gettext
```

`max` 不裁剪官方默认扩展和依赖能力。

## 运行时裁剪

所有 profile 默认移除 php-fpm 源码和 `-P` 入口，只保留 CLI/SFX 相关能力。CLI 内置 Web Server 相关代码保留，避免过度修改上游 CLI 入口造成兼容风险。

其他兼容性处理：

- macOS 构建使用 oniguruma 6.9.10 release tarball，以兼容新版 clang。
- 老版本上游引用的 libsodium 下载地址不可用时，构建脚本统一使用 libsodium 1.0.21 release tarball。
- CI 使用 GitHub API tarball 获取 Swoole CLI 源码，避免完整仓库 checkout 在 macOS runner 上长时间卡住；本地仍可用 `PHPSFX_SWOOLE_CLI_CHECKOUT_MODE=git` 选择浅克隆 tag/ref。

## 支持平台

| 系统 | 架构 | platform | Release |
|------|------|----------|---------|
| Linux | x86_64 | `linux-x64` | 是 |
| Linux | ARM64 | `linux-a64` | 是 |
| macOS | x86_64 | `macos-x64` | 是 |
| macOS | ARM64 | `macos-a64` | 是 |

暂不发布 Windows / CygWin 产物。

## 自动发布

GitHub Actions workflow：`.github/workflows/release.yml`。

触发方式：

- 推送 `v*` 标签：构建全部 Linux/macOS、PHP 版本和 profile 组合，并创建 GitHub Release。
- 手动运行 `Release swoole-cli`：可输入 `version`、`php_version`、`profile`、`swoole_cli_ref`、`prepare_flags`。

发版示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

手动运行 workflow 时：

- `php_version=all` 同时构建 PHP 8.1 与 8.4。
- `profile=all` 同时构建 `min/max`。
- 覆盖 `swoole_cli_ref` 时必须选择单个 PHP 版本，避免同一个 ref 同时套用到不同 PHP 版本线。

## 本地 / WSL 构建

Linux x86_64 或 WSL 可直接构建当前平台产物：

```bash
cd /mnt/d/WebRoot/phpsfx

PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PHP_VERSION=8.4 \
PHPSFX_PROFILE=min \
  bash scripts/build-swoole-cli.sh

PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PHP_VERSION=8.1 \
PHPSFX_PROFILE=max \
  bash scripts/build-swoole-cli.sh
```

构建输出位于 `dist/`。

常用环境变量：

| 变量 | 说明 |
|------|------|
| `PHPSFX_PLATFORM` | 目标平台，例如 `linux-x64`。 |
| `PHPSFX_PHP_VERSION` | PHP 版本线，默认 `8.4`。 |
| `PHPSFX_PROFILE` | 组件 profile，默认 `min`。 |
| `PHPSFX_SWOOLE_CLI_REF` | Swoole CLI 分支、标签或提交。 |
| `PHPSFX_SWOOLE_SRC_REF` | 可选 swoole-src ref，主要用于 PHP 8.1 版本线。 |
| `PHPSFX_SWOOLE_CLI_PREPARE_FLAGS` | 传给上游 `prepare.php` 的扩展开关。 |
| `PHPSFX_DISABLE_FPM_RUNTIME` | 是否移除 php-fpm 入口，profile 默认启用。 |
| `PHPSFX_STRIP_BINARY` | 是否 strip 二进制，默认启用。 |

## 运行时校验

构建脚本会直接执行生成的 `swoole-cli` 并校验：

- `PHP_VERSION` 以目标版本前缀开头。
- `PHP_SAPI === "cli"`。
- `SWOOLE_CLI` 常量存在。
- 当前 profile 声明的必需扩展全部已加载。
- 当前 profile 声明的排除扩展没有被打包。
- 二进制文件具备可执行权限。

手动校验已有产物：

```bash
PHPSFX_PROFILE=min \
PHPSFX_EXPECTED_PHP_PREFIX=8.4. \
  bash scripts/validate-swoole-cli.sh dist/swoole-cli-php8.4-min-linux-x64
```

## 下载 Release 运行时

下载最新版本：

```bash
PHPSFX_PHP_VERSION=8.4 PHPSFX_PROFILE=min \
  bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
```

下载指定版本：

```bash
PHPSFX_PHP_VERSION=8.1 PHPSFX_PROFILE=max \
  bash scripts/download-release-asset.sh linux-x64 v0.1.0 /tmp/swoole-cli
```

## PHP 源码打包

单个 PHP 入口文件可直接追加到 `swoole-cli`：

```bash
PHPSFX_PHP_VERSION=8.4 PHPSFX_PROFILE=min bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli

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

多文件应用推荐先生成可执行 Phar，再追加到 `swoole-cli`：

```bash
PHPSFX_PHP_VERSION=8.4 PHPSFX_PROFILE=min bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli

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
- 运行时读取外部配置、日志、上传目录、数据库快照等资源时，应按应用自己的 Phar 运行规则放在二进制同级或指定路径。
- 脚本兼容 `.bin` 这类自定义 Phar 后缀，会先复制为临时 `.phar` 做轻量校验。

## 打包实现自测

对已有 `swoole-cli` 同时测试 PHP 与 Phar 两种 SFX 打包方式：

```bash
bash scripts/test-packaging.sh swoole-cli-php8.4-min-linux-x64
# 或
bash scripts/test-packaging.sh swoole-cli-php8.1-max-linux-x64
```

## 参考

- [swoole/swoole-cli](https://github.com/swoole/swoole-cli)
- [Swoole CLI 构建选项](https://github.com/swoole/swoole-cli/blob/main/docs/options.md)
- [Swoole CLI SFX 打包说明](https://github.com/swoole/swoole-cli/blob/main/sapi/samples/sfx/README.md)
- [Swoole CLI 官方 pack-sfx.php](https://github.com/swoole/swoole-cli/blob/main/sapi/scripts/pack-sfx.php)
