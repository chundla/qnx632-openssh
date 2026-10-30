#!/bin/sh
# Build only; does not connect to or modify the head unit.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OPENSSH_WORK=${OPENSSH_WORK:-"$REPO/work"}
QNX_SDK_ROOT=${QNX_SDK_ROOT:-"$OPENSSH_WORK/sdk"}
QNX_HOST="$QNX_SDK_ROOT/host/linux/x86"
QNX_TARGET="$QNX_SDK_ROOT/target/qnx6"
export QNX_HOST QNX_TARGET
TARGET=sh-unknown-nto-qnx6.3.0
CC="$QNX_HOST/usr/bin/$TARGET-gcc -ml -m4"
AR="$QNX_HOST/usr/bin/$TARGET-ar"
RANLIB="$QNX_HOST/usr/bin/$TARGET-ranlib"
STRIP="$QNX_HOST/usr/bin/$TARGET-strip"
COMPILER_PATH="$QNX_HOST/usr/$TARGET/bin"
PATH="$COMPILER_PATH:$PATH"
CFLAGS=-O2
export CC AR RANLIB COMPILER_PATH PATH CFLAGS

SOURCE_ARCHIVE="$OPENSSH_WORK/downloads/openssh-10.6p1.tar.gz"
SOURCE_DIR="$OPENSSH_WORK/work/openssh-10.6p1"
PACKAGE_ROOT="$OPENSSH_WORK/package/ssh"
mkdir -p "$OPENSSH_WORK/work" "$OPENSSH_WORK/logs" "$OPENSSH_WORK/dist"
python3 - "$SOURCE_ARCHIVE" "$OPENSSH_WORK/work" <<'PY'
import hashlib, sys, tarfile
from pathlib import Path
source, work = map(Path, sys.argv[1:])
expected = "a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39"
if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
    raise SystemExit("OpenSSH archive checksum mismatch")
if not (work / "openssh-10.6p1").exists():
    with tarfile.open(source) as archive:
        archive.extractall(work, filter="data")
PY

cd "$SOURCE_DIR"
if patch -p1 --forward --dry-run < "$REPO/patches/qnx632.patch" >/dev/null 2>&1; then
    patch -p1 < "$REPO/patches/qnx632.patch"
else
    # Refuse partial/stale patches, while allowing an incremental rebuild.
    patch -p1 --reverse --dry-run < "$REPO/patches/qnx632.patch" >/dev/null
fi

./configure --host="$TARGET" --build=x86_64-pc-linux-gnu \
    --prefix=/mnt/ssh --sysconfdir=/mnt/ssh/etc \
    --with-privsep-path=/mnt/ssh/empty --with-pid-dir=/dev/shmem \
    --with-prngd-port=708 \
    --with-default-path=/proc/boot:/bin:/usr/bin:/sbin:/usr/sbin \
    --without-openssl --without-zlib --without-pam --without-selinux \
    --without-kerberos5 --without-libedit --disable-pkcs11 \
    --disable-security-key --without-security-key-builtin \
    --without-hardening --without-stackprotect --without-retpoline \
    --without-pie --with-sandbox=no > "$OPENSSH_WORK/logs/configure.log" 2>&1

# config.sub must preserve the version so QNX 6 gets its required workaround.
grep -q '^#define DISABLE_FD_PASSING 1' config.h
make -j"${JOBS:-4}" sshd sshd-session sshd-auth ssh-keygen sftp-server \
    > "$OPENSSH_WORK/logs/make.log" 2>&1

mkdir -p "$PACKAGE_ROOT/sbin" "$PACKAGE_ROOT/bin" "$PACKAGE_ROOT/libexec" \
    "$PACKAGE_ROOT/etc" "$PACKAGE_ROOT/empty"
chmod 755 "$PACKAGE_ROOT" "$PACKAGE_ROOT/sbin" "$PACKAGE_ROOT/bin" \
    "$PACKAGE_ROOT/libexec" "$PACKAGE_ROOT/etc" "$PACKAGE_ROOT/empty"
install -m 755 sshd "$PACKAGE_ROOT/sbin/sshd"
install -m 755 sshd-session sshd-auth sftp-server "$PACKAGE_ROOT/libexec/"
install -m 755 ssh-keygen "$PACKAGE_ROOT/bin/ssh-keygen"
$CC "$REPO/src/hello.c" -o "$PACKAGE_ROOT/bin/hello-shle"
$CC "$REPO/src/entropy-pool.c" -lsocket -o "$PACKAGE_ROOT/bin/entropy-pool"
for program in "$PACKAGE_ROOT/sbin/sshd" "$PACKAGE_ROOT/bin/ssh-keygen" \
    "$PACKAGE_ROOT/bin/hello-shle" "$PACKAGE_ROOT/bin/entropy-pool" "$PACKAGE_ROOT/libexec/sshd-session" \
    "$PACKAGE_ROOT/libexec/sshd-auth" "$PACKAGE_ROOT/libexec/sftp-server"; do
    "$STRIP" "$program"
done
install -m 644 "$REPO/unit/sshd_config" "$PACKAGE_ROOT/etc/sshd_config.example"
install -m 755 "$REPO/unit/session-setup.sh" \
    "$REPO/unit/session-firewall.sh" "$PACKAGE_ROOT/"
install -m 644 LICENCE "$PACKAGE_ROOT/LICENCE"
install -m 644 "$REPO/docs/build.md" "$PACKAGE_ROOT/README.md"
python3 - "$PACKAGE_ROOT" <<'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1])
lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n"
         for p in sorted(root.rglob("*")) if p.is_file() and p.name != "SHA256SUMS"]
(root / "SHA256SUMS").write_text("".join(lines))
PY
tar --sort=name --mtime=@1791280023 --owner=0 --group=0 --numeric-owner \
    -C "$OPENSSH_WORK/package" -czf "$OPENSSH_WORK/dist/openssh-10.6p1-qnx632-shle.tar.gz" ssh
sha256sum "$OPENSSH_WORK/dist/openssh-10.6p1-qnx632-shle.tar.gz"
