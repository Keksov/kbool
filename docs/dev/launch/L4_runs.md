# L4.2 — kbool on bash 5.1 / 5.0 / 4.4

Date 2026-10-29. Measurement only (no fixes): kb-debian, snapshot `clean-bashes` (L4.1: `/opt/bash-5.1.16`, `/opt/bash-5.0.18`, `/opt/bash-4.4.23`, `/opt/bash-3.2.57`; `ls -d /opt/bash-*/bin/bash` after `up` showed all four, none dropped; `/usr/bin/bash` is 5.2.37). The failing files with first lines and causes: [`L4_failures.tsv`](L4_failures.tsv). Input for the owner's decision OG2 (floor 5.1 or 5.2). Format model: [`L3_runs.md`](L3_runs.md).

Host tree: kbool `0d67da7` (untracked: `docs/dev/launch/L4_failures.tsv`, `docs/dev/launch/L4_runs.md`, `tools/vmlab/checks/guard.sh` — this card's files); submodules kcl `a606d45`, kklass `0626d32`, kkore `83e750b`, ktests `9c8cc3c`. The VM copy (`vmlab.sh sync`) has no `.git`: `gate repos: (not a git repository)` is expected. No Windows gate ran.

Floor patch (VM copy only, applied after guard.sh; the host tree is untouched): `sed -i 's/^__KK_BASH_MIN=5\.2$/__KK_BASH_MIN=4.4/' ~/kbool/kbool.sh`; `grep -n '^__KK_BASH_MIN=' ~/kbool/kbool.sh` gave `56:__KK_BASH_MIN=4.4`.

## Step 2 — guard.sh with the real floor (5.2)

`bash tools/vmlab/vmlab.sh run kb-debian -- 'bash /tmp/guard.sh'` (rc 0, every row `ok`; the version in parentheses is `$BASH_VERSION`):

```
floor=5.2 dir=/home/kb/kbool
3.2 (3.2.57(2)-release) kbool rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 3.2.57(2)-release (/opt/bash-3.2.57/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
3.2 (3.2.57(2)-release) tstringlist rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 3.2.57(2)-release (/opt/bash-3.2.57/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
4.4 (4.4.23(1)-release) kbool rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 4.4.23(1)-release (/opt/bash-4.4.23/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
4.4 (4.4.23(1)-release) tstringlist rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 4.4.23(1)-release (/opt/bash-4.4.23/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
5.0 (5.0.18(1)-release) kbool rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 5.0.18(1)-release (/opt/bash-5.0.18/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
5.0 (5.0.18(1)-release) tstringlist rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 5.0.18(1)-release (/opt/bash-5.0.18/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
5.1 (5.1.16(1)-release) kbool rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 5.1.16(1)-release (/opt/bash-5.1.16/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
5.1 (5.1.16(1)-release) tstringlist rc=2 ok
  err: kbool: bash >= 5.2 is required, this is 5.1.16(1)-release (/opt/bash-5.1.16/bin/bash)
  err: kbool: on macOS install a current bash (brew install bash) and run scripts with it
5.2 (5.2.37(1)-release) kbool rc=0 ok
5.2 (5.2.37(1)-release) tstringlist rc=0 ok
```

Result: 3.2, 4.4, 5.0 and 5.1 are refused with rc=2 and `kbool: bash >= 5.2 is required` for both the whole `kbool.sh` and the single unit file `tstringlist.sh`; 5.2.37 loads with rc=0 and empty stderr. No `UNEXPECTED` row, no `bad substitution` line on 3.2.

## Step 4 — the gates (floor lowered to 4.4 in the VM copy)

All three through `bash tools/vmlab/vmlab.sh run kb-debian -- "cd ~/kbool && KT_GATE_BASHES=<bash> timeout -k 120 <cap> bash ktests/tools/gate.sh --out ~/gNN --rerun-failed 1 --timeout <t> <suites>"` with `VMLAB_TIMEOUT=5400`; OUT fetched with `vmlab.sh fetch` (scratch only).

### R1 — bash 5.1.16, all suites

Command: `KT_GATE_BASHES=/opt/bash-5.1.16/bin/bash timeout -k 120 5000 bash ktests/tools/gate.sh --out ~/g51 --rerun-failed 1 --timeout 900 all`

```
gate bashes: 5.1.16 /opt/bash-5.1.16/bin/bash
gate 5.1.16: 30 cells  26 PASS  4 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 9412/9536  9m06s
__GATE__:FAIL:30:26:4:0:0:0:0:9412:9536
```

Failing cells: `kcl` (1 file: 202_math), `kcl/thttpserver` (10 files, all), `kklass` (147_Round6), `ktests` (051_GateVerdicts, 053_GateReports). 26 of 30 cells PASS, including all of kkore and every other kcl unit. The two files flaky on 5.2 in L3_runs.md Run 9 (kcl/tawk 005_Run, kcl/tfile 007_Decrypt) passed.

### R2 — bash 5.0.18, suites kkore kklass

Command: `KT_GATE_BASHES=/opt/bash-5.0.18/bin/bash timeout -k 120 5000 bash ktests/tools/gate.sh --out ~/g50 --rerun-failed 1 --timeout 900 kkore kklass`

```
gate bashes: 5.0.18 /opt/bash-5.0.18/bin/bash
gate 5.0.18: 2 cells  0 PASS  2 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 1552/1614  48s
__GATE__:FAIL:2:0:2:0:0:0:0:1552:1614
```

### R3 — bash 4.4.23, suites kkore kklass

First: `/opt/bash-4.4.23/bin/bash -c 'echo "[${EPOCHSECONDS-unset}]"'` gave `[unset]`. Run once, as the card says: `KT_GATE_BASHES=/opt/bash-4.4.23/bin/bash timeout -k 120 3000 bash ktests/tools/gate.sh --out ~/g44 --rerun-failed 1 --timeout 300 kkore kklass`

```
gate bashes: 4.4.23 /opt/bash-4.4.23/bin/bash
gate 4.4.23: 2 cells  0 PASS  2 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 1444/1615  1m05s
__GATE__:FAIL:2:0:2:0:0:0:0:1444:1615
```

The gate itself started and ran its cells under 4.4.23 (no usage error; no CRASH/TIMEOUT/STRAY), so the card's F18 trigger did not occur and no harness F18 row was made. What 4.4 does show: the cell durations are `0.0s` in the progress lines (the gate's EPOCHREALTIME timers read empty), kklass counts 856 tests where 5.0 counts 855, and library behaviour is polluted by `shopt: localvar_unset: invalid shell option name` on every kklass method call (kklass/kklass.sh:1451/1458). Whether the harness numbers on 4.4 can be trusted is an owner question; no workaround was built.

## Totals

| run | bash | suites | verdict | cells fail | files failing | tests passed/total |
|---|---|---|---|---|---|---|
| R1 | 5.1.16 | all (30 cells) | FAIL | 4 / 30 | 14 | 9412 / 9536 |
| R2 | 5.0.18 | kkore kklass | FAIL | 2 / 2 | 24 (kklass 23, kkore 1) | 1552 / 1614 |
| R3 | 4.4.23 | kkore kklass | FAIL | 2 / 2 | 39 (kklass 35, kkore 4) | 1444 / 1615 |

77 rows in `L4_failures.tsv` (14 + 24 + 39).

## Failing files per feature (`tools/porting/bashfeatures.tsv` id)

A `feature` id is entered only with evidence (source line + bash error text). Almost every failure is a behavioural difference of the older bash, for which `bashfeatures.tsv` (a syntax/feature list) has no row; those stay `unknown` and the `evidence` column names the cause.

| id | feature | min | rows | which |
|---|---|---|---|---|
| F23 | SRANDOM | 5.1 | 3 | 5.0.18: kklass 128_SetUContract, 145_ForkFreeBuild; 4.4.23: kklass 128_SetUContract |
| F18 | EPOCHREALTIME / EPOCHSECONDS | 5.0 | 2 | 4.4.23: kklass 120_DeleteForkFree, kkore 017_GnuTools |
| every other id | | | 0 | |
| unknown | | | 72 | split below |

`unknown` rows by named cause (none of these has a row in `bashfeatures.tsv`):

| cause | works from | rows | probe |
|---|---|---|---|
| a nameref bound to an array element (`local -n v='d[value]'`) read in `$(( ))` gives 0 (kklass.sh:1383) | 5.1 | 22 (5.0: 13, 4.4: 9), symptom only | P1 |
| `shopt -s localvar_unset` (kklass.sh:1451) | option exists from 5.0 | 18 (4.4 only; 16 more 4.4 rows also print it, counted under the other causes) | error text |
| `declare -f` prints `>&"$fd"` as `&> "$fd"`, so the stored function writes to a file named after the fd (thttpmessage.sh:865) | 5.2 | 10 (5.1: all of kcl/thttpserver) | P3 |
| `${!name[@]@a}` (indirect attribute of an array name, kuse.sh:1570-1571) is empty | 5.1 | 2 (kkore 011_ConfigProject on 5.0 and 4.4) | P2 |
| `unset arr["   "]` (blank-only assoc key, kvar.sh:140) `not a valid identifier` | not measured on 5.0 | 1 (4.4, kkore 002) | error text |
| cause not isolated | | 19 (5.1: 4, 5.0: 8, 4.4: 7) | |

(18 + 22 + 10 + 2 + 1 + 19 = 72.)

## Probes (run in the VM, bounded one-liners)

P1 (nameref to an array element in arithmetic): `declare -A d=([value]=7); f() { local -n v='d[value]'; echo $((v * 2)); echo "[$v]"; echo $(( v + 1 )); }; f`
gave 4.4.23: `0 / [7] / 1`; 5.0.18: `0 / [7] / 1`; 5.1.16: `14 / [7] / 8`.

P2 (`${!name@a}` with `name="A[@]"`, as in kkore/kuse.sh:1570-1571): `declare -A A=([k]=v); declare -r R=(1); declare -a P=(1 2); for n in A R P; do at="$n[@]"; at=${!at@a}; echo "$n: [$at]"; done`
gave 4.4.23 and 5.0.18: `A: []  R: []  P: []`; 5.1.16: `A: [A]  R: [ar]  P: [a a]`.

P3 (`declare -f` of `g1() { local fd="$1" out="X1"; if ! printf '%s' "$out" 2>/dev/null >&"$fd"; then echo bad; fi; }`)
gave 5.1.16: `if ! printf '%s' "$out" 2> /dev/null &> "$fd"; then`; 5.2.37: `if ! printf '%s' "$out" 2> /dev/null >&"$fd"; then`. In the gate OUT, `g51/cells/014/cwd/{10,14,15,16}` hold `HTTP/1.1 200 OK ...` (the responses went to files named after the fds).

## Summary

On 5.1.16 the library passes except `kcl/thttpserver` (one cause: the 5.1 `declare -f` deparse of `>&"$fd"` in `THttpResponse.SendContent`), and four single files not isolated (kcl 202_math, kklass 147_Round6, ktests 051 and 053); kkore passes fully. 5.0.18 fails 24 kklass/kkore files (mainly the nameref-array-element arithmetic; two need SRANDOM, which `kklass.sh` itself documents as 5.1+). 4.4.23 additionally has no `localvar_unset`, no EPOCHREALTIME and no SRANDOM. No 5.2-only syntax feature (F24-F26) is used by core or tests (`bashfeatures_summary.txt`), so the 5.1 failures are behavioural differences of 5.1, not missing syntax.
