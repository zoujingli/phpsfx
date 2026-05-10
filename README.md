# phpsfx

`phpsfx` 用于自动构建和发布多平台 **Swoole CLI PHP 8.1 / 8.4 静态运行时**。产物用于把 PHP 源码或 Phar 追加进运行时后生成单文件可执行程序。

本分支已从 `micro.sfx` 切换为 `swoole-cli` 机制，核心格式为：

```text
swoole-cli + payload.php|app.phar + pack('J', payloadSize)
```

其中 `pack('J', payloadSize)` 是 Swoole CLI 官方 SFX 读取逻辑需要的 8 字节长度尾部（与官方 `pack-sfx.php` 保持一致）。相比 `micro.sfx`，该方式直接复用 Swoole CLI 的 SFX 读取逻辑。

运行已打包产物时需要传入 `--self`，例如 `./app --self list`。这是 Swoole CLI 官方 SFX 模式的入口开关。

## Release 产物

默认同时发布两个 PHP 版本、三个组件 profile、四个平台。资产命名格式：

```text
swoole-cli-php{php_version}-{profile}-{platform}
```

PHP 版本映射：

| PHP | Swoole CLI ref |
|-----|----------------|
| 8.4.x | `v6.2.0.0` |
| 8.1.x | `v6.0.2.0` |

组件 profile：

| profile | 组件集合 |
|---------|----------|
| `min` | `bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,mysqlnd,openssl,pcntl,pdo,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib` |
| `mid` | `bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,mysqlnd,openssl,pcntl,pdo,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib` |
| `max` | Swoole CLI 官方默认组件：`opcache,curl,iconv,bz2,bcmath,pcntl,filter,session,tokenizer,mbstring,ctype,zlib,zip,posix,sockets,pdo,sqlite3,phar,mysqlnd,mysqli,intl,fileinfo,pdo_mysql,soap,xsl,gmp,exif,sodium,openssl,readline,xml,gd,redis,swoole,yaml,imagick,mongodb,xlswriter,gettext` |

平台：

| 平台 | platform |
|------|----------|
| Linux x86_64 | `linux-x64` |
| Linux ARM64 | `linux-a64` |
| macOS x86_64 | `macos-x64` |
| macOS ARM64 | `macos-a64` |

示例资产：

```text
swoole-cli-php8.4-min-linux-x64
swoole-cli-php8.4-mid-linux-x64
swoole-cli-php8.4-max-linux-x64
swoole-cli-php8.1-min-linux-x64
swoole-cli-php8.1-mid-linux-x64
swoole-cli-php8.1-max-linux-x64
```

同时发布：

- `SHA256SUMS`
- `build-meta.json`

暂不发布 Windows 产物。

## 组件裁剪说明

`min` 额外裁剪：

- Swoole 扩展：不启用 `pgsql/sqlite/odbc/ssh2/ftp/thread/brotli/zstd` 等可选功能。
- libcurl：保留 HTTP(S)、OpenSSL、zlib、c-ares，不启用 HTTP3、SSH2、IDN、PSL、Brotli、Zstd。
- libzip：保留 Zip + zlib + OpenSSL，不启用 BZip2、LZMA、Zstd。
- zlib：移除上游模板中与 zlib 构建无关的 BZip2 依赖。
- redis：关闭 redis session 支持，因为该 profile 不打包 PHP `session` 扩展。

`mid` 额外裁剪：

- Swoole 扩展：不启用 `pgsql/sqlite/odbc/ssh2/ftp/thread/brotli/zstd` 等可选功能。
- redis：关闭 redis session 支持，因为该 profile 不打包 PHP `session` 扩展。
- curl/libzip/zlib 保持上游默认依赖能力。

`max` 不裁剪官方默认组件和依赖能力。

所有 profile 在 macOS 构建时使用 oniguruma 6.9.10 release tarball，以兼容新版 clang。

## 自动发布

GitHub Actions workflow：`.github/workflows/release.yml`。

触发方式：

- 推送 `v*` 标签：自动构建所有 PHP/profile/platform 组合并创建 GitHub Release。
- 手动运行 `Release swoole-cli`：可输入 `version`、`php_version`、`profile`、`swoole_cli_ref`、`prepare_flags`。

示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

默认上游源码：

```text
https://github.com/swoole/swoole-cli.git
```

手动运行 workflow 时：

- `php_version=all` 同时构建 PHP 8.1 与 8.4。
- `profile=all` 同时构建 `min/mid/max`。
- 如需覆盖上游 ref，请选择单个 PHP 版本再填写 `swoole_cli_ref`。

## 本地 / WSL 调试

WSL 或 Linux x86_64 本地只构建当前平台：

```bash
cd /mnt/d/WebRoot/phpsfx

PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PHP_VERSION=8.4 \
PHPSFX_PROFILE=min \
  bash scripts/build-swoole-cli.sh

PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PHP_VERSION=8.1 \
PHPSFX_PROFILE=mid \
  bash scripts/build-swoole-cli.sh
```

构建完成后输出到 `dist/`。

## 运行时校验

构建脚本会直接执行生成的 `swoole-cli`，并校验：

- `PHP_VERSION` 以目标版本前缀开头。
- `PHP_SAPI === "cli"`。
- `SWOOLE_CLI` 常量存在。
- profile 声明的必需扩展已加载。
- profile 声明的排除扩展未被打包。

手动校验已有产物：

```bash
PHPSFX_PROFILE=min \
PHPSFX_EXPECTED_PHP_PREFIX=8.4. \
  bash scripts/validate-swoole-cli.sh dist/swoole-cli-php8.4-min-linux-x64
```

## 下载 Release 运行时

```bash
PHPSFX_PHP_VERSION=8.4 PHPSFX_PROFILE=min \
  bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
```

也可指定版本：

```bash
PHPSFX_PHP_VERSION=8.1 PHPSFX_PROFILE=mid \
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
- 运行时读取外部配置、日志、上传目录、数据库快照等资源时，仍应按应用自己的 Phar 运行规则放在二进制同级或指定路径。
- 脚本兼容 `.bin` 这类自定义 Phar 后缀，会先复制为临时 `.phar` 做轻量校验。

## 打包实现自测

对已有 `swoole-cli` 同时测试 PHP 与 Phar 两种 SFX 打包方式：

```bash
bash scripts/test-packaging.sh swoole-cli-php8.4-min-linux-x64
# 或
bash scripts/test-packaging.sh swoole-cli-php8.1-mid-linux-x64
```

## 参考

- [swoole/swoole-cli](https://github.com/swoole/swoole-cli)
- [Swoole CLI 构建选项](https://github.com/swoole/swoole-cli/blob/main/docs/options.md)
- [Swoole CLI SFX 打包说明](https://github.com/swoole/swoole-cli/blob/main/sapi/samples/sfx/README.md)
- [Swoole CLI 官方 pack-sfx.php](https://github.com/swoole/swoole-cli/blob/main/sapi/scripts/pack-sfx.php)
