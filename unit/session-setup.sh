#!/bin/ksh
# Prepare only a temporary account overlay and compiled-path mapping.
# All payload files must already be in the existing RAM filesystem.
set -e
umask 077
root=/fs/tmpfs/mmi-ssh
passwd_source=/mnt/efs-system/etc/passwd
group_source=/mnt/efs-system/etc/group
passwd_ram=/dev/shmem/mmi-ssh.passwd
group_ram=/dev/shmem/mmi-ssh.group
changed=0
created=0

fail() { echo "SSH setup: $*" >&2; exit 1; }
fingerprint() { set -- $(cksum "$1"); echo "$1 $2"; }
rollback() {
    if [ "$changed" = 1 ]; then
        ln -sfP "$passwd_source" /etc/passwd
        ln -sfP "$group_source" /etc/group
    fi
    if [ "$created" = 1 ]; then
        rm -f "$passwd_ram" "$group_ram"
    fi
}
trap 'rollback' 0
[ "$(uname -s)" = QNX ] || fail "Run on the MMI."
[ -x "$root/sbin/sshd" ] || fail "RAM payload is missing."
[ -f "$root/etc/ssh_host_ed25519_key" ] || fail "Host key is missing."
[ -f "$root/etc/authorized_keys" ] || fail "Authorized key is missing."
[ ! -e /mnt/ssh ] || fail "/mnt/ssh is already in use."
[ ! -e "$passwd_ram" ] || fail "An earlier SSH account overlay exists."
[ ! -e "$group_ram" ] || fail "An earlier SSH group overlay exists."
passwd_before=$(fingerprint "$passwd_source")
group_before=$(fingerprint "$group_source")
[ "$(fingerprint /etc/passwd)" = "$passwd_before" ] || fail "Unknown passwd override."
[ "$(fingerprint /etc/group)" = "$group_before" ] || fail "Unknown group override."
while IFS=: read -r name secret uid gid remaining; do
    [ "$name" != sshd ] || fail "sshd account already exists."
    [ "$uid" != 15 ] || fail "UID 15 is already in use."
done < /etc/passwd
while IFS=: read -r name secret gid members; do
    [ "$name" != sshd ] || fail "sshd group already exists."
    [ "$gid" != 15 ] || fail "GID 15 is already in use."
done < /etc/group
[ -d "$root/empty" ] || mkdir "$root/empty"
chmod 755 "$root/empty"
chmod 600 "$root/etc/ssh_host_ed25519_key" "$root/etc/authorized_keys"
created=1
# StrictModes stops checking ancestors at the user's home. The shared RAM
# filesystem's parent is writable, so use our private directory as root's
# temporary home rather than weakening key checks or changing shared modes.
sed 's|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:|\1/fs/tmpfs/mmi-ssh:|' "$passwd_source" > "$passwd_ram"
echo '' >> "$passwd_ram"
echo 'sshd:*:15:15:OpenSSH privilege separation:/mnt/ssh/empty:/bin/ksh' >> "$passwd_ram"
cat "$group_source" > "$group_ram"
echo '' >> "$group_ram"
echo 'sshd:*:15:' >> "$group_ram"
chmod 600 "$passwd_ram" "$group_ram"
changed=1
ln -sfP "$group_ram" /etc/group
ln -sfP "$passwd_ram" /etc/passwd
[ "$(fingerprint /etc/passwd)" = "$(fingerprint "$passwd_ram")" ] || fail "Passwd mapping failed."
[ "$(fingerprint /etc/group)" = "$(fingerprint "$group_ram")" ] || fail "Group mapping failed."
[ "$(fingerprint "$passwd_source")" = "$passwd_before" ] || fail "Stored passwd changed."
[ "$(fingerprint "$group_source")" = "$group_before" ] || fail "Stored group changed."
ln -sP "$root" /mnt/ssh
changed=0
trap - 0
echo "SSH account and group are mapped to RAM. Stored account files are unchanged."
echo "The /mnt/ssh prefix points to $root. Reboot clears this session setup."
