# L3.1a — Alpine and FreeBSD gate runs (no fixes)

Date 2026-10-27. Four full gates, one VM at a time, via `bash tools/vmlab/vmlab.sh gate VM --snapshot SNAP -- --rerun-failed 1 --timeout 900 all`
(`clean` = the non-GNU userland, `clean-gnu` = the GNU tools added). Input for the owner's decision OG1 (GNU-tool policy)
and for L3.1b (reproductions); the failing files with first lines: [`L3_failures.tsv`](L3_failures.tsv). Format model: [`L2_runs.md`](L2_runs.md).

Host tree (all four `vm.txt`): kbool `53c09d0`; submodules kcl `ce157f1`, kklass `3448501`, kkore `dba5c20`, ktests `5e78a6b`; no `-dirty`.
OUT dirs: `C:/Users/1/AppData/Local/Temp/claude/c--projects-kkbot-kbool/1a013733-d305-4d7e-868c-ab115a4fc7da/scratchpad/launch/L3.1/o_*` (scratch; `progress.txt`, `cells.tsv`, `cells/NNN/…`, `vm.txt`).
No Windows gate ran (Git-bash 5.3.15 / MSYS2 5.3.9 on the host were not used).

## Preflight (step 0)

One VM at a time: `reset VM SNAP`, `up VM`, one `run`, `down VM`. Both kb-alpine command lines contain `nohz=off` (L1.7). Output literal (rc 0 each):

### kb-alpine / clean

```
BOOT_IMAGE=vmlinuz-virt root=UUID=2afbb217-96a0-4d44-9813-bd4cf7a9e483 modules=sd-mod,usb-storage,ext4 quiet rootfstype=ext4 nohz=off initrd=initramfs-virt
GNU bash, version 5.3.9(1)-release (x86_64-alpine-linux-musl)
This is not GNU sed version 4.0
awk: unrecognized option: -
/usr/bin/timeout
/bin/ps
```

### kb-alpine / clean-gnu

```
BOOT_IMAGE=vmlinuz-virt root=UUID=2afbb217-96a0-4d44-9813-bd4cf7a9e483 modules=sd-mod,usb-storage,ext4 quiet rootfstype=ext4 nohz=off initrd=initramfs-virt
GNU bash, version 5.3.9(1)-release (x86_64-alpine-linux-musl)
sed (GNU sed) 4.9
GNU Awk 5.3.2, API 4.0
/usr/bin/perl
/usr/bin/gawk
/usr/bin/timeout
/bin/ps
```

### kb-freebsd / clean

```
15.1-RELEASE
GNU bash, version 5.3.20(0)-release (amd64-portbld-freebsd15.1)
sed: illegal option -- -
awk version 20250804
/usr/local/bin/perl
/bin/timeout
/bin/ps
```

### kb-freebsd / clean-gnu

```
15.1-RELEASE
GNU bash, version 5.3.20(0)-release (amd64-portbld-freebsd15.1)
sed: illegal option -- -
awk version 20250804
/usr/local/bin/perl
/usr/local/bin/gawk
/usr/local/bin/gsed
/usr/local/bin/gnustat
/usr/local/bin/gtimeout
/bin/timeout
/bin/ps
```

FreeBSD `clean-gnu` keeps the BSD tools under their own names (`sed`, `awk`, `grep`, `find`, `stat`, `date` stay BSD) and adds the GNU ones mostly `g`-prefixed (`gsed`, `gawk`, `gnustat`, `gtimeout`, …; the `command -v` above shows them), so a difference between its two runs comes only from code that looks for a GNU name. Alpine `clean-gnu` is different: the GNU tools take the plain names (`sed` is GNU sed 4.9, `awk` is `gawk`, `perl` and GNU `timeout` are there), so they replace the busybox ones for every caller.

## Run 1 — kb-alpine, snapshot `clean`

* command: `bash tools/vmlab/vmlab.sh gate kb-alpine --snapshot clean --out "$SCRATCH/o_alpine_clean" -- --rerun-failed 1 --timeout 900 all` (vmlab rc 1)
* OUT: `C:/Users/1/AppData/Local/Temp/claude/c--projects-kkbot-kbool/1a013733-d305-4d7e-868c-ab115a4fc7da/scratchpad/launch/L3.1/o_alpine_clean`
* snapshot: `clean`
* VM: Linux kb-alpine 6.18.57-0-virt #1-Alpine SMP PREEMPT_DYNAMIC 2026-10-16 17:58:03 x86_64 Linux / Alpine Linux v3.24; GNU bash, version 5.3.9(1)-release (x86_64-alpine-linux-musl)
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 351 s

```
gate 2026-10-26T23:35:24 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.3.9 /bin/bash
gate options: --rerun-failed 1
gate 5.3.9: 30 cells  23 PASS  7 FAIL  0 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 9244/9275  5m21s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:23:7:0:0:0:0:9244:9275
```

## Run 2 — kb-alpine, snapshot `clean-gnu`

* command: `bash tools/vmlab/vmlab.sh gate kb-alpine --snapshot clean-gnu --out "$SCRATCH/o_alpine_clean-gnu" -- --rerun-failed 1 --timeout 900 all` (vmlab rc 1)
* OUT: `C:/Users/1/AppData/Local/Temp/claude/c--projects-kkbot-kbool/1a013733-d305-4d7e-868c-ab115a4fc7da/scratchpad/launch/L3.1/o_alpine_clean-gnu`
* snapshot: `clean-gnu`
* VM: Linux kb-alpine 6.18.57-0-virt #1-Alpine SMP PREEMPT_DYNAMIC 2026-10-16 17:58:03 x86_64 GNU/Linux / Alpine Linux v3.24; GNU bash, version 5.3.9(1)-release (x86_64-alpine-linux-musl)
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 370 s

```
gate 2026-10-26T23:41:26 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.3.9 /bin/bash
gate options: --rerun-failed 1
gate 5.3.9: 30 cells  27 PASS  2 FAIL  1 FLAKY  0 ENV  0 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 9270/9275  5m43s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:27:2:1:0:0:0:9270:9275
```

## Run 3 — kb-freebsd, snapshot `clean`

* command: `bash tools/vmlab/vmlab.sh gate kb-freebsd --snapshot clean --out "$SCRATCH/o_freebsd_clean" -- --rerun-failed 1 --timeout 900 all` (vmlab rc 1)
* OUT: `C:/Users/1/AppData/Local/Temp/claude/c--projects-kkbot-kbool/1a013733-d305-4d7e-868c-ab115a4fc7da/scratchpad/launch/L3.1/o_freebsd_clean`
* snapshot: `clean`
* VM: FreeBSD freebsd 15.1-RELEASE FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC amd64 / FreeBSD 15.1-RELEASE; GNU bash, version 5.3.20(0)-release (amd64-portbld-freebsd15.1)
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 3046 s

```
gate 2026-10-26T23:48:01 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.3.20 /usr/local/bin/bash
gate options: --rerun-failed 1
gate 5.3.20: 30 cells  6 PASS  21 FAIL  0 FLAKY  0 ENV  3 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 7815/8199  49m55s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:6:21:0:0:3:0:7815:8199
```

## Run 4 — kb-freebsd, snapshot `clean-gnu`

* command: `bash tools/vmlab/vmlab.sh gate kb-freebsd --snapshot clean-gnu --out "$SCRATCH/o_freebsd_clean-gnu" -- --rerun-failed 1 --timeout 900 all` (vmlab rc 1)
* OUT: `C:/Users/1/AppData/Local/Temp/claude/c--projects-kkbot-kbool/1a013733-d305-4d7e-868c-ab115a4fc7da/scratchpad/launch/L3.1/o_freebsd_clean-gnu`
* snapshot: `clean-gnu`
* VM: FreeBSD freebsd 15.1-RELEASE FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC amd64 / FreeBSD 15.1-RELEASE; GNU bash, version 5.3.20(0)-release (amd64-portbld-freebsd15.1)
* total wall time (whole `vmlab gate`: reset, boot, sync, gate, fetch, poweroff): 2168 s

```
gate 2026-10-27T00:39:05 root=/home/kb/kbool out=/home/kb/gate-out
gate repos: (not a git repository)
gate bashes: 5.3.20 /usr/local/bin/bash
gate options: --rerun-failed 1
gate 5.3.20: 30 cells  6 PASS  22 FAIL  0 FLAKY  0 ENV  2 TIMEOUT  0 STRAY  0 CRASH  0 NOTRUN  tests 7867/8378  35m17s
gate FAIL  out=/home/kb/gate-out
__GATE__:FAIL:30:6:22:0:0:2:0:7867:8378
```

No run needed a retry (no rc 14/11); vmlab rc 1 = the gate's FAIL in all four.

## Totals

Non-PASS test files per run (rows of `L3_failures.tsv`):

| run | FAIL cells | FLAKY | STRAY | TIMEOUT | CRASH | ENV | NOTRUN/UNSTARTED | rows |
|---|---|---|---|---|---|---|---|---|
| kb-alpine clean | 7 | 0 | 0 | 0 | 0 | 0 | 0 | dateutils 1 + math 1 + tdirectory 5 + tfile 5 + tpath 2 + tregex 1 + kklass 1 = **16** |
| kb-alpine clean-gnu | 2 | 1 (tpipe 003) | 0 | 0 | 0 | 0 | 0 | tgrep 1 + tregex 1 = 2, + flaky 1 = **3** |
| kb-freebsd clean | 21 | 0 | 0 | 3 (kcl, kcl/math, kkore) | 0 | 0 | 0 | 91 files in the 21 FAIL cells, + 3 timeout cells (no file named: `log.txt` empty) = **94** |
| kb-freebsd clean-gnu | 22 | 0 | 0 | 2 (kcl/math, kkore) | 0 | 0 | 0 | 125 files in the 22 FAIL cells, + 2 timeout cells = **127** |

16 + 3 + 94 + 127 = **240** rows (`L3_failures.tsv` has 241 lines with its header).

FreeBSD file arithmetic (files per cell, the `Failed test files` lists):

* `clean`: dateutils 2 + tarray 1 + tcustomapplication 6 + tdictionary 2 + tdirectory 18 + tfile 18 + thashset 3 + thttpserver 4 + tinifile 3 + tlist 1 + tobjectlist 1 + tpath 6 + tpipe 4 + tqueuestack 1 + tregex 3 + tstopwatch 2 + tstringhelper 3 + tstringlist 1 + tutil 3 + kklass 8 + ktests 1 = 91.
* `clean-gnu`: kcl 30 + dateutils 2 + tarray 1 + tawk 2 + tcustomapplication 6 + tdictionary 2 + tdirectory 18 + tfile 18 + thashset 3 + thttpserver 7 + tinifile 3 + tlist 1 + tobjectlist 1 + tpath 6 + tpipe 4 + tqueuestack 1 + tregex 3 + tstopwatch 2 + tstringhelper 3 + tstringlist 1 + tutil 3 + kklass 8 = 125.

Notes on the runs:

* **kb-freebsd `clean`, three TIMEOUT cells** (`kcl`, `kcl/math`, `kkore`): `timeout 900s, group stopped`, `log.txt` empty (0 bytes), no rerun. Each took 901 s, which is why the run lasted 3046 s. In `clean-gnu` `kcl` no longer times out (it fails 30 files instead); `kcl/math` and `kkore` still time out (run 2168 s).
* **FreeBSD `kklass.sh:838 printf: write error: Bad file descriptor`** (ledger `L2.7-N3-o3`) appears in the failing entry of 48 `clean` rows and in `clean-gnu` alike (the `notes` column marks only rows whose own failing entry text contains it): the same in both snapshots.
* **FreeBSD time/attribute files** (`tdirectory`, `tfile`, `tpath`: stat/date/touch) fail in both snapshots (`gnustat`, `gdate` have `g` names).
* Alpine `clean` fails the time files (tdirectory 5, tfile 5: creation time and setters), `tpath` 009/018 (`..` not collapsed), `kcl/dateutils` 024 (`perl: command not found`), `kcl/math` 018, `kklass` 143 (`touch: invalid date '2 hours ago'`); all of these pass in `clean-gnu`. `kcl/tregex` 011 fails in both Alpine snapshots and both FreeBSD ones (the only file failing in all four runs: `ALL4`).
* Alpine `clean-gnu`: `kcl/tgrep` 007_Bench fails (grep=1873us search=20031us ceiling=18730us; known `L2.7-P-o2`), `kcl/tpipe` 003_Sinks was FLAKY (passed on the rerun).
* Alpine ktests passes in both snapshots (664/664), so `L2.7-K-o1` / `L2.7-K-o2` (049, 052) did not show. FreeBSD ktests: `042_KilledRunCleanup` fails in `clean` only (`rc=143 left=[kt_nap…]`).
* The `notes` column is a lookup by suite/file/symptom (PORTING.md `H20-H23` stat/date/touch time and attribute code, `H24` realpath, `H27` awk engine, `H40`-`H43` wrappers; ledger ids); no cause analysis was done, a row without a note is unclassified. The `H20-H23` / `H24` labels of the `tdirectory`, `tfile` and `tpath` rows were set by file name alone (the failing text was not checked): best-effort, for the triage to confirm.

## For OG1

A *file* is a (suite, file) pair (a TIMEOUT cell without a named file counts as the pair (suite, `-`)); "fails" = any non-PASS row. Counts only.

| VM | files failing only in `clean` | in both | only in `clean-gnu` |
|---|---|---|---|
| kb-alpine | 15 | 1 | 2 |
| kb-freebsd | 2 | 92 | 35 |

Rows per suite per run (non-PASS rows of `L3_failures.tsv`):

| suite | alpine clean | alpine clean-gnu | freebsd clean | freebsd clean-gnu |
|---|---|---|---|---|
| kcl | 0 | 0 | 1 | 30 |
| kcl/dateutils | 1 | 0 | 2 | 2 |
| kcl/math | 1 | 0 | 1 | 1 |
| kcl/tarray | 0 | 0 | 1 | 1 |
| kcl/tawk | 0 | 0 | 0 | 2 |
| kcl/tcustomapplication | 0 | 0 | 6 | 6 |
| kcl/tdictionary | 0 | 0 | 2 | 2 |
| kcl/tdirectory | 5 | 0 | 18 | 18 |
| kcl/tfile | 5 | 0 | 18 | 18 |
| kcl/tgrep | 0 | 1 | 0 | 0 |
| kcl/thashset | 0 | 0 | 3 | 3 |
| kcl/thttpserver | 0 | 0 | 4 | 7 |
| kcl/tinifile | 0 | 0 | 3 | 3 |
| kcl/tlist | 0 | 0 | 1 | 1 |
| kcl/tobjectlist | 0 | 0 | 1 | 1 |
| kcl/tpath | 2 | 0 | 6 | 6 |
| kcl/tpipe | 0 | 1 | 4 | 4 |
| kcl/tqueuestack | 0 | 0 | 1 | 1 |
| kcl/tregex | 1 | 1 | 3 | 3 |
| kcl/tstopwatch | 0 | 0 | 2 | 2 |
| kcl/tstringhelper | 0 | 0 | 3 | 3 |
| kcl/tstringlist | 0 | 0 | 1 | 1 |
| kcl/tutil | 0 | 0 | 3 | 3 |
| kklass | 1 | 0 | 8 | 8 |
| kkore | 0 | 0 | 1 | 1 |
| ktests | 0 | 0 | 1 | 0 |
| **total** | **16** | **3** | **94** | **127** |
