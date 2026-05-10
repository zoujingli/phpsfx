#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def env_or_default(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value not in (None, "") else default


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

    first = platforms[0]
    payload = {
        "version": env_or_default("PHPSFX_RELEASE_VERSION", ""),
        "runtime": "swoole-cli",
        "sfx_format": "swoole-cli + payload + pack('J', payloadSize)",
        "php_version": env_or_default("PHPSFX_PHP_VERSION", first.get("php_version", "")),
        "swoole_cli_ref": env_or_default("PHPSFX_SWOOLE_CLI_REF", first.get("swoole_cli_ref", "")),
        "extensions": env_or_default("PHPSFX_EXTENSIONS", first.get("extensions", "")),
        "prepare_flags": env_or_default("PHPSFX_SWOOLE_CLI_PREPARE_FLAGS", first.get("prepare_flags", "")),
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
