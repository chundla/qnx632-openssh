#!/bin/sh
# Build experimental local-entropy probes; no connection or deployment.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OPENSSH_WORK=${OPENSSH_WORK:-"$REPO/work"}
QNX_SDK_ROOT=${QNX_SDK_ROOT:-"$OPENSSH_WORK/sdk"}
QNX_HOST="$QNX_SDK_ROOT/host/linux/x86"
QNX_TARGET="$QNX_SDK_ROOT/target/qnx6"
export QNX_HOST QNX_TARGET
TARGET=sh-unknown-nto-qnx6.3.0
CC="$QNX_HOST/usr/bin/$TARGET-gcc"
SOURCE="$OPENSSH_WORK/work/jitterentropy-library-3.7.0"
BUILD="$OPENSSH_WORK/jitter-build"
test "$(git -C "$SOURCE" rev-parse HEAD)" = e783cf1c450bce4d72f95c9f9c84546a6094976a
# The adapter changes only the platform timer, never the noise/crypto/health code.
git -C "$SOURCE" diff --exit-code -- src jitterentropy.h >/dev/null
if patch -d "$SOURCE" -p1 --forward --dry-run < "$REPO/patches/jitterentropy-qnx632.patch" >/dev/null 2>&1; then
    patch -d "$SOURCE" -p1 < "$REPO/patches/jitterentropy-qnx632.patch"
else
    patch -d "$SOURCE" -p1 --reverse --dry-run < "$REPO/patches/jitterentropy-qnx632.patch" >/dev/null
fi
mkdir -p "$BUILD"
# -O0 is a security requirement of upstream's noise collection code.
# No internal timer thread: this head unit has one CPU.
for source in "$SOURCE"/src/*.c; do
    object="$BUILD/$(basename "${source%.c}").o"
    "$CC" -ml -m4 -O0 -std=gnu99 -Wall -W \
        -I"$SOURCE" -I"$SOURCE/src" -I"$REPO/src" -c "$source" -o "$object"
done
"$CC" -ml -m4 -O0 -std=gnu99 -Wall -W -I"$SOURCE" -I"$REPO/src" \
    "$REPO/src/jitter-probe.c" "$BUILD"/*.o -o "$BUILD/jitter-probe"
"$CC" -ml -m4 -O0 -std=gnu99 -Wall -W -I"$SOURCE" -I"$SOURCE/src" -I"$REPO/src" \
    "$REPO/src/jitter-raw.c" "$BUILD"/*.o -o "$BUILD/jitter-raw"
"$CC" -ml -m4 -O0 -std=gnu99 -Wall -W -I"$SOURCE" -I"$REPO/src" \
    "$REPO/src/jitter-egd.c" "$BUILD"/*.o -lsocket -o "$BUILD/jitter-egd"
"$CC" -ml -m4 -O0 -std=gnu99 -Wall -W \
    "$REPO/src/timer-probe.c" -o "$BUILD/timer-probe"
"$CC" -ml -m4 -O0 -std=gnu99 -Wall -W \
    "$REPO/src/egd-probe.c" -lsocket -o "$BUILD/egd-probe"
"$QNX_HOST/usr/bin/$TARGET-strip" "$BUILD/jitter-probe" "$BUILD/timer-probe" \
    "$BUILD/jitter-raw" "$BUILD/jitter-egd" "$BUILD/egd-probe"
sha256sum "$BUILD/jitter-probe" "$BUILD/timer-probe" "$BUILD/jitter-raw" \
    "$BUILD/jitter-egd" "$BUILD/egd-probe"

PACKAGE="$OPENSSH_WORK/jitter-package/jitterentropy"
mkdir -p "$PACKAGE/bin" "$OPENSSH_WORK/dist"
chmod 755 "$PACKAGE" "$PACKAGE/bin"
install -m 755 "$BUILD/jitter-egd" "$PACKAGE/bin/jitter-egd"
install -m 644 "$SOURCE/LICENSE.bsd" "$PACKAGE/LICENSE.bsd"
install -m 644 "$REPO/docs/randomness.md" "$PACKAGE/README.md"
python3 - "$REPO" "$SOURCE" "$PACKAGE" "$CC" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
task, source, package = map(Path, sys.argv[1:4])
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {
    "status": "experimental; no boot installer",
    "source": "https://github.com/smuellerDD/jitterentropy-library",
    "tag": "v3.7.0",
    "commit": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
    "compiler": subprocess.check_output([sys.argv[4], "--version"], text=True).splitlines()[0],
    "flags": "-ml -m4 -O0 -std=gnu99 -Wall -W; no internal timer thread",
    "timer_patch_sha256": sha(task / "patches/jitterentropy-qnx632.patch"),
    "timer_adapter_sha256": sha(task / "src/qnx-jitter-timer.h"),
    "egd_adapter_sha256": sha(task / "src/jitter-egd.c"),
    "binary_sha256": sha(package / "bin/jitter-egd"),
    "osr": 3, "continuous_health_tests": True,
    "persistent_seed": False,
}
(package / "BUILD.json").write_text(json.dumps(manifest, indent=2) + "\n")
(package / "SHA256SUMS").write_text("".join(
    f"{sha(p)}  {p.relative_to(package)}\n" for p in sorted(package.rglob("*"))
    if p.is_file() and p.name != "SHA256SUMS"))
PY
tar --sort=name --mtime=@1791280023 --owner=0 --group=0 --numeric-owner \
    -C "$OPENSSH_WORK/jitter-package" \
    -czf "$OPENSSH_WORK/dist/jitterentropy-3.7.0-qnx632-shle-experimental.tar.gz" jitterentropy
sha256sum "$OPENSSH_WORK/dist/jitterentropy-3.7.0-qnx632-shle-experimental.tar.gz"
