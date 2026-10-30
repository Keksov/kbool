# L5 — CI runs

Date 2026-10-30 (the runs are of 2026-10-29, UTC). Measurement only (no fixes, no gate, no VM): GitHub Actions `Keksov/kbool`, workflow `ci`, three runs read from their `gate-<job>-<slug>` artifacts (the gate's OUT dir of each row: `progress.txt`, `cells.tsv`, `cells/NNN/{log.txt,fails.txt,result,summary}`, `rerun-R/`, `summary.json`). The failing files with the first `[FAIL]` line, the earlier-sighting columns and the notes: [`L5_failures.tsv`](L5_failures.tsv) (72 rows, all of R2). Format model: [`L4_runs.md`](L4_runs.md), [`L3_runs.md`](L3_runs.md). Earlier analyses cited, not redone: [`L2_failures.tsv`](L2_failures.tsv), [`L3_failures.tsv`](L3_failures.tsv), [`L4_failures.tsv`](L4_failures.tsv), the ledger items `L5.0-o1`, `L34-F1-o1`, `L45-4-o1` in [`../launch_ledger.json`](../launch_ledger.json).

How a file gets its verdict in the TSV: the cell's `summary` lists the files that failed in the full run; the gate re-ran exactly those files once (`--rerun-failed 1`); a file that is also in `cells/NNN/rerun-1/summary` is FAIL, a file that passed in the rerun is FLAKY (the FLAKY cells name them in `cells.tsv`, column `flaky`). The `[FAIL]` text of a file is taken from the cell's `fails.txt` (the gate cuts long messages; `ktests/054_GateSelection.sh` on macOS gnu has no tagged line left and shows `-`). No artifact was missing for R0, R1 (except the two FreeBSD rows, which R1 did not upload) and R2; no log was unreadable.

## Runs

| run | id | commit | commit title |
|---|---|---|---|
| R0 | 40965193938 | main `efa12ee` | launch L4.5-6: vmlab gate honours --env KT_GATE_BASHES, CI row bash 5.1.16 alpine |
| R1 | 40967544797 | main `94195d2` | launch L5.1: full CI matrix (linux containers, macOS bsd/gnu, FreeBSD, Windows) |
| R2 | 40974474908 | main `236d040` | launch L5.1 round 2: ktests gate parent-watch fix (su/sudo -u), FreeBSD run script set +e |

`gate repos:` line of the rows (`progress.txt`): R0 `kbool efa12ee ktests 0493ad3 kcl b59b370 kklass 498bdd5 kkore 9d21c81`; R1 `kbool 94195d2 ktests 0493ad3 kcl b59b370 kklass 498bdd5 kkore 9d21c81`; R2 `kbool 236d040 ktests 3bd5e0e kcl b59b370 kklass 498bdd5 kkore 9d21c81`. The msys2 row says `gate repos: (no git)` in R1 and R2. Every gate ran `ktests/tools/gate.sh --out OUT --rerun-failed 1 --timeout 900 all` (`argv.txt`).

### R0 — 4 rows (L5.0)

The `__GATE__` lines copied from each row's `progress.txt` (artifacts `gate-0..3`; the row is named from the `gate bashes:` line: 5.3.9 `/usr/bin/bash` = ubuntu host, `/usr/local/bin/bash` 5.1.16 / 5.2.37 / 5.3.20 = the alpine rows):

```
linux-ubuntu-host        __GATE__:FAIL:30:26:3:1:0:0:0:9548:9556
linux-alpine-51          __GATE__:FLAKY:30:29:0:1:0:0:0:9533:9534
linux-alpine-52          __GATE__:PASS:30:30:0:0:0:0:0:9534:9534
linux-alpine-53          __GATE__:FLAKY:30:29:0:1:0:0:0:9533:9534
```

| job | row | bash | verdict | cells fail | tests passed/total |
|---|---|---|---|---|---|
| linux | ubuntu host, system bash | 5.3.9 | FAIL | 3 FAIL, 1 FLAKY | 9548/9556 |
| linux | alpine, bash 5.1 | 5.1.16 | FLAKY | 1 FLAKY | 9533/9534 |
| linux | alpine, bash 5.2 | 5.2.37 | PASS | 0 | 9534/9534 |
| linux | alpine, bash 5.3 | 5.3.20 | FLAKY | 1 FLAKY | 9533/9534 |

### R1 — 11 rows uploaded of 13

```
linux-ubuntu-host        __GATE__:FAIL:30:26:3:1:0:0:0:9549:9556
linux-alpine-51          __GATE__:PASS:30:30:0:0:0:0:0:9534:9534
linux-alpine-52          __GATE__:PASS:30:30:0:0:0:0:0:9534:9534
linux-alpine-53          __GATE__:FLAKY:30:29:0:1:0:0:0:9532:9534
linux-debian-13          __GATE__:INTERRUPTED:30:0:0:0:0:0:0:0:0
linux-ubuntu-2404        __GATE__:INTERRUPTED:30:0:0:0:0:0:0:0:0
linux-fedora-44          __GATE__:INTERRUPTED:30:0:0:0:0:0:0:0:0
macos-bsd                __GATE__:FAIL:30:21:9:0:0:0:0:9301:9555
macos-gnu                __GATE__:FAIL:30:24:4:2:0:0:0:9514:9555
windows-git-bash         __GATE__:FAIL:30:28:2:0:0:0:0:9565:9571
windows-msys2            __GATE__:FAIL:30:28:1:0:0:0:1:9529:9550
```

| job | row | bash | verdict | cells fail | tests passed/total |
|---|---|---|---|---|---|
| linux | ubuntu host, system bash | 5.3.9 | FAIL | 3 FAIL, 1 FLAKY | 9549/9556 |
| linux | alpine, bash 5.1 | 5.1.16 | PASS | 0 | 9534/9534 |
| linux | alpine, bash 5.2 | 5.2.37 | PASS | 0 | 9534/9534 |
| linux | alpine, bash 5.3 | 5.3.20 | FLAKY | 1 FLAKY | 9532/9534 |
| linux | debian 13 | 5.2.37 | INTERRUPTED | INTERRUPTED at cell 1, 29 not run | 0/0 |
| linux | ubuntu 24.04 | 5.2.21 | INTERRUPTED | INTERRUPTED at cell 1, 29 not run | 0/0 |
| linux | fedora 44 | 5.3.9 | INTERRUPTED | INTERRUPTED at cell 1, 29 not run | 0/0 |
| macos | bsd tools, brew bash | 5.3.20 | FAIL | 9 FAIL | 9301/9555 |
| macos | gnu tools, brew bash | 5.3.20 | FAIL | 4 FAIL, 2 FLAKY | 9514/9555 |
| windows | git-bash | 5.3.15 | FAIL | 2 FAIL | 9565/9571 |
| windows | msys2 | 5.3.20 | FAIL | 1 FAIL, 1 STRAY | 9529/9550 |

The debian, ubuntu 24.04 and fedora rows are the INTERRUPTED rows of the harness bug fixed before R2 (cell 1 interrupted, 29 cells never ran, `0/0`): they are not measurements. The two FreeBSD rows of R1 uploaded no artifact.

### R2 — 13 rows, every row reached a verdict

```
linux-ubuntu-host        __GATE__:FAIL:30:26:3:1:0:0:0:9549:9556
linux-alpine-51          __GATE__:FLAKY:30:29:0:1:0:0:0:9533:9534
linux-alpine-52          __GATE__:FLAKY:30:29:0:1:0:0:0:9531:9534
linux-alpine-53          __GATE__:PASS:30:30:0:0:0:0:0:9534:9534
linux-debian-13          __GATE__:PASS:30:30:0:0:0:0:0:9534:9534
linux-ubuntu-2404        __GATE__:FLAKY:30:29:0:1:0:0:0:9531:9534
linux-fedora-44          __GATE__:PASS:30:30:0:0:0:0:0:9534:9534
macos-bsd                __GATE__:FAIL:30:21:9:0:0:0:0:9303:9555
macos-gnu                __GATE__:FAIL:30:24:4:2:0:0:0:9518:9555
freebsd-clean            __GATE__:FLAKY:30:29:0:1:0:0:0:9532:9533
freebsd-gnu              __GATE__:PASS:30:30:0:0:0:0:0:9533:9533
windows-git-bash         __GATE__:FAIL:30:28:1:0:0:0:1:8888:8890
windows-msys2            __GATE__:FAIL:30:28:2:0:0:0:0:9532:9550
```

| job | row | bash | verdict | cells fail | tests passed/total |
|---|---|---|---|---|---|
| linux | ubuntu host, system bash | 5.3.9 | FAIL | 3 FAIL, 1 FLAKY | 9549/9556 |
| linux | alpine, bash 5.1 | 5.1.16 | FLAKY | 1 FLAKY | 9533/9534 |
| linux | alpine, bash 5.2 | 5.2.37 | FLAKY | 1 FLAKY | 9531/9534 |
| linux | alpine, bash 5.3 | 5.3.20 | PASS | 0 | 9534/9534 |
| linux | debian 13 | 5.2.37 | PASS | 0 | 9534/9534 |
| linux | ubuntu 24.04 | 5.2.21 | FLAKY | 1 FLAKY | 9531/9534 |
| linux | fedora 44 | 5.3.9 | PASS | 0 | 9534/9534 |
| macos | bsd tools, brew bash | 5.3.20 | FAIL | 9 FAIL | 9303/9555 |
| macos | gnu tools, brew bash | 5.3.20 | FAIL | 4 FAIL, 2 FLAKY | 9518/9555 |
| freebsd | clean, pkg bash | 5.3.20 | FLAKY | 1 FLAKY | 9532/9533 |
| freebsd | gnu, pkg bash | 5.3.20 | PASS | 0 | 9533/9533 |
| windows | git-bash | 5.3.15 | FAIL | 1 FAIL, 1 STRAY | 8888/8890 |
| windows | msys2 | 5.3.20 | FAIL | 2 FAIL | 9532/9550 |

Wall time of a gate (`gate <bash>: ... tests X/Y  TIME` in `progress.txt`): Linux rows 3m40s to 5m09s, FreeBSD 3m15s and 3m35s, macOS 10m20s (gnu) and 10m34s (bsd), msys2 18m29s, git-bash 24m52s.

## R2 — failing files per row

Rows in [`L5_failures.tsv`](L5_failures.tsv) (one row per failing test file; FLAKY = failed, passed on the rerun):

| job | row | failing files | FAIL | FLAKY | no file |
|---|---|---|---|---|---|
| linux | ubuntu-host | 6 | 5 | 1 | 0 |
| linux | alpine-51 | 1 | 0 | 1 | 0 |
| linux | alpine-52 | 1 | 0 | 1 | 0 |
| linux | alpine-53 | 0 | 0 | 0 | 0 |
| linux | debian-13 | 0 | 0 | 0 | 0 |
| linux | ubuntu-2404 | 1 | 0 | 1 | 0 |
| linux | fedora-44 | 0 | 0 | 0 | 0 |
| macos | bsd | 40 | 40 | 0 | 0 |
| macos | gnu | 17 | 15 | 2 | 0 |
| freebsd | clean | 1 | 0 | 1 | 0 |
| freebsd | gnu | 0 | 0 | 0 | 0 |
| windows | git-bash | 2 | 1 | 0 | 1 (STRAY) |
| windows | msys2 | 3 | 3 | 0 | 0 |
| total | | 72 | 64 | 7 | 1 |

By suite on the two macOS rows: bsd = kcl/math 3, kcl/thttpserver 4, kcl/tpipe 6, kcl/tregex 2, kcl/tsed 1, kcl/tutil 4, kklass 3, kkore 2, ktests 15; gnu = kcl/thttpserver 3, kcl/tregex 2, kcl/tutil 1, kklass 1 (FLAKY), kkore 1 (FLAKY), ktests 9. Four rows have no failing file at all: alpine-53, debian-13, fedora-44, freebsd gnu.

## R2 — clusters seen (observations only: no causes, no fixes)

1. **Ubuntu host and macOS gnu: the same five files with the same text.** `kcl/thttpserver` 002_Response (`rc=0 out='alive'`), 005_Lifecycle (`before='trap -- '' SIGINT|...' after1=...`), 006_Application (`traps ... fds 8 -> 8 left: active=0`), `kcl/tutil` 005_TextMode (`od='0000000 x y |0000004' false=1 head=2`; `cells/027/fails.txt` of the two rows is equal up to the spacing of the `od` columns) and `ktests` 051_GateVerdicts (the line `[no FDS=0 1 2( 255)?]`). `cells/014/fails.txt` of the two rows is equal once the runner path and the digits are normalised. On macOS gnu, 051 has three or more `[FAIL]` lines (`rc=1 failed=3 fail_lines=3 | gate ...` first; the FDS line is one of them). This is the ledger item `L5.0-o1` (ubuntu host: the same five files in R0 and R1); the macOS gnu row is a second platform with the same texts. All ten failed on the rerun too.
2. **macOS bsd: `timeout` is not found, in 36 of its 40 failing files.** 27 files have `timeout: command not found` in their `[FAIL]` lines; kklass 142 and kkore 015 have `env: timeout: No such file or directory`; ktests 057 has `exec: timeout: not found`; six more show only `rc=127` / `t=127` (tpipe 002 and 005, tsed 008, kklass 143 and 144, ktests 042). The four bsd files without such text: kcl/math 018 (`printf: Broken pipe`), kcl/tregex 002 and 011, ktests 052. The macOS gnu row has no `timeout: command not found` and no `rc=127` in any file. The same 40 files failed in R1, plus two FLAKY files of R1 (cluster 8).
3. **kcl/tregex on both macOS rows, `cells/021/fails.txt` byte-equal:** 002_IsMatch `expected match (rc0) for text='a foo b' re='\<foo\>' flags=''`; 011_T3_T4_LocaleAndAnchors `got 'C|en_US.UTF-8'` and two lines `n=0 offs='' want n=5 offs='0 1 2 3 4'`. No other row of R2 has a tregex failure. The L3 rows for these two files (FreeBSD `expected match (rc0) for text='the cat sat' re='cat'`; Alpine `n=6 ... want n=5`) carry a different text, so the TSV does not mark them known.
4. **ktests gate self-tests fail on both macOS rows:** gnu 9 files (045, 049, 050, 051, 052, 053, 054, 056, 057), bsd 15 (033, 042, 044, 045, 046, 048 to 057). The nine gnu files are all among the bsd ones; 056_PlatformHarness has the same first line `[session /, want ]` on both. On gnu none of them has `command not found` or `rc=127`; on bsd most print `timeout: command not found`. All in R1 as well.
5. **kcl/math 018_DE1_ProgfileSweep on five rows:** FLAKY on ubuntu host (`printf: Broken pipe`, math.sh:850), alpine 5.1 (`killed pid '...' leaked=yes, left '.math_fe_...awk ...'`), alpine 5.2 and ubuntu 24.04 (`out=''`); FAIL on the rerun on macOS bsd (`printf: Broken pipe`, math.sh:850). Ledger `L34-F1-o1`. Earlier runs: FLAKY on alpine 5.3 in R1, on alpine 5.1 and ubuntu host in R0 (the R0 ubuntu host cell lists 018 and 020_L357_ProcsubFifo as flaky), FAIL on macOS bsd in R1. R2 PASS rows for the file: alpine 5.3, debian 13, fedora 44, FreeBSD x2. On macOS bsd 014_M1_EngineDomain and 020_L357_ProcsubFifo also fail (`timeout: command not found`).
6. **Windows, both rows: kkore 011_ConfigProject fails the same two tests** (`KBOOL_CONFIG given as C:\...: relative entries join its folder ...` and `kk.project NAME: not under ~ -> $USERPROFILE/.kbool/NAME/project.conf (C:\ folder, relative paths join it) [U6, U29]`; `fails.txt` equal after the drive paths are removed), also on the rerun, and in R1 on both rows. The L2 rows for this file (Debian/Fedora/Ubuntu) have a different message, so it is not marked known.
7. **Windows ktests cell:** git-bash lost the cell (section below); msys2 fails 054_GateSelection (`git: command not found`, `ktests/tests/054_GateSelection.sh: line 79`) and 057_GateDeafStop (`rec [984 2704] | deaf=no | plain=gone | killf=gone`). R1 msys2 had the same two files plus 044, 045, 052 (STRAY cell; those three are gone in R2); R1 git-bash had 057 with the same text shape (`rec [80 7716] | deaf=no | plain=gone | killf=gone`), not reported in R2 (the cell was lost).
8. **FLAKY single files:** FreeBSD clean ktests 042_KilledRunCleanup (`rc=143 left=[kt_nap...]`, the line of L3_failures:241 on kb-freebsd `clean`); macOS gnu kklass 139_ClassDeclarationSites (`out='files=1 props=a dup=1|gone=0 props=a warn=1 at=1|live=1 props= warn=0 at=0'`) and kkore 007_DebugAndOutName (`1006 ms / 2000 calls`, a timing line); both macOS files were also in R1 (gnu FLAKY, bsd inside its FAIL cells; on bsd they do not fail in R2).
9. **Rows that changed between R1 and R2:** alpine 5.1 and 5.2 were PASS 9534/9534 in R1 and are FLAKY (018) in R2; alpine 5.3 was FLAKY in R1 and is PASS in R2. debian 13, ubuntu 24.04, fedora 44 and the two FreeBSD rows are first measurements (R1 was INTERRUPTED or absent).

### Windows git-bash: why the total is 8890 and not about 9571

`__GATE__:FAIL:30:28:1:0:0:0:1:8888:8890`. The `total` column of the 29 cells that report counts sums to 8890 (`awk` over `cells.tsv`). Cell 30, suite `ktests`, has `verdict=STRAY rc=143 total=0 passed=0 failed=0 duration_ms=907494 reason=2 stray process(es), stopped`, so it counts 0/0. In R1 the same cell had 681 tests (677 passed): 8890 + 681 = 9571, the R1 total of the row.

What its log shows: nothing. `cells/030/log.txt` is empty (0 bytes), `fails.txt` is empty, `summary` is `0 0 0 143` / `error interrupted`, `seg-1.clog` (38 bytes) holds only the path of cell 30's log (no result line for the cell). The cell ran 907.4 s with the gate's `--timeout 900`; `progress.txt`: `[30/30] 5.3.15 threaded neutral ktests STRAY 0/0 907.4s log=cells/030/log.txt (2 stray process(es), stopped)`. The report names two strays, `stray: pid 42592 (yes) started during cell 30: /usr/bin/bash` and `stray: pid 42620 (yes) started during cell 30: /usr/bin/bash`; `strays.txt`: `pid 42592 ppid 1 age 902s orphan=yes started during cell 30: /usr/bin/bash` and `pid 42620 ppid 42592 age 902s orphan=yes ...`, then `stopped them, none left`. `seg-1.result` says `status=done cells_run=30 strays_final=0`. Which test file was running at the time limit is not recorded (empty cell log). For comparison, R1's git-bash ktests cell ended normally (677/681, 057 FAIL) and R2's msys2 ktests cell reported 682 tests.

## Rows known vs new (R2, 72 rows of the TSV)

* known 16: `L5.0-o1` 10 (ubuntu host 5, macOS gnu 5), `L34-F1-o1` 5 (math 018 on ubuntu host, alpine 5.1, alpine 5.2, ubuntu 24.04, macOS bsd), `L3_failures:241` 1 (FreeBSD clean ktests 042).
* new 56: everything else on macOS bsd (39 files), the macOS gnu tregex, ktests, kklass and kkore files (12), the Windows kkore 011 (2), the msys2 ktests 054 and 057 and the git-bash STRAY cell (3).
* `in_R1`: yes 67, no 3 (alpine 5.1 and 5.2 math 018, the git-bash STRAY cell), n-a 2 (ubuntu 24.04 math 018 and FreeBSD clean ktests 042: R1 did not measure those rows).
* `L45-4-o1` (ktests 051 on bash 5.1.16) did not recur: the alpine 5.1 row has no 051 failure in R0, R1 or R2.
