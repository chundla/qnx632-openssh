# OpenSSH and entropy architecture

Read [platform](platform.md) for the target and [status](status.md) for
what was validated. Build inputs/outputs are private under `work/`.

## Build and entropy flow

`extract_qnx632.py` extracts and verifies an SDK subset. `build.sh`
checks the OpenSSH 10.6p1 archive hash, applies `patches/qnx632.patch`,
cross-compiles server components with internal cryptography and packages
under `work/package/ssh` and `work/dist`. The patch preserves the QNX
version for descriptor-passing workarounds, supplies missing declarations
and corrects a forwarding condition. Forwarding remains disabled in the
example configs. The build uses no OpenSSL or zlib; see [build](build.md)
for algorithm and hardening limits.

`build-jitter.sh` requires pinned Jitterentropy 3.7.0 source at
`work/work/jitterentropy-library-3.7.0`. Only platform timer selection is
patched; upstream noise/conditioning/health code is unchanged and compiled
with `-O0`. Output is in `work/jitter-build`, `work/jitter-package` and
`work/dist`. `src/qnx-jitter-timer.h` reads the upper 32 bits of the SH
`ClockCycles()` count and extends wraps for a single-threaded collector.
It is not a general wall clock across long idle gaps.

`src/jitter-egd.c` serves EGD command 2 on `127.0.0.1:708`, with startup
and read watchdogs and upstream health checks. OpenSSH's PRNGD support
and the station supplicant request bytes there. Failure provides no weak
fallback. `src/entropy-pool.c` is the older finite, one-use RAM-session
source; its input must never be saved for reuse across service starts.
See [randomness](randomness.md) for assessment evidence and limitations.

`verify_elf.py` checks SH ELF imports against supplied target libraries,
including captured libraries without symbol section headers. This does
not execute the binary or certify entropy.

## Installed startup and recovery

Factory `lsd.sh` starts `/mnt/efs-persist/openssh-start.sh` in the
background. This launcher waits for HDD installation and `uap0`, then
runs `/mnt/persistence/openssh/start.sh` (`unit/persistent-start.sh`).
It clears inherited preload, checks account collisions, creates private
RAM account overlays under `/fs/tmpfs/mmi-openssh`, and maps the HDD
payload at compiled prefix `/mnt/ssh`. Stored passwd/group files remain
unchanged. It starts entropy, waits for readiness, checks SSH config,
starts SSH, and enables its scoped live PF rule. Owned PIDs prevent
successful duplicate startup; partial startup is refused or cleaned up
rather than silently adopted.

`unit/install-persistent.sh` finalizes an already staged, verified,
unit-specific installation. It requires prepared startup/firewall files
under payload `backup/`, exact factory checksums and no preexisting backup.
It is not a generic package installer. Source-to-installed names and
recovery commands are in [persistent installation](persistent.md).

The disabled marker prevents future launches. Rollback restores the
backed-up factory startup/firewall files; a subsequent reboot clears
running services and RAM overlays. Payload stays on HDD. Do not assume
rollback preserves later edits to those same factory files: reconcile
station hooks and other owners' changes before using a whole-file backup.

## Station and wired integration

The separate [Wi-Fi station project](https://github.com/chundla/mmi3g-wifi-sta)
requires EGD for nonces and can run its bundled daemon without SSH.
When OpenSSH is running, it also uses `/mnt/ssh` to expose a listener on
the hotspot lease. The station manages that listener and its interface
rule; this project's base listener remains on `192.168.1.1:2222`.

That project also owns the wired `en5` helper and second listener. Its
installer appends an `en5/start.sh` line to the installed OpenSSH startup.
The installed script can therefore differ from this repository's file.
The current station startup uses its own `lsd.sh` block; an older station
build appended to OpenSSH startup instead. Preserve these distinctions
when comparing checksums, upgrading or restoring backups.

## Where to change and check

| Task | Implementation | Host tests |
| --- | --- | --- |
| OpenSSH port/build | `build.sh`, `patches/qnx632.patch`, `extract_qnx632.py` | No dedicated cross-build/SDK extraction test; inspect logs and target imports |
| EGD service and one-use pool | `src/jitter-egd.c`, `src/entropy-pool.c` | `tests/test_openssh_jitter_egd.py`, `tests/test_openssh_entropy_pool.py` |
| SH timer adapter | `src/qnx-jitter-timer.h`, `patches/jitterentropy-qnx632.patch` | `tests/test_openssh_qnx_timer.py` |
| ELF imports | `verify_elf.py` | `tests/test_verify_elf.py` |
| Startup/accounts/PF/install/rollback | `unit/` | No dedicated unit-shell behavioral suite or inventory enforcement |

Tests compile C adapters with host GCC and fake QNX/collector interfaces.
They cover protocol boundaries, failure handling and timer arithmetic,
not hardware entropy quality, target shell behavior or startup reliability.
