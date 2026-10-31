#!/usr/bin/env python3
"""Verify the paginated GitHub Release inventory against locally checked artifacts."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


PLATFORMS = ("linux-x64", "linux-a64", "macos-x64", "macos-a64")
DATABASES = (
    "sqlite", "mysql", "pgsql", "mysql-pgsql", "pgsql-sqlite",
    "mysql-sqlite", "mysql-pgsql-sqlite",
)
RELEASE_PLATFORMS = ("linux-x64", "linux-a64", "macos-a64")
RELEASE_PACKAGES = (
    ("mysql", "mysql", False),
    ("pgsql", "pgsql", False),
    ("odbc", "odbc", True),
    ("sqlite-mysql-pgsql", "sqlite-mysql-pgsql", True),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_assets(dist: Path, version: str, php_versions: tuple[str, ...] | None = None) -> dict[str, tuple[int, str]]:
    summary = json.loads((dist / "build-meta.json").read_text(encoding="utf-8"))
    assert summary["version"] == version
    if php_versions is None:
        php_versions = ("8.5",) if version == "v6.2.3.2" else ("8.4", "8.5")
    assert php_versions and set(php_versions) <= {"8.4", "8.5"}
    assert len(php_versions) == len(set(php_versions))
    assert summary["php_versions"] == sorted(php_versions), "Missing or unexpected PHP version line"
    compact = version not in ("v6.2.3.2", "v6.2.3.3")
    platforms = RELEASE_PLATFORMS if compact else PLATFORMS
    packages = RELEASE_PACKAGES if compact else tuple(
        (database + ("-odbc" if odbc else ""), database, odbc)
        for database in DATABASES for odbc in (False, True)
    )
    if version == "v6.2.3.4":
        packages = packages[:-1] + (("sqlite-mysql-pgsql-odbc", "sqlite-mysql-pgsql", True),)
    variants = {f"{platform}-{suffix}": (
                    platform, database,
                    odbc and not (platform == "macos-a64" and suffix == "sqlite-mysql-pgsql"))
                for platform in platforms for suffix, database, odbc in packages}
    identities = {(php, variant) for php in php_versions for variant in variants}
    count = len(identities)
    assert len(summary["platforms"]) == count
    assert {(item["php_version"], item["variant"]) for item in summary["platforms"]} == identities
    assert summary["cli_versions"] == [version]
    assert summary["database_variants"] == sorted({p[1] for p in packages})
    full_versions = {
        "8.4": os.getenv("PHPSFX_PHP84_FULL_VERSION") or "8.4.27",
        "8.5": os.getenv("PHPSFX_PHP85_FULL_VERSION") or "8.5.12",
    }
    # v6.2.3.2 predates the dual-PHP security rebuild and keeps its original inputs.
    if version == "v6.2.3.2":
        full_versions["8.5"] = "8.5.9"
    assert summary["php_full_versions"] == sorted(full_versions[php] for php in php_versions)

    checksums = {}
    for line in (dist / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        assert name not in checksums and re.fullmatch(r"[0-9a-f]{64}", digest)
        checksums[name] = digest
    assert len(checksums) == count
    assert set(checksums) == {item["asset"] for item in summary["platforms"]}

    expected = {}
    metadata_files = set()
    for item in summary["platforms"]:
        variant = item["variant"]
        name = item["asset"]
        php = item["php_version"]
        meta = f"build-meta-php{php}-{variant}.json"
        if version == "v6.2.3.2":
            meta = f"build-meta-{variant}.json"
        else:
            assert item["metadata_asset"] == ("build-meta.json" if compact else meta)
        assert name == f"swoole-cli-php{item['php_version']}-{variant}"
        assert item["php_full_version"] == full_versions[php]
        assert item["php_full_version"].startswith(php + ".")
        swoole_ref = (os.getenv("PHPSFX_SWOOLE_SRC_REF") or version.rsplit(".", 1)[0]).removeprefix("v")
        if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", swoole_ref):
            assert item["swoole_version"] == swoole_ref
        platform, database, odbc = item["platform"], item["database_variant"], item["swoole_odbc"]
        assert isinstance(odbc, bool)
        assert (platform, database, odbc) == variants[variant]
        assert item["profile"] == ("hyperfadmin-odbc" if odbc else "hyperfadmin-slim")
        drivers = [] if database == "odbc" else database.split("-")
        assert item["required_pdo_drivers"] == ",".join(drivers + (["odbc"] if odbc else []))
        extensions = set(item["extensions"].split(","))
        required = set(item["required_extensions"].split(","))
        excluded = set(item["forbidden_extensions"].split(","))
        assert {"mysqli", "pgsql", "sqlite3"} <= excluded
        assert not {"mysqli", "pgsql", "sqlite3"} & extensions
        for driver in ("mysql", "pgsql", "sqlite"):
            extension = f"pdo_{driver}"
            if driver in drivers:
                assert extension in extensions and extension in required and extension not in excluded
            else:
                assert extension in excluded and extension not in extensions and extension not in required
        dependency = "libodbc.so.2" if platform.startswith("linux-") else "libodbc.2.dylib"
        assert item["odbc_dynamic_dependency"] == (dependency if odbc else "")
        assert item["cli_version"] == version and item["sha256"] == checksums[name]
        metadata_files.add(meta)
        if not compact or (dist / meta).exists():
            assert json.loads((dist / meta).read_text(encoding="utf-8")) == item
        assert sha256(dist / name) == checksums[name]
        expected[name] = ((dist / name).stat().st_size, checksums[name])
        if not compact:
            expected[meta] = ((dist / meta).stat().st_size, sha256(dist / meta))
    assert len(expected) == count * (1 if compact else 2)
    assert {p.name for p in dist.glob("swoole-cli-php*")} == set(checksums)
    found_metadata = {p.name for p in dist.glob("build-meta-*.json")}
    assert found_metadata == metadata_files or (compact and not found_metadata)
    for name in ("build-meta.json", "SHA256SUMS"):
        expected[name] = ((dist / name).stat().st_size, sha256(dist / name))
    return expected


def get_json(url: str) -> object:
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "phpsfx-release-verifier"}
    if token := os.getenv("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    with urlopen(Request(url, headers=headers), timeout=40) as response:
        return json.load(response)


def release_assets(repo: str, version: str) -> list[dict]:
    root = f"https://api.github.com/repos/{repo}/releases"
    release = get_json(f"{root}/tags/{quote(version, safe='')}")
    assert isinstance(release, dict) and release["tag_name"] == version and not release["draft"]
    assets = []
    page = 1
    while True:
        batch = get_json(f"{root}/{release['id']}/assets?per_page=100&page={page}")
        assert isinstance(batch, list)
        assets.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return assets


def verify_inventory(assets: list[dict], expected: dict[str, tuple[int, str]]) -> None:
    assert len(assets) == len(expected), f"Found {len(assets)} assets, expected {len(expected)}"
    names = [asset["name"] for asset in assets]
    assert len(names) == len(set(names)) and set(names) == set(expected), "Release asset names differ"
    for asset in assets:
        size, digest = expected[asset["name"]]
        assert asset["state"] == "uploaded", f"Incomplete upload: {asset['name']}"
        assert asset["size"] == size, f"Size mismatch: {asset['name']}"
        assert asset.get("digest") == f"sha256:{digest}", f"SHA-256 mismatch: {asset['name']}"


def check_public_links(assets: list[dict]) -> None:
    variants = (
        "linux-x64-sqlite", "linux-a64-mysql-pgsql-odbc",
        "macos-x64-pgsql", "macos-a64-mysql-pgsql-sqlite-odbc",
    )
    by_name = {asset["name"]: asset for asset in assets}
    if any(name.endswith("-sqlite-mysql-pgsql") for name in by_name):
        variants = ("linux-x64-mysql", "linux-a64-sqlite-mysql-pgsql", "macos-a64-sqlite-mysql-pgsql")
    elif any(name.endswith("-sqlite-mysql-pgsql-odbc") for name in by_name):
        variants = ("linux-x64-mysql", "linux-a64-odbc", "macos-a64-sqlite-mysql-pgsql-odbc")
    php_versions = {name.split("-php", 1)[1].split("-", 1)[0] for name in by_name if name.startswith("swoole-cli-php")}
    samples = ["SHA256SUMS", "build-meta.json"] + [
        f"swoole-cli-php{php}-{variant}" for php in sorted(php_versions) for variant in variants
    ]
    for name in samples:
        url = by_name[name]["browser_download_url"]
        with urlopen(Request(url, method="HEAD", headers={"User-Agent": "phpsfx-release-verifier"}), timeout=40) as response:
            assert response.status == 200, f"Public download failed: {name}"


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: verify-release-assets.py <owner/repo>|--local <tag> <dist-dir>", file=sys.stderr)
        return 2
    repo, version, directory = sys.argv[1:]
    php_versions = tuple(os.environ["PHPSFX_PHP_VERSIONS"].split()) if os.getenv("PHPSFX_PHP_VERSIONS") else None
    expected = expected_assets(Path(directory), version, php_versions)
    binary_count = sum(name.startswith("swoole-cli-php") for name in expected)
    if repo == "--local":
        print(f"Verified {binary_count} local binaries, metadata, PDO combinations and SHA-256 values")
        return 0
    for attempt in range(4):
        try:
            assets = release_assets(repo, version)
            verify_inventory(assets, expected)
            check_public_links(assets)
            break
        except (AssertionError, OSError) as error:
            if attempt == 3:
                raise
            print(f"Release assets not ready ({error}); retrying", file=sys.stderr)
            time.sleep(2 ** attempt)
    print(f"Verified {len(assets)} published assets, {binary_count} binary SHA-256 values and public download links")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
