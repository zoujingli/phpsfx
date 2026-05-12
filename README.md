# phpsfx

`phpsfx` 用于自动构建和发布多平台 **Swoole CLI PHP 8.4 静态运行时**。产物用于把 PHP 源码入口或可执行 Phar 追加进运行时后生成单文件可执行程序。

运行时使用 Swoole CLI 官方 SFX 格式：

```text
swoole-cli + payload.php|app.phar + pack('J', payloadSize)
```

其中 `pack('J', payloadSize)` 是 Swoole CLI 官方 SFX 读取逻辑需要的 8 字节长度尾部（与官方 `pack-sfx.php` 保持一致）。

运行已打包产物时需要传入 `--self`，例如 `./app --self list`。这是 Swoole CLI 官方 SFX 模式的入口开关。

## Release 产物

默认构建 PHP 8.4 运行时，覆盖以下平台：

| 平台 | Release 文件 |
|------|--------------|
| Linux x86_64 | `swoole-cli-php8.4-linux-x64` |
| Linux ARM64 | `swoole-cli-php8.4-linux-a64` |
| macOS x86_64 | `swoole-cli-php8.4-macos-x64` |
| macOS ARM64 | `swoole-cli-php8.4-macos-a64` |

同时发布：

- `SHA256SUMS`
- `build-meta.json`

首版不发布 Windows 产物。

## 内置扩展与裁剪

默认使用 `scripts/profiles/hyperfadmin-slim.env`，只保留 SFX、Swoole 服务、Phar 发布、数据库、基础网络、图片处理、二维码压缩和 OPcache 常用扩展：

```text
bcmath,bz2,ctype,curl,dom,fileinfo,filter,gd,iconv,mbstring,opcache,
openssl,pcntl,pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,
swoole,tokenizer,xml,xmlreader,xmlwriter,zip,zlib
```

默认裁剪未使用或体积较大的扩展：

```text
exif,gettext,gmp,imagick,intl,mongodb,mysqli,readline,session,soap,
sqlite3,xlswriter,xsl,yaml
```

说明：Swoole CLI 的 `+xml` 构建项会同时启用 `dom/simplexml/xmlreader/xmlwriter`；`json/hash/pcre/reflection/PDO/libxml` 等属于 PHP core 或依赖扩展带出的基础能力，不作为独立 `prepare.php +xxx` 参数传入。`intl` 默认不打包，`bz2/gd/opcache` 作为 dmskc 标准能力保留。

构建脚本还会把 Swoole CLI 上游默认的 full profile 收敛为 `PHPSFX_SWOOLE_CLI_ENABLED_EXTENSIONS`，并进一步裁剪底层依赖：

- Swoole 扩展：保留 server/coroutine/curl hook/mysqlnd/c-ares DNS，默认不启用 `pgsql/sqlite/odbc/ssh2/ftp/thread/brotli/zstd` 等未使用功能。
- libcurl：保留 HTTP(S)、OpenSSL、zlib、c-ares，默认不启用 HTTP3、SSH2、IDN、PSL、Brotli、Zstd。
- libzip：保留 Zip + zlib + OpenSSL，默认不启用 LZMA、Zstd。
- zlib：移除上游模板中与 zlib 构建无关的额外依赖。
- redis：默认关闭 redis session 支持，因为本运行时不打包 PHP `session` 扩展。
- oniguruma：使用 6.9.10 release tarball，并在 macOS 构建时兼容新版 clang 对旧版函数指针告警的严格处理。

依赖库安装前缀默认放在 `.build/swoole-cli/.global-prefix/<platform>`，不会写入 `/usr/local/swoole-cli`，适合 GitHub Actions 和 WSL 普通权限构建。

## 自动发布

GitHub Actions workflow：`.github/workflows/release.yml`。

触发方式：

- 推送 `v*` 标签：自动构建所有平台并创建 GitHub Release。
- 手动运行 `Release swoole-cli`：可输入 `version`、`php_version`、`swoole_cli_ref`、`prepare_flags`。

示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

默认上游源码：

```text
https://github.com/swoole/swoole-cli.git
```

默认 `swoole_cli_ref=v6.2.0.0`。如果未来要固定官方 tag 或提交，可在 workflow 手动输入，或设置环境变量 `PHPSFX_SWOOLE_CLI_REF`。

`v6.2.0.0` 上游默认 PHP 版本为 `8.4.14`；构建脚本默认使用 `PHPSFX_PHP_FULL_VERSION=8.4.21` 覆盖 `sapi/PHP-VERSION.conf`，用于构建 PHP 8.4 安全补丁运行时。产物命名仍保留 `php8.4` 线，例如 `swoole-cli-php8.4-linux-x64`，完整补丁版本会写入 `build-meta.json` 的 `php_full_version`。

## 本地 / WSL 调试

WSL 或 Linux x86_64 本地只构建当前平台：

```bash
cd /mnt/d/WebRoot/phpsfx
PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PHP_VERSION=8.4 \
PHPSFX_PHP_FULL_VERSION=8.4.21 \
PHPSFX_SWOOLE_CLI_REF=v6.2.0.0 \
  bash scripts/build-swoole-cli.sh
```

构建完成后输出到 `dist/`。

如果本地已经安装了同版本 Swoole CLI（例如 `/usr/local/bin/php` 输出 `Swoole 6.2.0`），可以先导入为 phpsfx 标准命名产物，用于快速验证下游打包链路。注意官方 full runtime 通常包含 `mongodb/sqlite3/imagick` 等额外扩展，导入时如只是本地调试可显式允许额外扩展；正式发布仍应使用源码构建的 slim 产物：

```bash
PHPSFX_ALLOW_EXTRA_EXTENSIONS=1 \
PHPSFX_SWOOLE_CLI_REF=v6.2.0.0 \
  bash scripts/import-swoole-cli.sh linux-x64 /usr/local/bin/php
```

常用覆盖项：

```bash
# 使用依赖镜像，适合网络不稳定时。
PHPSFX_DOWNLOAD_MIRROR_URL=https://example.com \
  bash scripts/build-swoole-cli.sh linux-x64

# 临时调整扩展裁剪。
PHPSFX_SWOOLE_CLI_PREPARE_FLAGS='+redis +swoole +pdo_mysql +xml -mongodb -sqlite3' \
  bash scripts/build-swoole-cli.sh linux-x64
```

> Linux/macOS 构建均依赖本机编译工具链。CI 会安装基础依赖；本地请参考 Swoole CLI 官方 Linux/macOS 构建文档准备环境。

## 运行时校验

构建脚本会直接执行生成的 `swoole-cli`，并校验：

- `PHP_VERSION` 以目标版本前缀开头。
- `PHP_SAPI === "cli"`。
- `SWOOLE_CLI` 常量存在。
- `swoole`、`redis`、`pdo_mysql`、`openssl`、`curl`、`mbstring`、`phar`、`zlib`、`zip`、`dom`、`simplexml`、`xmlreader`、`xmlwriter`、`bz2`、`gd`、`opcache` 等必需扩展已加载。
- `exif/gettext/gmp/imagick/intl/mongodb/mysqli/readline/session/soap/sqlite3/xlswriter/xsl/yaml` 等未使用扩展未被打包。

手动校验已有产物：

```bash
PHPSFX_EXPECTED_PHP_PREFIX=8.4. \
PHPSFX_REQUIRED_EXTENSIONS=swoole,redis,pdo_mysql,openssl,curl,mbstring,phar,zlib,zip,dom,simplexml,xmlreader,xmlwriter,bz2,gd,opcache \
PHPSFX_FORBIDDEN_EXTENSIONS=exif,gettext,gmp,imagick,intl,mongodb,mysqli,readline,session,soap,sqlite3,xlswriter,xsl,yaml \
  bash scripts/validate-swoole-cli.sh dist/swoole-cli-php8.4-linux-x64
```

## 下载 Release 运行时

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli
```

也可指定版本：

```bash
bash scripts/download-release-asset.sh linux-x64 v0.1.0 /tmp/swoole-cli
```

## PHP 源码打包

单个 PHP 入口文件可直接追加到 `swoole-cli`：

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli

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
bash scripts/download-release-asset.sh linux-x64 latest /tmp/swoole-cli

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
bash scripts/test-packaging.sh swoole-cli-php8.4-linux-x64
```


## 参考

- [swoole/swoole-cli](https://github.com/swoole/swoole-cli)
- [Swoole CLI 构建选项](https://github.com/swoole/swoole-cli/blob/main/docs/options.md)
- [Swoole CLI SFX 打包说明](https://github.com/swoole/swoole-cli/blob/main/sapi/samples/sfx/README.md)
- [Swoole CLI 官方 pack-sfx.php](https://github.com/swoole/swoole-cli/blob/main/sapi/scripts/pack-sfx.php)
