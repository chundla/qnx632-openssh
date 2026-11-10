# Status and validation limits

Documentation review: **2026-11-09**. Original source baseline:
`602b29795454f6d10625e1e4124cb4e3fafa84c5`. The subsequent SSH-priority
change in `unit/persistent-start.sh` is tracked together with its November 7
installed observations in `docs/persistent.md`. It is not part of that
original baseline. Recording the change in Git does not establish which
Git revision was installed during the earlier trial. Read
[platform](platform.md) for the supported unit and
[architecture](architecture.md) for component ownership.

## Recorded results

| Evidence | Result and limit |
| --- | --- |
| RAM sessions and runtime randomness assessment, October 2026 | Command login, PTY and SFTP with native EGD passed on unit 9411; timer/raw-noise assessment and limitations are in `randomness.md` |
| Persistent service restart, 2026-10-18 | Repeated startup, account preservation, command/PTY/SFTP and preload correction verified; this alone is not boot validation |
| Forced QNX reboot, 2026-10-18 | Automatic entropy and SSH startup followed by command/PTY/SFTP passed with `LD_PRELOAD` cleared |
| Full power-off, 2026-10-28 | Entropy process disappeared and SSH failed; manual restart restored access, subsequent forced reboot worked; root cause unresolved |
| Owner priority update, 2026-11-07 | After forced reboot, startup at priority 9 launched SSH/sessions at 10; entropy remained at 1. Engine-off relay login took 6 s, banner 2.9 s; engine-running improvement untested |

The [persistent record](persistent.md) retains exact checksums, installed
layout and validation. Its November 7 installed script includes the wired
helper's appended line as well as the priority update; it is not identical
to the repository script. Earlier installed source revisions were not
recorded; artifact checksums remain the evidence.

## Known problems and limits

The cold-boot entropy loss is open. The record fits the EGD read watchdog
expiring under startup load, but an external termination was not ruled out.
Do not present that inference as a diagnosis. The service does not silently
restart itself or weaken its entropy policy. Structured restart and extended
environmental assessments remain deferred, and the runtime assessment is
not formal entropy certification.

The port uses experimental OpenSSH internal cryptography without OpenSSL,
limited algorithms and no additional privilege-separation sandbox. The
old toolchain lacks modern hardening. Public-key authentication, account
separation and the existing scoped PF rules still matter; see build docs.

Installation assumes specific factory files, checksums, UID/GID availability,
paths and client addressing. It requires prepared private staging and
backups, not just an extracted archive. No other firmware combination is
validated. Whole-file rollback can overwrite later station/startup changes;
reconcile ownership first. Firmware updates may replace EFS hooks.

The pinned OpenSSH source used by the station is not a hardware-tested
source pair by itself. Entropy, wired/lease listeners, PF rules and startup
hooks require combined validation after a change. Station operation without
OpenSSH has no recorded target trial.

## Host validation

Run `python3 -m unittest discover -s tests` from this repository root.
The suite uses Python 3, host GCC and loopback sockets. Fake collectors
exercise adapter failures and protocol boundaries, not entropy quality.
There is no dedicated shell/startup behavior suite or inventory-based
shell enforcement; adding those is follow-up implementation work.

On 2026-11-09, `python3 -m unittest discover -s tests` passed all 18
host tests, with no skips, against the reviewed working tree. This does
not exercise the startup-priority change on hardware. Host shell syntax
and extracted priority-parser checks also passed for `9r`, `10r`, `13o`
and a missing priority; they do not validate QNX scheduling.
No cross-compilation, installation, target execution, reboot, full power-off
or new randomness assessment is part of this documentation review.
