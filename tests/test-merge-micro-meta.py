#!/usr/bin/env python3

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/merge-micro-meta.py"


class MicroMetadataTests(unittest.TestCase):
    def make_artifacts(self, root):
        files = []
        for php in ("8.4", "8.5"):
            for platform in ("linux-x64", "linux-a64", "macos-x64", "macos-a64"):
                databases = ("mysql", "pgsql") if platform in ("macos-x64", "macos-a64") else ("mysql", "pgsql", "odbc")
                for database in databases:
                    directory = root / "dist" / f"micro-{php}-{platform}-{database}"
                    directory.mkdir(parents=True)
                    asset = platform.replace("-", ".") + f".{database}.sfx"
                    binary = directory / asset
                    binary.write_bytes(f"{php}:{asset}".encode())
                    binary.chmod(0o644)  # Actions download-artifact drops executable permissions.
                    item = {
                        "runtime": "micro", "platform": platform, "php_version": php,
                        "variant": f"{platform}-{database}", "database_variant": database,
                        "asset": asset, "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                        "sfx_size": binary.stat().st_size,
                    }
                    metadata = directory / f"build-meta-{php}-{platform}-{database}.json"
                    metadata.write_text(json.dumps(item))
                    files.append((metadata, binary))
        return files

    def merge(self, root):
        return subprocess.run([sys.executable, str(SCRIPT), str(root), str(root / "build-meta.json")],
                              capture_output=True, text=True)

    def test_nested_artifacts_keep_both_php_lines_and_checksum_nonexecutable_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_artifacts(root)
            result = self.merge(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads((root / "build-meta.json").read_text())
            self.assertEqual(summary["build_count"], 20)
            self.assertEqual(summary["php_versions"], ["8.4", "8.5"])
            self.assertEqual(len({item["asset"] for item in summary["builds"]}), 10)
            checksums = dict(line.split("  ", 1)[::-1] for line in (root / "SHA256SUMS").read_text().splitlines())
            self.assertEqual(len(checksums), 20)
            for item in summary["builds"]:
                binary = root / item["asset_path"]
                self.assertEqual(checksums[item["asset_path"]], hashlib.sha256(binary.read_bytes()).hexdigest())

    def test_missing_build_cannot_produce_successful_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata, binary = self.make_artifacts(root)[-1]
            metadata.unlink()
            binary.unlink()
            result = self.merge(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Incomplete micro matrix", result.stderr)
            self.assertFalse((root / "build-meta.json").exists())

    def test_missing_tampered_or_wrong_size_binary_is_rejected(self):
        for failure in ("missing", "hash", "size"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                metadata, binary = self.make_artifacts(root)[0]
                if failure == "missing":
                    binary.unlink()
                elif failure == "hash":
                    original = binary.read_bytes()
                    binary.write_bytes(b"!" + original[1:])
                else:
                    item = json.loads(metadata.read_text())
                    item["sfx_size"] += 1
                    metadata.write_text(json.dumps(item))
                result = self.merge(root)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn({"missing": "Missing micro binary", "hash": "SHA-256 mismatch", "size": "Size mismatch"}[failure], result.stderr)

    def test_duplicate_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata, _ = self.make_artifacts(root)[0]
            (metadata.parent / "build-meta-duplicate.json").write_bytes(metadata.read_bytes())
            result = self.merge(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Duplicate micro identity", result.stderr)

    def test_wrong_filename_or_unlisted_binary_is_rejected(self):
        for failure in ("filename", "unlisted"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                metadata, binary = self.make_artifacts(root)[0]
                if failure == "filename":
                    item = json.loads(metadata.read_text())
                    item["asset"] = "linux-x64-mysql.sfx"
                    metadata.write_text(json.dumps(item))
                else:
                    (binary.parent / "unexpected.sfx").write_bytes(b"extra")
                result = self.merge(root)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unexpected micro " + ("asset" if failure == "filename" else "binaries"), result.stderr)


if __name__ == "__main__":
    unittest.main()
