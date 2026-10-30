#!/usr/bin/env python3
"""Extract the SHLE build subset from the QNX 6.3.2 Linux setup JAR.

This reads the installer archive; it does not run the installer or extracted
executables. No QNX files are distributed with this script. Optional loader
adjustments let the old 32-bit Linux tools use a private Linux runtime.
"""

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import struct
import subprocess
from zipfile import ZipFile
import zlib


JAR_SHA256 = "9b0de18479d53c9aaa00dc297a9a902261ea99775057a6bee6e4c9fe45c3efa0"
TARGET = "sh-unknown-nto-qnx6.3.0"
TOOLS = ("as", "ld", "ar", "ranlib", "strip", "objcopy", "objdump",
         "nm", "size", "readelf", "strings")


def entries(archive, base):
    data = archive.read(base + "/index")
    version, chunks = struct.unpack_from(">II", data)
    if version != 1000:
        raise ValueError("Unsupported installer index version")
    offset, expected_index = 8, 0
    for _ in range(chunks):
        size = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        block = zlib.decompress(data[offset:offset + size])
        offset += size
        count = struct.unpack_from(">I", block)[0]
        cursor = 4
        for _ in range(count):
            index = struct.unpack_from(">I", block, cursor)[0]
            digest = block[cursor + 4:cursor + 20].hex()
            length = struct.unpack_from(">H", block, cursor + 20)[0]
            name = block[cursor + 22:cursor + 22 + length].decode()
            cursor += 22 + length
            metadata = block[cursor:cursor + 45]
            cursor += 45
            if index != expected_index or len(metadata) != 45:
                raise ValueError("Invalid installer index record")
            expected_index += 1
            yield name, digest, metadata
        if cursor != len(block):
            raise ValueError("Unexpected installer index trailer")
    if offset != len(data):
        raise ValueError("Unexpected installer archive trailer")


def link_if_missing(path, target):
    if not path.exists() and not path.is_symlink():
        path.symlink_to(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("setup_jar", type=Path)
    parser.add_argument("destination", type=Path, help="New SDK directory")
    parser.add_argument("--loader", type=Path, help="Private Linux ld-linux.so.2")
    parser.add_argument("--patchelf", type=Path)
    args = parser.parse_args()
    if bool(args.loader) != bool(args.patchelf):
        parser.error("--loader and --patchelf must be supplied together")
    if hashlib.sha256(args.setup_jar.read_bytes()).hexdigest() != JAR_SHA256:
        parser.error("Archive SHA-256 differs from the examined 200709062316 media")
    args.destination = args.destination.resolve()
    args.destination.mkdir(parents=True, exist_ok=False)
    count = 0
    with ZipFile(args.setup_jar) as archive:
        base = next(n for n in archive.namelist() if n.endswith("/index")).rsplit("/", 1)[0]
        for name, digest, metadata in entries(archive, base):
            if not name.startswith(("host/linux/x86/", "target/qnx6/usr/include/",
                                    "target/qnx6/shle/")):
                continue
            relative = PurePosixPath(name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Unsafe archive path")
            path = args.destination / name
            flags = int.from_bytes(metadata[22:26], "big")
            if flags & 0x1000:
                path.mkdir(parents=True, exist_ok=True)
                continue
            data = archive.read(base + "/md5/" + digest)
            data = zlib.decompress(data) if data else b""
            if (hashlib.md5(data).hexdigest() != digest or
                    len(data) != int.from_bytes(metadata[4:12], "big")):
                raise ValueError(f"Installer content verification failed: {name}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(0o755 if flags & 0x100 else 0o644)
            count += 1

    host = args.destination / "host/linux/x86"
    programs = host / "usr/bin"
    for tool in TOOLS:
        multi = programs / ("ntomulti-" + tool)
        named = programs / (TARGET + "-" + tool)
        if multi.exists():
            link_if_missing(named, multi.name)
        if named.exists():
            link_if_missing(programs / ("ntosh-" + tool), named.name)
            directory = host / "usr" / TARGET / "bin"
            directory.mkdir(parents=True, exist_ok=True)
            link_if_missing(directory / tool, named)

    # The installer normally creates unversioned library links separately.
    for directory in ("lib", "usr/lib"):
        parent = args.destination / "target/qnx6/shle" / directory
        for library in sorted(parent.glob("*.so.*")):
            link_if_missing(library.with_name(library.name.split(".so.")[0] + ".so"),
                            library.name)

    if args.loader:
        loader = args.loader.resolve()
        # Only adjust Linux compiler/binutils hosts, never QNX target binaries.
        candidates = list(programs.glob(TARGET + "-*"))
        candidates += list(programs.glob("ntomulti-*"))
        candidates += list((host / "usr/lib/gcc-lib" / TARGET / "3.3.5").glob("*"))
        for path in candidates:
            if not path.is_file() or path.is_symlink():
                continue
            header = path.read_bytes()[:20]
            if header[:5] == b"\x7fELF\x01" and header[16:18] == b"\x02\x00":
                subprocess.run([str(args.patchelf.resolve()), "--set-interpreter",
                                str(loader), "--set-rpath", str(loader.parent),
                                str(path)], check=True)
    print(f"Extracted and verified {count} files into {args.destination}")


if __name__ == "__main__":
    main()
