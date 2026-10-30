"""Check EGD boundaries with a deterministic, fault-injectable test collector.

These tests validate the adapter's failure handling, not entropy quality.
Hardware raw-noise assessment and upstream health tests are separate.
"""
import os
from pathlib import Path
import selectors
import socket
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "src/jitter-egd.c"
STUB = r'''
#include <stdlib.h>
#include <sys/types.h>
#include <string.h>
#define JENT_FORCE_FIPS 32
#define JENT_DISABLE_INTERNAL_TIMER 16
struct rand_data { unsigned next; };
static int jent_entropy_init_ex(unsigned osr, unsigned flags) {
    if (osr != 3 || flags != 48) abort();
    return getenv("JENT_STUB_INIT_FAIL") ? 9 : 0;
}
static struct rand_data *jent_entropy_collector_alloc(unsigned a, unsigned b) {
    (void)a; (void)b;
    return getenv("JENT_STUB_ALLOC_FAIL") ? NULL : calloc(1, sizeof(struct rand_data));
}
static void jent_entropy_collector_free(struct rand_data *p) { free(p); }
static unsigned jent_version(void) { return 3070000; }
static void jent_memset_secure(void *p, size_t n) { memset(p, 0, n); }
static ssize_t jent_read_entropy(struct rand_data *p, char *out, size_t n) {
    size_t i;
    for (i = 0; i < n; i++) out[i] = (char)((p->next++) % 251);
    /* Deliberately fill a buffer before returning failure/partial success. */
    if (getenv("JENT_STUB_READ_FAIL")) return -3;
    if (getenv("JENT_STUB_SHORT_READ")) return (ssize_t)n - 1;
    return (ssize_t)n;
}
'''


class JitterEgdTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="mmi-jitter-egd-test-")
        root = Path(cls.work.name)
        (root / "jitterentropy.h").write_text(STUB)
        cls.binary = root / "jitter-egd"
        subprocess.run(["gcc", "-std=c99", "-D_POSIX_C_SOURCE=200809L",
                        "-Wall", "-Wextra", "-Werror", "-DJITTER_EGD_TESTING",
                        "-I", str(root), str(SOURCE), "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def start(self, **faults):
        process = subprocess.Popen([str(self.binary), "0"], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env={**os.environ, **faults})
        def cleanup():
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            self.assertTrue(selector.select(5), "Service startup timed out")
        line = process.stdout.readline().decode()
        self.assertIn("JITTER_EGD_READY 127.0.0.1:", line)
        return process, int(line.split(":")[1].split()[0])

    def request(self, port, count, command=2):
        with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
            connection.sendall(bytes([command, count]))
            result = b""
            while True:
                part = connection.recv(256)
                if not part:
                    return result
                result += part

    def test_requests_use_the_collector_each_time(self):
        _, port = self.start()
        self.assertEqual(self.request(port, 40), bytes(range(40)))
        self.assertEqual(self.request(port, 40), bytes(range(40, 80)))
        self.assertEqual(len(self.request(port, 255)), 255)

    def test_invalid_commands_and_zero_requests_do_not_collect(self):
        _, port = self.start()
        for command in (0, 1, 3, 255):
            self.assertEqual(self.request(port, 40, command), b"")
        self.assertEqual(self.request(port, 0), b"")
        self.assertEqual(self.request(port, 40), bytes(range(40)))

    def test_health_failure_returns_no_buffer_and_stops(self):
        process, port = self.start(JENT_STUB_READ_FAIL="1")
        self.assertEqual(self.request(port, 40), b"")
        self.assertNotEqual(process.wait(5), 0)

    def test_short_read_returns_no_buffer_and_stops(self):
        process, port = self.start(JENT_STUB_SHORT_READ="1")
        self.assertEqual(self.request(port, 40), b"")
        self.assertNotEqual(process.wait(5), 0)

    def test_failed_startup_never_announces_readiness(self):
        for fault in ("JENT_STUB_INIT_FAIL", "JENT_STUB_ALLOC_FAIL"):
            with self.subTest(fault=fault):
                result = subprocess.run([str(self.binary), "0"], capture_output=True,
                                        env={**os.environ, fault: "1"}, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(b"JITTER_EGD_READY", result.stdout)

    def test_busy_port_fails(self):
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            result = subprocess.run([str(self.binary), str(occupied.getsockname()[1])],
                                    capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b"JITTER_EGD_READY", result.stdout)

    def test_stop_closes_listener(self):
        process, port = self.start()
        process.terminate()
        self.assertEqual(process.wait(5), 0)
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", port), timeout=1)

    def test_invalid_arguments(self):
        for args in (["abc"], ["-1"], ["65536"], ["1", "2"]):
            result = subprocess.run([str(self.binary), *args], capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
