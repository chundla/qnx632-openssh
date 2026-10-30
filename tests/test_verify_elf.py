"""Link checks for SHLE programs and shared objects such as io-net drivers."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

VERIFY = Path(__file__).resolve().parents[1] / "verify_elf.py"


def shle_elf(soname, imports=(), exports=(), needed=(), interpreter=None):
    """Return a minimal little-endian SuperH ELF32 with a dynamic table."""
    names = [soname, *needed, *imports, *exports]
    strtab, offsets = b"\0", {}
    for name in names:
        if name not in offsets:
            offsets[name] = len(strtab)
            strtab += name.encode() + b"\0"
    symbols = [(0, 0, 0)] + [(offsets[n], 0x10, 0) for n in imports] \
        + [(offsets[n], 0x12, 1) for n in exports]
    symtab = b"".join(struct.pack("<IIIBBH", name, 0, 0, info, 0, section)
                      for name, info, section in symbols)
    hashtab = struct.pack("<II", 1, len(symbols)) + b"\0" * 4 * (1 + len(symbols))
    interp = interpreter.encode() + b"\0" if interpreter else b""
    phnum = 3 if interp else 2
    base = 52 + 32 * phnum
    layout, cursor = {}, base
    for key, blob in (("interp", interp), ("strtab", strtab), ("symtab", symtab),
                      ("hash", hashtab)):
        layout[key] = cursor
        cursor += (len(blob) + 3) & ~3
    entries = [(1, offsets[n]) for n in needed] + [
        (5, layout["strtab"]), (6, layout["symtab"]), (4, layout["hash"]),
        (11, 16), (14, offsets[soname]), (0, 0)]
    layout["dynamic"] = cursor
    dynamic = b"".join(struct.pack("<II", *e) for e in entries)
    size = cursor + len(dynamic)
    header = b"\x7fELF\x01\x01\x01" + b"\0" * 9 + struct.pack(
        "<HHIIIIIHHHHHH", 3, 42, 1, 0, 52, 0, 9, 52, 32, phnum, 40, 0, 0)
    phdrs = struct.pack("<8I", 1, 0, 0, 0, size, size, 5, 0x1000)
    phdrs += struct.pack("<8I", 2, layout["dynamic"], layout["dynamic"], 0,
                         len(dynamic), len(dynamic), 6, 4)
    if interp:
        phdrs += struct.pack("<8I", 3, layout["interp"], layout["interp"], 0,
                             len(interp), len(interp), 4, 1)
    image = bytearray(size)
    image[:52 + len(phdrs)] = header + phdrs
    for key, blob in (("interp", interp), ("strtab", strtab), ("symtab", symtab),
                      ("hash", hashtab), ("dynamic", dynamic)):
        image[layout[key]:layout[key] + len(blob)] = blob
    return bytes(image)


class VerifyElfTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.libc = self.write("libc.so.2", shle_elf("libc.so.2", exports=["slogf"]))

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, data):
        path = self.dir / name
        path.write_bytes(data)
        return path

    def run_verify(self, program, *flags):
        return subprocess.run(
            [sys.executable, str(VERIFY), "--library", str(self.libc), *flags, str(program)],
            capture_output=True, text=True)

    def test_shared_driver_passes_only_in_shared_mode(self):
        driver = self.write("devn-test.so", shle_elf(
            "devn-test.so", imports=["slogf"], exports=["io_net_dll_entry"],
            needed=["libc.so.2"]))
        self.assertEqual(self.run_verify(driver, "--shared").returncode, 0)
        self.assertEqual(self.run_verify(driver).returncode, 1)

    def test_shared_mode_rejects_program_interpreter(self):
        program = self.write("hello", shle_elf(
            "hello", imports=["slogf"], needed=["libc.so.2"],
            interpreter="/usr/lib/ldqnx.so.2"))
        self.assertEqual(self.run_verify(program).returncode, 0)
        self.assertEqual(self.run_verify(program, "--shared").returncode, 1)

    def test_missing_import_fails(self):
        driver = self.write("devn-test.so", shle_elf(
            "devn-test.so", imports=["slogf", "InterruptAttach"], needed=["libc.so.2"]))
        result = self.run_verify(driver, "--shared")
        self.assertEqual(result.returncode, 1)
        self.assertIn("InterruptAttach", result.stdout)


if __name__ == "__main__":
    unittest.main()
