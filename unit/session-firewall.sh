#!/bin/ksh
# Allow only the Pi address observed in this test session. Filter rules only.
set -e
umask 077
runtime=/dev/shmem/mmi-ssh.pf
label=mmi_temp_ssh
mode=${1:-enable}
pfctl -sr > "${runtime}.current"
if [ "$mode" = disable ]; then
    sed '/label "mmi_temp_ssh"/d' "${runtime}.current" > "${runtime}.next"
elif [ "$mode" = enable ]; then
    if grep -q 'label "mmi_temp_ssh"' "${runtime}.current"; then
        echo "The temporary SSH filter rule already exists."
        exit 0
    fi
    [ "$(grep -c '^pass out ' "${runtime}.current")" = 1 ]
    sed '/^pass out /i\
pass in quick on uap0 inet proto tcp from 192.168.1.109 to 192.168.1.1 port = 2222 flags S/SA keep state label "mmi_temp_ssh"
' "${runtime}.current" > "${runtime}.next"
else
    echo "Usage: session-firewall.sh enable|disable" >&2
    exit 1
fi
pfctl -n -R -f "${runtime}.current"
pfctl -n -R -f "${runtime}.next"
if ! pfctl -R -f "${runtime}.next"; then
    pfctl -R -f "${runtime}.current"
    exit 1
fi
if ! pfctl -sr > "${runtime}.verified"; then
    pfctl -R -f "${runtime}.current"
    exit 1
fi
if [ "$mode" = enable ]; then
    if ! grep -q 'label "mmi_temp_ssh"' "${runtime}.verified"; then
        pfctl -R -f "${runtime}.current"
        exit 1
    fi
    echo "Temporary SSH access is limited to the Pi at 192.168.1.109."
else
    if grep -q 'label "mmi_temp_ssh"' "${runtime}.verified"; then
        pfctl -R -f "${runtime}.current"
        exit 1
    fi
    echo "Temporary SSH filter rule removed. Existing connections may remain."
fi
