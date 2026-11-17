#!/usr/bin/env python3
"""Merge micro experiment metadata without changing the release metadata schema."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: scripts/merge-micro-meta.py <metadata-dir> <output.json>", file=sys.stderr)
        return 2

    source_dir = Path(sys.argv[1])
    output = Path(sys.argv[2])
    files = sorted(source_dir.rglob("build-meta-*.json"))
    if not files:
        raise SystemExit(f"No micro metadata files found in {source_dir}")

    builds = []
    identities = set()
    binaries = set()
    checksums = []
    packages = {
        "linux-x64": ("mysql", "pgsql", "odbc"),
        "linux-a64": ("mysql", "pgsql", "odbc"),
        "macos-a64": ("mysql", "pgsql"),
    }
    expected = {(php, f"{platform}-{database}")
                for php in ("8.4", "8.5") for platform, databases in packages.items()
                for database in databases}
    for path in files:
        item = json.loads(path.read_text(encoding="utf-8"))
        if item.get("runtime") != "micro":
            raise SystemExit(f"Unexpected runtime in {path}: {item.get('runtime')!r}")
        for field in ("platform", "php_version", "variant", "asset", "sha256"):
            if not item.get(field):
                raise SystemExit(f"Missing {field} in {path}")
        identity = (item.get("php_version"), item.get("variant"))
        if identity in identities:
            raise SystemExit(f"Duplicate micro identity: {identity}")
        identities.add(identity)
        database = item.get("database_variant")
        platform = item["platform"]
        if identity not in expected or database not in packages.get(platform, ()) or item["variant"] != f"{platform}-{database}":
            raise SystemExit(f"Unexpected micro identity in {path}: {identity}")
        asset = f"{platform.replace('-', '.')}.{database}.sfx"
        if item["asset"] != asset:
            raise SystemExit(f"Unexpected micro asset in {path}: {item['asset']}")
        binary = path.parent / asset
        if not binary.is_file():
            raise SystemExit(f"Missing micro binary: {binary}")
        if binary.stat().st_size != item.get("sfx_size"):
            raise SystemExit(f"Size mismatch: {binary}")
        digest = hashlib.sha256()
        with binary.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != item["sha256"]:
            raise SystemExit(f"SHA-256 mismatch: {binary}")
        binaries.add(binary.resolve())
        item["asset_path"] = Path(os.path.relpath(binary, output.parent)).as_posix()
        checksums.append(f"{digest.hexdigest()}  {item['asset_path']}\n")
        builds.append(item)

    if identities != expected:
        raise SystemExit(f"Incomplete micro matrix; missing: {sorted(expected - identities)}")
    actual_binaries = {path.resolve() for path in source_dir.rglob("*.sfx") if path.is_file()}
    if actual_binaries != binaries:
        raise SystemExit(f"Unexpected micro binaries: {sorted(str(path) for path in actual_binaries - binaries)}")

    result = {
        "runtime": "micro",
        "sfx_format": "micro.sfx + [INI magic/length/data] + payload",
        "experimental": True,
        "build_count": len(builds),
        "php_versions": sorted({item.get("php_version") for item in builds}),
        "platforms": sorted({item.get("platform") for item in builds}),
        "variants": sorted({item.get("variant") for item in builds}),
        "builds": builds,
    }
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    output.with_name("SHA256SUMS").write_text("".join(checksums), encoding="utf-8")
    print(f"Verified {len(builds)} micro binaries, 8 per PHP line; wrote metadata and SHA256SUMS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
