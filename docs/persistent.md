# Persistent OpenSSH on the test unit

The owner chose to proceed with the runtime randomness assessment already
completed, without the proposed extended boot/environment test campaign.
This is a hardware-specific installation for QNX 6.3.2 HB_SH7785 and the
Pi at `192.168.1.109`. It does not establish formal entropy certification.

## Installed layout

- `/mnt/persistence/openssh`: private root-owned HDD directory containing
  `sshd`, `sshd-auth`, `sshd-session`, `jitter-egd`, configuration, stable
  Ed25519 host key, authorized public key, licenses, startup scripts and backups.
  No SDK, seed file, external entropy pool or diagnostic sample is installed.
- `/mnt/ssh`: QNX process-manager alias pointing to that HDD directory.
- `/fs/tmpfs/mmi-openssh`: private RAM directory for account overlays, PID
  files, startup lock and logs. QNX's `/dev/shmem` accepts files but does not
  support the directory creation needed here.
- `/mnt/efs-persist/openssh-start.sh`: small background launcher.
- `/mnt/efs-persist/openssh-rollback.sh`: restore the original startup/firewall files.
- `/mnt/efs-system/lsd/lsd.sh`: five-line marked hook immediately after the
  shebang launches the background helper before the original script continues.
- `/mnt/efs-system/scripts/Connectivity/pf.conf`: one added filter rule,
  labeled `mmi_openssh_pi`, allowing only `192.168.1.109` to SSH port 2222
  on `192.168.1.1` through `uap0`. No persistent Telnet exception is added.

Both modified factory files have adjacent `.pre-openssh` backups, copies on
the HDD under `backup/`, and copies kept by the author off the unit. Their
original POSIX checksums on the test unit are:

| File | Checksum | Bytes |
| --- | ---: | ---: |
| `lsd.sh` | 2252741285 | 11676 |
| `pf.conf` | 3554363799 | 2832 |

Stored passwd/group files are unchanged. Each launch builds a RAM copy of
those files, adds locked UID/GID 15 for privilege separation, and gives root
the private install directory as its home so key permission checks succeed.
Password login and forwarding remain disabled. Host identity and authorized
key are the same as in the tested RAM installation.

On 2026-10-30 a second public key, for the owner's phone SSH client, was
appended to `/mnt/persistence/openssh/etc/authorized_keys` for the
[Wi-Fi station's 7.3 run](https://github.com/chundla/mmi3g-wifi-sta/blob/main/docs/wifi-client-mode.md#phase-73-results), with the original kept
beside it on the HDD. The file stayed mode 600. Both `sshd` instances and
the station's read it.

## Startup behavior

The hook launches a separate background process; HMI startup does not wait
for storage, networking or entropy. The launcher waits 30 seconds, then
allows up to 120 seconds for the HDD installation and `uap0` address to
appear. Missing prerequisites cause it to exit without starting SSH.

The HDD script clears inherited `LD_PRELOAD`, sets a fixed library search path, checks required executables
and account collisions, creates the RAM overlays and starts Jitterentropy
at its existing priority 1. It waits for successful entropy initialization
before validating and starting SSH. It adds the same Pi-only rule to the
live filter rules without reloading NAT or flushing states.

Initialization/read health failures do not cause weaker fallback or an
automatic retry loop. A subsequent manual launch refuses a partially running
service so its logs can be inspected first. Repeating a launch with both
owned service PIDs alive returns successfully without starting duplicates.
Startup failure stops the new processes and restores the factory account
mappings. Logs stay in RAM.

## Access and recovery

The author connects with a dedicated client key and the pinned host key,
through the Pi on the car's Wi-Fi (`ssh -J`). The filter rule admits only
`192.168.1.109`. On 2026-10-23 the Pi also held `192.168.1.110` on the
car's Wi-Fi and routed from it, so every connection timed out during the
banner exchange. Relaying through `nc -s 192.168.1.109` on the Pi
(an SSH `ProxyCommand`) instead of `ssh -J` connected. Throughput through
that relay was about 2 KB/s.

A USB Ethernet path (`en5`) reaches a second `sshd` directly, with no Pi
in between. It measured about 149 KB/s and, unlike the Wi-Fi path, it
survives the access point being switched off. Both instances share the
host key and authorized keys. See
[en5 established](https://github.com/chundla/mmi3g-wifi-sta/blob/main/docs/wifi-client-mode.md#en5-established) for the interface itself and the
`pf` exposure that comes with it; its start-up script is in the
[Wi-Fi station repository](https://github.com/chundla/mmi3g-wifi-sta).

To suppress subsequent launches, from an MMI root shell:

```sh
echo disabled > /mnt/efs-persist/openssh.disabled
```

This does not terminate a running SSH session. Remove that marker to permit
startup again. To restore the original startup and firewall files:

```sh
/bin/ksh /mnt/efs-persist/openssh-rollback.sh
```

Reboot afterward to clear running processes, RAM account mappings and live
filter exceptions. The private HDD payload is retained for recovery. The
rollback script itself does not reboot the MMI or interrupt the active shell.

Inspect running-service logs with:

```sh
cat /fs/tmpfs/mmi-openssh/entropy.log
cat /fs/tmpfs/mmi-openssh/sshd.log
cat /dev/shmem/mmi-openssh-boot.log
```

## Validation boundary

The reviewed originals were downloaded before changing flash. All four
server binaries and both key files matched the prior tested artifacts by
POSIX checksum and size. The MMI's own ksh and PF parser validated the
new scripts/configuration. The disabled marker was exercised against both
entry points before activation.

The HDD partition had 165,773 KiB free before installation and 162,515 KiB
free afterward: 3,258 KiB (3.18 MiB) used, with **158.71 MiB free**. System
flash usage increased by 16 KiB for the hook, filter change and backups.
The original RAM test payload was cleared by the subsequently observed reboot.

A supervised clean service restart succeeded, duplicate startup returned
without starting another process, and the installed background launcher
completed its 30-second wait and recognized the running services.
Fresh SSH login used the existing pinned host identity and the persistent
root home. Terminal allocation passed, and a 4 KiB SFTP upload/download
matched SHA-256 `061f9ab6cbb33488170deeb4be31cb545e22e4bc4a51398668d7b23001ac302c`.
The ignored local installation evidence records these results alongside
source/target checksums. The superseded RAM-test SSH firewall exception was
removed after the persistent Pi-only exception was active.

A forced reboot on 2026-10-18 reset QNX uptime and cleared the old RAM test
payload. The boot hook automatically started Jitterentropy and the SSH
listener, but client connections failed with `fork: Function not implemented`.
The boot environment supplied `LD_PRELOAD=/usr/lib/libmc.so`; the running
SSH process had an extra `libmc_RM_Thread` and a `/dev/memstat/sshd` connection.
QNX documents both multithreading and nonduplicable descriptors as causes of
this error in [SDP 6.3.2](https://www.qnx.com/support/knowledgebase.html?id=50130000000SpVx).
The startup script now clears that preload before launching either service.
The original script is retained on the HDD as `start.sh.pre-bootfix`.

After the correction, a supervised service restart deliberately invoked the
script with `LD_PRELOAD=/usr/lib/libmc.so`. Both services had one thread, and
the SSH process mapped only its expected libc/socket libraries. Fresh public-key
login, terminal allocation, and the same 4 KiB SFTP round trip passed.
Repeated startup also succeeded with the preload present and absent. The unset
operation tolerates this ksh returning failure when the variable is already
absent under `set -e`. Stored account checksums remained unchanged.
The final installed script's POSIX checksum/size is `3430974729 4126`.
The author keeps the evidence privately.

The owner forced another reboot on 2026-10-18. At the first successful SSH
check, QNX uptime was 1 minute 52 seconds. The new RAM boot log reported
automatic startup with entropy PID 540715 and SSH PID 725065; both processes
had one thread, and the installed startup script matched the checksum above.
The entropy log reported readiness with health tests enabled. Public-key
command login with the existing pinned host key, terminal allocation, and the
same 4 KiB SFTP round trip all passed. No service was launched manually during
this check. The live firewall contained the persistent Pi-only SSH rule and
no temporary Telnet exception. This verifies automatic SSH startup after a
forced QNX reboot; it does not establish a complete power-off cold-boot test.
The author keeps the evidence privately.

## Cold-boot entropy failure

Local hardware result, 2026-10-28, after the car had been off overnight
(a full power-off, not a forced reboot). The radio, `uap0` and the `en5`
address all came up, but neither SSH server was listening more than 15
minutes later. Read through the SD-card Telnet path:

- `/dev/shmem/mmi-openssh-boot.log` reported `OpenSSH ready` with entropy
  and SSH PIDs, and `entropy.log` held only the `JITTER_EGD_READY` line.
  The RAM state was written at about 00:01 of uptime.
- Both PIDs were gone. `jitter-egd` left no failure line: not its
  initialization, collector or read/health messages.
- `sshd.log` read `Couldn't connect to PRNGD port 708: Connection refused`
  and `Couldn't open /dev/urandom`. The `en5` second `sshd` had failed its
  config test with `Couldn't read from PRNGD socket: Connection reset by
  peer`, so `jitter-egd` died while serving that request.

Neither service restarts itself, by design (see
[Startup behavior](#startup-behavior)), so access stayed down. Running the
installed `start.sh` by hand, detached, restored both `sshd`s and the
entropy service within 3 s. The firewall step found its rule already
present. The forced reboot that followed started SSH normally.

The cause is not established. The evidence fits `jitter-egd`'s own
`alarm(20)` around a read: a SIGALRM ends the process without a message,
the service runs at priority 1, and that start-up was busy (the media
database file was still being written at 16 minutes). An external SIGTERM
would also exit silently and was not ruled out. Nothing has been changed
in response; any fix is a persistent change to the HDD installation and
follows the rules above.

Extended environmental and structured restart entropy assessments were
deferred at the owner's request.
See [the randomness assessment](randomness.md) for the measured
runtime evidence and its limits.
