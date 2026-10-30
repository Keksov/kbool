# L5.4 — triage of the CI failures (run R2)

Date 2026-10-30, tree kbool `dc866b1` (kcl `b59b370`, kklass `498bdd5`, kkore `9d21c81`, ktests `3bd5e0e`
— the submodules of CI run R2 = 40974474908, kbool `236d040`; no `-dirty`). Input:
[`L5_failures.tsv`](L5_failures.tsv) (72 rows, all of R2), [`L5_runs.md`](L5_runs.md) (clusters 1–9),
the R0/R1/R2 artifacts (`gate-<job>-<slug>` OUT dirs), [`../../../.github/workflows/ci.yml`](../../../.github/workflows/ci.yml)
and [`../../../.github/ci/linux.sh`](../../../.github/ci/linux.sh). Format model: [`L3_triage.md`](L3_triage.md),
[`L2_triage.md`](L2_triage.md); batch template: [`../LAUNCH_TASKS.md`](../LAUNCH_TASKS.md) "L*.fix — fix batch
template". Hazard ids: [`../PORTING.md`](../PORTING.md) §2. Every mechanism is marked **repro:** (a
probe in a lab VM or on the Windows host, command and output quoted) or **inferred:** (the evidence
named). macOS and the Ubuntu 26 runner have no lab VM; three read-only diagnostic CI steps are in §6.

Probes run for this triage (one VM at a time, each powered off after): kb-freebsd `clean` (SIGPIPE
gate, inherited-fd 051, a `ps` without `sid`, the math 018 race loop), kb-debian `clean` (the math 018
race loop idle and under an 8-worker fork storm), the Windows host (SIGPIPE one-liner, math 018 under
an ignored SIGPIPE, kkore 011 from a `subst` drive). Probe scripts: the L5.4 scratch folder of the
supervisor session (`race018.sh`), not in the tree.

**The main finding.** `L5.0-o1` is not uutils. The five files that fail on the Ubuntu 26 host row fail
the same way on macOS `gnu` (GNU tools, no uutils) and pass in the `ubuntu:24.04`, Debian, Fedora and
Alpine *containers* of the same runner: what the host rows share is the **GitHub runner process**,
which starts every step with **SIGPIPE ignored** (C2, 4 of the 5 files) and with **an extra open file
descriptor** (C3, ktests 051). Neither can be undone by bash (a signal ignored at entry cannot be
trapped or reset by a non-interactive shell; the gate does not close inherited fds). No R2 row needs
uutils-specific work.

## 0. Summary

| cluster | rows | cause (one line) | class | executor | batch / decision |
|---|---|---|---|---|---|
| C1 no `timeout` on macOS `bsd` | 35 | the tests call `timeout`; stock macOS has none (brew coreutils installs only `gtimeout`) | T-test | S (+O) | **OG11** |
| C2 SIGPIPE ignored by the runner | 11 | the runner starts steps with SIGPIPE ignored; bash can never restore it; tests assume the default (and math.sh:850 prints the EPIPE) | PLAT | O | **OG12** (+ L5.4-4 for the 2 math rows) |
| C3 inherited fd in the gate's cells | 1 | the runner leaves an fd > 2 open; the gate promises "fds 0-2 only" in a cell but never closes inherited ones | T-harness | O | L5.4-3 |
| C4 Darwin `ps` has no `sid` | 10 | the harness's stray/session logic falls back to "no session column": self-tests stop and count each other's deliberate orphans | T-harness | O | **OG13** (D1 first) |
| C5 macOS ERE has no `\<` `\>` | 2 | macOS libc `regcomp` (no REG_ENHANCED) rejects `\<foo\>`: rc 2 | PLAT | S | **OG14** |
| C6 tregex 011 assumes no `LC_CTYPE` | 2 | the macOS runner exports `LC_CTYPE`; the "locale the caller chose" case lets the child inherit it and wants `unset` | T-test | S | L5.4-5 (+ OG14 for its `\<` lines) |
| C7 math 018 flake in containers | 3 | the engine probe write into a co-process that already exited kills the caller with SIGPIPE before the sweep (`L34-F1-o1`) | FLAKE | O | L5.4-4 |
| C8 kklass 139 FIFO `source` EINTR | 1 | `source FIFO` on macOS: `Interrupted system call` (3 of 4 macOS cells in R1+R2) | FLAKE | S | L5.4-7 |
| C9 kkore 007 1 s ceiling | 1 | 2000 calls in 1006/1110/1339 ms on the macOS runner (threaded suite on 3 vCPU) | FLAKE | S | L5.4-6 |
| C10 ktests 042 `kt_nap` FIFO left | 1 | FreeBSD nap FIFO lives between `mkfifo` and `rm`; a TERM in that window leaves it (`L3_failures:241`) | FLAKE | O | L5.4-8 |
| C11 kkore 011 hard-coded `C:` | 2 | the expectation is `C:/${F:3}`; CI checks out on `D:` | T-test | S | L5.4-1 |
| C12 msys2 row has no git | 1 | ci.yml installs no `git` in MSYS2; 054 calls `git` unguarded | CI | S | L5.4-2 |
| C13 ktests 057 suspend on the runner | 1 | `NtSuspendProcess` through PowerShell `Add-Type` does not make the process deaf on windows-latest (`deaf=no`) | PLAT | O | SV-1 (D3 first) |
| C14 Git-bash ktests cell wedged | 1 | the cell hung from its first seconds (orphans aged 902 s of 907 s, empty log); 900 s is not too short | FLAKE | — | SV-2 (re-run, watch) |

Per CI row (class counts; the arithmetic of the row set is in §1.0):

| row | rows | T-test | T-harness | PLAT | CI | FLAKE |
|---|---|---|---|---|---|---|
| linux ubuntu-host | 6 | — | 1 | 5 | — | — |
| linux alpine-51 | 1 | — | — | — | — | 1 |
| linux alpine-52 | 1 | — | — | — | — | 1 |
| linux ubuntu-2404 | 1 | — | — | — | — | 1 |
| macos bsd | 40 | 36 | 1 | 3 | — | — |
| macos gnu | 17 | 1 | 9 | 5 | — | 2 |
| freebsd clean | 1 | — | — | — | — | 1 |
| windows git-bash | 2 | 1 | — | — | — | 1 |
| windows msys2 | 3 | 1 | — | 1 | 1 | — |
| **total** | **72** | **39** | **11** | **14** | **1** | **7** |

T-core 0 as a primary class: the two library defects found (math.sh:850 EPIPE noise and the math
probe SIGPIPE, both C7/C2) are fixed by L5.4-4. `L45-4-o1` (ktests 051 on bash 5.1) did not recur:
the 051 rows of R2 are C3/C4, not the 150 s inner-gate stop of L4.2.

Owner decisions needed: **OG11** (timeout), **OG12** (SIGPIPE), **OG13** (Darwin sessions), **OG14**
(tregex word boundaries on macOS) — §2, §3. Supervisor choices: SV-1…SV-4 (§3). Batches that wait on
nothing: L5.4-1 … L5.4-8 (§4).

## 1. Clusters

### 1.0 The row set (step 1)

A row = one line of [`L5_failures.tsv`](L5_failures.tsv) (R2, a failing test file or the lost cell).
Where a file has two causes it is counted in the cluster of its **first** `[FAIL]` line (the TSV's
`first_fail_line`) and named under "also" in the other; the batch of each cause lists it.

| row | TSV rows | per cluster | sum |
|---|---|---|---|
| ubuntu-host | 6 | C2 5 (thttpserver 002 005 006, tutil 005, math 018) + C3 1 (ktests 051) | 5+1 = **6** |
| alpine-51 | 1 | C7 1 (math 018) | **1** |
| alpine-52 | 1 | C7 1 (math 018) | **1** |
| alpine-53, debian-13, fedora-44, freebsd gnu | 0 | — | **0** |
| ubuntu-2404 | 1 | C7 1 (math 018) | **1** |
| macos bsd | 40 | C1 35 + C2 2 (thttpserver 006, math 018) + C4 1 (ktests 056) + C5 1 (tregex 002) + C6 1 (tregex 011) | 35+2+1+1+1 = **40** |
| macos gnu | 17 | C2 4 (thttpserver 002 005 006, tutil 005) + C4 9 (ktests 045 049 050 051 052 053 054 056 057) + C5 1 + C6 1 + C8 1 (kklass 139) + C9 1 (kkore 007) | 4+9+1+1+1+1 = **17** |
| freebsd clean | 1 | C10 1 (ktests 042) | **1** |
| windows git-bash | 2 | C11 1 (kkore 011) + C14 1 (ktests cell) | **2** |
| windows msys2 | 3 | C11 1 (kkore 011) + C12 1 (ktests 054) + C13 1 (ktests 057) | **3** |
| **total** | **72** | C1 35 + C2 11 + C3 1 + C4 10 + C5 2 + C6 2 + C7 3 + C8 1 + C9 1 + C10 1 + C11 2 + C12 1 + C13 1 + C14 1 | **72** |

Files with a second cause ("also"): macOS bsd thttpserver 006 (C2 first, then `timeout` lines: C1),
tutil 005 (C1 first, then the C2 line `head=2` with `sed: stdout: Broken pipe`), ktests 051 (C1 first;
after OG11 its C3/C4 lines remain), ktests 056 (C4 first, then C1); macOS gnu ktests 051 (C4 first,
then the C3 line `[no FDS=0 1 2( 255)?]`); tregex 011 on both macOS rows (C6 first, then the C5
`\<` scan lines `n=0 offs=''`). After OG11 the macOS `bsd` ktests cell is expected to show the C4
failures of the `gnu` row (its 15 files reach the session checks only once `timeout` exists).

### C1 — no `timeout` on macOS `bsd` (35 rows: bsd 35)

Rows: kcl/math 014, 020; kcl/thttpserver 002, 008, 009; kcl/tpipe 001, 002, 003, 004, 005, 006; kcl/tsed
008; kcl/tutil 001, 002, 003, 005; kklass 142, 143, 144; kkore 015, 017; ktests 033, 042, 044, 045, 046,
048, 049, 050, 051, 052, 053, 054, 055, 057. Failing lines (25 + 2 + 1 + 7 = 35):
`timeout: command not found` in 25 files; only `env: timeout: No such file or directory` in kklass 142
and kkore 015 (the doc-example runner `kkore/tests/doc_examples.sh:87` runs each example as
`timeout 300 "$BASH" example.sh`); only `exec: timeout: not found` in ktests 057; only `rc=127`/`t=127`
or nothing in 7 (tpipe 002, 005, tsed 008, kklass 143, 144, ktests 042, and 052, whose driver is
started as `timeout -k 10 150 "$lb" drv.sh … >/dev/null 2>&1` at 052:239-240: the 127 is silent and the
driver's `o1.drv` never appears — `line 234: … o1.drv: No such file or directory`).

Mechanism — **inferred:** the R2 text itself (`timeout: command not found` at the cited lines) plus
ci.yml: the `bsd` row installs only `bash`; macOS ships no `timeout(1)`; Homebrew `coreutils` puts
`timeout` only in `libexec/gnubin` (as `gtimeout` in `bin`), and the `gnu` row, which appends gnubin
at the END of PATH, has no such line in any file. Class **T-test**: no library code uses `timeout`
(§2.1). The owner decision is **OG11** (§2).

### C2 — SIGPIPE ignored by the runner (11 rows: ubuntu-host 5, macOS gnu 4, macOS bsd 2)

Rows: thttpserver 002_Response (ubuntu-host, gnu), 005_Lifecycle (ubuntu-host, gnu), 006_Application
(ubuntu-host, gnu, bsd); tutil 005_TextMode (ubuntu-host, gnu); math 018_DE1_ProgfileSweep (ubuntu-host
FLAKY, bsd FAIL). Failing lines:

* 002 `[FAIL] rc=0 out='alive'` — the case "without the trap the same write kills the shell (rc 141)"
  writes into a dead pipe and expects death by SIGPIPE (002:387-398).
  (macOS bsd 002 is in C1: its first line is a `timeout` one; its rc-141 case failed there with
  `rc=127`, the missing `timeout`.)
* 005 `before='trap -- '' SIGINT|trap -- ': custom term' SIGTERM|trap -- '' SIGPIPE'` and 006 `traps
  … trap -- '' SIGPIPE' → …` — the fixture sets `trap ": custom pipe" PIPE` (005:84) and
  `ths_custom_traps` (`_ths_socket.sh:413`) requires `custom pipe` in the server child's traps; the
  child shows `trap -- '' SIGPIPE`.
* tutil 005 `od='0000000 x y |0000004' false=1 head=2` — the `od` part is equal to its expectation;
  `head=2` is the case "SIGPIPE from a tool that stops reading is not an error"
  (`yes | head -c 200000 | tutil._crStdin head -n 1`, 005:365): the CR filter's `sed` gets EPIPE
  instead of SIGPIPE, prints `sed: stdout: Broken pipe` (visible in the bsd `fails.txt`) and exits 4,
  `_crStdin` answers 2.
* math 018 `out='…/math.sh: line 850: printf: Broken pipe … printf: write error: Broken pipe
  0.8414709848078965|.math_fe_NNNN.awk'` — the first case of 018 makes `awk` refuse `/dev/fd/*`
  (the `SHIM`, 018:31) so the engine's program writer `<(printf '%s\n' "$__MATH_AWK_PROG")`
  (math.sh:850) writes into a pipe nobody reads; with SIGPIPE at its default that writer dies
  silently, ignored it prints two lines into the caller's stderr (captured by `2>&1`). On ubuntu-host
  it is a race (FLAKY), on macOS bsd it lost every time (R1, R2, both attempts).

Mechanism. A signal ignored when a non-interactive bash starts can never be trapped or reset by it or
its children (POSIX; bash enforces it). The runner process ignores SIGPIPE, every step inherits it, and
the gate resets only INT and QUIT for its cells (`env --default-signal=INT,QUIT`, gate.sh:1229; perl
mode `$SIG{INT} = $SIG{QUIT} = "DEFAULT"`). The container rows (`docker run`: a fresh process tree)
and the FreeBSD VM rows pass all five files.

**repro: Windows host (Git-bash 5.3.15)**, the bash rule and the 002 shape:

```
$ bash -c 'bash -c "trap \": custom pipe\" PIPE; trap -p PIPE"'
trap -- ': custom pipe' SIGPIPE
$ bash -c 'trap "" PIPE; bash -c "trap \": custom pipe\" PIPE; trap -p PIPE; exec {fd}> >(exec true); wait \$!; printf x >&\$fd; echo alive rc=\$?"'
trap -- '' SIGPIPE
bash: line 1: printf: write error: Broken pipe
alive rc=1
```

**repro: kb-freebsd `clean`**, the gate started from a parent that ignores SIGPIPE (BSD userland, as
macOS bsd):

```
$ bash -c "trap \"\" PIPE; exec bash ktests/tools/gate.sh --out \$HOME/gpipe --timeout 600 kcl/thttpserver kcl/tutil kcl/math"
[1/3] 5.3.20 threaded neutral kcl/math         PASS          199/199            14.7s
[2/3] 5.3.20 threaded neutral kcl/thttpserver  FAIL          534/536            14.6s  log=cells/002/log.txt
[3/3] 5.3.20 threaded neutral kcl/tutil        FAIL          234/235             3.1s  log=cells/003/log.txt
__GATE__:FAIL:3:1:2:0:0:0:0:967:970
[FAIL] rc=0 out='alive' (002_Response.sh)
[FAIL] traps 'trap -- ': custom int' SIGINT
trap -- ': custom term' SIGTERM
trap -- '' SIGPIPE' → 'trap -- ': custom int' SIGINT
trap -- ': custom term' SIGTERM
trap -- '' SIGPIPE' fds 4 → 4 left: active=0 (006_Application.sh)
[FAIL] od='0000000    x
y
|0000004' false=1 head=2 (005_TextMode.sh)
```

The texts are those of R2. 005_Lifecycle passes there as on macOS bsd: its server cases need an `nc`
dialect FreeBSD's and Apple's `nc` do not offer (`ths_have_nc`; inferred from the two passing rows).
Math 018 passed in that run (the race of the writer); **repro: Windows host**, deterministic:

```
$ for i in 1 2 3; do bash -c 'trap "" PIPE; exec bash kcl/math/tests/018_DE1_ProgfileSweep.sh' | grep -aE "FAIL|Broken"; done
[FAIL] out='/c/projects/kkbot/kbool/kcl/math/math.sh: line 850: printf: Broken pipe
/c/projects/kkbot/kbool/kcl/math/math.sh: line 850: printf: write error: Broken pipe
… (3/3 runs, rc=1)
$ bash kcl/math/tests/018_DE1_ProgfileSweep.sh     # control: SIGPIPE default
control rc=0
```

That the runner itself ignores SIGPIPE is **inferred** (all five texts equal on two runner OSes, absent
in every container/VM row, reproduced exactly by an ignoring parent); D2/D1 (§6) print `SigIgn` and the
child's `trap -p` to confirm it. Class **PLAT** (the process state a CI host hands over). The math rows
are fixed by L5.4-4 (the writer's stderr), the other nine wait on **OG12**.

### C3 — an inherited fd in the gate's cells (1 row: ubuntu-host 1; also macOS gnu 051)

Row: ktests 051_GateVerdicts on ubuntu-host, `[FAIL] [no FDS=0 1 2( 255)?]` (the only failing case of
the file there, `FAIL 17/18`). The probe fixture (`ktests/tests/gate_fixtures/probe/suite/tests.sh:10`)
lists `/proc/$$/fd` (or `/dev/fd`) of the cell; gate.sh:221 documents the cell as "stdin /dev/null,
fds 0-2 only", but nothing in gate.sh closes an fd the launcher inherited — the cell gets it.

**repro: kb-freebsd `clean`**, the test file started with one extra inherited fd, then without:

```
$ bash -c "exec 7</dev/null; exec timeout -k 10 800 bash ktests/tests/051_GateVerdicts.sh"
051 rc=1
[FAIL] [no FDS=0 1 2( 255)?]  (051_GateVerdicts.sh)
$ timeout -k 10 800 bash ktests/tests/051_GateVerdicts.sh
051 control rc=0
```

Which fd the runner leaves open is **inferred** (not in the artifacts); D1/D2 list them. Class
**T-harness** (the gate's own contract). Batch L5.4-3.

### C4 — Darwin `ps` has no `sid` (10 rows: macOS gnu 9, macOS bsd 1)

Rows: macOS gnu ktests 045, 049, 050, 051, 052, 053, 054, 056, 057; macOS bsd ktests 056. Failing
lines: 056 `[session /, want ]`, `[segment 14238: session '?', want its own]`, `[bb=1 ends rc=0; bb=1
stays rc=0; bb=0 ends rc=0; ]`; 057 `deadstart TIMEOUT 0/0 120.8s (timeout 120s, group stopped)`
(want `runner did not start` at ~36 s); 049 `a-left [7882 8516] c0 [6696] b [8444] | s1=0 | row= |
labels= | s2=0`; 050, 051, 052, 053, 054: inner gates whose cells turn STRAY on processes of **another**
test file, e.g. 054 `stray: pid 10298 (yes) started during cell 1: kt_iso-kt045x3984x220316085-stubborn`,
051 `stray: pid 12274 (yes) … kt_iso-kt045x…-lagA` (045's deliberate orphans), and 045 itself
`target 12274 alive=no` (its target was stopped by someone else's stray check).

Mechanism. The ps backend of `ktests/ktest_proc.sh` (:186-215) probes `ps -o pid= -o ppid= -o pgid=
-o sid= …`; macOS ps has no `sid` keyword (its `sess` is a kernel session pointer), so
`KT_PROC_HAS_SID=0` and `tools/strays.sh` (:402-505) runs its `nosid` rules: no per-session roots, the
start-grace look for "a worker in the segment's session" cannot work, a segment's "own session" cannot
be shown. The ktests suite runs threaded, so inner gates of 050-054 run beside 045's deliberate orphans
and, without session scoping, count and stop them. FreeBSD's ps has `sid` (both FreeBSD rows pass).

**repro: kb-freebsd `clean`**, the ktests suite with a `ps` shim on PATH that refuses the `sid`
keyword (`~/shim/ps`: `case "$a" in sid|sid=|*,sid*|sid,*) echo "ps: sid: keyword not found" >&2;
exit 1;; esac; exec /bin/ps "$@"`):

```
$ PATH=$HOME/shim:$PATH timeout -k 60 1300 bash ktests/tools/gate.sh --out $HOME/gnosid --timeout 900 ktests
gate: segment start = perl
[1/1] 5.3.20 threaded neutral ktests    FAIL          645/666           169.3s  log=cells/001/log.txt
__GATE__:FAIL:1:0:1:0:0:0:0:645:666
  12 (045_StrayGuard.sh)   1 (049_SuiteJob.sh)   2 (051_GateVerdicts.sh)   5 (056_PlatformHarness.sh)   1 (057_GateDeafStop.sh)
[FAIL] a-left [28105 29455] c0 [27090] b [29370] | s1=0 | row= | labels= | s2=0 (049_SuiteJob.sh)
[FAIL] [session /, want ]  (056_PlatformHarness.sh)
[FAIL] [bb=1 ends rc=0; bb=1 stays rc=0; bb=0 ends rc=0; ] (want: busybox + gone in time -> 0; busybox + stays -> 1; not busybox -> 1) (056_PlatformHarness.sh)
[FAIL] [segment 45502: session '?', want its own]  | gate … outS.perl …
[FAIL] rc=1 dt=140s [[1/2] 5.3.20 single   neutral deadstart    TIMEOUT           0/0           120.5s  log=cells/001/log.txt  (timeout 120s, group stopped)] …
[FAIL] no 'yes' row for 24980 in: strays: none (bash 5.3.20(0)-release, runtime freebsd15.1, process table ps) (045_StrayGuard.sh)
```

049, 056 (all three shapes) and 057 reproduce with the macOS texts; 045 and 051 fail with other lines
(the cross-test kills depend on timing: the macOS runner is slower). 050, 052, 053, 054 did not fail
on FreeBSD: on macOS their STRAY lines name 045's orphans, so they are **inferred** to be the same
missing session scoping under macOS timing. That macOS ps lacks `sid` is **inferred** (BSD ps manual,
the `session '?'` and empty `KT_PROC_SID` texts); D1 prints the keywords. Class **T-harness**;
decision **OG13** (§3).

056 on gnu also has `[failing env: rc=1]`: the case hides `env` to force the perl start, but the
gate also accepts `genv` (brew coreutils, gate.sh:1196) — a test assumption of its own, in the same
file; the OG13 batch takes it (rule: the case hides `genv` as well).

### C5 — macOS ERE has no `\<` `\>` (2 rows: bsd 1, gnu 1)

Rows: tregex 002_IsMatch, `expected match (rc0) for text='a foo b' re='\<foo\>' flags=''` (002:70);
also the two scan lines of 011 (`n=0 offs='' want n=5 offs='0 1 2 3 4'`: `\<` at 011:110, `\>` at
011:111). `cells/021/fails.txt` is byte-equal on both macOS rows (brew GNU tools do not change bash's
regex engine).

Mechanism — **inferred:** TRegEx matches with bash `[[ =~ ]]`, i.e. the C library's `regcomp` (ERE).
macOS libc supports `\<` `\>` only under `REG_ENHANCED`, which bash does not pass; its word boundaries
are `[[:<:]]` `[[:>:]]` — which musl rejects ([`L3_triage.md`](L3_triage.md) C8: `[[:<:]] rc=2` on
Alpine). L3's "`\<` `\>` work everywhere" therefore does not hold on macOS, and no single word-boundary
spelling works on every platform. D1 probes both spellings. Class **PLAT**; decision **OG14** (§3).

### C6 — tregex 011 assumes no `LC_CTYPE` (2 rows: bsd 1, gnu 1)

Row: tregex 011_T3_T4_LocaleAndAnchors, `[FAIL] got 'C|en_US.UTF-8'` — the case "the unit does not
override a locale the caller chose" (011:70-74) runs `bash -c "export LC_ALL=C; source …; printf
'%s|%s' \"\$LC_ALL\" \"\${LC_CTYPE:-unset}\""` and wants `C|unset`. The unit did not set `LC_CTYPE`
(it self-heals only an empty `LC_ALL`/`LC_CTYPE`/`LANG`, tregex.sh:105); the child inherited
`LC_CTYPE=en_US.UTF-8` from the cell, which keeps the caller's locale variables. **Inferred:** the
macOS runner environment exports `LC_CTYPE` (D1 prints `LANG`/`LC_*`); the sibling probe at 011:61
already does `env -u LC_ALL -u LC_CTYPE -u LANG -u LC_COLLATE`. Class **T-test**. Batch L5.4-5 (the
locale line); its `\<` lines wait on OG14.

### C7 — math 018 flake in the containers (3 rows: alpine-51, alpine-52, ubuntu-2404; `L34-F1-o1`)

Rows: kcl/math 018_DE1_ProgfileSweep, FLAKY on alpine-51 (`killed pid '5707' leaked=yes, left
'.math_fe_5364.awk … .math_fe_5707.awk …'`), alpine-52 and ubuntu-2404 (`out=''`, then `left
'… .math_fe_4502.awk …'` = the dead pid's file not swept, then `killed pid … leaked=yes`). Earlier:
R0/R1 alpine and the L34-F1 kb-alpine/kb-fedora gates (ledger).

Mechanism — **inferred** from the code and the three shapes. With the `SHIM` the procsub awk exits at
once. `math._fe_start` tries the procsub source first (math.sh:996) and sweeps old `.math_fe_*.awk`
files only on the fallback path afterwards (math.sh:1004). `math._fe_spawn` writes its probe
`printf 'pi\n' 2>/dev/null >&$__MATH_FE_IN` (math.sh:878) right after `coproc`: when the co-process has
already exited, that write raises SIGPIPE in the **calling** shell — default disposition in a container
— and the whole `bash -c` dies with no output (`2>&1` captured nothing): `out=''`. A shell that dies
there never reaches the sweep, which explains the other two shapes (the dead pid's file in case 2,
the killed pid's file in case 3, where the sweeping process is the `math.cos 0` start). With SIGPIPE
ignored (C2 rows) the same write gets EPIPE, the fallback runs, and only the :850 noise is left —
the same race seen from the other disposition.

Not reproduced: `race018.sh` (the 018 case-1 snippet in a loop, counting rc/output):

```
kb-freebsd clean (BWK awk)            300  rc=0 out=0.8414709848
kb-debian clean (gawk), idle          300  rc=0 out=0.8414709848
kb-debian clean, SIGPIPE ignored      100  rc=0 out=0.8414709848
kb-debian clean, 8-worker fork storm  300  rc=0 out=0.8414709848
Windows host (Git-bash)                40  rc=0 out=0.8414709848
```

On an idle box the co-process (a fork that runs `math._fe_pfopen <(…)` first) is always slower than
the parent's next `printf`; the CI hits are rare and load-dependent (5 rows in 3 runs, on 5 different
rows). Class **FLAKE** (a T-core race). Batch L5.4-4.

### C8 — kklass 139 `source` of a FIFO: EINTR on macOS (1 row: gnu 1)

Row: kklass 139_ClassDeclarationSites, FLAKY, `out='files=1 props=a dup=1|gone=0 props=a warn=1
at=1|live=1 props= warn=0 at=0' err='…/S25.sh: line 10: …/sh-np.h1: Interrupted system call'`. S25
(139:724-737) starts `printf … > "$TMPD/sh-np.h1" &` and then `source "$TMPD/sh-np.h1"`: the reader's
blocking FIFO `open()` returns EINTR (a SIGCHLD of the fast-exiting writer). R1: the same line on
macOS bsd and gnu; R1 bsd had also `live=1 props=a … err=''` (the `sh-np-2` FIFO). Linux, FreeBSD and
Windows never showed it. **Inferred** (the EINTR text; Darwin does not restart a FIFO open after a
handled signal). Class **FLAKE**. Batch L5.4-7.

### C9 — kkore 007 1 s ceiling on the macOS runner (1 row: gnu 1)

Row: kkore 007_DebugAndOutName, FLAKY, `[FAIL] 1006 ms / 2000 calls` ("2000 kk._outName calls cost
under 1 s [perf contract]", 007:495-504; no fork in the window). Sightings: R1 bsd 1339 ms, R1 gnu
1110 ms, R2 gnu 1006 ms; every Linux/FreeBSD/Windows row passes. **Inferred:** the kkore suite runs
threaded (several test files at once) on a 3-vCPU macOS runner — CPU contention, not a regression.
Class **FLAKE**. Batch L5.4-6 (best-of-3, the precedent of `kcl/tinifile/tests/011_T6_Performance.sh`,
`kcl/tutil/tests/004_Bench.sh`).

### C10 — ktests 042 leaves a `kt_nap` FIFO on FreeBSD (1 row: freebsd clean 1; `L3_failures:241`)

Row: ktests 042_KilledRunCleanup, FLAKY, `[FAIL] rc=143 left=[kt_nap.84431.387116910]` ("a threaded
run killed with TERM leaves nothing in TMPDIR", 042:92-104). The only creator of `kt_nap.*` is
`kt_proc_napfd` (ktest_proc.sh:138-142): where there is no `/dev/ptmx` (FreeBSD) it does `mkfifo`,
`exec {fd}<>` and `rm -f` — a FIFO exists in TMPDIR between those commands, and a process of the run
that gets the TERM (rc 143) there leaves it. **Inferred** (code + the two sightings: L3 kb-freebsd
`clean` FAIL, R2 CI FLAKY); FreeBSD `gnu` lacks `/dev/ptmx` too and passed by chance. Class **FLAKE**
(T-harness race). Batch L5.4-8.

### C11 — kkore 011 hard-codes the `C:` drive (2 rows: git-bash 1, msys2 1)

Rows: kkore 011_ConfigProject, the cases "KBOOL_CONFIG given as C:\\..." (011:92) and "kk.project NAME:
not under ~ …" (011:231): the expectations are `C:/${F:3}/c/4/sub/lib2` and `C:/${F:3}/w/.kbool/wproj/lib`
(`${F:3}` strips `/c/`); CI checks out on `D:\a\kbool\kbool`, the unit answers `D:/a/kbool/…`
correctly.

**repro: Windows host**, the tree on a `subst` drive (`subst Q: C:\projects\kkbot\kbool`, removed
after with `subst Q: /D`):

```
$ cd /q && timeout -k 10 300 bash kkore/tests/011_ConfigProject.sh | grep FAIL
[FAIL] KBOOL_CONFIG given as C:\...: relative entries join its folder (separators folded to /), the unit is found — rc=0 out='u=0 1 | Q:/kkore/tests/.tmp/ConfigProject.011_ConfigProject.363257/fx/c/4/winlib,Q:/kkore/tests/.tmp/ConfigProject.011_ConfigProject.363257/fx/c/4/sub/lib2' (011_ConfigProject.sh)
[FAIL] kk.project NAME: not under ~ -> $USERPROFILE/.kbool/NAME/project.conf (C:\ folder, relative paths join it) [U6, U29] — rc=0 out='p=0 | u=0 L=1 | Q:/kkore/tests/.tmp/ConfigProject.011_ConfigProject.363257/fx/w/.kbool/wproj/lib' (011_ConfigProject.sh)
rc=1
```

No other test has the `C:/${X:3}` form (grep of every `tests/*.sh` for `{NAME:3}` and `"C:/`). Class
**T-test**. Batch L5.4-1.

### C12 — the msys2 row has no git (1 row: msys2 1)

Row: ktests 054_GateSelection, `[FAIL] /d/a/kbool/kbool/ktests/tests/054_GateSelection.sh: line 79:
git: command not found`, then every `--changed` case `rc=2 | gate: --changed needs git`. ci.yml's
msys2 install list (`gnu-netcat gawk diffutils findutils grep sed curl openssl perl util-linux`) has no
`git`; the gate itself copes (`gate repos: (no git)`, a clear usage error for `--changed`), the test
does not (054:78-80 builds its fixture repo with `git` unguarded). **Inferred** (the text + ci.yml).
Class **CI** (+ a test without a SKIP). Batch L5.4-2.

### C13 — ktests 057 cannot suspend a process on windows-latest (1 row: msys2 1)

Row: ktests 057_GateDeafStop, `[FAIL] rec [984 2704] | deaf=no | plain=gone | killf=gone` (R1 git-bash:
`rec [80 7716] | deaf=no …`), then the scenarios built on a deaf process. `drv_deaf` (057:166-186)
suspends a `sleep` with PowerShell `Add-Type … NtSuspendProcess` and expects `kill -KILL` to fail
(`deaf=yes`); on the runner the process dies (`deaf=no`). The PowerShell call's output goes to
`/dev/null`, so why it does not suspend (Add-Type compile, `Get-Process` access, a policy of the image)
is unknown — **inferred** only that the suspend does not take effect; passes on this host in every
Windows gate. Class **PLAT** (provisional). SV-1: run D3 (§6) first.

### C14 — the Git-bash ktests cell wedged (1 row: git-bash 1)

Row: cell 30 (ktests) `verdict=STRAY rc=143 total=0 duration_ms=907494`, `log.txt` empty, two orphans
`pid 42592 ppid 1 age 902s` and `pid 42620 ppid 42592 age 902s` (`/usr/bin/bash`), "stopped them,
none left".

Is 900 s too short? No. The ktests cell on the Windows runner took 578 s (R1 git-bash, incl. a 057
re-run), 500 s (R1 msys2) and 582 s (R2 msys2): 900 s is 1.55× the slowest. The R2 cell did not run
slowly — it hung at once: both orphans were 902 s old in a 907 s cell (started in its first ~5 s) and
the cell log never got a byte (a running test file writes its header at once). That is the Git-bash
runtime wedge of [`../../../ktests/docs/GATE_FOR_AGENTS.md`](../../../ktests/docs/GATE_FOR_AGENTS.md)
("runner did not start … a cygwin FIFO open that never returns, launch L2.7-G"); the start-grace stop
did not fire because a child (42620) existed. **Inferred** (the ages, the empty log, R1's normal run of
the same row). Class **FLAKE**, one sighting. SV-2.

## 2. OG11 — `timeout` on macOS (decision for the owner)

### 2.1 Where kbool needs `timeout`

`timeout` invocations (`grep -E` for `timeout` followed by an option, `--` or a duration, at a
command position, `env …`, `exec`; comments excluded):

| where | files | lines | what |
|---|---|---|---|
| library code (kcl units, kklass, kkore, kbool.sh) | 0 | 0 | — |
| harness (ktests) | 2 | 3 | `ktest_proc.sh:583` optional (`[[ -x "$__ktp_bin/timeout" ]]`), `:617` busybox probe (harmless without it); `tools/timing_check.sh:373` `exec timeout` (dev tool, hard) |
| harness name checks (no call) | 4 | ~8 | gate.sh:2004, ktest_proc.sh:495, strays.sh `timeout D` roots, suitejob.sh:310 — they recognise a `timeout` *parent*/*watcher* by its argv |
| test files | 52 | 179 | kcl/math 2/2, tawk 2/19, tfind 2/5, tgrep 2/4, thead 2/4, thttpserver 8/24, tpipe 6/12, tsed 3/7, ttail 2/10, tutil 4/8; kklass 2/3 (142 via kkore's doc runner, 143, 144 → 2 files + the shared runner); kkore 2/4 (`doc_examples.sh:87`, 017); ktests 15/77 |
| lab tooling (host only) | 4 | ~8 | tools/vmlab (Windows host, not shipped behaviour) |

Options the tests use: plain `timeout N` (389 occurrences incl. the ones in arrays/strings), `-k N`
(54), `-s TERM` (3), `--foreground` (1, FreeBSD `KT_TMO_BOUND`), `--preserve-status` (042), and rc 124
for "timed out" (044:61, math 014). The wrapper suites (tawk, tfind, tgrep, thead, ttail, most of tsed)
did not fail on `bsd` only because they SKIP their behavioural cases on a non-GNU tool before reaching
`timeout`.

### 2.2 Options

**(a) The tests require GNU `timeout` by that name; without it they SKIP with a reason.** A helper in
`ktests/ktest.sh` (`kt_need_timeout`) at the top of each of the 52 files; ci.yml's `bsd` row stays
"Apple tools only" (it SKIPs) or installs coreutils with gnubin (then it is the `gnu` row).
A stock Mac (`brew install bash` only) runs `bash ktests/tools/gate.sh kcl/tpipe` and sees
`[SKIP] needs timeout(1) (GNU coreutils: brew install coreutils, with libexec/gnubin on PATH)` for 6 of
the 7 tpipe files; a Mac with brew coreutils but no gnubin on PATH (the brew default) still SKIPs,
because brew names it `gtimeout`. Cost: helper ~15 lines + 52 files × 1-2 lines, Sonnet. Risk: low;
coverage on macOS drops unless the user changes PATH.

**(b) ktests ships a portable `kt_timeout` (bash) and the tests use it.** An executable script
`ktests/tools/kt_timeout.sh` (a function cannot be `exec`ed or run through `env`, which 9 call sites
do): `kt_timeout [-k K] [-s SIG] [--foreground] [--preserve-status] DUR CMD…` — CMD as a child, on
expiry SIG (default TERM) then KILL after K, rc 124 on expiry (137 after KILL with GNU's
`--preserve-status` semantics), TERM/INT/HUP to the wrapper forwarded to CMD, CMD's rc otherwise.
A stock Mac runs every test with no install. Cost: the script ~120 lines + its own test ~150 lines
(Opus), 52 files mechanical (~180 lines, Sonnet), and the harness name checks of §2.1 must learn the
new process shape (a bash, not `timeout`, as parent/watcher — gate parent watch, strays roots,
FreeBSD reaper rule): ~40 lines in gate.sh/ktest_proc.sh/strays.sh/suitejob.sh, Opus, floor gate.
Risk: **high** — timing and process-group semantics differ from GNU/BSD/busybox `timeout`
(GNU's own process group and `kill(0, sig)`), and every harness rule keyed on `timeout` argv changes;
the busybox/FreeBSD special cases of L2.1 would be re-opened.

**(c) Resolve `timeout`/`gtimeout` by name, as the OG1 wrappers do; neither → SKIP with a reason.**
`ktests/ktest.sh` sets `KT_TIMEOUT` (a path: usable with `exec`, `env` and plain calls) to `timeout`,
else `gtimeout`; the 52 files call `"$KT_TIMEOUT"` and start with `kt_need_timeout` (SKIP when empty).
The harness name checks also accept `gtimeout`. A Mac with `brew install coreutils` (no PATH change)
runs everything through `/opt/homebrew/bin/gtimeout`; a stock Mac sees `[SKIP] needs timeout(1) or
gtimeout (brew install coreutils)`; Linux/FreeBSD/Windows unchanged. Cost: helper ~20 lines,
52 files mechanical (~180 lines + 52 guard lines, Sonnet), harness name checks ~8 lines (Opus, floor
gate). Risk: low — the same GNU binary and semantics the harness already handles; ci.yml's `bsd` row
either keeps Apple tools only (SKIPs) or, if the runner image has `gtimeout` preinstalled (its
"preinstalled GNU tools (bsd row)" step-summary already lists it — SV can read R2's summary; D1 prints
it too), runs the tests through it.

**Recommendation: (c).** It is OG1's rule applied to the test tool (g-name resolved, else a clear
SKIP), keeps the GNU `timeout` semantics the harness was tuned on (`-k`, rc 124, `--foreground`,
`--preserve-status`, the busybox/FreeBSD watcher rules), and costs a mechanical Sonnet pass plus a
small Opus harness change. (b) only if the owner wants full coverage on a Mac without Homebrew
coreutils. **The owner decides — OG11.**

## 3. Other decisions

### OG12 — SIGPIPE ignored by the caller (C2: 9 rows after L5.4-4)

What a user sees today, example: in a GitHub Actions step (or under any parent that ignores SIGPIPE)
`yes | head -c 200000 | tutil._crStdin head -n 1` returns **2** and prints `sed: stdout: Broken pipe`;
in a terminal it returns 0 silently. THttpServer cannot restore a custom PIPE trap there (bash refuses
to set it), so its "traps identical before and after Serve" promise holds only as "identical".

* **(a) The gate gives every cell SIGPIPE at its default, like INT/QUIT.** `env
  --default-signal=INT,QUIT,PIPE` (probe it in `_kt_gate_spawn_detect`), the perl start
  `$SIG{PIPE}="DEFAULT"`, jobctl (busybox) cannot ⇒ the existing `[WARN]` names PIPE too. CI host rows
  then test what a terminal user gets; a user under an ignoring parent still sees the example above
  (PORTING.md gets the caveat). Cost: gate.sh ~6 lines + one 056 case + a README line; Opus, floor gate.
* **(b) The library and the tests support an ignored SIGPIPE.** A `kt_sigpipe_ignored` probe; 002's
  rc-141 case, 005/006's custom PIPE trap pass as N/A (`ths_int_ignored` is the precedent for INT);
  tutil `_crStdin` must tell "the reader left" from a real filter failure without SIGPIPE (design
  work in tutil, O). Cost: 4 test files ~40 lines + an open tutil design.
* **(c) ci.yml only.** The host rows start the gate through `env --default-signal=PIPE` (Ubuntu) and
  `perl -e '$SIG{PIPE}="DEFAULT"; exec @ARGV'` (macOS). CI turns green; a developer whose own shell
  ignores SIGPIPE gets the 9 FAILs from the gate. Cost: ~4 lines of ci.yml, Sonnet.

Recommendation: **(a)** — the gate already guarantees "INT/QUIT trappable in the cells" for the same
reason (a disposition the cell cannot repair), it fixes the gate for every caller, not only CI, and it
is the smallest harness change; the user-visible caveat is documented, not hidden.

### OG13 — stray accounting where `ps` has no session id (C4: macOS)

Example: a macOS developer runs `bash ktests/tools/gate.sh ktests`; 9-10 harness self-tests FAIL
because concurrent inner gates stop and count each other's deliberate orphans (`stray: pid 10298 (yes)
started during cell 1: kt_iso-kt045…-stubborn`). Normal suites are hardly affected (only processes
carrying a test marker that start inside the cell window are taken).

* **(a) A session id from another source on Darwin.** If D1 shows a usable one (`ps -o sess` that
  differs per session and equals for one session, or `os.getsid` through a python3 that every macOS
  image has — one fork per snapshot), `ktest_proc.sh` fills `KT_PROC_SID` from it; the macOS developer
  gets Linux/FreeBSD behaviour. Cost: ktest_proc.sh ~30 lines + 056 case; Opus, floor gate. Risk:
  `sess` may be a pointer (equality only: "leads its session" `sid == pid` cannot be computed).
* **(b) Serialize the self-tests where there is no session column.** The ktests suite runs 045-057
  one at a time on such a platform. Not sufficient alone: the FreeBSD repro shows 045, 049, 056, 057
  fail in no-sid mode by themselves (they assert session facts).
* **(c) The session-dependent self-tests SKIP with a reason on a platform without session ids**
  (`no session ids from ps on this platform: stray scoping not testable`), the gate keeps its current
  no-sid rules (documented as weaker). The macOS developer sees ~10 files SKIP. Cost: a guard in 10
  files + PORTING note; Sonnet.

Recommendation: run **D1 first**; **(a)** if it finds a real session id, else **(c)**.

### OG14 — word boundaries in TRegEx on macOS (C5)

Example: `TRegEx.isMatch "a foo b" '\<foo\>'` is rc 0 on Linux, FreeBSD, Windows and rc 2 (invalid
pattern) on macOS; `\b` is rc 2 on macOS and FreeBSD; `[[:<:]]foo[[:>:]]` works on macOS and FreeBSD
but is rc 2 on musl. No spelling works everywhere.

* **(a) N/A + docs** (the L3 C8 precedent): 002/011 probe `\<` and pass its rows as `N/A: this C
  library's ERE has no \< \> (macOS: [[:<:]] [[:>:]])`; the README/`docs/ERE-vs-PCRE.md` table gets the
  macOS column. Cost: 2 test files ~15 lines + doc; Sonnet.
* **(b) TRegEx translates** `\<` `\>` (and `\b`) to the spelling the C library accepts, probed once
  per process. Users write `\<foo\>` on every platform. Cost: tregex.sh ~40 lines (escape- and
  bracket-aware rewriting) + tests; Opus. Risk: pattern-rewriting bugs (`[\<]`, `\\<`).

Recommendation: **(a)** for the launch; (b) as a later feature if the owner wants portable word
boundaries.

### SV-1 — ktests 057 on windows-latest (C13)

Run D3 (§6) on both Windows rows; it prints PowerShell's own output of the suspend. Then: if
`Add-Type`/the suspend fails on the image for a reason the test can detect, 057's deaf scenarios
SKIP with that reason (S card); if it works there and the process still dies, it is a harness finding
(O card). Until then the msys2 row (and git-bash, R1) stays red on 057.

### SV-2 — the Git-bash wedge (C14)

Keep `--timeout 900` (raising it only makes a wedge cost more; the slowest real ktests cell is 582 s).
Re-run on the next push; if the same shape recurs (empty log, bash orphans from the first seconds,
STRAY at the timeout), open an O investigation of why the start-grace rule (gate.sh:254-259,
"a test file's shell … in the segment's session") counted the wedged child as a started runner.

### SV-3 — ledger

`L5.0-o1`: resolved as C2 (4 files) + C3 (051); not uutils. `L34-F1-o1`: the 018 shapes explained by
C7 (+ the :850 noise of C2); 019/020 flakes of the ledger are not in R2. `L3_failures:241`: C10.
`L45-4-o1`: no recurrence (close or keep watching — SV).

### SV-4 — batch order (one gate slot, one VM at a time)

L5.4-1, L5.4-2, L5.4-5, L5.4-6, L5.4-7 (Sonnet, independent, test/CI files) → L5.4-4 (O, kcl/math) →
L5.4-3 + L5.4-8 (O, ktests; one floor gate for both) → after OG11-OG14: their batches; OG11's
mechanical pass after L5.4-3/-8 (both touch ktests). One push after each group; the CI rows of §5 are
the acceptance.

## 4. Fix batches

```
CARD: L5.4-1  [S]
Goal: kkore 011 passes on any drive letter; nothing else changes behaviour.
Rows: windows git-bash + msys2, kkore 011_ConfigProject.sh — "KBOOL_CONFIG given as C:\..." (:92) and
      "kk.project NAME: not under ~ ..." (:231); repro §1 C11 (subst Q:); cause: expectation C:/${F:3}.
Fix rule: build the two expectations from the real drive spelling of $F: `uf_win "$F"; FW=${UF_WIN//\\//}`
          (the helper the file already uses for W4LIB) and expect "$FW/c/4/sub/lib2" and
          "$FW/w/.kbool/wproj/lib" instead of "C:/${F:3}/...". No other line changes.
Write scope: kkore/tests/011_ConfigProject.sh
Acceptance:
  - repro: `cmd //c 'subst Q: C:\projects\kkbot\kbool'; cd /q && timeout -k 10 300 bash kkore/tests/011_ConfigProject.sh; cmd //c 'subst Q: /D'`
    → no [FAIL] (literal output); `subst` lists nothing afterwards
  - gate kkore on both Windows runtimes PASS, totals unchanged (GATE_FOR_AGENTS.md)
  - CI: windows git-bash and msys2, cell kkore PASS
Stop if: uf_win does not give the C:/-style spelling on one runtime → BLOCKED with its output.
Timebox: 30 min
```

```
CARD: L5.4-2  [S]
Goal: the msys2 CI row has git; 054 SKIPs (not FAILs) its git cases where git is missing.
Rows: windows msys2, ktests 054_GateSelection.sh, `line 79: git: command not found` + every --changed case.
Fix rule: (1) .github/workflows/ci.yml, step "MSYS2 (msys2 row)": add `git` to `install:` (the gate's
          `gate repos:` line and --changed are part of what an MSYS2 user runs; pacman has git).
          (2) 054: when `command -v git` fails, every case that needs the fixture repo passes as
          `kt_test_pass "N/A: no git on PATH (gate --changed needs git)"` — same titles, same count; the
          cases that do not use git run as before. Comment/header line of ci.yml updated ("the msys2
          row has no git inside its shell" → it has).
Write scope: .github/workflows/ci.yml (that step and the comment above the windows job), ktests/tests/054_GateSelection.sh
Acceptance:
  - YAML valid: `python -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/ci.yml`
  - 054 with git hidden: `PATH=<a dir without git>:… bash ktests/tests/054_GateSelection.sh` → 0 FAIL, the N/A lines (literal)
  - gate ktests on both Windows runtimes PASS; bash-floor gate (ktests changed) PASS
  - CI: windows msys2 shows `gate repos: kbool …` (not `(no git)`) and no 054 failure
Stop if: msys2/setup-msys2 cannot install git within the step → BLOCKED with the log.
Timebox: 45 min
```

```
CARD: L5.4-3  [O]
Goal: a gate cell has exactly fds 0-2 (+ bash's 255) whatever the caller left open.
Rows: linux ubuntu-host ktests 051_GateVerdicts.sh `[no FDS=0 1 2( 255)?]` (also macOS gnu 051); repro §1 C3.
Fix rule: the launcher closes every fd > 2 it inherited before it starts a segment (list /proc/$$/fd,
          else /dev/fd, at launcher start, before it opens any fd of its own; skip 255 and the fds the
          gate itself opens later, e.g. the nap fd). Also for the rescue watchdog start. Document it at
          gate.sh:221. No fd closing in tests.sh/ktests.sh (the cell contract is the gate's).
Write scope: ktests/tools/gate.sh; ktests/tests/051_GateVerdicts.sh (one new case: the gate started
             with an extra fd 7 → the probe still shows FDS=0 1 2[ 255]); ktests/tools/README.md (one line)
Acceptance:
  - red first: the new 051 case fails on the current gate (literal)
  - repro in kb-freebsd clean: `bash -c "exec 7</dev/null; exec timeout -k 10 800 bash ktests/tests/051_GateVerdicts.sh"` → rc 0
  - gate ktests on both Windows runtimes PASS; bash-floor gate kb-debian clean-bashes PASS
  - CI: ubuntu-host ktests cell has no 051 failure
Stop if: an fd the gate needs is inherited from its caller by design (e.g. a --nohup path) → BLOCKED.
Timebox: 2 h
```

```
CARD: L5.4-4  [O]
Goal: the math engine start can never kill or pollute its caller through a dead co-process pipe.
Rows: C7 — kcl/math 018 FLAKY on alpine-51, alpine-52, ubuntu-2404 (out='', dead pid's file not swept,
      killed pid leaked; L34-F1-o1); C2 — kcl/math 018 on ubuntu-host (FLAKY) and macOS bsd (FAIL):
      `math.sh: line 850: printf: Broken pipe`.
Fix rule: (1) math.sh:850 — the program writer of the procsub sends its own stderr to /dev/null
          (`<(printf '%s\n' "$__MATH_AWK_PROG" 2>/dev/null)`); (2) math._fe_spawn's probe write
          (math.sh:878) cannot deliver SIGPIPE to the calling shell: do it in a subshell
          (`( printf 'pi\n' >&$__MATH_FE_IN ) 2>/dev/null` — one fork per engine START only, never per
          call), its failure = rc 1 as now. Keep the 5.1-safe unquoted fd form (launch L4.3).
Write scope: kcl/math/math.sh; kcl/math/tests/018_DE1_ProgfileSweep.sh (a case run under
             `trap '' PIPE` in the parent: out has no "Broken pipe"); one new or extended test that makes
             the co-process exit before the probe deterministically (e.g. an awk stub plus a wait on its
             exit before the probe — your design) and checks the caller survives with the fallback.
Acceptance:
  - red first for both new cases (literal output)
  - host repro: `for i in 1 2 3; do bash -c 'trap "" PIPE; exec bash kcl/math/tests/018_DE1_ProgfileSweep.sh'; done` → 3× rc 0
  - gate kcl/math on both Windows runtimes PASS, totals +N only for the new cases
  - kcl only: CI rows alpine-51/52/53, ubuntu-2404, ubuntu-host, macOS bsd: no 018 failure (two consecutive pushes)
Stop if: the deterministic test cannot be built without a test hook in math.sh → BLOCKED with the options.
Timebox: 2 h
```

```
CARD: L5.4-5  [S]
Goal: tregex 011's "caller chose a locale" case does not depend on the cell's LC_CTYPE.
Rows: macOS bsd + gnu, kcl/tregex 011_T3_T4_LocaleAndAnchors.sh `[FAIL] got 'C|en_US.UTF-8'` (011:70-74).
Fix rule: start that child as the sibling probe at 011:61 does: `env -u LC_CTYPE -u LANG bash -c "export LC_ALL=C; …"`
          (LC_ALL=C is the caller's choice under test; nothing else inherited). The `\<` scan lines of
          011 are NOT touched here (OG14).
Write scope: kcl/tregex/tests/011_T3_T4_LocaleAndAnchors.sh
Acceptance:
  - `LC_CTYPE=en_US.UTF-8 bash kcl/tregex/tests/011_T3_T4_LocaleAndAnchors.sh` on the host: the case passes (red before: literal)
  - gate kcl/tregex on both Windows runtimes PASS
  - CI: macOS rows, 011 no longer shows `got 'C|en_US.UTF-8'`
Stop if: the case fails for another reason on the host → BLOCKED.
Timebox: 30 min
```

```
CARD: L5.4-6  [S]
Goal: kkore 007's perf contract is measured robustly on a loaded runner.
Rows: macOS gnu kkore 007_DebugAndOutName.sh `[FAIL] 1006 ms / 2000 calls` (R1: 1339, 1110 ms).
Fix rule: the 2000-call loop runs up to 3 times; the case passes when the BEST run is < 1000 ms (stop
          early on the first pass); the message names every run (`best 812 ms of [1006 812] / 2000
          calls`). Precedent: kcl/tinifile/tests/011_T6_Performance.sh, kcl/tutil/tests/004_Bench.sh.
          No fork inside the timed window (unchanged).
Write scope: kkore/tests/007_DebugAndOutName.sh
Acceptance:
  - gate kkore on both Windows runtimes PASS
  - CI: macOS gnu and bsd kkore cells without 007 in two consecutive runs
Timebox: 20 min
```

```
CARD: L5.4-7  [S]
Goal: kklass 139 S25 survives an interrupted FIFO open on macOS.
Rows: macOS gnu kklass 139_ClassDeclarationSites.sh FLAKY, `S25.sh: line 10: …/sh-np.h1: Interrupted system call`
      (R1 bsd + gnu: same; R1 bsd also `live=1 props=a` on sh-np-2).
Fix rule: in the S25 fixture each `source FIFO` (the sh-np.h1 and sh-np-2 cases) is retried once when it
          failed and its stderr says "Interrupted system call" (the writer is still blocked in its open,
          nothing was read); the second stderr is the one checked. No change to kklass.
Write scope: kklass/tests/139_ClassDeclarationSites.sh
Acceptance:
  - gate kklass on both Windows runtimes PASS, totals unchanged
  - CI: macOS rows kklass cell without 139 in two consecutive runs
Stop if: the sh-np-2 failure of R1 bsd (`live=1`, no stderr) is not covered by the rule → report it as OPEN, do not widen the retry.
Timebox: 30 min
```

```
CARD: L5.4-8  [O]
Goal: no kt_nap.* FIFO outlives a TERMed ktests run on a platform without /dev/ptmx.
Rows: freebsd clean ktests 042_KilledRunCleanup.sh FLAKY `rc=143 left=[kt_nap.84431.387116910]`
      (L3_failures:241: FAIL on kb-freebsd clean).
Fix rule: kt_proc_napfd's FIFO must not be visible in a shared TMPDIR window that a TERM can freeze: the
          runner's TERM/EXIT cleanup (the code that removes its kt_iso.* dirs) also removes
          "$TMPDIR/kt_nap.<pid>.*" for its own pid and every member pid it recorded — the name already
          carries the creating $BASHPID. No change on platforms with /dev/ptmx (no FIFO is made there).
Write scope: ktests/ktest_proc.sh, ktests/ktest_runner.sh (or the file holding that cleanup),
             ktests/tests/042_KilledRunCleanup.sh (a case with KT_PROC_NAPFD forced to the FIFO path
             if that knob exists — else add it to ktest_proc.sh's header as a test knob)
Acceptance:
  - red first: the forced-FIFO case shows a left kt_nap.* before the fix (literal)
  - kb-freebsd clean: `vmlab.sh gate kb-freebsd --snapshot clean -- --repeat 3 ktests` PASS
  - gate ktests on both Windows runtimes PASS; bash-floor gate PASS
Stop if: the FIFO is created by a process whose pid the runner never records → BLOCKED with the evidence.
Timebox: 2 h
```

After the decisions (outline; SV fills the cards from the chosen option):

* **OG11 = (c)** → L5.4-9 [S + O]: `KT_TIMEOUT`/`kt_need_timeout` in ktest.sh, the harness name checks
  accept `gtimeout` (O, ktests), then the 52 files mechanically (S, per repo). Acceptance: macOS bsd
  row: the 35 C1 rows run (gtimeout) or SKIP with the reason, no `command not found`.
* **OG12 = (a)** → L5.4-10 [O]: gate.sh PIPE default (env/perl/jobctl), 056 case, README; floor gate;
  CI ubuntu-host and macOS: thttpserver 002/005/006, tutil 005 pass.
* **OG13** (after D1) → L5.4-11 [O or S].
* **OG14 = (b)** (owner, 2026-10-30) → L5.4-12 [O + critic]: TRegEx rewrites `\<` `\>` `\b` where the
  C library does not spell them (FreeBSD `\b` → `(\<|\>)`, macOS → `[[:<:]]`/`[[:>:]]`), probed once,
  inserted groups removed from the user's numbering; 002/011 N/A branches go.

## 5. Expected effect per CI row

| row | now (R2) | after L5.4-1…8 | after OG11-OG14 batches | open |
|---|---|---|---|---|
| ubuntu-host | FAIL 6 | 018 (L5.4-4), 051 (L5.4-3) gone → 4 left (C2) | PASS (OG12) | — |
| alpine-51 / alpine-52 / ubuntu-2404 | FLAKY 018 | PASS if C7 is the mechanism (watch two runs) | — | C7 not reproduced |
| alpine-53, debian-13, fedora-44, freebsd gnu | PASS | PASS | PASS | — |
| macos bsd | FAIL 40 | 018 (L5.4-4), tregex 011 locale line (L5.4-5) → 39 files still failing | C1 35 (OG11), 006 (OG12), 056 + the C4 files the `timeout` fix uncovers (OG13), tregex (OG14) | ktests C4 depends on D1 |
| macos gnu | FAIL 17 | flakes 139, 007 (L5.4-6/7) gone; tregex 011 locale line → 15 files | C2 4 (OG12), C4 9 (OG13), tregex 002/011 (OG14) → PASS | — |
| freebsd clean | FLAKY 042 | PASS (L5.4-8) | — | — |
| windows git-bash | FAIL (STRAY cell) | kkore 011 (L5.4-1) gone; the cell's wedge needs a re-run | — | 057 likely back (R1: `deaf=no`) → SV-1 |
| windows msys2 | FAIL 3 | kkore 011 (L5.4-1), 054 (L5.4-2) gone → 057 | — | 057 → SV-1/D3 |

## 6. Diagnostic CI steps (read-only, for SV to run by `workflow_dispatch`)

Each is one extra step, bounded by `timeout-minutes`, `set +e` (it never fails the job). Put it
**before** the job's `gate` step. They print only; no file in the workspace is changed.

**D1 — macOS job (both rows):** SIGPIPE/fds of a step child, ps keywords, a session id source, locale
variables, ERE word boundaries, `timeout` names.

```yaml
      - name: diag L5.4 (read-only)
        timeout-minutes: 3
        shell: bash
        run: |
          set +e
          b="$(brew --prefix)/bin/bash"
          echo "== C2: signal dispositions a child bash inherits"
          "$b" -c 'trap -p; trap ": x" PIPE INT QUIT; echo "after set:"; trap -p PIPE INT QUIT'
          echo "== C3: open fds of a child bash"
          "$b" -c 'for f in /dev/fd/*; do [[ -e $f ]] && printf "%s " "${f##*/}"; done; echo'
          lsof -a -p $$ -d 0-99 2>/dev/null
          echo "== C4: ps keywords (one per call)"
          for k in sid sess tsess pgid etimes etime lstart state; do printf '%-7s ' "$k"; ps -o pid= -o "$k=" -p $$ 2>&1 | head -1; done
          "$b" -c 'echo "self=$$ ppid=$PPID"; ps -o pid= -o pgid= -o sess= -p $$; ps -o pid= -o pgid= -o sess= -p $PPID; ( exec perl -MPOSIX -e "POSIX::setsid(); exec q(ps), q(-o), q(pid=), q(-o), q(sess=), q(-p), \$\$" )'
          python3 -c 'import os; print("getsid self", os.getsid(0), "parent", os.getsid(os.getppid()), "pid1", os.getsid(1))'
          echo "== C6: locale variables"
          env | grep -E '^(LANG|LC_)' | sort
          echo "== C5: ERE word boundaries in [[ =~ ]]"
          "$b" -c 're="\\<foo\\>"; [[ "a foo b" =~ $re ]]; echo "\\<foo\\> rc=$?"; re="[[:<:]]foo[[:>:]]"; [[ "a foo b" =~ $re ]]; echo "[[:<:]] rc=$?"; re="\\bfoo\\b"; [[ "a foo b" =~ $re ]]; echo "\\b rc=$?"'
          echo "== C1: timeout names"
          for t in timeout gtimeout; do printf '%s: ' "$t"; command -v "$t" || echo "-"; done
          ls -l "$(brew --prefix)/opt/coreutils/libexec/gnubin/timeout" 2>&1
```

**D2 — linux job, ubuntu host row only:** SigIgn of the step shell and a child, its fds, whether this
`env` takes `PIPE` in `--default-signal`.

```yaml
      - name: diag L5.4 (read-only, ubuntu host)
        if: matrix.image == ''
        timeout-minutes: 3
        run: |
          set +e
          grep -E '^Sig(Ign|Blk|Cgt)' /proc/$$/status
          bash -c 'grep -E "^SigIgn" /proc/$$/status; trap ": x" PIPE; trap -p PIPE'
          ls -l /proc/$$/fd
          bash -c 'ls -l /proc/$$/fd'
          readlink -f "$(command -v env)"; env --version 2>&1 | head -1
          env --default-signal=INT,QUIT,PIPE bash -c 'grep -E "^SigIgn" /proc/$$/status; trap ": x" PIPE; trap -p PIPE'; echo "env --default-signal=INT,QUIT,PIPE rc=$?"
```

(SigIgn bit 13 = SIGPIPE: `0000000000001000` when ignored.)

**D3 — windows job (both rows; Git-bash shell):** the 057 suspend with PowerShell's output visible.

```yaml
      - name: diag L5.4 (read-only, NtSuspendProcess)
        timeout-minutes: 3
        shell: bash
        run: |
          set +e
          ( exec sleep 60 ) </dev/null >/dev/null 2>&1 & p=$!
          sleep 1; w=$(cat /proc/$p/winpid); echo "pid $p winpid $w"
          ps1="$(cygpath -u "$SYSTEMROOT")/System32/WindowsPowerShell/v1.0/powershell.exe"
          c="$(cygpath -w "$RUNNER_TEMP")"
          MSYS2_ARG_CONV_EXCL='*' TEMP="$c" TMP="$c" timeout -k 5 90 "$ps1" -NoProfile -NonInteractive -Command "Add-Type -Name N -Namespace W -MemberDefinition '[DllImport(\"ntdll.dll\")] public static extern int NtSuspendProcess(IntPtr h);'; \$q=Get-Process -Id $w; 'NtSuspendProcess=' + [W.N]::NtSuspendProcess(\$q.Handle); (Get-Process -Id $w).Threads | ForEach-Object { \$_.ThreadState.ToString() + '/' + \$_.WaitReason }"
          echo "powershell rc=$?"
          kill -KILL "$p"; sleep 1
          kill -0 "$p" 2>/dev/null && echo "deaf=yes" || echo "deaf=no"
          /usr/bin/kill -f -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; true
```

D1 answers OG13's precondition and confirms C2/C3/C5/C6 on macOS; D2 confirms C2/C3 on Ubuntu 26 and
the `env` of OG12 (a); D3 decides SV-1. No other mechanism needs a CI run.

## 7. Diagnostic results (SV, 2026-10-30, `diag.yml` run 40982440264)

* **D2 ubuntu host** (Ubuntu 26.04.1, image ubuntu26/20261025.179): step shell `SigIgn:
  0000000000001004` (SIGPIPE + SIGQUIT ignored), a child bash prints `trap -- '' SIGPIPE`; inherited
  fds `142`, `145` (pipes) besides 0-2 and 255 — **C2 and C3 confirmed**. `env` is uutils 0.10.0
  (`/usr/lib/cargo/bin/coreutils/env`); `env --default-signal=INT,QUIT,PIPE bash -c …` → child
  `SigIgn: 0000000000000004`, `trap -- ': x' SIGPIPE`, rc 0 — OG12 (a) works there.
* **D1 macOS** (macOS 26.6.2 arm64, both rows): SIGPIPE ignored in a child (`trap -- '' SIGPIPE`
  survives `trap ": x" PIPE`) — **C2 confirmed**; a child bash's fds `0 1 2 131 142/140 143 146` —
  **C3 confirmed**. `ps -o sid` → `keyword not found`; `ps -o sess`/`tsess` → `0` for every process
  (also after `POSIX::setsid`) — useless; `python3 os.getsid` works (`getsid self 1 parent 1 pid1 1`:
  the runner's processes sit in launchd's session) — a real session id source for OG13 (a), one
  python3 fork per snapshot. Locale: `LANG`, `LC_ALL`, `LC_CTYPE` all `en_US.UTF-8`. ERE in
  `[[ =~ ]]`: `\<foo\>` rc 1 (no match, not an error), `\bfoo\b` rc 1, `[[:<:]]foo[[:>:]]` rc 0.
  `timeout`: gnu row `/opt/homebrew/bin/timeout` and `/opt/homebrew/bin/gtimeout` (brew coreutils
  9.12 installs `timeout` unprefixed: macOS has no `timeout`); bsd row neither (no preinstalled
  gtimeout) — under OG11 (c) the bsd row SKIPs the `timeout` cases.
* **D3 windows** (Windows Server 2025): `NtSuspendProcess=0`, threads `Wait/Suspended`, `kill -KILL`
  → `deaf=yes`: the suspend works on windows-latest, so 057's `deaf=no` in CI is a harness finding
  (SV-1 → O card), not a missing API.
