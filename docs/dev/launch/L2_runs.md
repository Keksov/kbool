# L2.4 — Linux gate runs (no fixes)

Date 2026-10-21. Four full gates, one VM at a time, via `bash tools/vmlab/vmlab.sh gate VM [--env …] -- --rerun-failed 1 all`
(snapshot `clean`). Input for L2.5; failures with repros: [`L2_failures.tsv`](L2_failures.tsv).
Host tree: kbool `801b8a0` for run 1, `598b7e8` for runs 2-4 (a docs-only commit in between, preamble); submodules kcl `b138394`, kklass `a0421b4`, kkore `96fbffc`, ktests `05a5b29`; no `-dirty`.
OUT dirs are on the Windows host under `%TEMP%/kb-vmlab/` (`C:/Users/1/AppData/Local/Temp/kb-vmlab/…`).

## Run 1 — kb-ubuntu (default locale)

* command: `bash tools/vmlab/vmlab.sh gate kb-ubuntu -- --rerun-failed 1 all`
* OUT: `C:/Users/1/AppData/Local/Temp/kb-vmlab/20261021-195732-kb-ubuntu-clean`
* VM: Linux kb-ubuntu 6.8.0-147-generic #147-Ubuntu SMP PREEMPT_DYNAMIC Thu  / Ubuntu 24.04.5 LTS; GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu); 
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 349 s

```
gate 2026-10-21T16:57:53 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.2.21 /usr/bin/bash
gate options: --rerun-failed 1
gate: segment start = env
gate 5.2.21: 30 cells  19 PASS  10 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  1 STRAY  0 CRASH  0 NOTRUN  tests 8845/9014  5m22s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:19:10:0:0:0:1:8845:9014
```

## Run 2 — kb-debian (default locale)

* command: `bash tools/vmlab/vmlab.sh gate kb-debian -- --rerun-failed 1 all`
* OUT: `C:/Users/1/AppData/Local/Temp/kb-vmlab/20261021-200334-kb-debian-clean`
* VM: Linux vbox 6.12.107+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.107 / Debian GNU/Linux 13 (trixie); GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu); 
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 310 s

```
gate 2026-10-21T17:04:15 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.2.37 /usr/bin/bash
gate options: --rerun-failed 1
gate: segment start = env
gate 5.2.37: 30 cells  18 PASS  11 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  1 STRAY  0 CRASH  0 NOTRUN  tests 8845/9014  4m24s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:18:11:0:0:0:1:8845:9014
```

## Run 3 — kb-fedora (default locale)

* command: `bash tools/vmlab/vmlab.sh gate kb-fedora -- --rerun-failed 1 all`
* OUT: `C:/Users/1/AppData/Local/Temp/kb-vmlab/20261021-200854-kb-fedora-clean`
* VM: Linux kb-fedora 6.19.10-300.fc44.x86_64 #1 SMP PREEMPT_DYNAMIC Wed Mar / Fedora Linux 44 (Cloud Edition); GNU bash, version 5.3.9(1)-release (x86_64-redhat-linux-gnu); 
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 628 s

```
gate 2026-10-21T17:09:24 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.3.9 /usr/bin/bash
gate options: --rerun-failed 1
gate: segment start = env
gate 5.3.9: 30 cells  19 PASS  9 FAIL  1 FLAKY  0 ENV  0 TIMEOUT  1 STRAY  0 CRASH  0 NOTRUN  tests 8968/9063  9m54s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:19:9:1:0:0:1:8968:9063
```

## Run 4 — kb-debian (LC_ALL=de_DE.UTF-8)

* command: `bash tools/vmlab/vmlab.sh gate kb-debian --env LC_ALL=de_DE.UTF-8 -- --rerun-failed 1 all`
* OUT: `C:/Users/1/AppData/Local/Temp/kb-vmlab/20261021-201938-kb-debian-clean`
* VM: Linux vbox 6.12.107+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.107 / Debian GNU/Linux 13 (trixie); GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu); env: LC_ALL=de_DE.UTF-8
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 357 s

```
gate 2026-10-21T17:20:12 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.2.37 /usr/bin/bash
gate options: --rerun-failed 1
gate: segment start = env
gate 5.2.37: 30 cells  17 PASS  12 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  1 STRAY  0 CRASH  0 NOTRUN  tests 8845/9014  5m17s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:17:12:0:0:0:1:8845:9014
```

## Totals

Non-PASS test files per run (rows of `L2_failures.tsv`):

| run | FAIL cells | FLAKY | STRAY | files |
|---|---|---|---|---|
| kb-ubuntu | 10 | 0 | 1 | kcl 1 + math 17 + tawk 1 + tfile 1 + tgrep 1 + thttpserver 5 + tregex 1 + tsed 1 + ttail 1 + kkore 1 = 30, + tpipe stray 1 = **31** |
| kb-debian | 11 | 0 | 1 | ubuntu's 30 + thead 1 = 31, + stray 1 = **32** |
| kb-fedora | 9 | 1 (math 018) | 1 | tawk 1 + tfile 1 + tgrep 1 + thead 1 + thttpserver 5 + tregex 1 + tsed 1 + ttail 1 + kkore 1 = 13, + flaky 1 + stray 1 = **15** |
| kb-debian de_DE | 12 | 0 | 1 | debian's 31 + ktests 045_StrayGuard 1 = 32, + stray 1 = **33** |

31 + 32 + 15 + 33 = **111** rows.

Notes on the runs:

* No test was FLAKY except kb-fedora `kcl/math/018_DE1_ProgfileSweep.sh` (failed in the cell, passed on `--rerun-failed`).
* `kcl/thead 005_Run.sh` fails on debian (default and de_DE) and fedora, passes on ubuntu.
* `ktests 045_StrayGuard.sh` fails only in the de_DE run; alone (`repro_ok=no`) it passes.
* `kcl/math` and `kcl` `202_math.sh` fail on ubuntu and debian (mawk) and pass on fedora (gawk).
* Locale: `locale -a` on kb-debian lists `de_DE.utf8`; default `LANG=en_US.UTF-8`.
* Repros were run alone, once per row, in a `vmlab up` + `sync` + `run` + `down` batch per VM (`repro_ok=yes`: the runner exited 1 and listed the file under "Failed test files"). Their output: scratch only.

## L2.8 — closing gates (2026-10-27)

Tree: kbool aa404b0 (ktests 5e78a6b, kcl ce157f1). Every run `--rerun-failed 1 all`, one at a time.

| run | bash | `__GATE__` | tests | wall |
|---|---|---|---|---|
| Windows Git-bash + MSYS2 (`kt-gate/20261027-013813-1619`) | 5.3.15 / 5.3.9 | `PASS:60:60:0:0:0:0:0:18625:18625` | 9312 + 9313 | 11m28s / 11m38s |
| kb-ubuntu | 5.2.21 | `PASS:30:30:0:0:0:0:0:9297:9297` | 9297 | 5m20s |
| kb-debian | 5.2.37 | `PASS:30:30:0:0:0:0:0:9297:9297` | 9297 | 4m13s |
| kb-fedora | 5.3.9 | `PASS:30:30:0:0:0:0:0:9297:9297` | 9297 | 4m53s |
| kb-debian `LC_ALL=de_DE.UTF-8` | 5.2.37 | `PASS:30:30:0:0:0:0:0:9297:9297` | 9297 | 4m11s |

No FAIL, FLAKY, STRAY or rerun in any run (L2.4: 111 non-PASS rows).

**Rescan.** `tools/porting/scan.sh`: 2646 rows (L0 `inventory.tsv`: 2083). New
core/wrapper/harness rows (key pattern + file + text, line numbers ignored):
212, all reviewed by the supervisor — the platform branches L2 added
(process-tree backends `/proc` → `ps` in `kcl/tpipe` and `ktests/ktest_proc.sh`,
cygwin branches, nc/socat detection and the msys 3.6.10 stop in
`kcl/thttpserver`, gate/strays session backends) and host-only dev tools
(`tools/porting/numbers.sh`, `tools/vmlab/checks/timer.sh`,
`docs/dev/launch/nc_twoslot_probe.sh`); each platform branch is guarded. The
one P01 row (`#!/bin/bash`, `tools/porting/tests/mdlinks/run.sh:90`) is the
content of a fixture heredoc. `inventory.tsv` stays the L0 baseline.
