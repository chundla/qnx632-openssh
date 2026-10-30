# OpenSSH and Jitterentropy for QNX 6.3.2 SH4 (Audi MMI 3G+)

OpenSSH 10.6p1 and a Jitterentropy 3.7.0 EGD service, built for the
Harman-Becker MMI 3G Plus head unit (QNX 6.3.2, Renesas SH7785, SH-4
little-endian). The head unit has no `/dev/random` or `/dev/urandom`, so
`jitter-egd` serves OpenSSH's EGD/PRNGD interface on `127.0.0.1:708` from
CPU timing jitter.

**Status.** Built and tested on one unit only: **9411,
HN+R_US_AU_K0942_3, MU 1038** (2012 Audi A6, North America). Public-key
login, terminal allocation and SFTP work, the service starts by itself
after a forced reboot, and it has run persistently since 2026-10-18. One
cold start after a full power-off lost SSH because `jitter-egd` exited;
the cause was not established ([details](docs/persistent.md#cold-boot-entropy-failure)).
Nothing here has been checked on another train, region or MU variant.

| Document | Contents |
| --- | --- |
| [docs/build.md](docs/build.md) | Package contents, source verification, the QNX patch, reproducing the build, the temporary RAM session |
| [docs/randomness.md](docs/randomness.md) | Why Jitterentropy, the SH timer adapter, the EGD service and its NIST SP800-90B raw-noise assessment |
| [docs/persistent.md](docs/persistent.md) | The persistent installation on the test unit, start-up behaviour, rollback and validation |

## Layout

| Path | Contents |
| --- | --- |
| `build.sh` | Builds OpenSSH (`sshd`, `sshd-session`, `sshd-auth`, `sftp-server`, `ssh-keygen`) and packages it |
| `build-jitter.sh` | Builds `jitter-egd` and the timing probes against a pinned Jitterentropy checkout |
| `extract_qnx632.py` | Extracts the needed SDK subset from the QNX 6.3.2 installer JAR, checking each file's MD5 and length |
| `verify_elf.py` | Checks that every import of a built SH ELF is exported by libraries copied from the unit |
| `src/` | `jitter-egd.c`, the SH `ClockCycles()` timer adapter, the finite-pool `entropy-pool` used before it, and probes |
| `patches/` | `qnx632.patch` (OpenSSH) and `jitterentropy-qnx632.patch` (timer selection only) |
| `unit/` | The on-unit scripts exactly as run on the test unit (see below) |
| `tests/` | Host tests: `python3 -m unittest discover -s tests` |

## Building

You need the QNX 6.3.2 SDK (`sh-unknown-nto-qnx6.3.0-gcc` 3.3.5). It is
commercial software and is not included; [docs/build.md](docs/build.md)
records the media used and its hashes. Binaries from the QNX 6.5 toolchain
are not a substitute: the unit has `libc.so.2`, not `libc.so.3`.

```sh
python3 extract_qnx632.py /path/to/qnx_linux_setup.jar work/sdk
# put the signature-checked openssh-10.6p1.tar.gz in work/downloads/
git clone --depth 1 --branch v3.7.0 \
  https://github.com/smuellerDD/jitterentropy-library.git \
  work/jitterentropy-library-3.7.0
sh build-jitter.sh
sh build.sh
```

Everything is written under `work/` (ignored). `QNX_SDK_ROOT` and
`OPENSSH_WORK` override the defaults. From this tree, the seven runtime
binaries are byte-identical to the ones installed on the test unit:

| Binary | POSIX `cksum` |
| --- | --- |
| `sbin/sshd` | `3110266375 853096` |
| `libexec/sshd-session` | `4088295058 1188932` |
| `libexec/sshd-auth` | `883102595 1160500` |
| `libexec/sftp-server` | `1241218377 136132` |
| `bin/ssh-keygen` | `934342447 786072` |
| `bin/entropy-pool` | `206563639 7632` |
| `jitter-egd` | `2336099037 35856` |

## On-unit scripts

The scripts in `unit/` are kept byte-for-byte as they ran on the test
unit, so they are evidence as well as code. They are **specific to that
unit**:

- `install-persistent.sh` refuses to run unless the unit's
  `/mnt/efs-system/lsd/lsd.sh` and `.../Connectivity/pf.conf` match that
  unit's checksums (`2252741285 11676` and `3554363799 2832`).
- `persistent-firewall.sh` and `session-firewall.sh` admit SSH from a single
  client on the car's Wi-Fi, `192.168.1.109`.
- `persistent-start.sh` expects the payload in `/mnt/persistence/openssh`
  and maps it at `/mnt/ssh`, the prefix the binaries were configured with.
- `persistent-firewall.sh` is installed as `firewall.sh` beside
  `persistent-start.sh`, and `sshd_config.persistent` is the installed
  `sshd_config`; `sshd_config` is the RAM-session one.

Read [docs/persistent.md](docs/persistent.md) before adapting them. The
start-up hook is a five-line block added after the shebang of the unit's
`lsd.sh`; the factory file itself is not reproduced here.

Downstream user: the [MMI 3G+ Wi-Fi station](https://github.com/chundla/mmi3g-wifi-sta)
takes its `wpa_supplicant` nonces from `jitter-egd` and serves SSH over a
phone hotspot with this `sshd`.

## Licence and credits

The files in this repository are under the [BSD 2-Clause licence](LICENSE).
OpenSSH, Jitterentropy and the QNX SDK are not included; see
[CREDITS.md](CREDITS.md) for their licences and the other work this builds on.
