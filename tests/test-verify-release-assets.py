#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-release-assets.py"
SPEC = importlib.util.spec_from_file_location("verify_release_assets", SCRIPT)
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


class ReleaseAssetTests(unittest.TestCase):
    def test_paginates_beyond_embedded_release_assets(self):
        pages = [
            {"id": 17, "tag_name": "v6.2.3.2", "draft": False, "assets": []},
            [{"name": f"asset-{n}"} for n in range(100)],
            [{"name": f"asset-{n}"} for n in range(100, 114)],
        ]
        with patch.object(verify, "get_json", side_effect=pages) as request:
            assets = verify.release_assets("example/phpsfx", "v6.2.3.2")
        self.assertEqual(len(assets), 114)
        self.assertIn("page=2", request.call_args_list[-1].args[0])

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
