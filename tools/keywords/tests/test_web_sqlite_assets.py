import http.client
import threading
import unittest
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


WEB_DIR = Path(__file__).resolve().parents[3] / "web"


class _QuietStaticHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


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
        cases = (
            ("/sqflite_sw.js", "javascript", b"", 10_000),
            ("/sqlite3.wasm", "wasm", b"\x00asm", 100_000),
        )

        for path, content_type, magic, minimum_size in cases:
            with self.subTest(path=path):
                status, actual_content_type, body = self._get(path)
                self.assertEqual(status, 200)
                self.assertIn(content_type, actual_content_type)
                self.assertGreater(len(body), minimum_size)
                if magic:
                    self.assertTrue(body.startswith(magic))


if __name__ == "__main__":
    unittest.main()
