#!/usr/bin/env python3
"""Merge micro experiment metadata without changing the release metadata schema."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: scripts/merge-micro-meta.py <metadata-dir> <output.json>", file=sys.stderr)
        return 2

    source_dir = Path(sys.argv[1])
    output = Path(sys.argv[2])
    files = sorted(source_dir.glob("build-meta-*.json"))
    if not files:
        raise SystemExit(f"No micro metadata files found in {source_dir}")

    builds = []
    identities = set()
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
        builds.append(item)

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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
