#!/usr/bin/env python3
"""Check QNX SHLE executables (or, with --shared, shared objects such as
io-net drivers) against libraries captured from the actual MMI.

Reads ELF program headers and dynamic tables, including IFS libraries whose
symbol section headers were removed. This is a link compatibility check,
not a substitute for execution on the head unit.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct


def inspect(path):
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x01\x01" or struct.unpack_from("<H", data, 18)[0] != 42:
        raise ValueError(f"Not a little-endian ELF32 SuperH file: {path}")
    phoff = struct.unpack_from("<I", data, 28)[0]
    size, count = struct.unpack_from("<HH", data, 42)
    headers = [struct.unpack_from("<8I", data, phoff + i * size) for i in range(count)]

    def offset(address):
        for kind, start, virtual, _, length, *_ in headers:
            if kind == 1 and virtual <= address < virtual + length:
                return start + address - virtual
        raise ValueError(f"Unmapped ELF address {address:#x} in {path}")

    dynamic = next(h for h in headers if h[0] == 2)
    tags, needed = {}, []
    for cursor in range(dynamic[1], dynamic[1] + dynamic[4], 8):
        kind, value = struct.unpack_from("<II", data, cursor)
        if kind == 0:
            break
        if kind == 1:
            needed.append(value)
        tags[kind] = value
    strings = offset(tags[5])

    def string(index):
        start = strings + index
        return data[start:data.index(b"\0", start)].decode()

    symbols = offset(tags[6])
    count = struct.unpack_from("<II", data, offset(tags[4]))[1]
    imports, exports = set(), set()
    for index in range(count):
        name, _, _, info, _, section = struct.unpack_from(
            "<IIIBBH", data, symbols + index * tags.get(11, 16))
        name = string(name)
        if not name:
            continue
        if section == 0 and info >> 4 == 1:
            imports.add(name)
        elif section != 0 and info >> 4 in (1, 2):
            exports.add(name)
    interpreter = next((data[h[1]:h[1] + h[4]].rstrip(b"\0").decode()
                        for h in headers if h[0] == 3), None)
    return {
        "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
        "interpreter": interpreter, "needed": [string(n) for n in needed],
        "soname": string(tags[14]) if 14 in tags else path.name,
        "imports": imports, "exports": exports,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--shared", action="store_true",
                        help="check shared objects (no program interpreter)")
    parser.add_argument("program", type=Path, nargs="+")
    args = parser.parse_args()
    libraries = {str(p): inspect(p) for p in args.library}
    exports = set().union(*(v["exports"] for v in libraries.values()))
    sonames = {v["soname"] for v in libraries.values()}
    report = {"libraries": {}, "programs": {}, "passed": True,
              "scope": "Static ELF/link checks only; target execution required"}
    for path, info in libraries.items():
        report["libraries"][path] = {k: v for k, v in info.items()
                                     if k not in ("imports", "exports")}
    for path in args.program:
        info = inspect(path)
        missing = sorted(info["imports"] - exports)
        unknown_libraries = sorted(set(info["needed"]) - sonames)
        interpreter = None if args.shared else "/usr/lib/ldqnx.so.2"
        passed = not missing and not unknown_libraries and info["interpreter"] == interpreter
        report["passed"] &= passed
        report["programs"][str(path)] = {
            **{k: v for k, v in info.items() if k not in ("imports", "exports")},
            "required_symbols": len(info["imports"]), "missing_symbols": missing,
            "missing_libraries": unknown_libraries, "passed": passed,
        }
    result = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(result)
    print(result)
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
