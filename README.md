# phpsfx

`phpsfx` 用于自动构建和发布多平台 PHP `micro.sfx` 运行时。产物面向下游 PHP/Phar 项目，用于把应用代码追加到 `micro.sfx` 后生成单文件可执行程序。

## Release 产物

首版固定构建 PHP 8.4 常用运行集，覆盖以下平台：

| 平台 | Release 文件 |
|------|--------------|
| Linux x86_64 | `micro.sfx-php8.4-linux-x64` |
| Linux ARM64 | `micro.sfx-php8.4-linux-a64` |
| macOS x86_64 | `micro.sfx-php8.4-macos-x64` |
| macOS ARM64 | `micro.sfx-php8.4-macos-a64` |

同时发布：

- `SHA256SUMS`
- `build-meta.json`

## 内置扩展

固定首版扩展组合：

```text
bcmath,ctype,curl,dom,fileinfo,filter,iconv,mbstring,openssl,pcntl,
pdo_mysql,phar,posix,redis,simplexml,sockets,sodium,swoole,tokenizer,
xml,xmlreader,xmlwriter,zlib
```

`json`、`hash`、`pcre`、`reflection` 等按 PHP core 默认能力处理，不显式传入 static-php-cli 扩展列表。

## 自动发布

GitHub Actions workflow：`.github/workflows/release.yml`。

触发方式：

- 推送 `v*` 标签：自动构建所有平台并创建 GitHub Release。
- 手动运行 `Release micro.sfx`：可输入 `version`、`php_version`、`spc_ref`。

示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 本地 / WSL 调试

WSL 或 Linux x86_64 本地只构建当前平台：

```bash
cd /mnt/d/WebRoot/phpsfx
PHPSFX_PLATFORM=linux-x64 \
PHPSFX_PHP_VERSION=8.4 \
PHPSFX_SPC_REF=main \
  bash scripts/build-micro-sfx.sh
```

构建完成后输出到 `dist/`。

> Linux 构建依赖 Docker；macOS 构建依赖本机 Xcode Command Line Tools 和 static-php-cli 可自动修复的系统依赖。

## 校验方式

构建脚本会把临时 PHP payload 追加到 `micro.sfx` 后执行，并校验：

- `PHP_VERSION` 以目标版本前缀开头。
- `PHP_SAPI === "cli"`，确认 `--with-micro-fake-cli` 生效。
- `swoole`、`redis`、`pdo_mysql`、`openssl`、`curl`、`mbstring`、`phar`、`zlib` 已加载。

也可以手动校验已有产物：

```bash
PHPSFX_EXPECTED_PHP_PREFIX=8.4. \
PHPSFX_REQUIRED_EXTENSIONS=swoole,redis,pdo_mysql,openssl,curl,mbstring,phar,zlib \
  bash scripts/validate-micro-sfx.sh dist/micro.sfx-php8.4-linux-x64
```

## PHP 源码打包

单个 PHP 入口文件可以直接追加到 `micro.sfx`。推荐直接使用 phpsfx 最新 Release 产物：

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/micro.sfx

bash scripts/pack-php.sh \
  /tmp/micro.sfx \
  examples/hello.php \
  build/hello

./build/hello
```

等价原理：

```bash
cat micro.sfx-php8.4-linux-x64 examples/hello.php > build/hello
chmod +x build/hello
```

该模式适合单文件命令行工具或入口文件已经自包含的场景；复杂项目不要直接追加源码目录。

## Phar 打包

复杂项目推荐先生成可执行 Phar，再追加到 `micro.sfx`。推荐直接使用 phpsfx 最新 Release 产物：

```bash
bash scripts/download-release-asset.sh linux-x64 latest /tmp/micro.sfx

bash scripts/pack-phar.sh \
  /tmp/micro.sfx \
  app.phar \
  build/app

./build/app
```

等价原理：

```bash
cat micro.sfx-php8.4-linux-x64 app.phar > build/app
chmod +x build/app
```

约束：

- `app.phar` 必须自带可执行 Phar stub。
- 运行时读取外部配置、日志、上传目录、数据库快照等资源时，仍应按应用自己的 Phar 运行规则放在二进制同级或指定路径。
- HyperfAdmin 的 `xadmin:build:phar --name=system.bin` 生成物可直接作为 `pack-phar.sh` 输入；脚本会兼容 `.bin` 这类自定义 Phar 后缀。

## 打包实现自测

对已有 `micro.sfx` 同时测试 PHP 与 Phar 两种打包方式：

```bash
bash scripts/test-packaging.sh micro.sfx-php8.4-linux-x64
```

## HyperfAdmin 打包示例

```bash
# 1. 在 HyperfAdmin 中生成 Phar。
cd /mnt/d/WebRoot/HyperfAdmin
APP_ENV=prod SCAN_CACHEABLE=true \
  sh bin/swoole-cli -d phar.readonly=Off ./bin/hyperf.php \
  xadmin:build:phar --mount=.env --name=system.bin --phar-version=2.0.0

# 2. 下载 phpsfx 最新 Release 中对应平台的 micro.sfx。
cd /mnt/d/WebRoot/phpsfx
bash scripts/download-release-asset.sh linux-x64 latest /tmp/micro.sfx

# 3. 追加 HyperfAdmin Phar 生成单文件二进制。
bash scripts/pack-phar.sh \
  /tmp/micro.sfx \
  /mnt/d/WebRoot/HyperfAdmin/system.bin \
  /mnt/d/WebRoot/HyperfAdmin/build/hyperf-admin-micro-linux-x64

# 4. 运行命令。HyperfAdmin 当前 Phar stub 可直接透传命令参数。
cd /mnt/d/WebRoot/HyperfAdmin
./build/hyperf-admin-micro-linux-x64 list
./build/hyperf-admin-micro-linux-x64 start
```

## 参考

- [static-php-cli](https://github.com/crazywhalecc/static-php-cli)
- [static-php-cli 手动构建文档](https://static-php.dev/zh/guide/manual-build.html)
- [micro SAPI 深入说明](https://micro.static-php.dev/zh/digging-deeper.html)
