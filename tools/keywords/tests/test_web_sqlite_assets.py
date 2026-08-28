import http.client
import subprocess
import sys
import tempfile
import threading
import unittest
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError

import tools.keywords.verify_web_sqlite_assets as verifier
from tools.keywords.verify_web_sqlite_assets import (
    VerificationError,
    verify_asset_response,
)


WEB_DIR = Path(__file__).resolve().parents[3] / "web"
LOCK_FILE = Path(__file__).resolve().parents[3] / "pubspec.lock"
VERIFIER = Path(__file__).resolve().parents[1] / "verify_web_sqlite_assets.py"

VALID_LOCK_CONTENTS = """packages:
  sqflite_common_ffi_web:
    dependency: "direct main"
    description:
      name: sqflite_common_ffi_web
      sha256: "79338d0b69521d70cea10f841209ac87ce617921aaf7d33e7380682c83da1f06"
      url: "https://pub.dev"
    source: hosted
    version: "1.1.1"
  sqlite3:
    dependency: transitive
    description:
      name: sqlite3
      sha256: "4c7fe79840389aaeaf05fd093f795b631b5a98e2bd28d54e555c100f4a9c7a1c"
      url: "https://pub.dev"
    source: hosted
    version: "3.5.2"
"""


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


class _OversizedResponse:
    status = 200
    headers = {"Content-Type": "text/javascript"}

    def __init__(self):
        self.read_sizes = []
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.closed = True

    def read(self, size=None):
        self.read_sizes.append(size)
        if size is None:
            return b"x" * 264_001
        return b"x" * size


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

    def _verify_lock_contents(self, contents):
        with tempfile.TemporaryDirectory() as directory:
            lock_file = Path(directory, "pubspec.lock")
            lock_file.write_text(contents, encoding="utf-8")
            verifier.verify_lock_file(lock_file)

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
        drifted = VALID_LOCK_CONTENTS.replace(
            'version: "3.5.2"',
            'version: "9.9.9"',
        )

        with self.assertRaisesRegex(
            VerificationError,
            r"sqlite3.*version.*3\.5\.2.*9\.9\.9",
        ):
            self._verify_lock_contents(drifted)

    def test_lock_verifier_rejects_non_hosted_source(self):
        forged = VALID_LOCK_CONTENTS.replace(
            "    source: hosted",
            "    source: path",
            1,
        )

        with self.assertRaisesRegex(VerificationError, r"sqflite.*source.*hosted"):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_wrong_description_name(self):
        forged = VALID_LOCK_CONTENTS.replace(
            "      name: sqlite3",
            "      name: sqlite3_forged",
        )

        with self.assertRaisesRegex(VerificationError, r"sqlite3.*name"):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_non_pub_dev_url(self):
        forged = VALID_LOCK_CONTENTS.replace(
            '      url: "https://pub.dev"',
            '      url: "https://packages.example"',
            1,
        )

        with self.assertRaisesRegex(VerificationError, r"sqflite.*url.*pub\.dev"):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_missing_sha256(self):
        forged = VALID_LOCK_CONTENTS.replace(
            '      sha256: "79338d0b69521d70cea10f841209ac87ce617921aaf7d33e7380682c83da1f06"\n',
            "",
        )

        with self.assertRaisesRegex(VerificationError, r"sqflite.*sha256.*missing"):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_wrong_sha256(self):
        forged = VALID_LOCK_CONTENTS.replace(
            "4c7fe79840389aaeaf05fd093f795b631b5a98e2bd28d54e555c100f4a9c7a1c",
            "0" * 64,
        )

        with self.assertRaisesRegex(VerificationError, r"sqlite3.*sha256"):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_duplicate_version(self):
        forged = VALID_LOCK_CONTENTS.replace(
            '    version: "1.1.1"',
            '    version: "1.1.1"\n    version: "1.1.1"',
        )

        with self.assertRaisesRegex(VerificationError, r"sqflite.*duplicate.*version"):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_duplicate_description_block(self):
        forged = VALID_LOCK_CONTENTS.replace(
            "    description:\n",
            "    description:\n    description:\n",
            1,
        )

        with self.assertRaisesRegex(
            VerificationError,
            r"sqflite.*duplicate.*description",
        ):
            self._verify_lock_contents(forged)

    def test_lock_verifier_rejects_duplicate_target_package(self):
        duplicate = VALID_LOCK_CONTENTS + VALID_LOCK_CONTENTS.split("packages:\n", 1)[1]

        with self.assertRaisesRegex(VerificationError, r"duplicate.*sqflite"):
            self._verify_lock_contents(duplicate)

    def test_lock_verifier_rejects_missing_target_package(self):
        missing = VALID_LOCK_CONTENTS.split("  sqlite3:\n", 1)[0]

        with self.assertRaisesRegex(VerificationError, r"sqlite3.*missing"):
            self._verify_lock_contents(missing)

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

    def test_http_verifier_wraps_http_error(self):
        error = HTTPError(
            "http://example.test/sqflite_sw.js",
            404,
            "Not Found",
            {},
            None,
        )

        with patch.object(verifier, "urlopen", side_effect=error):
            with self.assertRaisesRegex(
                VerificationError,
                r"sqflite_sw\.js.*HTTP 404",
            ):
                verifier.verify_http("http://example.test")

    def test_http_verifier_wraps_url_error(self):
        with patch.object(
            verifier,
            "urlopen",
            side_effect=URLError("connection refused"),
        ):
            with self.assertRaisesRegex(
                VerificationError,
                r"sqflite_sw\.js.*connection refused",
            ):
                verifier.verify_http("http://127.0.0.1:1")

    def test_http_verifier_wraps_os_error(self):
        with patch.object(
            verifier,
            "urlopen",
            side_effect=OSError("socket unavailable"),
        ):
            with self.assertRaisesRegex(
                VerificationError,
                r"sqflite_sw\.js.*socket unavailable",
            ):
                verifier.verify_http("http://example.test")

    def test_http_verifier_rejects_invalid_url_without_raw_value_error(self):
        with self.assertRaisesRegex(VerificationError, r"sqflite_sw\.js.*unknown url"):
            verifier.verify_http("invalid-scheme://host")

    def test_http_verifier_limits_each_asset_read_to_expected_size_plus_one(self):
        response = _OversizedResponse()

        with patch.object(verifier, "urlopen", return_value=response):
            with self.assertRaisesRegex(VerificationError, "expected length"):
                verifier.verify_http("http://example.test")

        self.assertEqual(response.read_sizes, [264_000])
        self.assertTrue(response.closed)

    def test_cli_reports_invalid_url_as_one_line_without_traceback(self):
        result = subprocess.run(
            [
                sys.executable,
                str(VERIFIER),
                "--url",
                "invalid-scheme://host",
                "--lock-file",
                str(LOCK_FILE),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertRegex(result.stderr, r"^ERROR: .*unknown url.*\n$")
        self.assertNotIn("Traceback", result.stderr)

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

    def test_rejects_content_types_that_only_contain_the_expected_token(self):
        cases = (
            ("/sqflite_sw.js", "application/notjavascript"),
            ("/sqlite3.wasm", "application/notwasm"),
        )

        for path, content_type in cases:
            with self.subTest(path=path, content_type=content_type):
                body = (WEB_DIR / path.removeprefix("/")).read_bytes()
                with self.assertRaisesRegex(VerificationError, "content type"):
                    verify_asset_response(path, 200, content_type, body)

    def test_accepts_exact_content_types_with_case_and_parameters_normalized(self):
        cases = (
            ("/sqflite_sw.js", " Text/JAVASCRIPT ; Charset=UTF-8 "),
            ("/sqflite_sw.js", "APPLICATION/JAVASCRIPT;charset=utf-8"),
            ("/sqlite3.wasm", " APPLICATION/WASM ; charset=binary"),
        )

        for path, content_type in cases:
            with self.subTest(path=path, content_type=content_type):
                body = (WEB_DIR / path.removeprefix("/")).read_bytes()
                verify_asset_response(path, 200, content_type, body)


if __name__ == "__main__":
    unittest.main()
