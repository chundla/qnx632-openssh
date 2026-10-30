"""Exercise the actual SH timer adapter at a 32-bit counter wrap."""
from pathlib import Path
import subprocess
import tempfile
import unittest


class QnxJitterTimerTests(unittest.TestCase):
    def test_fixed_bits_wrap_and_stuck_counter(self):
        source = Path(__file__).resolve().parents[1] / "src"
        with tempfile.TemporaryDirectory(prefix="mmi-qnx-timer-test-") as work:
            root = Path(work)
            (root / "sys").mkdir()
            (root / "sys/neutrino.h").write_text("uint64_t ClockCycles(void);\n")
            (root / "test.c").write_text(r'''
#include <assert.h>
#include <stdint.h>
#include "qnx-jitter-timer.h"
static uint32_t ticks;
uint64_t ClockCycles(void) { return (uint64_t)ticks << 32; }
static void expect(uint32_t next, uint64_t expected) {
    uint64_t result;
    ticks = next;
    jent_get_nstime(&result);
    assert(result == expected);
}
int main(void) {
    expect(1, 1); /* fixed low bits of ClockCycles must be stripped */
    expect(2, 2);
    expect(2, 2); /* a stuck timer must remain detectable */
    expect(0xfffffff0U, 0xfffffff0ULL);
    expect(0xffffffffU, 0xffffffffULL);
    expect(0, 0x100000000ULL);
    expect(2, 0x100000002ULL);
    return 0;
}
''')
            subprocess.run(["gcc", "-std=c99", "-Wall", "-Wextra", "-Werror",
                            "-I", str(root), "-I", str(source), str(root / "test.c"),
                            "-o", str(root / "test")], check=True)
            subprocess.run([str(root / "test")], check=True)


if __name__ == "__main__":
    unittest.main()
