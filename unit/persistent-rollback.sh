#!/bin/ksh
# Disable future launches and restore only the two backed-up factory files.
# Reboot afterward to clear RAM account mappings and running SSH processes.
set -eu
umask 077
echo disabled > /mnt/efs-persist/openssh.disabled
startup=/mnt/efs-system/lsd/lsd.sh
firewall=/mnt/efs-system/scripts/Connectivity/pf.conf
for target in "$startup" "$firewall"; do
    [ -f "$target.pre-openssh" ] || { echo "Missing backup: $target.pre-openssh" >&2; exit 1; }
done
mount -uw /mnt/efs-system
for target in "$startup" "$firewall"; do
    cp -p "$target.pre-openssh" "$target.openssh-restore"
    mv -f "$target.openssh-restore" "$target"
done
echo 'Original startup/firewall files restored. Reboot to clear this SSH session.'
echo 'The private HDD payload remains available for recovery or later removal.'
