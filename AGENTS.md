# Contributor and agent guidance

## Start here

Read [README](README.md), [platform rules](docs/platform.md),
[architecture](docs/architecture.md) and [status](docs/status.md).
Then read [build/session](docs/build.md), [randomness](docs/randomness.md)
or [persistent installation](docs/persistent.md) for the task at hand.

## Ownership and commands

This repository owns the QNX/SH4 OpenSSH port, entropy adapter, SDK
extraction, patches, installers, rollback and host tests. The separate
mmi3g-wifi-sta project owns radio, supplicant, wired helpers and their
startup integration. Coordinate shared EGD/SSH interfaces; do not duplicate
those implementations here.

From the root, run `python3 -m unittest discover -s tests` before committing.
For entropy changes use `python3 -B tests/test_openssh_jitter_egd.py` and
`python3 -B tests/test_openssh_qnx_timer.py`; other test files run directly.
Tests need Python 3, GCC and loopback sockets. Fake collectors test failure
handling, not entropy quality. No unit-shell inventory checker is integrated.

Build with `sh build-jitter.sh` and `sh build.sh` after preparing the inputs
in README/build docs. These are host builds, not deployment commands.
Keep SDKs, archives, libraries, keys and outputs in ignored `work/`.

## Editing rules

Preserve owner changes, including startup priority code and its recorded
observations. Apply the local platform rules to unit shell and native code.
Keep Jitterentropy noise code at upstream-required `-O0`; do not replace
health failures with weak randomness, saved seeds or retry loops without
a separately designed and assessed change.

Installation scripts are specific to the recorded unit and exact factory
checksums. Do not relax guards for another firmware. Preserve account
backing files, RAM mappings, preload clearing, scoped PF rules, repeated
startup handling and independent rollback. An existing wired helper may
append to installed `start.sh`; do not overwrite that owner's integration.

Retain historical commands/checksums and add dated corrections. Source,
host checks and installed behavior are separate evidence. The cold-boot
entropy failure remains unresolved; forced reboot success does not close it.
