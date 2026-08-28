import http.client
import subprocess
import sys
import tempfile
import threading
import unittest
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import tools.keywords.verify_web_sqlite_assets as verifier
from tools.keywords.verify_web_sqlite_assets import (
    VerificationError,
    verify_asset_response,
)


WEB_DIR = Path(__file__).resolve().parents[3] / "web"
LOCK_FILE = Path(__file__).resolve().parents[3] / "pubspec.lock"
VERIFIER = Path(__file__).resolve().parents[1] / "verify_web_sqlite_assets.py"


class _QuietStaticHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


class _SpaFallbackHandler(_QuietStaticHandler):
    def send_error(self, code, message=None, explain=None):
        if code == 404:
            self.path = "/index.html"
            self.do_GET()
            return
        super().send_error(code, message, explain)


class WebSqliteAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        handler = partial(_QuietStaticHandler, directory=str(WEB_DIR))
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def _get(self, path):
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.server.server_port, timeout=5
        )
        try:
            connection.request("GET", path)
            response = connection.getresponse()
            return response.status, response.getheader("Content-Type"), response.read()
        finally:
            connection.close()

    def test_web_root_serves_sqflite_worker_and_wasm(self):
        paths = ("/sqflite_sw.js", "/sqlite3.wasm")

        for path in paths:
            with self.subTest(path=path):
                status, actual_content_type, body = self._get(path)
                verify_asset_response(path, status, actual_content_type, body)

    def test_http_verifier_accepts_source_assets(self):
        verifier.verify_http(f"http://127.0.0.1:{self.server.server_port}")

    def test_directory_verifier_accepts_source_assets(self):
        verifier.verify_directory(WEB_DIR)

    def test_lock_verifier_accepts_resolved_runtime_versions(self):
        verifier.verify_lock_file(LOCK_FILE)

    def test_lock_verifier_rejects_runtime_version_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            lock_file = Path(directory, "pubspec.lock")
            lock_file.write_text(
                """packages:
  sqflite_common_ffi_web:
    dependency: "direct main"
    version: "1.1.1"
  sqlite3:
    dependency: transitive
    version: "9.9.9"
""",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                VerificationError,
                r"sqlite3.*expected 3\.5\.2.*got 9\.9\.9",
            ):
                verifier.verify_lock_file(lock_file)

    def test_cli_verifies_a_deployment_directory(self):
        result = subprocess.run(
            [
                sys.executable,
                str(VERIFIER),
                "--directory",
                str(WEB_DIR),
                "--lock-file",
                str(LOCK_FILE),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Web SQLite deployment assets verified", result.stdout)

    def test_http_verifier_rejects_missing_asset_hidden_by_spa_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "index.html").write_text(
                "<!doctype html><title>SPA fallback</title>",
                encoding="utf-8",
            )
            handler = partial(_SpaFallbackHandler, directory=directory)
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with self.assertRaisesRegex(VerificationError, "SPA fallback"):
                    verifier.verify_http(f"http://127.0.0.1:{server.server_port}")
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_rejects_worker_with_extra_bytes(self):
        worker = (WEB_DIR / "sqflite_sw.js").read_bytes() + b"x"

        with self.assertRaisesRegex(VerificationError, "length|SHA-256"):
            verify_asset_response(
                "/sqflite_sw.js",
                200,
                "text/javascript",
                worker,
            )

    def test_rejects_wasm_magic_followed_by_garbage(self):
        fake_wasm = b"\x00asm" + (b"x" * (733_428 - 4))

        with self.assertRaisesRegex(VerificationError, "length|SHA-256"):
            verify_asset_response(
                "/sqlite3.wasm",
                200,
                "application/wasm",
                fake_wasm,
            )


if __name__ == "__main__":
    unittest.main()
