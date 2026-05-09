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
  scripts/build-micro-sfx.sh
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
  scripts/validate-micro-sfx.sh dist/micro.sfx-php8.4-linux-x64
```

## 下游使用示例

`micro.sfx` 本身不能直接执行 PHP 命令，需要追加 PHP 代码后再运行：

```bash
cat micro.sfx-php8.4-linux-x64 index.php > app
chmod +x app
./app
```

如果下游输入是 Phar，建议使用 static-php-cli 的 `micro:combine` 做合并，INI 注入和资源嵌入也由下游项目自行处理。

## 参考

- [static-php-cli](https://github.com/crazywhalecc/static-php-cli)
- [static-php-cli 手动构建文档](https://static-php.dev/zh/guide/manual-build.html)
- [micro SAPI 深入说明](https://micro.static-php.dev/zh/digging-deeper.html)
