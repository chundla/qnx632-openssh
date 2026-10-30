"""Exercise the finite EGD service's consumption and failure boundaries."""
import os
from pathlib import Path
import selectors
import socket
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "src/entropy-pool.c"


class EntropyPoolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="mmi-egd-build-")
        cls.binary = Path(cls.build.name) / "entropy-pool"
        subprocess.run(["gcc", "-std=c99", "-Wall", "-Wextra", "-Werror",
                        "-DENTROPY_POOL_TESTING", str(SOURCE), "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="mmi-egd-test-")
        self.addCleanup(self.work.cleanup)
        self.path = Path(self.work.name) / "pool"
        self.data = bytes((i * 37 + 11) % 256 for i in range(1024))
        self.path.write_bytes(self.data)
        self.path.chmod(0o600)

    def start(self):
        process = subprocess.Popen([str(self.binary), str(self.path), "0"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        def cleanup():
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            self.assertTrue(selector.select(timeout=5), "Service did not become ready")
        line = process.stdout.readline().decode()
        self.assertIn("EGD ready at 127.0.0.1:", line)
        port = int(line.split(":")[1].split(";")[0])
        return process, port

    def request(self, port, count, command=2):
        with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
            connection.sendall(bytes([command, count]))
            chunks = []
            while True:
                data = connection.recv(256)
                if not data:
                    break
                chunks.append(data)
            return b"".join(chunks)

    def test_unique_consumption_and_exhaustion(self):
        process, port = self.start()
        self.assertFalse(self.path.exists(), "Input must be consumed before serving")
        result = b"".join(self.request(port, n) for n in [255, 255, 255, 255, 4])
        self.assertEqual(result, self.data)
        self.assertEqual(process.wait(timeout=5), 0)
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", port), timeout=1)

    def test_unsupported_request_does_not_consume(self):
        _, port = self.start()
        self.assertEqual(self.request(port, 40, command=1), b"")
        self.assertEqual(self.request(port, 40), self.data[:40])

    def test_overdraw_returns_no_partial_response(self):
        self.data = self.data[:256]
        self.path.write_bytes(self.data)
        process, port = self.start()
        self.assertEqual(self.request(port, 255), self.data[:255])
        self.assertEqual(self.request(port, 2), b"")
        self.assertEqual(self.request(port, 1), self.data[-1:])
        self.assertEqual(process.wait(timeout=5), 0)

    def test_used_input_cannot_be_restarted(self):
        process, _ = self.start()
        process.terminate()
        self.assertEqual(process.wait(timeout=5), 0)
        restarted = subprocess.run([str(self.binary), str(self.path), "0"], capture_output=True)
        self.assertNotEqual(restarted.returncode, 0)

    def test_public_input_is_rejected(self):
        self.path.chmod(0o644)
        result = subprocess.run([str(self.binary), str(self.path), "0"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.path.exists())

    def test_busy_port_preserves_unused_input(self):
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            port = occupied.getsockname()[1]
            result = subprocess.run([str(self.binary), str(self.path), str(port)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.path.read_bytes(), self.data)


if __name__ == "__main__":
    unittest.main()
