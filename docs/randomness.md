# Local randomness for MMI OpenSSH

The native source is **Jitterentropy 3.7.0**, using the MMI's own high-resolution
timer and an EGD adapter for the existing OpenSSH build. It needs no saved
seed, finite entropy file, network server, or Pi for randomness after startup.
The runtime entropy assessment passed on the owner's hardware using a RAM
test installation. A later [persistent installation](persistent.md)
uses the same tested daemon. After the SSH startup correction, an owner-forced
reboot confirmed automatic entropy initialization and working SSH login,
terminal access and SFTP. Details are recorded in that installation document.
A complete cold-boot and environmental
assessment remains outstanding.
Fresh SSH command execution, PTY allocation, and SFTP were then verified with
this native service supplying the existing OpenSSH entropy endpoint.

## Why this source

The QNX SDK's old `random` binary is not sufficient evidence of a sound
randomness service. Research found missing runtime reseeding in versions
before QNX 6.6 and other weaknesses in initialization and reseed control.
See [Dissecting QNX, section 5.1](https://i.blackhat.com/briefings/asia/2018/asia-18-Wetzels_Abassi_dissecting_qnx__WP.pdf).
Timestamps, process IDs, MAC addresses, and predictable system-command
output must not be treated as a secret seed.

[Jitterentropy](https://github.com/smuellerDD/jitterentropy-library/tree/v3.7.0)
collects execution-time variations and provides startup and continuous
health tests. Upstream describes how to assess the *raw noise*, rather than
testing only the conditioned random output. Passing a short runtime probe
does not by itself establish the available entropy rate.

## Timer adapter

The live MMI's normal monotonic clock advanced only 204 times in 100,000
successive reads, in increments of approximately 1 ms. `ClockCycles()`
changed in all 100,000 reads, with no backwards observations in that probe.

QNX 6.3 SH puts its 32-bit TMU hardware count in the **upper 32 bits** of
the `ClockCycles()` result. Its reported frequency has the same shift.
The observed hardware frequency is 11,000,000 Hz, approximately 90.9 ns
per timer tick. Feeding the shifted value directly to software that examines
the low bits would leave those bits permanently zero.

`src/qnx-jitter-timer.h` removes the fixed zero bits and extends
32-bit counter wraps using unsigned subtraction. Its unit test covers
ordinary increments, a stuck count, and the counter wrap. It is intended
for a single-threaded collector. Across idle gaps longer than one hardware
wrap it does not preserve elapsed wall time; subsequent fine-grained
measurement differences still use the actual hardware counter.

Only the upstream platform timer selection is patched. The noise source,
conditioning implementation, health tests, and initialization code are
unchanged. All upstream library code is compiled with required `-O0`.
This GCC 3.3.5 toolchain does not support upstream's modern compiler and
hardening options, including `-fwrapv`; the build uses its supported flags.

## Source provenance and build

The signed release tag is `v3.7.0`, commit
`e783cf1c450bce4d72f95c9f9c84546a6094976a`.
Its signature was verified against the maintainer key obtained from the
maintainer's GitHub account, fingerprint
`342C4E3A39EA5F19909BE38AAE5D0DA3FD092353`.
This establishes consistency with that published key, not an independent
identity verification.

Using the SDK described in [the OpenSSH build notes](build.md):

```sh
git clone --depth 1 --branch v3.7.0 \
  https://github.com/smuellerDD/jitterentropy-library.git \
  work/jitterentropy-library-3.7.0
sh build-jitter.sh
```

The script pins that commit, refuses modifications to upstream core files,
applies the timer-selection patch, and builds into `work/jitter-build/`.
The five executables are `jitter-egd`, `jitter-probe`, `timer-probe`,
`egd-probe`, and the diagnostic `jitter-raw` recorder. They require only the
existing MMI C/socket libraries; the library is linked into the programs.
No SDK or vendor library is included in the experimental archive.

## EGD service behavior

`jitter-egd [PORT]` binds only `127.0.0.1`, default TCP 708, matching the
existing OpenSSH build. Production builds require root and a privileged
port. Initial experiments used 709 alongside the original finite pool on 708.
After the runtime assessment, that finite-pool process was stopped and a fresh
Jitterentropy process started successfully on 708 for the SSH integration test.

The service enables `JENT_FORCE_FIPS` to activate continuous health checking,
uses upstream's default oversampling rate of 3, retains memory-access noise,
and disables the internal timer thread. The MMI has one CPU. This flag
selection **does not certify** the service or device under FIPS or SP800-90B.

The process disables core dumps, requires `mlockall()` success, and runs at
QNX scheduling priority 1. It serves only the blocking EGD command 2 used by
OpenSSH. Each request collects fresh output. There is no persistent state,
output cache, weaker fallback, or automatic retry after a collector failure.
Any initialization/read/health error prevents output and stops the service.
Startup and collection have wall-time watchdogs. Normal cleanup wipes buffers
and frees the upstream collector. Idle operation waits for requests.

The daemon is approximately 35 KiB. `pidin memory` for its initial revision
reported 36 KiB code and 376 KiB data, plus stack and existing shared libraries.
This is a process snapshot, not a complete measurement of additional physical
RAM. The initial 256 KiB memory-access buffer is retained. Replacing the
7.5 KiB finite-pool helper with this daemon still fits the proposed 4 MiB
minimal-install budget.

## Verification and limits

Completed on the owner's MMI:

- Library startup/hash/GCD checks and 1 KiB of output with continuous health
  tests: passed, 18.334 s wall time and 15.406 s CPU time for the complete probe.
- EGD command 2: twelve separate 40-byte requests passed without errors or
  adjacent repeated blocks. The initial service took 12.345 s; the low-priority
  revision took 25.631 s while the raw recorder also ran.
- Separate service launches initialized successfully without a seed file.
- Static ELF checks resolved required imports against the captured actual
  MMI libraries. Locked-memory startup succeeded on the target.
- After replacing the original finite pool on 708, twelve more EGD requests
  passed in 12.838 s. A new SSH command printed `JITTER_SSH_OK`; a terminal
  check printed `JITTER_PTY_OK`; a 4 KiB SFTP upload/download matched SHA-256
  `c8f5d0341d54d951a71b136e6e2afcb14d11ed8489a7ae126a8fee0df6ecf193`.

Two initially concurrent integration clients timed out on the Pi-to-MMI TCP
connection before reaching SSH. The entropy process remained healthy, and
fresh command, terminal, and SFTP checks subsequently passed. The precise
network cause was not established. The author's client now bounds connection
setup with `ConnectTimeout=15`; this is not a claimed network repair.

Host tests validate no-output behavior on initialization failure, collector
allocation failure, health/read failure, and short reads; invalid commands,
zero-length requests, a busy port, argument parsing, and shutdown are covered.
These tests use a deterministic fake collector only for adapter verification:

```sh
python3 -B tests/test_openssh_jitter_egd.py
python3 -B tests/test_openssh_qnx_timer.py
```

The raw-noise recorder collects one million low-eight-bit timing deltas into
RAM for analysis with [NIST's non-IID estimators](https://github.com/usnistgov/SP800-90B_EntropyAssessment).
This is diagnostic data, never used to seed SSH. NIST tool commit
`87c104d0ed4cbc96103e7b8b38d6f2c7e0a6b289` was built privately; its supplied
biased-random-bits self-test agreed with reference results to maximum delta
`4.18241830058008e-14`.

The capture completed with health-failure mask 0 and 1,645 stuck samples
out of 1,000,000; stuck measurements are checked/rejected by the production
collector. The capture used 435.567 CPU seconds at scheduling priority 1.
The one-million-byte file matched target POSIX checksum `4227375721` after
SFTP export. Its SHA-256 is
`fe667e5b70e5f6e9ca88ee900040db6abedab4e5cfd3094e065beeb9455791fc`.

The assessment command was:

```sh
OMP_NUM_THREADS=2 work/entropy-assessment/cpp/ea_non_iid \
  -i -a -v work/live/mmi-raw-timing.bin 8
```

Results:

| Estimate | Result |
| --- | ---: |
| H_original | 6.638399 bits/sample |
| H_bitstring | 0.815143 bits/bit |
| min(H_original, 8 × H_bitstring) | **6.521141 bits/sample** |
| Configuration's entropy assumption at OSR 3 | **1/3 bit/sample** |

The measured runtime dataset therefore exceeds the configured assumption.
This statistical assessment applies to the sampled conditions, rather than
establishing a bound for every possible temperature, load, or boot condition.
The machine-readable evidence and the complete estimator output are kept
privately by the author.

Cold boots and representative operating conditions were recommended as
additional validation. The owner subsequently chose to proceed without that
extended campaign; see [the persistent installation](persistent.md).
A full entropy-source
validation additionally requires the upstream restart-data methodology and
environmental testing; the short probes are not that validation.

The separately generated archive is
`work/dist/jitterentropy-3.7.0-qnx632-shle-experimental.tar.gz`.
It contains the daemon, upstream BSD license, build provenance, checksums,
and these notes; it contains no seed, keys, SDK, vendor library, or boot hook.
The main OpenSSH archive remains the original build package; adding this
experimental archive does not install or enable permanent startup.
