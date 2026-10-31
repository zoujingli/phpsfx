#!/usr/bin/env python3

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-release-assets.py"
SPEC = importlib.util.spec_from_file_location("verify_release_assets", SCRIPT)
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


@patch.dict(os.environ, {"PHPSFX_SWOOLE_SRC_REF": ""})
class ReleaseAssetTests(unittest.TestCase):
    def make_dist(self, directory, php_versions=("8.4", "8.5"), version="v6.2.3.3"):
        dist = Path(directory)
        items = []
        checksums = []
        full_versions = {"8.4": "8.4.27", "8.5": "8.5.9" if version == "v6.2.3.2" else "8.5.12"}
        compact = version not in ("v6.2.3.2", "v6.2.3.3")
        platforms = ("linux-x64", "linux-a64", "macos-a64") if compact else verify.PLATFORMS
        packages = [(database + ("-odbc" if odbc else ""), database, odbc)
                    for database in verify.DATABASES for odbc in (False, True)]
        if compact:
            packages = [("mysql", "mysql", False), ("pgsql", "pgsql", False),
                        ("odbc", "odbc", True), ("sqlite-mysql-pgsql-odbc", "sqlite-mysql-pgsql", True)]
        if compact and version != "v6.2.3.4":
            packages[-1] = ("sqlite-mysql-pgsql", "sqlite-mysql-pgsql", True)
        for php in php_versions:
            full = full_versions[php]
            for platform in platforms:
                for suffix, database, supports_odbc in packages:
                    odbc = supports_odbc and not (platform == "macos-a64" and suffix == "sqlite-mysql-pgsql")
                    variant = f"{platform}-{suffix}"
                    name = f"swoole-cli-php{php}-{variant}"
                    meta = f"build-meta-php{php}-{variant}.json"
                    if version == "v6.2.3.2":
                        meta = f"build-meta-{variant}.json"
                    (dist / name).write_bytes(name.encode())
                    digest = verify.sha256(dist / name)
                    drivers = [] if database == "odbc" else database.split("-")
                    item = {
                        "platform": platform, "variant": variant, "asset": name,
                        "metadata_asset": "build-meta.json" if compact else meta, "database_variant": database,
                        "php_version": php, "php_full_version": full,
                        "cli_version": version, "swoole_version": ".".join(version.removeprefix("v").split(".")[:3]),
                        "profile": "hyperfadmin-odbc" if odbc else "hyperfadmin-slim",
                        "required_pdo_drivers": ",".join(drivers + (["odbc"] if odbc else [])),
                        "extensions": ",".join(f"pdo_{d}" for d in drivers),
                        "required_extensions": ",".join(f"pdo_{d}" for d in drivers),
                        "forbidden_extensions": ",".join(
                            ["mysqli", "pgsql", "sqlite3"] +
                            [f"pdo_{d}" for d in ("mysql", "pgsql", "sqlite") if d not in drivers]),
                        "swoole_odbc": odbc,
                        "odbc_dynamic_dependency": (
                            "libodbc.so.2" if platform.startswith("linux") else "libodbc.2.dylib"
                        ) if odbc else "",
                        "sha256": digest,
                    }
                    (dist / meta).write_text(json.dumps(item))
                    items.append(item)
                    checksums.append(f"{digest}  {name}\n")
        summary = {"version": version, "php_versions": sorted(php_versions),
                   "cli_versions": [version], "database_variants": sorted({p[1] for p in packages}),
                   "php_full_versions": sorted(full_versions[p] for p in php_versions), "platforms": items}
        (dist / "build-meta.json").write_text(json.dumps(summary))
        (dist / "SHA256SUMS").write_text("".join(checksums))
        return dist, summary

    def test_compact_release_has_24_binaries_and_two_shared_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, _ = self.make_dist(directory, version="v6.2.3.4")
            env = {**os.environ, "PHPSFX_RELEASE_VERSION": "v6.2.3.4"}
            result = subprocess.run(["python3", str(SCRIPT.with_name("merge-build-meta.py")),
                                     str(dist), str(dist / "build-meta.json")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = verify.expected_assets(dist, "v6.2.3.4")
            self.assertEqual(len(expected), 26)
            self.assertEqual(sum(name.startswith("swoole-cli-php") for name in expected), 24)
            self.assertFalse(any(name.startswith("build-meta-") for name in expected))
            for path in dist.glob("build-meta-*.json"):
                path.unlink()
            self.assertEqual(verify.expected_assets(dist, "v6.2.3.4"), expected)

    def test_compact_odbc_only_rejects_extra_database_driver(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, summary = self.make_dist(directory, version="v6.2.3.4")
            item = next(item for item in summary["platforms"] if item["database_variant"] == "odbc")
            item["required_pdo_drivers"] = "mysql,odbc"
            (dist / f"build-meta-php{item['php_version']}-{item['variant']}.json").write_text(json.dumps(item))
            (dist / "build-meta.json").write_text(json.dumps(summary))
            with self.assertRaises(AssertionError):
                verify.expected_assets(dist, "v6.2.3.4")

    def test_compact_rejects_binary_outside_release_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, _ = self.make_dist(directory, version="v6.2.3.4")
            (dist / "swoole-cli-php8.5-macos-x64-mysql").write_bytes(b"extra")
            with self.assertRaises(AssertionError):
                verify.expected_assets(dist, "v6.2.3.4")

    def test_development_package_odbc_depends_on_platform(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, summary = self.make_dist(directory, version="v6.2.3.6")
            self.assertEqual(len(verify.expected_assets(dist, "v6.2.3.6")), 26)
            for item in summary["platforms"]:
                if item["database_variant"] == "sqlite-mysql-pgsql":
                    self.assertFalse(item["asset"].endswith("-odbc"))
                    self.assertEqual(item["swoole_odbc"], item["platform"].startswith("linux-"))
                elif item["database_variant"] == "odbc":
                    self.assertTrue(item["swoole_odbc"])

    def test_rejects_wrong_development_package_odbc_for_platform(self):
        for platform in ("linux-x64", "linux-a64", "macos-a64"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                dist, summary = self.make_dist(directory, version="v6.2.3.6")
                verify.expected_assets(dist, "v6.2.3.6")
                item = next(i for i in summary["platforms"] if i["platform"] == platform and i["database_variant"] == "sqlite-mysql-pgsql")
                item["swoole_odbc"] = not item["swoole_odbc"]
                item["profile"] = "hyperfadmin-odbc" if item["swoole_odbc"] else "hyperfadmin-slim"
                item["required_pdo_drivers"] = "sqlite,mysql,pgsql" + (",odbc" if item["swoole_odbc"] else "")
                item["odbc_dynamic_dependency"] = (
                    "libodbc.so.2" if platform.startswith("linux-") else "libodbc.2.dylib"
                ) if item["swoole_odbc"] else ""
                (dist / f"build-meta-php{item['php_version']}-{item['variant']}.json").write_text(json.dumps(item))
                (dist / "build-meta.json").write_text(json.dumps(summary))
                with self.assertRaises(AssertionError):
                    verify.expected_assets(dist, "v6.2.3.6")

    def test_updated_swoole_and_legacy_release_versions_validate(self):
        for version in ("v6.2.3.6", "v6.2.4.0"):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                dist, _ = self.make_dist(directory, version=version)
                self.assertEqual(len(verify.expected_assets(dist, version)), 26)
                result = subprocess.run(["python3", str(SCRIPT), "--local", version, str(dist)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Verified 24 local binaries", result.stdout)

    def test_rejects_previous_swoole_version_in_updated_release(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, summary = self.make_dist(directory, version="v6.2.4.0")
            for item in summary["platforms"]:
                item["swoole_version"] = "6.2.3"
                (dist / f"build-meta-php{item['php_version']}-{item['variant']}.json").write_text(json.dumps(item))
            (dist / "build-meta.json").write_text(json.dumps(summary))
            with self.assertRaises(AssertionError):
                verify.expected_assets(dist, "v6.2.4.0")

    def test_two_php_lines_keep_matching_variants_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, _ = self.make_dist(directory)
            expected = verify.expected_assets(dist, "v6.2.3.3")
            self.assertEqual(len(expected), 226)
            env = {**os.environ, "PHPSFX_RELEASE_VERSION": "v6.2.3.3"}
            result = subprocess.run(["python3", str(SCRIPT.with_name("merge-build-meta.py")),
                                     str(dist), str(dist / "build-meta.json")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(verify.expected_assets(dist, "v6.2.3.3")), 226)
            result = subprocess.run(["python3", str(SCRIPT), "--local", "v6.2.3.3", str(dist)],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Verified 112 local binaries", result.stdout)

    def test_rejects_missing_php_line_before_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, summary = self.make_dist(directory)
            summary["php_versions"] = ["8.5"]
            summary["platforms"] = [i for i in summary["platforms"] if i["php_version"] == "8.5"]
            (dist / "build-meta.json").write_text(json.dumps(summary))
            with self.assertRaises(AssertionError):
                verify.expected_assets(dist, "v6.2.3.3")

    def test_rejects_wrong_database_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, summary = self.make_dist(directory)
            item = summary["platforms"][0]
            item["required_pdo_drivers"] = "mysql,sqlite"
            (dist / item["metadata_asset"]).write_text(json.dumps(item))
            (dist / "build-meta.json").write_text(json.dumps(summary))
            with self.assertRaises(AssertionError):
                verify.expected_assets(dist, "v6.2.3.3")

    def test_single_line_dispatch_and_legacy_assets_still_validate(self):
        for version, php in (("v6.2.4.0", "8.4"), ("v6.2.4.0", "8.5"),
                             ("v6.2.3.6", "8.4"), ("v6.2.3.6", "8.5"),
                             ("v6.2.3.5", "8.4"), ("v6.2.3.5", "8.5"),
                             ("v6.2.3.4", "8.4"), ("v6.2.3.4", "8.5"),
                             ("v6.2.3.3", "8.4"), ("v6.2.3.3", "8.5"), ("v6.2.3.2", "8.5")):
            with self.subTest(version=version, php=php), tempfile.TemporaryDirectory() as directory:
                dist, _ = self.make_dist(directory, (php,), version)
                selected = (php,) if version != "v6.2.3.2" else None
                self.assertEqual(len(verify.expected_assets(dist, version, selected)),
                                 114 if version in ("v6.2.3.2", "v6.2.3.3") else 14)

    def test_merge_rejects_duplicate_build_within_one_php_line(self):
        with tempfile.TemporaryDirectory() as directory:
            dist, summary = self.make_dist(directory)
            (dist / "build-meta-duplicate.json").write_text(json.dumps(summary["platforms"][0]))
            result = subprocess.run(["python3", str(SCRIPT.with_name("merge-build-meta.py")),
                                     str(dist), str(dist / "build-meta.json")],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate php_version/variant", result.stderr)

    def test_paginates_beyond_embedded_release_assets(self):
        pages = [
            {"id": 17, "tag_name": "v6.2.3.3", "draft": False, "assets": []},
            [{"name": f"asset-{n}"} for n in range(100)],
            [{"name": f"asset-{n}"} for n in range(100, 200)],
            [{"name": f"asset-{n}"} for n in range(200, 226)],
        ]
        with patch.object(verify, "get_json", side_effect=pages) as request:
            assets = verify.release_assets("example/phpsfx", "v6.2.3.3")
        self.assertEqual(len(assets), 226)
        self.assertIn("page=3", request.call_args_list[-1].args[0])

    def test_rejects_mismatched_remote_digest_or_size(self):
        expected = {f"asset-{n}": (10, "a" * 64) for n in range(114)}
        assets = [{"name": name, "size": 10, "state": "uploaded", "digest": "sha256:" + "a" * 64}
                  for name in expected]
        verify.verify_inventory(assets, expected)
        assets[0]["digest"] = "sha256:" + "b" * 64
        with self.assertRaisesRegex(AssertionError, "SHA-256 mismatch"):
            verify.verify_inventory(assets, expected)
        assets[0]["digest"] = "sha256:" + "a" * 64
        assets[0]["size"] = 9
        with self.assertRaisesRegex(AssertionError, "Size mismatch"):
            verify.verify_inventory(assets, expected)


if __name__ == "__main__":
    unittest.main()
