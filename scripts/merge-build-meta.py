#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: scripts/merge-build-meta.py <dist-dir> <output-json>", file=sys.stderr)
        return 2

    dist = Path(sys.argv[1])
    output = Path(sys.argv[2])
    platforms = []
    for path in sorted(dist.glob("build-meta-*.json")):
        with path.open("r", encoding="utf-8") as fp:
            platforms.append(json.load(fp))

    if not platforms:
        print(f"No build-meta-*.json files found in {dist}", file=sys.stderr)
        return 1

    payload = {
        "version": os.getenv("PHPSFX_RELEASE_VERSION", ""),
        "php_version": os.getenv("PHPSFX_PHP_VERSION", platforms[0].get("php_version", "")),
        "spc_ref": os.getenv("PHPSFX_SPC_REF", platforms[0].get("spc_ref", "")),
        "extensions": os.getenv("PHPSFX_EXTENSIONS", platforms[0].get("extensions", "")),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "platforms": platforms,
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as fp:
        json.dump(payload, fp, ensure_ascii=False, indent=2)
        fp.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
