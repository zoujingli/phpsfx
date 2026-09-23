#!/usr/bin/env python3
"""Verify the paginated GitHub Release inventory against locally checked artifacts."""

from __future__ import annotations

import hashlib
import json
import os
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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_assets(dist: Path, version: str) -> dict[str, tuple[int, str]]:
    summary = json.loads((dist / "build-meta.json").read_text(encoding="utf-8"))
    assert summary["version"] == version
    variants = {f"{platform}-{database}{suffix}" for platform in PLATFORMS
                for database in DATABASES for suffix in ("", "-odbc")}
    assert len(summary["platforms"]) == 56
    assert {item["variant"] for item in summary["platforms"]} == variants

    checksums = {}
    for line in (dist / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        assert name not in checksums and len(digest) == 64
        checksums[name] = digest
    assert len(checksums) == 56
    assert set(checksums) == {item["asset"] for item in summary["platforms"]}

    expected = {}
    for item in summary["platforms"]:
        variant = item["variant"]
        name = item["asset"]
        meta = f"build-meta-{variant}.json"
        assert name == f"swoole-cli-php{item['php_version']}-{variant}"
        assert item["cli_version"] == version and item["sha256"] == checksums[name]
        assert json.loads((dist / meta).read_text(encoding="utf-8")) == item
        assert sha256(dist / name) == checksums[name]
        expected[name] = ((dist / name).stat().st_size, checksums[name])
        expected[meta] = ((dist / meta).stat().st_size, sha256(dist / meta))
    assert len(expected) == 112
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
    assert len(assets) == len(expected) == 114, f"Found {len(assets)} assets, expected 114"
    names = [asset["name"] for asset in assets]
    assert len(names) == len(set(names)) and set(names) == set(expected), "Release asset names differ"
    for asset in assets:
        size, digest = expected[asset["name"]]
        assert asset["state"] == "uploaded", f"Incomplete upload: {asset['name']}"
        assert asset["size"] == size, f"Size mismatch: {asset['name']}"
        assert asset.get("digest") == f"sha256:{digest}", f"SHA-256 mismatch: {asset['name']}"


def check_public_links(assets: list[dict]) -> None:
    samples = (
        "SHA256SUMS", "build-meta.json",
        "linux-x64-sqlite", "linux-a64-mysql-pgsql-odbc",
        "macos-x64-pgsql", "macos-a64-mysql-pgsql-sqlite-odbc",
    )
    by_name = {asset["name"]: asset for asset in assets}
    for sample in samples:
        name = next(name for name in by_name if name == sample or name.endswith("-" + sample))
        url = by_name[name]["browser_download_url"]
        with urlopen(Request(url, method="HEAD", headers={"User-Agent": "phpsfx-release-verifier"}), timeout=40) as response:
            assert response.status == 200, f"Public download failed: {name}"


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: verify-release-assets.py <owner/repo> <tag> <dist-dir>", file=sys.stderr)
        return 2
    repo, version, directory = sys.argv[1:]
    expected = expected_assets(Path(directory), version)
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
    print(f"Verified {len(assets)} published assets, 56 binary SHA-256 values and public download links")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
