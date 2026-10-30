#!/bin/ksh
# Installed on the MMI HDD. Account overlays and logs stay in RAM.
set -eu
umask 077
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
# The factory boot environment preloads libmc.so, which creates a second
# thread. QNX 6.3.2 cannot fork a multithreaded SSH process. Keep that
# instrumentation out of both services and every SSH session helper.
unset LD_PRELOAD || :
LD_LIBRARY_PATH=/lib:/lib/dll:/usr/lib:/usr/lib/dll:/proc/boot
export LD_LIBRARY_PATH
root=/mnt/persistence/openssh
state=/fs/tmpfs/mmi-openssh
passwd_source=/mnt/efs-system/etc/passwd
group_source=/mnt/efs-system/etc/group
mapped=0
entropy_pid=
sshd_pid=
fail() { echo "OpenSSH startup: $*" >&2; exit 1; }
owned_pid() {
    [ -f "$1" ] || return 1
    read -r checked_pid < "$1"
    case "$checked_pid" in ''|*[!0-9]*) return 1;; esac
    kill -0 "$checked_pid" 2>/dev/null &&
        pidin -p "$checked_pid" ar 2>/dev/null | grep -q "$2"
}
[ ! -e /mnt/efs-persist/openssh.disabled ] || exit 0
[ "$(uname -s)" = QNX ] || fail "Run on the MMI."
[ -f "$root/INSTALL_READY" ] || fail "Installation is incomplete."
[ -d "$state" ] || mkdir "$state"
chmod 700 "$state"
if owned_pid "$state/sshd.pid" '/mnt/ssh/sbin/sshd' &&
   owned_pid "$state/entropy.pid" '/mnt/ssh/bin/jitter-egd'; then
    echo "OpenSSH is already running."
    exit 0
fi
if owned_pid "$state/sshd.pid" '/mnt/ssh/sbin/sshd' ||
   owned_pid "$state/entropy.pid" '/mnt/ssh/bin/jitter-egd'; then
    fail "A partial service is still running; inspect its RAM logs before restarting."
fi
mkdir "$state/start.lock" 2>/dev/null || fail "Another startup is active."
cleanup() {
    result=$?
    trap - 0
    if [ "$result" != 0 ]; then
        [ -z "$sshd_pid" ] || kill "$sshd_pid" 2>/dev/null || :
        [ -z "$entropy_pid" ] || kill "$entropy_pid" 2>/dev/null || :
        if [ "$mapped" = 1 ]; then
            ln -sfP "$passwd_source" /etc/passwd
            ln -sfP "$group_source" /etc/group
        fi
        rm -f "$state/sshd.pid" "$state/entropy.pid"
    fi
    rm -rf "$state/start.lock"
    exit "$result"
}
trap cleanup 0
for file in sbin/sshd libexec/sshd-auth libexec/sshd-session bin/jitter-egd; do
    [ -x "$root/$file" ] || fail "Missing executable: $file"
done
[ -s "$root/etc/ssh_host_ed25519_key" ] || fail "Missing host key."
[ -s "$root/etc/authorized_keys" ] || fail "Missing authorized key."
# Refuse account collisions instead of rewriting an existing user/group.
while IFS=: read -r name secret uid gid remaining; do
    [ "$name" != sshd ] && [ "$uid" != 15 ] || fail "Stored UID/name collision."
done < "$passwd_source"
while IFS=: read -r name secret gid remaining; do
    [ "$name" != sshd ] && [ "$gid" != 15 ] || fail "Stored GID/name collision."
done < "$group_source"
sed 's|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:|\1/mnt/persistence/openssh:|' "$passwd_source" > "$state/passwd"
echo '' >> "$state/passwd"
echo 'sshd:*:15:15:OpenSSH privilege separation:/mnt/ssh/empty:/bin/ksh' >> "$state/passwd"
cat "$group_source" > "$state/group"
echo '' >> "$state/group"
echo 'sshd:*:15:' >> "$state/group"
chmod 600 "$state/passwd" "$state/group"
[ ! -e /mnt/ssh ] || [ -x /mnt/ssh/sbin/sshd ] || fail "Unknown /mnt/ssh mapping."
ln -sfP "$root" /mnt/ssh
mapped=1
ln -sfP "$state/group" /etc/group
ln -sfP "$state/passwd" /etc/passwd
(trap '' 1; exec /mnt/ssh/bin/jitter-egd 708 > "$state/entropy.log" 2>&1) &
entropy_pid=$!
echo "$entropy_pid" > "$state/entropy.pid"
attempt=0
until grep -q '^JITTER_EGD_READY ' "$state/entropy.log"; do
    kill -0 "$entropy_pid" 2>/dev/null || fail "Entropy startup failed; see $state/entropy.log."
    [ "$attempt" -lt 65 ] || fail "Entropy startup timed out."
    sleep 1
    attempt=$((attempt + 1))
done
/mnt/ssh/sbin/sshd -t -f /mnt/ssh/etc/sshd_config
(trap '' 1; exec /mnt/ssh/sbin/sshd -D -e -f /mnt/ssh/etc/sshd_config > "$state/sshd.log" 2>&1) &
sshd_pid=$!
echo "$sshd_pid" > "$state/sshd.pid"
sleep 2
kill -0 "$sshd_pid" 2>/dev/null || fail "SSH startup failed; see $state/sshd.log."
/bin/ksh "$root/firewall.sh" enable
echo "OpenSSH ready on 192.168.1.1:2222; entropy PID $entropy_pid; SSH PID $sshd_pid."
