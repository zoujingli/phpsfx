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
    php_versions = sorted({str(item.get("php_version", "")) for item in platforms if item.get("php_version", "")})
    profiles = sorted({str(item.get("profile", "")) for item in platforms if item.get("profile", "")})
    swoole_cli_refs = sorted({str(item.get("swoole_cli_ref", "")) for item in platforms if item.get("swoole_cli_ref", "")})
    profile_components = {
        profile: next(
            (
                str(item.get("extensions", ""))
                for item in platforms
                if str(item.get("profile", "")) == profile and item.get("extensions", "")
            ),
            "",
        )
        for profile in profiles
    }
    payload = {
        "version": env_or_default("PHPSFX_RELEASE_VERSION", ""),
        "runtime": "swoole-cli",
        "sfx_format": "swoole-cli + payload + pack('J', payloadSize)",
        "profiles": profiles,
        "profile_components": profile_components,
        "php_versions": php_versions,
        "swoole_cli_refs": swoole_cli_refs,
        "extensions": env_or_default("PHPSFX_EXTENSIONS", first.get("extensions", "")) if len(profiles) <= 1 else "",
        "required_extensions": env_or_default("PHPSFX_REQUIRED_EXTENSIONS", first.get("required_extensions", "")) if len(profiles) <= 1 else "",
        "forbidden_extensions": env_or_default("PHPSFX_FORBIDDEN_EXTENSIONS", first.get("forbidden_extensions", "")) if len(profiles) <= 1 else "",
        "prepare_flags": env_or_default("PHPSFX_SWOOLE_CLI_PREPARE_FLAGS", first.get("prepare_flags", "")) if len(profiles) <= 1 else "",
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
