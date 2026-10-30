#!/bin/ksh
# Finalize an already staged and checksum-verified installation on this MMI.
# Leave startup disabled until a supervised first launch succeeds.
set -eu
umask 077
root=/mnt/persistence/openssh
startup=/mnt/efs-system/lsd/lsd.sh
firewall=/mnt/efs-system/scripts/Connectivity/pf.conf
changed=0
fail() { echo "OpenSSH install: $*" >&2; exit 1; }
[ "$(uname -s)" = QNX ] || fail "Run on the MMI."
set -- $(cksum "$startup")
[ "$1 $2" = '2252741285 11676' ] || fail "Startup file differs from the reviewed original."
set -- $(cksum "$firewall")
[ "$1 $2" = '3554363799 2832' ] || fail "Firewall file differs from the reviewed original."
for target in "$startup" "$firewall"; do
    [ ! -e "$target.pre-openssh" ] || fail "Backup already exists: $target.pre-openssh"
done
for script in start.sh boot-launch.sh rollback.sh backup/lsd.sh.installed; do
    /bin/ksh -n "$root/$script"
done
pfctl -n -f "$root/backup/pf.conf.installed"
echo disabled > /mnt/efs-persist/openssh.disabled
mount -uw /mnt/efs-system
cp -p "$startup" "$startup.pre-openssh"
cp -p "$firewall" "$firewall.pre-openssh"
cp -p "$startup" "$root/backup/lsd.sh.original"
cp -p "$firewall" "$root/backup/pf.conf.original"
rollback() {
    result=$?
    trap - 0
    if [ "$result" != 0 ] && [ "$changed" = 1 ]; then
        cp -p "$startup.pre-openssh" "$startup"
        cp -p "$firewall.pre-openssh" "$firewall"
        echo 'Install failed; original files restored and startup remains disabled.' >&2
    fi
    exit "$result"
}
trap rollback 0
cp "$root/boot-launch.sh" /mnt/efs-persist/openssh-start.sh
cp "$root/rollback.sh" /mnt/efs-persist/openssh-rollback.sh
chmod 700 /mnt/efs-persist/openssh-start.sh /mnt/efs-persist/openssh-rollback.sh
for target in "$startup" "$firewall"; do
    cp -p "$target" "$target.openssh-new"
done
cat "$root/backup/lsd.sh.installed" > "$startup.openssh-new"
cat "$root/backup/pf.conf.installed" > "$firewall.openssh-new"
/bin/ksh -n "$startup.openssh-new"
pfctl -n -f "$firewall.openssh-new"
changed=1
mv -f "$startup.openssh-new" "$startup"
mv -f "$firewall.openssh-new" "$firewall"
echo 'OpenSSH 10.6p1 + Jitterentropy 3.7.0' > "$root/INSTALL_READY"
echo 'Persistent files installed. Startup remains disabled pending supervised launch.'
