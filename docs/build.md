# OpenSSH build

OpenSSH 10.6p1 was tested on the author's MMI 3G Plus (9411,
HN+R_US_AU_K0942_3, MU 1038), QNX 6.3.2, HB_SH7785 / SHLE. On 2026-10-18,
public-key command execution, PTY allocation, and a 4 KiB SFTP
upload/download were verified through a Raspberry Pi on the car's Wi-Fi.
The transferred file's SHA-256 matched after the round trip.

**Current status:** SSH is installed on persistent HDD storage with a
background startup hook. See [installation, validation and rollback](persistent.md).
Automatic startup after an owner-forced reboot is verified: public-key login,
terminal allocation and a 4 KiB SFTP round trip passed. The startup script clears
inherited memory-checker instrumentation that prevented SSH from forking on
the first boot test.

The original temporary test session described below kept binaries, host key,
authorized key, logs and entropy service in the existing `/fs/tmpfs` filesystem.
The initial finite-pool helper was subsequently replaced in RAM by a native
Jitterentropy service after its runtime assessment; see
[Local randomness for MMI OpenSSH](randomness.md).
The account/group overlays and `/mnt/ssh` alias are process-manager mappings.
Checksums of the stored passwd, group, and shadow files match the original
backup. A reboot cleared that original setup; it had no startup hook or flash install.

The author connected with a dedicated Ed25519 client key and a pinned host
key, using the Pi as an SSH jump host (`ssh -J`). The temporary firewall
exception allows only the Pi's observed source address, `192.168.1.109`, to
TCP 2222.

The earlier SD smoke test also passed: `hello-shle` printed
`MMI SHLE toolchain test: QNX 6.3.2 HB_SH7785` and exited with status 0.
The MMI has no stock random service on PATH, no random device nodes, and no
stored `sshd` account. Those requirements are handled for this session below.

## Package

The generated archive is
`work/dist/openssh-10.6p1-qnx632-shle.tar.gz`. It contains:

- `ssh/sbin/sshd`
- `ssh/libexec/sshd-session` and `sshd-auth`, both required by this release
- `ssh/libexec/sftp-server` (the example configuration uses internal SFTP)
- `ssh/bin/ssh-keygen`, `hello-shle`, and `entropy-pool`
- `ssh/session-setup.sh` and `session-firewall.sh` for the temporary test setup
- `ssh/etc/sshd_config.example`, this document, and the upstream license

The binaries link only to `libc.so.2` and `libsocket.so.2`. The accompanying
`verify_elf.py` check reads dynamic symbols directly, including the captured
IFS libc whose symbol section headers have been removed. A successful check
means every required symbol is available in the supplied MMI libraries;
the separately recorded hardware tests establish the tested login and transfer behavior.

This first build uses OpenSSH's internal cryptography, with no external
OpenSSL/libcrypto or compression dependency. Upstream labels this build mode
experimental. Use Ed25519 host and login keys; RSA/ECDSA and AES are not
provided by this build. The available internal algorithms include
Curve25519 and ChaCha20-Poly1305. PAM, FIDO, and PKCS#11 are disabled.
The old toolchain cannot provide modern PIE/stack-protector hardening, and
this QNX build has no additional privilege-separation sandbox. OpenSSH's
privilege-separation account/chroot mechanism remains enabled.

## Source verification and patches

The source came from the official OpenBSD mirror. Its detached PGP signature
was verified with fingerprint
`7168B983815A5EEF59A4ADFD2A3F414E736060BA`, matching the key documented by
[OpenSSH Portable](https://www.openssh.org/portable.html).

SHA-256 of `openssh-10.6p1.tar.gz`:
`a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39`.

`patches/qnx632.patch` makes four small changes:

1. Preserve the Neutrino version in `config.sub`. Otherwise it silently
   canonicalizes the target to `sh-unknown-nto-qnx` and misses the QNX 6
   file-descriptor-passing workaround.
2. Include the shadow-password declaration in `platform.c`.
3. Include QNX's `unix.h` declaration of `openpty` in `sshpty.c`.
4. Backport the upstream correction in the `SKIP_PRIVDROP` remote-forwarding
   check, using the requested forwarding port instead of an undefined
   variable. This matches the condition in
   [upstream channels.c](https://github.com/openssh/openssh-portable/blob/master/channels.c).

The example config disables forwarding and permits public-key login as root
on `192.168.1.1:2222`. It does not enable a listener by itself. It contains
no host private key or authorized login key.

## Reproduce the build

Build inputs and outputs belong in the ignored `work/` directory. No QNX SDK
or vendor runtime library is committed to this repository or included in the
deployment package.

The QNX media used was `6.3.2-linux-200709062316.iso`, obtained from the
fsck.technology software archive. This third-party archive has no publisher
signature verified here. Its installer JAR passes the media's POSIX checksum
(`714202238 520702728`), and each extracted file is checked against the
installer index's MD5 and length. These detect corruption, not publisher
authenticity.

SHA-256 values of the examined media:

```text
6b667a8dacff27faf95de9eff5341266b5b4d151333d0777247b7517b0e6d038  6.3.2-linux-200709062316.iso
9b0de18479d53c9aaa00dc297a9a902261ea99775057a6bee6e4c9fe45c3efa0  qnx_linux_setup.jar
```

For the archived JAR, extract the SDK subset with:

```sh
python3 extract_qnx632.py /path/to/qnx_linux_setup.jar work/sdk
```

On a Linux host lacking the 32-bit loader, the optional `--loader` and
`--patchelf` arguments adjust only Linux host tools to use a private runtime.
The current workspace uses the Ubuntu `libc6-i386` and `patchelf` packages,
extracted with `dpkg-deb -x` under `work/linux-runtime/`. No system
packages were installed. For this layout, add:

```sh
--loader "$PWD/work/linux-runtime/usr/lib32/ld-linux.so.2" \
--patchelf "$PWD/work/linux-runtime/usr/bin/patchelf"
```

Place the verified OpenSSH tarball at
`work/downloads/openssh-10.6p1.tar.gz`, then run:

```sh
sh build.sh
```

The script checks the source SHA-256, applies the patch, configures and builds
the server components, strips them, and writes the archive. It does not run
target executables. Logs are under `work/logs/`; the compiler target,
prefix, and options are recorded in the build's `config.log` and Makefile.
Set `QNX_SDK_ROOT` to use another extracted SDK and `JOBS` to change parallelism.
The SDK and workspace paths must not contain spaces. In an environment whose
sandbox blocks 32-bit Linux syscalls, compilation requires execution outside
that sandbox.

Validate the package against libraries from the actual head unit:

```sh
python3 verify_elf.py \
  --library /path/to/mmi/libc.so.2 \
  --library /path/to/mmi/libsocket.so.2 \
  --output work/elf-verification.json \
  work/package/ssh/sbin/sshd \
  work/package/ssh/libexec/sshd-session \
  work/package/ssh/libexec/sshd-auth \
  work/package/ssh/libexec/sftp-server \
  work/package/ssh/bin/ssh-keygen \
  work/package/ssh/bin/hello-shle
```

## Entropy for the temporary session

The MMI has neither `/dev/random` nor `/dev/urandom`. The extracted QNX SDK
includes a legacy `random` executable, but research documents initialization
and reseeding defects in those versions. See
[Dissecting QNX, section 5.1](https://i.blackhat.com/briefings/asia/2018/asia-18-Wetzels_Abassi_dissecting_qnx__WP.pdf).

This build instead enables OpenSSH's existing EGD/PRNGD support on TCP 708.
`entropy-pool` binds **127.0.0.1 only**, on a privileged port. It supplies EGD
command 2 requests from a finite pool generated with Linux `os.urandom()`.
It implements no cryptographic generator, never repeats consumed bytes,
rejects requests larger than the remaining supply, wipes consumed memory,
and deletes the private RAM input before accepting requests. It disables
core dumps and erases the remaining pool on normal termination.

The test used a fresh 1 MiB pool. The local staging copy was deleted after
verified transfer, and the MMI helper consumed its RAM input before serving.
No entropy file is included in the deployment archive. Every restarted
helper needs a newly generated pool. This finite supply is suitable for
this test session; unattended startup needs a separate entropy design.
The native Jitterentropy replacement and its hardware assessment are described
in [Local randomness for MMI OpenSSH](randomness.md).
Initial provisioning used the existing SSH-to-Pi / private-Wi-Fi transfer
path. The later SSH and SFTP tests used public-key authentication and a
host key pinned from provisioning.

Six host tests cover unique sequential consumption, exhaustion, overdraw,
unsupported requests, rejection of readable input files, input reuse, and
port conflicts. Run them with:

```sh
python3 -B tests/test_openssh_entropy_pool.py
```

## Repeat the temporary RAM session

Keep Telnet available during setup. The steps below describe the tested
layout; they are not an automatic boot installer.

1. Create a private root-owned `/fs/tmpfs/mmi-ssh` directory in the existing
   RAM filesystem and stage the archive's `ssh/` contents there. Keep
   directories below this private root and executable files suitably owned
   and executable. The MMI lacks `tar`, so use SD file copies or another
   transfer whose checksums you verify on the unit.
2. Place the unique Ed25519 host private key at `etc/ssh_host_ed25519_key`
   and the intended client's Ed25519 public key at `etc/authorized_keys`,
   both mode 0600. Copy `sshd_config.example` to `sshd_config`.
3. Supply a **fresh** Linux-generated entropy pool as
   `/fs/tmpfs/mmi-ssh/entropy-pool-once.bin`, mode 0600. No pool may be reused
   after a prior service instance has started.
4. Run `/bin/ksh /fs/tmpfs/mmi-ssh/session-setup.sh`. It checks that the
   visible account files match their stored originals and that UID/GID 15
   are unused. It adds a locked `sshd` account/group in RAM, gives root the
   private RAM test directory as its temporary home, creates the privilege
   separation directory, verifies stored account checksums, and maps
   `/mnt/ssh` to the RAM directory. Changing the temporary home lets
   StrictModes validate the key without traversing the writable shared
   `/fs/tmpfs` parent; StrictModes stays enabled.
5. Start `/mnt/ssh/bin/entropy-pool` with the private pool path. For background
   operation from Telnet, ignore HUP in the launching subshell and redirect
   logs into the private RAM directory. Verify its ready message and that
   the input file has disappeared.
6. Run `/mnt/ssh/sbin/sshd -t -f /mnt/ssh/etc/sshd_config`. Then start
   `/mnt/ssh/sbin/sshd -D -e -f /mnt/ssh/etc/sshd_config` in a background
   subshell that ignores HUP, with logs redirected to the private directory.
7. Run `/bin/ksh /mnt/ssh/session-firewall.sh enable`. It validates current
   and proposed PF filter rules, adds the Pi-only exception, and verifies
   the result. NAT rules are untouched. Check the Pi's source address if
   repeating this on a changed network.
8. Connect from the allowed client with the matching key. Verify a
   command, `[ -t 0 ]` with a forced terminal (`ssh -tt`), and an SFTP
   round trip.

Rebooting the MMI removes the services, files, mappings, and firewall
exception. To block new SSH connections earlier, run
`/bin/ksh /mnt/ssh/session-firewall.sh disable`; existing connections may
remain until closed. No persistent startup configuration was changed.

## Permanent-install assessment (2026-10-18)

**Later update:** the owner chose to proceed with a persistent installation.
See [the installed layout and recovery instructions](persistent.md).
The assessment below records the earlier RAM-only state.

After the owner reported a shutdown and reenabled Telnet, a read-only live
check found the RAM payload, the same recorded entropy/sshd PIDs, both
listeners, and the SSH firewall exception still present. A command over
SSH succeeded. The SSH test environment therefore survived that
event; these observations do not establish what caused the apparent shutdown.
The setup still cannot survive a full reboot.

The following free-space figures come from that live `df -k` capture.
The projection reserves **4 MiB for a minimal runtime installation**, including
the three required server executables, entropy helper, configuration, keys,
and scripts. It excludes the archive, build tools, `ssh-keygen`, the smoke-test
binary, and the separate SFTP server (internal SFTP is already enabled).
The four required binaries total 3,210,160 bytes, or 3.061 MiB. A future
replacement entropy service may change the budget.

| Location | Free now | Free after 4 MiB install |
| --- | ---: | ---: |
| HDD `/mnt/persistence` | 161.89 MiB | 157.89 MiB |
| Flash `/mnt/efs-persist` | 25.66 MiB | 21.66 MiB |
| System flash `/mnt/efs-system` | 1.88 MiB | Insufficient |

The proposed location is a private root-owned `/mnt/persistence/openssh`
directory, retaining `/mnt/ssh` as the compiled-prefix alias. The captured
HDD manager configuration mounts this partition writable. Navigation has
about 9.34 GiB free but is configured read-only and need not be modified.

An automatic install would need these additional pieces:

1. Store the minimal payload, stable host key, authorized key, and configuration
   on persistent storage with appropriate ownership and permissions.
2. Provide a randomness source that works across boots. The tested finite
   pool cannot be copied to disk and reused. Unattended startup is not ready
   until its replacement is implemented and verified. A native Jitterentropy
   replacement has since passed a runtime assessment and command/PTY/SFTP
   integration tests in RAM; cold-boot and environmental checks remain.
3. Add a small background launcher to a verified persistent startup path.
   The captured service-starter configuration launches `/lsd/lsd.sh`, and
   the live file corresponds to `/mnt/efs-system/lsd/lsd.sh`; this is a
   candidate hook, not a tested SSH boot integration. Preserve the original
   script and ensure missing storage or SSH failure cannot block HMI startup.
4. Adapt the temporary account/prefix setup for the persistent directory,
   recreate its RAM mappings each boot, and restore the Pi-only firewall
   exception after networking is ready. Keep logs in RAM and make repeated
   launcher calls harmless.
5. Test a full reboot, command login, PTY, SFTP, unavailable-HDD behavior,
   and rollback. A successful command in the current session is not this test.

No persistent installation or startup edit was made during this assessment.
The current `/fs/tmpfs` has 7,288 KiB (7.12 MiB) free with the RAM test
installed. This is RAM-filesystem capacity, not a measurement of free system
RAM or SSH process memory. Running executables from HDD could avoid their
RAM-filesystem copies, but the process memory cost has not been measured.
