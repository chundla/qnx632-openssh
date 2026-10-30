# Credits

This repository holds build scripts, patches, adapters and on-unit scripts.
The software it builds, and the research it relies on, belong to others.

## Built from, not included

| Work | Author | Licence | Used as |
| --- | --- | --- | --- |
| [OpenSSH Portable](https://www.openssh.com/portable.html) 10.6p1 | The OpenBSD project and contributors | BSD-style; see the release's `LICENCE` | Built with `patches/qnx632.patch`; release archive SHA-256 `a9dc9565…7d5f39`, signature checked against key `7168B983815A5EEF59A4ADFD2A3F414E736060BA`. The built package carries upstream's `LICENCE`. One patch hunk backports the `SKIP_PRIVDROP` forwarding check from upstream `channels.c`. |
| [Jitterentropy library](https://github.com/smuellerDD/jitterentropy-library) 3.7.0 | Stephan Müller | BSD-3-Clause or GPL-2.0 (dual); used under BSD-3-Clause | Linked into `jitter-egd`, tag `v3.7.0`, commit `e783cf1c…6094976a`. Only the platform timer selection is patched. The package carries upstream's `LICENSE.bsd`. |
| QNX Momentics 6.3.2 SDK | QNX Software Systems | Commercial | Compiler, headers and libraries for the build. Not included and not redistributable. |

## Research and tools

- Jos Wetzels and Ali Abbasi,
  [*Dissecting QNX*](https://i.blackhat.com/briefings/asia/2018/asia-18-Wetzels_Abassi_dissecting_qnx__WP.pdf)
  (Black Hat Asia 2018): the weaknesses of the QNX 6.x `random` service
  that ruled it out.
- NIST, [SP800-90B Entropy Assessment](https://github.com/usnistgov/SP800-90B_EntropyAssessment):
  the non-IID estimators used on the raw timing data.
- [DrGER2/MMI3G-Info](https://github.com/DrGER2/MMI3G-Info): the
  MMI 3G+ research and scripts in whose fork this work began, including
  the access used to reach the unit before SSH existed.
- [dspl1236/MMI3G-Toolkit](https://github.com/dspl1236/MMI3G-Toolkit):
  MMI 3G+ platform research consulted along the way.
- The QNX 6.3.2 installation media came from the fsck.technology software
  archive (hashes in [docs/build.md](docs/build.md)).
