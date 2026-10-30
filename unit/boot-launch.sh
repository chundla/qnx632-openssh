#!/bin/ksh
# Called in the background by lsd.sh. Never wait on the HMI startup path.
trap '' 1
umask 077
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
[ ! -e /mnt/efs-persist/openssh.disabled ] || exit 0
sleep 30
attempt=0
while [ "$attempt" -lt 60 ]; do
    [ ! -e /mnt/efs-persist/openssh.disabled ] || exit 0
    if [ -f /mnt/persistence/openssh/INSTALL_READY ] &&
       ifconfig uap0 2>/dev/null | grep -q 'inet 192.168.1.1 '; then
        exec /bin/ksh /mnt/persistence/openssh/start.sh
    fi
    sleep 2
    attempt=$((attempt + 1))
done
echo 'OpenSSH skipped: HDD installation or Wi-Fi unavailable after startup wait.'
