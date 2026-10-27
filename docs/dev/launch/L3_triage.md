# L3.5-b — triage of the remaining L3 rows (Alpine, FreeBSD)

Date 2026-10-27, tree kbool `b6ae12a` (kcl `4e53fd5`, kklass `b245f66`, kkore `e01a00c`, ktests
`5e78a6b`; no `-dirty`). Input: [`L3_runs.md`](L3_runs.md), [`L3_failures.tsv`](L3_failures.tsv)
(L3.1a, before L3.5-a), the L3.5-a OUT dirs, and four new full gates on this tree (below). Every
mechanism was checked by a probe in a lab VM (kb-alpine, kb-freebsd; the probe scripts and their
literal output are in the L3.5-b scratch folder of the supervisor session, not in the tree). Format
model: [`L2_triage.md`](L2_triage.md). Hazard ids: [`../PORTING.md`](../PORTING.md) §2.

Tool facts measured in the probes:

| VM / snapshot | bash | awk | sed | stat | date `-d` | touch `-d @E` | realpath `-m` | wc pads | perl | socat |
|---|---|---|---|---|---|---|---|---|---|---|
| kb-alpine `clean` | 5.3.9 musl | busybox (math built in) | busybox (`-i` ok) | busybox `-c`; `%W` prints `W` | yes | yes | no (busybox) | no | no | no |
| kb-alpine `clean-gnu` | 5.3.9 musl | gawk 5.3.2 as `awk` | GNU 4.9 | GNU | yes | yes | yes | no | yes | **no** |
| kb-freebsd `clean` | 5.3.20 pkg | BWK `awk version 20250804` | BSD | BSD (`-f`) | no (`-j -f`) | no | no | **yes** (`       3`) | yes | no |
| kb-freebsd `clean-gnu` | 5.3.20 pkg | BWK as `awk`, `gawk` | BSD as `sed`, `gsed` | BSD as `stat`, `gnustat` | BSD as `date`, `gdate` | BSD as `touch`, `gtouch` | BSD as `realpath`, `grealpath` | yes | yes | 1.8.1.3 |

FreeBSD has no `/bin/bash` (bash is `/usr/local/bin/bash`), and its pkg bash builds `<( )` as a FIFO
(PORTING H14).

## 0. Summary

| cluster | rows (Ac/Ag/Fc/Fg) | cause (one line) | class | executor | batch |
|---|---|---|---|---|---|
| C1 tpath time/attribute helpers on BSD | 70 (0/0/35/35) | `stat -c`, `date -d @E`, `date -d STR`, `touch -d @E` in tpath (H20-H23); the tests' own oracles use the same GNU forms | T-core (+ test oracles) | O + S | L3.5-1, L3.5-2 |
| C2 birth time on busybox | 10 (10/0/0/0) | busybox `stat -c %W` prints `W`; the `%W`→`%Y` fallback only knows `-1` | T-core | O | L3.5-1 |
| C3 `getFullPath` without `-m` | 6 (2/0/2/2) | busybox/BSD `realpath`/`readlink` have no `-m`; the last fallback is a raw `$PWD/$path` join (H24) | T-core | O | L3.5-1 |
| C4 BSD `wc` pads its count | 8 (0/0/4/4) | `$(wc -l)` compared as a string: `       3` ≠ `3` | T-test | S | L3.5-3 |
| C5 BSD `sed -i` / GNU `4i text` | 8 (0/0/4/4) | `sed -i SCRIPT FILE` takes the script as the suffix; `i` needs `\`+newline | T-test (+1 doc example) | S | L3.5-3 |
| C6 relative `touch -d` (+ busybox `timeout --preserve-status`) | 6 (2/0/2/2) | `touch -d '10 minutes ago'` is GNU-only | T-test | S | L3.5-3 |
| C7 no perl | 1 (1/0/0/0) | dateutils 024's reference oracle is perl; Alpine `clean` has none | T-test | S | L3.5-3 |
| C8 tregex `\b` per C library | 6 (1/1/2/2) | FreeBSD libc ERE rejects `\b` (rc 2); musl matches `\b` on the empty string at the end | PLAT | S | L3.5-4 |
| C9 kcl/math on BWK awk | 3 (0/0/2/1) | BWK stores every computed `-0` as `+0` (the engine's `-0` rewrite turns a correct field into `+0`); BWK reads a subnormal operand as 0; the 019 fixture assumes `-W interactive` | AWK | O | L3.5-5 |
| C10 TAwk inPlace data dir | 2 (0/0/0/2) | `-i /usr/share/awk/inplace.awk` hard-coded; FreeBSD has `/usr/local/share/awk` (H42) | T-wrap | S | L3.5-9 (after OG1) |
| C11 thttpserver relay FIFO on FreeBSD | 2 (0/0/0/2) | `exec nc < <(exec cat fifo)`: bash cannot unlink a FIFO procsub after `exec` → `sh-np.*` left in TMPDIR (H44's open item); + a fake nc with `#!/bin/bash` | PLAT (+ T-test) | O (+ S) | L3.5-7 (+ L3.5-3) |
| C12 ratio ceilings on Alpine | 2 (0/2/0/0) | bare tool ~1.3 ms, wrapper ~14 ms: the 10× ceiling fails on a fast-fork box even when idle | T-test | S | L3.5-6 |
| C13 tpipe EOF `wait` 127 | 2 (1/1/0/0) | `wait: pid N is not a child of this shell` at tpipe.sh:1037 under full-gate load; passes alone 10/10 | FLAKE | O | L3.5-8 |
| C14 tinifile 011 timing | 1 (0/0/1/0) | FLAKY once (L3.5-a run); 5/5 alone, absent in the HEAD run | FLAKE | — | watch at L3.6 |

Ac/Ag = kb-alpine `clean`/`clean-gnu`, Fc/Fg = kb-freebsd `clean`/`clean-gnu`. Rows: **127** = Ac 17 +
Ag 4 + Fc 52 + Fg 54 (§1.0). **T-core 86, T-test 25, PLAT 8, AWK 3, T-wrap 2, FLAKE 3** = 127. Only
C10 (2 rows) waits for OG1; everything else has a batch in §3 that does not depend on it.

Not visible in any row count: every wrapper suite gates on a GNU banner and passes each behavioural
case as `SKIP: non-GNU …` when the tool on PATH is not GNU — 763 cases on Alpine `clean` and FreeBSD
`clean`, still **577 on FreeBSD `clean-gnu`** with every GNU tool installed under its `g` name (§2.1).

## 1. Clusters

### 1.0 The row set (step 1)

Sources: the four OUT dirs named by the L3.5-b card (L3.1a Alpine, L3.5-a FreeBSD) and four full gates on
this tree (`vmlab.sh gate VM --snapshot S -- --rerun-failed 1 --timeout 900 all`, one VM at a time):

```
kb-alpine  clean      __GATE__:FAIL:30:22:7:1:0:0:0:9244:9276
kb-alpine  clean-gnu  __GATE__:FAIL:30:27:3:0:0:0:0:9271:9276
kb-freebsd clean      __GATE__:FAIL:30:22:8:0:0:0:0:9115:9275
kb-freebsd clean-gnu  __GATE__:FAIL:30:20:10:0:0:0:0:9107:9275
```

A row = a (vm, snapshot, suite, file) that is FAIL or FLAKY in either source (union):

| (vm, snapshot) | card's OUT dir | HEAD gate | in both | only card's | only HEAD | union |
|---|---|---|---|---|---|---|
| kb-alpine `clean` | 16 | 17 (16 + tutil 002 FLAKY) | 16 | 0 | 1 | **17** |
| kb-alpine `clean-gnu` | 3 (tgrep 007, tregex 011, tpipe 003 FLAKY) | 3 (tgrep 007, tregex 011, tsed 007) | 2 | 1 | 1 | **4** |
| kb-freebsd `clean` | 52 (51 + tinifile 011 FLAKY) | 51 | 51 | 1 | 0 | **52** |
| kb-freebsd `clean-gnu` | 54 | 54 | 54 | 0 | 0 | **54** |

17 + 4 + 52 + 54 = **127**. The FreeBSD HEAD rows are identical to the L3.5-a dirty-tree rows except
the flake; the Alpine HEAD rows are the L3.1a rows plus two load-only rows (C12 tsed, C13 tutil).

Per cluster, per (vm, snapshot):

| cluster | Ac | Ag | Fc | Fg |
|---|---|---|---|---|
| C1 | — | — | 35 | 35 |
| C2 | 10 | — | — | — |
| C3 | 2 | — | 2 | 2 |
| C4 | — | — | 4 | 4 |
| C5 | — | — | 4 | 4 |
| C6 | 2 | — | 2 | 2 |
| C7 | 1 | — | — | — |
| C8 | 1 | 1 | 2 | 2 |
| C9 | — | — | 2 | 1 |
| C10 | — | — | — | 2 |
| C11 | — | — | — | 2 |
| C12 | — | 2 | — | — |
| C13 | 1 | 1 | — | — |
| C14 | — | — | 1 | — |
| **sum** | 10+2+2+1+1+1 = **17** | 1+2+1 = **4** | 35+2+4+4+2+2+2+1 = **52** | 35+2+4+4+2+2+1+2+2 = **54** |

Each row is in exactly one cluster. Four files have a second, smaller cause, fixed in the batch named
there but counted only once: tfile 043 (C1 + the C4 `wc -c`), kklass 139 and 141 (C5 + the C4 `wc`),
thttpserver 004 (C11 + the `#!/bin/bash` fake nc), kcl/math 019 on Fc (C9 engine + C9 fixture).

### C1 — tpath time/attribute helpers on BSD (70 rows: Fc 35, Fg 35)

Rows (both FreeBSD snapshots): kcl/tdirectory 016 017 018 019 020 021 022 023 024 025 026 027 028 029
031 035 036 (17); kcl/tfile 012 013 014 015 016 017 018 030 031 032 033 034 035 036 041 043 (16);
kcl/tpath 012 019 (2). Failing lines, e.g. `[FAIL] GetAttributes - includes directory attribute
(expected faDirectory, got: '') (016_GetAttributes.sh)`, `[FAIL] SetLastWriteTime - changes the write
time (rc=1 stored=, wanted 1700000000) (027_SetLastWriteTime.sh)` preceded by `stat: illegal option --
c` and `date: illegal option -- d`.

Mechanism: the shared helpers in `kcl/tpath/tpath.sh` (R13, used by TFile and TDirectory) call
`stat -c FMT` (:389, :391, :466, :468), `date [-u] -d "@E"` (:397, :399), `date [-u] -d STRING`
(:425, :427) and `touch FLAG -d "@E"` (:437), all GNU forms. FreeBSD keeps the BSD tools under the
plain names in `clean-gnu` too, so both snapshots fail alike. Repro (kb-freebsd `clean`; `clean-gnu`
prints the same):

```
### H20 stat -c %Y / %W / %a
stat: illegal option -- c
### H20 stat -f '%m %a %B %Lp' (BSD)
1793072539 1793072539 1793072539 644
### H20 tpath._attrs / getAttributes
rc=1 r=[]
### H21 date -d @1700000000
date: illegal option -- d
### H21 printf %()T local/UTC (portable candidate)
2023-11-14 22:13:20|2023-11-14 22:13:20|2023-11-15 07:13:20
### H21 printf %()T after a temp TZ: does the shell's zone come back?
07 22
### H23 touch -m -d @1700000000
touch: out of range or illegal time specification: YYYY-MM-DDThh:mm:SS[.frac][tz]
### H23 TZ=UTC0 touch -m -t 202311142213.20 (portable candidate)
rc=0
-rw-r--r--  1 kb wheel 0 Nov 14 22:13:20 2023 /tmp/l35b.HYbqCR/f
### H23 tpath._touchTime
rc=1
```

The portable replacements were checked on kb-freebsd (verification session):

```
### BSD date -j -f: local and UTC parse of the canonical string
1704110400            (local, TZ unset = UTC)
1704110400            (-u)
1704078000            (TZ=Asia/Tokyo)
### BSD date -j -f rejects garbage
date: illegal time format ... rc=1
### touch -t with TZ=UTC0 round trip via stat -f %m (UFS home dir)
rc=0 st=202009131226.40 m=1600000000
a=1600000000
### stat -L -f %Lp on a symlink to a 444 file, and without -L
L=444 noL=755
```

The tests are the second half: 16 of the 35 files read the stored value back with their own
`stat -c`, `date -d @E` or `date -d STRING` (tdirectory 019 021 022 024 027 028 029 035, tfile 030 031
032 033 034 035 036 041), so they keep failing after the library is fixed (`035_G6_Times.sh: line 196:
((: (8#: invalid integer constant` is `$(( 8#$(stat -c %a …) ))` with an empty answer). The other 19
fail only through the library. tfile 043 also has the C4 `wc -c` compare (L3.5-3).

Class **T-core**; fix = portable rewrite in tpath (L3.5-1, rules there) + a portable test oracle
(L3.5-2). No tool policy needed: stat is detected by behaviour (one probe), the formatting is the
bash builtin `printf '%(…)T'` (fork-free), the setter uses POSIX `touch -t` under `TZ=UTC0`.

### C2 — birth time on busybox (10 rows: Ac 10)

Rows (kb-alpine `clean`): kcl/tdirectory 018 019 020 021 035; kcl/tfile 013 014 031 032 041. Failing
line e.g. `[FAIL] GetCreationTime - returns datetime value (expected: non-empty datetime)
(018_GetCreationTime.sh)`, `[FAIL] Get creation time of existing file (invalid timestamp: )`.

Mechanism: `tpath._statTime` falls back from `%W` to `%Y` only when the answer is `-1` (:390, G6-26).
busybox `stat` does not know `%W` and prints the letter:

```
### busybox stat %W / %w            (kb-alpine clean)
W|w|1793065732
rc=0
```

`W` is not numeric → rc 1 → every creation-time getter answers empty. (GNU coreutils prints `0` when
the birth time is unknown, cygwin `-1`.) All 10 pass in `clean-gnu` (GNU stat). Class **T-core**;
fix in L3.5-1 (R2: any answer that is not a positive integer falls back to the write time).

### C3 — `getFullPath` without `-m` (6 rows: Ac 2, Fc 2, Fg 2)

Rows: kcl/tpath 009 018 on kb-alpine `clean` and both FreeBSD snapshots. Failing lines:
`[FAIL] getFullPath with parent directory (expected: '…/.tmp', got: '…/GetFullPath.009_GetFullPath.55007/..')`,
`[FAIL] expected '/nosuch_g613/b', got '/nosuch_g613/a/../b' (018_G6_PathParsing.sh)`.

Mechanism: `tpath.getFullPath` (:679-698) tries `realpath -m`, then `readlink -m`, then answers the raw
`$PWD/$path`. Neither busybox nor BSD has `-m`:

```
### H24 realpath -m / readlink -m        (kb-freebsd clean)
realpath: illegal option -- m
readlink: illegal option -- m
### H24 tpath.getFullPath
[.] -> [/tmp/l35b.HYbqCR/.]
[..] -> [/tmp/l35b.HYbqCR/..]
[/nosuch_g613/a/../b] -> [/nosuch_g613/a/../b]
[./d/./../d] -> [/tmp/l35b.HYbqCR/./d/./../d]
```

kb-alpine `clean`: `realpath: -m: No such file or directory`, `readlink: unrecognized option: m`, the
same four answers. Class **T-core**; fix L3.5-1 R5 (a lexical normaliser in bash for the last
fallback). Note for D4: GNU `realpath -m` also resolves symlinks of existing components, a lexical
normaliser does not (FPC's `ExpandFileName` is lexical too).

### C4 — BSD `wc` pads its count (8 rows: Fc 4, Fg 4)

Rows (both FreeBSD snapshots): kcl/tdictionary 009 (`[FAIL] a listed key did not resolve`), kcl/tfile
042 (`[FAIL]        4 bytes`), kkore 001 (`kl.writeln didn't output newline correctly (expected 1,
got        1)`), kkore 015 (`stdout differs: got [… home=       0 …] want [… home=0 …]`).

```
### wc padding                      (kb-freebsd clean)
0000000                                4  \n
### wc padding: tdictionary 009 compare
string-ne [       3]
arith-eq
```

kb-alpine prints `4`/`3` unpadded (`string-eq`). The library is not involved: each site compares
`$(wc …)` as a string (tdictionary 009:55, tfile 042:238, :241, :246, :249, tfile 043:102, :105,
kkore 001:175, :194, kkore 015:95, kklass 139:644, :645, kklass 141:182). Class **T-test**; L3.5-3 R1.

### C5 — BSD `sed -i`, GNU one-line `i` (8 rows: Fc 4, Fg 4)

Rows (both FreeBSD snapshots): kklass 139, 141, 142; kkore 013. Failing lines: `err='sed: 1:
"/home/kb/gate-out/cells ...": invalid command code k'` (139:327, :621; kkore 013:127), `sed: 1:
"/home/kb/kbool/kklass/t ...": invalid command code k` (141:313, :317), `kklass_book.md:1915: stdout
differs … unexpected stderr: [sed: 1: "shape.sh|": unescaped newline inside substitute pattern …]`
(142 runs the book's doctest, whose example edits a unit with `sed -i`).

```
### sed -i 's/v1/v2/' FILE          (kb-freebsd clean)
sed: 1: "/tmp/l35b.HYbqCR/s.txt
": extra characters at the end of l command
rc=1 content=v1
### sed -i.bak (portable candidate)
rc=0 content=v2 bak=0
### sed 4i (kklass 141)
sed: 1: "4i return 6
": command i expects \ followed by text
```

BSD `sed -i` takes the next word as the backup suffix and the file name as the script. busybox and
GNU accept both forms (`rc=0 content=v2`, `1 2 3 return 6 4`). Class **T-test** (one user-facing
doc example); L3.5-3 R2.

### C6 — relative `touch -d`, busybox `timeout` (6 rows: Ac 2, Fc 2, Fg 2)

Rows: kcl/math 018 and kklass 143 on kb-alpine `clean` and both FreeBSD snapshots. Failing lines:
`touch: invalid date '10 minutes ago'` (Alpine) / `touch: out of range or illegal time specification`
(FreeBSD), then `[FAIL] left '… .math_fe_17577.awk …'` (math 018:46, :106, :127: the files are not
aged, so the sweep keeps them) and `[FAIL] dropped='kklass_compiler.…' left=…` (kklass 143:89, :90).
kklass 143 on Alpine also: `[FAIL] rc=1 left='' (143_CompilerTempCleanup.sh)` — 143:69 passes
`timeout -s TERM --preserve-status 3`:

```
### touch -d '2 hours ago'            (kb-alpine clean; FreeBSD: "out of range or illegal time specification")
touch: invalid date '2 hours ago'
rc=1
### printf+touch -t (portable candidate)
rc=0 st=202610270148.52
1                                     (find -mmin +60 sees it)
### timeout --preserve-status         (kb-alpine clean; FreeBSD timeout: rc=143)
timeout: unrecognized option: preserve-status
rc=1
```

Class **T-test**; L3.5-3 R3, R4.

### C7 — no perl on Alpine `clean` (1 row: Ac 1)

Row: kcl/dateutils 024 — `[FAIL] perl failed: …/024_IsoWeekSweep.sh: line 39: perl: command not
found`, then three cases with 0 rows compared. The probe: `### perl` → `no perl` (kb-alpine `clean`;
present in the other three). PORTING §2.5 P26 already says "→ SKIP when absent". Class **T-test**;
L3.5-3 R5.

### C8 — tregex `\b` per C library (6 rows: Ac 1, Ag 1, Fc 2, Fg 2)

Rows: kcl/tregex 011 on all four runs; kcl/tregex 002 on both FreeBSD snapshots. Failing lines:
`[FAIL] expected match (rc0) for text='the cat sat' re='cat' flags='' (002_IsMatch.sh)` (the row is
`\bcat\b`), `[FAIL] n=0 offs='' want n=5 offs='0 1 2 3 4'` (FreeBSD 011), `[FAIL] n=6 offs='0 1 2 3 4
5' want n=5 offs='0 1 2 3 4'` and `[replace(ab cd,\b,|)='|a|b| |c|d|' want '|a|b| |c|d']` (Alpine 011).

The engine is the C library's ERE (`[[ =~ ]]`, tregex.sh:205). `\b` is an extension, and the three
libraries differ:

```
kb-freebsd (libc):                               kb-alpine (musl):
### tregex: \b in [[ =~ ]]                        ### tregex: \b in [[ =~ ]]
rc=2                                              rc=0
[[: invalid regular expression `\bcat\b':         [[:<:]] rc=2
    trailing backslash (\)                        \< rc=0
[[:<:]] rc=0                                      ### tregex: empty-remainder \b
\< rc=0                                           '' =~ \b rc=0
### tregex 011 scans                              ### tregex 011 scans
n=0 offs=                                         n=6 offs=0 1 2 3 4 5
replace=[ab cd]                                   replace=[|a|b| |c|d|]
```

glibc and newlib (Linux VMs, Windows) accept `\b` and do not match it on the empty remainder, which is
what 002/011 pin. `\<` `\>` work everywhere (their rows pass). Class **PLAT**; fix = the tests take
the `\b` expectation from a probe of the engine, the README names the delta (L3.5-4). No unit change:
an invalid pattern is already rc 2 by contract.

### C9 — kcl/math on BWK awk (3 rows: Fc 2, Fg 1)

Rows: kcl/math 014 (Fc), 019 (Fc, Fg). FreeBSD `clean` has only BWK awk; `clean-gnu` has gawk, which
the engine prefers (L2.7-M B), so there only 019's "plain awk" row meets BWK.

What breaks:

1. **Negative zero.** `[FAIL] [math.arcTan2 0 -0 -> 0 want 3.1415926535897931] … (019)`. BWK's
   `setfval` stores every computed `-0` as `+0`, but it reads a field `-0` as `-0`. The engine's
   dispatch rewrites a `-0` field to `_NZ` (math.sh:272, for mawk 20250131, N2), and on BWK `_NZ`
   itself is `+0` — the rewrite destroys the one form BWK gets right:
   ```
   ### awk atan2(0,-0)                 (kb-freebsd, BWK 20250804)
   lit=0 neg=0 nz=0
   field=3.14159 fieldplus=0
   ### math unit on the system awk
   atan2(0,-0)=0
   ```
   Candidate fix verified on kb-freebsd: compute `_NZOK=(atan2(0,_NZ) > 3)` in BEGIN and rewrite only
   when it is true (a patched copy inside the VM):
   ```
   ### BWK: candidate engine fix … patched COPY inside the VM tree
   -0=3.1415926535897931 -0.0=3.1415926535897931 -.0=3.1415926535897931 -0.=3.1415926535897931 -0e0=3.1415926535897931 -00=3.1415926535897931 0=0 1=0
   ###   the same patched copy on gawk (must stay pi)
   -0=3.1415926535897931 -0.0=3.1415926535897931 0=0
   ```
2. **Subnormal operands.** `[FAIL] got '…|0 0|0.5 -1021|' want '…|0.5 -1073|0.5 -1021|' (014)`:
   `math.frexp 5e-324`. BWK computes subnormals but does not parse one (`strtod` ERANGE → the field is
   a string worth 0):
   ```
   ### BWK: computed vs parsed subnormal
   computed=4.9406564584124654e-324 parsed=0 is0=0
   ```
3. **The 019 fixture** (Fc only): `LINEWISE="$REAL_AWK" -W interactive` when there is no gawk — BWK
   reads `-W` as an unknown option and `interactive` as the PROGRAM (`awk: unknown option -W ignored`,
   `awk: can't open file {print "got", $0}`), so the fake-mawk/other-awk/no-W rows fail
   (`[FAIL] out='|||new:||nodate:||other:|' -W version calls: fakemawk=1 otherawk=`, `w_noW … cannot
   run the engine`, `long=1:|short=1:|cos=`, and the financial `nan` rows of the fake-mawk engine).

Both 1 and 3 applied to the VM's copy (verification session, kb-freebsd `clean`): 019 **16/16**, 014
**50/51** (only the `5e-324` row). busybox awk (Alpine `clean`) has none of these: `lit=3.14159
neg=3.14159 nz=3.14159`, subnormals parse, math passes except C6's 018. Class **AWK**; L3.5-5; the
subnormal row is decision D5.

### C10 — TAwk inPlace data dir (2 rows: Fg 2)

Rows: kcl/tawk 005, 006 on FreeBSD `clean-gnu` (gawk installed; in `clean` every tawk case SKIPs).
Ten cases, all `inPlace`: `err='gawk: fatal: cannot open source file `/usr/share/awk/inplace.awk' for
reading: No such file or directory'`.

```
### gawk inplace.awk location (H42)          (kb-freebsd clean-gnu)
AWKPATH=.:/usr/local/share/awk
ls: /usr/share/awk/inplace.awk: No such file or directory
-rw-r--r--  1 root wheel 2413 Oct 15 01:25 /usr/local/share/awk/inplace.awk
### TAwk inPlace with gawk installed (H42)
gawk: fatal: cannot open source file `/usr/share/awk/inplace.awk' for reading: No such file or directory
rc=1
lastRc=2
```

tawk.sh:690 hard-codes the Linux data dir (absolute on purpose: `-i inplace` searches AWKPATH, which
starts with `.`, a cwd hijack). Class **T-wrap**: TAwk exists to drive gawk. The fix is the same
under OG1 options A and B (gawk stays gawk); under C TAwk's gawk dependency is itself in question —
so L3.5-9 is cut but held until OG1.

### C11 — thttpserver relay FIFO on FreeBSD (2 rows: Fg 2)

Rows: kcl/thttpserver 004 and 009 on FreeBSD `clean-gnu` (socat is the backend there; in `clean` the
socket cases SKIP: no backend). Failing lines: `[FAIL] exit=0 rc=1 le='bind(5, {LEN=16 AF=2
127.0.0.1:31409}, 16): Address already in use' children=0 tmp='sh-np.9CMngf'` (004 fact 4: every
value right except the left-over temp entry), `[FAIL] quit='200:bye' … tmp='sh-np.1ygrHq sh-np.6XyG52
… (15 entries)'` (009, both demo cases).

Mechanism: with `StdinRelay = 1` the listener starts as `exec "${ths_argv[@]}" < <(exec cat
"$__ths_dir/fifo$__ths_s")` (thttpserver.sh:683). On a bash whose `<( )` is a FIFO (FreeBSD pkg bash,
PORTING H14) the shell that created the FIFO is replaced by the listener and never unlinks it — one
`sh-np.*` in TMPDIR per spawn. The same mechanism is L3.5-a's open item for the math co-process
(L3.5-a-o5, PORTING H44 "still open"):

```
### procsub FIFO leak after exec (thttpserver 004/009, H44)   (kb-freebsd; the same in clean-gnu)
with exec: sh-np.bmcndG
without inner exec:
plain procsub:
```

Second cause in 004 (the "once" case of fact 5): the fake nc is written with `#!/bin/bash`
(004:776), which FreeBSD does not have — `le=no usable network backend: unknown nc at …/once_nc is
not GNU netcat 0.7.1`:

```
### thttpserver 004 'once' fake nc under /bin/bash shebang
bash: /tmp/l35b.HYbqCR/once_nc: /bin/bash: bad interpreter: No such file or directory
rc=126
```

Class **PLAT** (relay: unit design, O, L3.5-7) + **T-test** (shebang, L3.5-3 R6).

### C12 — ratio ceilings on Alpine (2 rows: Ag 2)

Rows (kb-alpine `clean-gnu`): kcl/tgrep 007, kcl/tsed 007 — `[FAIL] grep hits='21' search hits='21'
(want 21); grep=1873us search=20031us (1069%) ceiling=18730us`, `[FAIL] same=1 records='1' (want 1);
sed=1347us edit=16359us (1214%) ceiling=13470us`. Not load: alone, idle VM, the same box:

```
### tgrep 7 alone x5                    4 of 5 FAIL, e.g. grep=1294us search=14317us (1106%) ceiling=12940us
### tsed 7 alone x5                     5 of 5 FAIL, e.g. sed=1054us edit=13080us (1240%) ceiling=10540us
```

The ceiling is 10× the bare tool's median (tgrep 007:145, :247, :256; tsed 007:171, :315), chosen on
Windows where a process start is ~28 ms and the wrapper's fixed bash cost is small beside it. On
Alpine a process start is ~1.3 ms and the wrapper's fixed cost (~13 ms: instance, argv, TUtil) is
10-12× that. Class **T-test** (the card's FLAKE class asks for pass-alone evidence; these fail
alone); L3.5-6.

### C13 — tpipe EOF-path `wait` 127 (2 rows: Ac 1, Ag 1)

Rows: kcl/tutil 002 (Alpine `clean`, HEAD gate, FLAKY), kcl/tpipe 003 (Alpine `clean-gnu`, L3.1a,
FLAKY). Failing lines: `tpipe.sh: line 1037: wait: pid 24727 is not a child of this shell` then
`[FAIL] rc=1 out='' stderr='…' (002_Sinks.sh)`; `[FAIL] RESULT='2' rc=1 lastRc='127' (003_Sinks.sh)`.
`tpipe._close` (EOF path, :1035-1037) closes the producer's fd and `wait`s for `$!` of the process
substitution; bash answered 127 "not a child", so `TPipe.lastRc` is 127 and the member rc 1.

Pass-alone evidence (kb-alpine `clean` and `clean-gnu`, each): `tpipe 3 alone x10` → 10 × `Passed:
68`, `tutil 2 alone x10` → 10 × `Passed: 64`. A minimal repro of the same shape (open `<( )`, read to
EOF, close, `wait $!`; plain / with `$( )` in the loop / with a second `<( )` before the wait) gave
`127 x 0 / 2000` for each, on both Alpine snapshots and on FreeBSD. 2 hits in 4 Alpine full gates
(L3.1a ×2, HEAD ×2), 0 in the 4 FreeBSD gates (L3.5-a ×2, HEAD ×2). Class **FLAKE** with a real, load-dependent
`wait` race (bash 5.3.9 on musl) behind it; L3.5-8 is an O investigation, not a test change.

### C14 — tinifile 011 timing (1 row: Fc 1)

Row: kcl/tinifile 011 FLAKY in the L3.5-a FreeBSD `clean` run (`[FAIL] position-dependent: sec1 5663
us, sec20 49645 us -> 87/10x`, then passed on the rerun); absent in the HEAD gate; alone 5/5:
`### tinifile 011 alone x5` → 5 × `Passed: 7`. Class **FLAKE**; no batch, watch at L3.6 (if it
recurs: the cell's timings and the gate's watchdog record).

## 2. OG1 numbers

### 2.1 rows per class, and what the rows do not show

| class | Ac | Ag | Fc | Fg | clusters |
|---|---|---|---|---|---|
| T-core | 12 | 0 | 37 | 37 | C1 C2 C3 |
| T-wrap | 0 | 0 | 0 | 2 | C10 |
| T-test | 3 | 2 | 10 | 10 | C4 C5 C6 C7 C12 |
| AWK | 0 | 0 | 2 | 1 | C9 |
| PLAT | 1 | 1 | 2 | 4 | C8 C11 |
| FLAKE | 1 | 1 | 1 | 0 | C13 C14 |
| **rows** | **17** | **4** | **52** | **54** | |
| hidden: wrapper cases passing as `SKIP: non-GNU` | 763 | 0 | 763 | **577** | — |
| hidden: thttpserver socket cases SKIP (no backend) | 75 | **75** | 75 | 0 | — |

The hidden lines count the `SKIP` lines of `bash kcl/<suite>/tests/tests.sh -v info` in each VM:
tsed 166, tawk 186, tgrep 108, tfind 96, thead 96, ttail 111 (= 763) on Alpine `clean` and FreeBSD
`clean`; on FreeBSD `clean-gnu` the same minus tawk (gawk is found by name) = **577** — gsed, ggrep,
gfind, ghead and gtail are installed but never used, and TSed with gsed installed still runs BSD sed
(`### TSed with gsed installed: which sed does it run?` → `usage: sed script [-Ealnru] …`, rc 1).
Alpine `clean-gnu` has the GNU tools under the plain names: 0. thttpserver's 75 are the backend
question (socat is not in the Alpine `clean-gnu` package list; OPEN).

### 2.2 the three options

**(A) the recommendation on the table** — core tool-free; wrapper units require the GNU tool,
resolved by name (`gsed`/`gawk`/`ggrep`/`gfind`/`ghead`/`gtail`, then the plain name, accepted only
with a GNU identity), a clear error naming the package, their tests SKIP with that reason.

* Leaves failing after the §3 batches and L3.3/L3.4: **0 known rows** on all four. C10 is fixed in
  L3.5-9 (or folded into L3.4). The T-core rows (86) are fixed by L3.5-1/-2, which A needs anyway.
* Changes the hidden numbers: Alpine `clean`/FreeBSD `clean` keep their SKIPs, now with a reason
  that names the package; FreeBSD `clean-gnu` **runs** the 577 cases against gsed/ggrep/gfind/ghead/
  gtail — new rows are likely there (BSD-hosted GNU tools, test oracles that call plain `sed`/`grep`
  must go through the resolver too); not measurable before L3.4.
* Cost: L3.3 resolver in kkore (~150 lines + tests ~200), L3.4 wrapper move (6 constructor lines,
  tutil messages, tawk H42, 41 wrapper test files' oracle calls through the resolver: ~348 sites,
  mechanical) ≈ 45-50 files, ~800 lines; plus the OG1-independent §3 batches (below) which every
  option needs except B-without-portability.

**(B) GNU tools a documented requirement everywhere, no name resolution.**

* FreeBSD `clean-gnu` has the GNU tools only under `g` names, so nothing changes there: the 37 T-core
  rows stay (tpath calls plain `stat`/`date`/`touch`/`realpath` — unless L3.5-1 lands anyway, which
  makes B's requirement moot for the core), the 10 T-test rows stay (BSD `wc` and `sed` keep their
  names; `wc` padding is not even a GNU question), the 577 wrapper cases stay SKIP and TSed/TGrep/
  TFind/THead/TTail stay unusable. Of the 54 Fg rows B itself fixes **0**; with all OG1-independent
  batches it leaves C10's 2.
* What a FreeBSD/macOS user must do: build a directory of plain-named links to the g-tools and put it
  first on PATH (Homebrew ships `gnubin` dirs for this; FreeBSD's packages do not). The lab's
  `clean-gnu` snapshot does not do that, so B also needs a provisioning change to be testable.
* Cost: docs only (README requirement, per-OS install line) ≈ 2 files, ~40 lines — but the support
  load moves to the user, and CI (L5) on FreeBSD/macOS needs the same PATH shim.

**(C) everything portable, no GNU requirement at all.**

* Core: the same §3 work as A. Wrappers: each needs a native-flavour layer (argv builder + rc/message
  map per flavour) and its tests an oracle per flavour. Features with **no POSIX/BSD/busybox
  equivalent** (they would be refused or emulated):
  * TSed: `--sandbox` (the default, owner Q1), `separate` (`-s`), `nullData` (`-z`), `-b` binary,
    `--posix`, `--debug`; the TUtil CR-strip expression for sed relies on GNU escape handling.
  * TAwk: the whole unit is gawk by design — `--sandbox`, `inPlace` (`-i inplace`,
    `inplace::suffix`), `BINMODE=3`, `nullData` (`RS='\0'`), `-e` program chunks.
  * TGrep: `binary` (`-U`), `nullData` (`-z`), `nullOut` (`-Z`; macOS grep `-Z` means decompress),
    `--include`/`--exclude`/`--exclude-dir`, the binary-match record contract.
  * THead/TTail: negative counts (`head -n -K`, `head -c -K`), `zeroTerminated` (`-z`), `quiet`/
    `verbose` on busybox.
  * TFind: `-maxdepth`/`-mindepth`/`-iname`/`-print0` exist on BSD and busybox (not POSIX) — the
    cheapest of the six.
* Leaves failing: 0 rows once done, but the 763 cases become flavour-split tests.
* Cost: PORTING §5.1 column B — per wrapper ~150-250 lines of flavour code (6 units ≈ 1200 lines),
  the 348 test oracle calls plus 88 GNU-sed and 171 gawk test lines split per flavour (~1000-1500
  lines), and a decision to drop TAwk's gawk-only members or the unit: **weeks**, not days.

### 2.3 recommendation

**A.** The rows say that the GNU question is small where it is visible (2 T-wrap rows) and large
where it is hidden (577 cases skipped on a box that has every GNU tool). The 86 T-core rows are not a
tool-policy question at all — one behaviour probe for `stat`, the bash builtin `printf '%(…)T'`, POSIX
`touch -t` and a lexical path normaliser make the core run on GNU, busybox and BSD alike (§3
L3.5-1, verified piecewise on kb-freebsd), so A's "core tool-free" costs one O batch. B fixes none of
the 54 FreeBSD rows and pushes a PATH shim onto every BSD/macOS user and CI job; C costs weeks and
still has to refuse most of TAwk and a third of TSed. A gives FreeBSD/macOS working wrappers the day
the user installs the packages under their normal names, and an honest, named SKIP before that. The
owner decides.

## 3. Fix batches

Common to all batches: Write scope = the files listed; keep LF; no unit code outside the files named;
`git -C <repo>` only for the repos named; never commit. Stop if a rule does not fit the code you see
→ BLOCKED with the evidence. Gate commands: Windows `bash $G <suites>` (both runtimes, per
`ktests/docs/GATE_FOR_AGENTS.md`); VMs `bash tools/vmlab/vmlab.sh gate VM --snapshot S -- --rerun-failed 1 <suites>`.
Repro form: `bash tools/vmlab/vmlab.sh run VM -- 'cd ~/kbool && bash kcl/<unit>/tests/tests.sh -n N'`
after `vmlab.sh reset VM S; vmlab.sh up VM; vmlab.sh sync VM` (and `vmlab.sh down VM` after).

Order (one gate slot): L3.5-3 → L3.5-4 → L3.5-6 (S, independent) → L3.5-1 (O) → L3.5-2 (S, needs
L3.5-1) → L3.5-5 (O) → L3.5-7 (O) → L3.5-8 (O, investigation) ; L3.5-9 after OG1.

### L3.5-1 — tpath: portable time, attribute and path helpers [O]

```
CARD: L3.5-1
Goal: TFile/TDirectory/TPath time getters and setters, getAttributes and getFullPath work on GNU,
      busybox and BSD userlands; Windows and the Linux VMs behave as today.
Rows: C1 tpath 012 019 (Fc, Fg); C2 (10, Ac); C3 tpath 009 018 (Ac, Fc, Fg); and the 17 C1 files of
      tdirectory/tfile that fail only through the library (tdirectory 016 017 018 020 023 025 026
      031 036; tfile 012 013 014 015 016 017 018 043-minus-its-wc-case) — with tpath 012/019 the 19
      library-only C1 files of §1 C1. Repros/causes: §1 C1-C3.
Fix rules (tpath.sh; line numbers of b6ae12a):
  R1 stat flavour, probed lazily once per process (no fork at source time):
       __TP_STAT=''   # '' unknown | gnu (`stat -c`: GNU, busybox) | bsd (`stat -f`: FreeBSD, macOS) | none
     tpath._statFlavour: `stat -c %Y -- / >/dev/null 2>&1` → gnu; else `stat -f %m -- / >/dev/null 2>&1`
     → bsd; else none (rc 1).
     tpath._stat LETTER PATH [L] → __tp_e = the GNU `stat -c %LETTER` value; LETTER X (atime), Y (mtime),
     W (birth), a (octal mode); bsd map X→%a Y→%m W→%B a→%Lp; a third argument `L` adds `-L` (both
     flavours accept it). rc 1 when stat fails.
  R2 tpath._statTime (:381-402): keep the signature ($2 = "%X" | "%Y" | "%W"; strip the `%`); value via
     tpath._stat; when the letter is W and the answer is not a positive integer (^[1-9][0-9]*$: GNU 0,
     cygwin -1, busybox `W`, BSD 0/-1) use Y (comment: G6-26 + busybox/BSD, launch L3.5-b C2);
     format with `printf -v __tp_r '%(%Y-%m-%d %H:%M:%S)T' "$__tp_e"`, UTC as `TZ=UTC0 printf -v …`
     (verified: the temporary TZ does not stick, `07 22`). No `date` call is left.
  R3 tpath._touchTime (:413-438): a date STRING → epoch via `date [-u] -d "$v" +%s` (GNU, busybox),
     else `date [-u] -j -f '%Y-%m-%d %H:%M:%S' "$v" +%s` (BSD; verified local/UTC/Tokyo and the
     garbage reject); keep the ^-?[0-9]+$ check. Then
       TZ=UTC0 printf -v __tp_st '%(%Y%m%d%H%M.%S)T' "$__tp_e"
       TZ=UTC0 "$__tp_touch" "$__tp_flag" -t "$__tp_st" -- "$__tp_p" 2>/dev/null
     (keep the /usr/bin/touch preference). Update the comments at :404-412 and tfile.sh:477-479
     (`touch -d @epoch` → `touch -t` under TZ=UTC0).
  R4 tpath._attrs (:459-499, the stat calls at :466, :468): `stat -c %a` / `stat -L -c %a` → `tpath._stat a "$p"` /
     `tpath._stat a "$p" L` (follow == true keeps -L, G6-14 unchanged).
  R5 tpath.getFullPath (:679-698): keep realpath -m, then readlink -m; replace the last fallback by
     a lexical normaliser for a path that starts with `/` after the $PWD join: split on `/`, drop
     empty and `.` components, `..` pops one (never above `/`), join with `/`, leading `/`, no
     trailing `/`. A drive-rooted or UNC path keeps today's answer. (Helper tpath._normPath, bash only.)
  R6 kcl/tpath/tests/_fsoracle.sh (new; for L3.5-2), sourced by tests:
       fso_stat LETTER PATH   → the GNU `stat -c %LETTER` value (X Y a), via `stat -c` else `stat -f`
                                (map as R1)
       fso_fmt EPOCH [utc]    → "YYYY-MM-DD HH:MM:SS" via printf '%(…)T' (utc: TZ=UTC0)
       fso_epoch STRING [utc] → epoch via `date [-u] -d` else `date [-u] -j -f '%Y-%m-%d %H:%M:%S'`
  R7 tests in kcl/tpath/tests (a new file NNN_L35_Portable.sh, next free number): R5's four probe
     inputs (`.` `..` `/nosuch_g613/a/../b` `./d/./../d` → $TMP, parent, /nosuch_g613/b, $TMP/d) with
     realpath/readlink shadowed by failing functions so the fallback runs on every platform; R1's bsd
     branch with a `stat` function that rejects -c and answers -f from fso_stat values; R2's W
     fallback with a `stat` function that prints `W`; R3's touch argv (a `touch` function recording
     "$@": `-m -t <stamp>` with TZ=UTC0 in its env).
  Docs: tpath/README.md:92 "`realpath -m`" → "`realpath -m`, else a lexical normaliser (busybox,
     BSD: `..` and `.` collapse, symlinks are not resolved)"; tfile/README.md:92 and
     tdirectory/README.md:94: "a date string" → "a date string (`YYYY-MM-DD HH:MM:SS` everywhere;
     other forms only where `date -d` parses them: GNU, busybox)".
Write scope: kcl/tpath/tpath.sh, kcl/tpath/README.md, kcl/tpath/tests/_fsoracle.sh (new),
     kcl/tpath/tests/NNN_L35_Portable.sh (new), kcl/tfile/tfile.sh (comment :477-479 only),
     kcl/tfile/README.md, kcl/tdirectory/README.md.
Acceptance:
  - repros: kb-freebsd clean and clean-gnu `tests.sh -n 9`, `-n 12`, `-n 18`, `-n 19` of kcl/tpath
    PASS; kb-alpine clean kcl/tpath `-n 9`, `-n 18` PASS, kcl/tdirectory `-n 18` … `-n 21`, `-n 35`,
    kcl/tfile `-n 13`, `-n 14`, `-n 31`, `-n 32`, `-n 41` PASS (tfile `-n 41` and tdirectory `-n 35`
    use GNU oracles only via busybox, which has them);
  - Windows: `bash $G kcl/tpath kcl/tfile kcl/tdirectory` PASS both runtimes, totals = old + R7's cases;
  - VMs: gate kcl/tpath kcl/tfile kcl/tdirectory on kb-alpine clean (PASS), kb-debian clean (PASS),
    kb-freebsd clean and clean-gnu (kcl/tpath PASS; tdirectory/tfile fail only in the 16 L3.5-2
    files and tfile 042/043's wc cases).
Timebox: 4 h. Critic after (core shared helpers, DL rules).
```

### L3.5-2 — tfile/tdirectory tests onto the portable oracle [S]

```
CARD: L3.5-2   (after L3.5-1)
Goal: the 16 test files that read stored times/modes with GNU tools use _fsoracle.sh instead.
Rows: C1 tdirectory 019 021 022 024 027 028 029 035; tfile 030 031 032 033 034 035 036 041 (Fc, Fg).
Fix rule: after the unit is sourced, each file gets
       source "$SCRIPT_DIR/../../tpath/tests/_fsoracle.sh"
   and every GNU call in the file is replaced, nothing else:
       stat -c %Y P | stat -c '%Y' P      → fso_stat Y P
       stat -c %X P | stat -c '%X' P      → fso_stat X P
       stat -c %a P                       → fso_stat a P
       read -r atime mtime <<< "$(stat -c '%X %Y' "$F")"
                                          → atime="$(fso_stat X "$F")"; mtime="$(fso_stat Y "$F")"
       date -d "@$E" '+%Y-%m-%d %H:%M:%S' → fso_fmt "$E"
       date -u -d "@$E" '+%Y-%m-%d %H:%M:%S' → fso_fmt "$E" utc
       date -d "STR" +%s                  → fso_epoch "STR"
       date -u -d "STR" +%s               → fso_epoch "STR" utc
   (`… 2>/dev/null || printf 0` tails stay as they are). After the edit
   `grep -nE 'stat -c|stat -L -c|date (-u )?-d' <file>` prints only comment lines.
Write scope: kcl/tdirectory/tests/{019,021,022,024,027,028,029,035}_*.sh,
             kcl/tfile/tests/{030,031,032,033,034,035,036,041}_*.sh.
Acceptance: repros: each row's `tests.sh -n N` on kb-freebsd clean and clean-gnu PASS; Windows
   `bash $G kcl/tfile kcl/tdirectory` PASS both runtimes, totals unchanged; VMs: gate kcl/tfile
   kcl/tdirectory on kb-freebsd clean + clean-gnu (PASS once L3.5-3 R1 is in for tfile 042/043),
   kb-alpine clean, kb-ubuntu clean PASS.
Timebox: 1.5 h.
```

### L3.5-3 — BSD/busybox test idioms (wc, sed -i, touch -d, timeout, perl, shebang) [S]

```
CARD: L3.5-3
Goal: the tests below stop depending on GNU/Linux spellings of wc, sed -i, touch -d,
      timeout --preserve-status, perl and /bin/bash; behaviour on Windows unchanged.
Rows: C4 (tdictionary 009, tfile 042, kkore 001, kkore 015 — Fc, Fg); C5 (kklass 139, 141, 142,
      kkore 013 — Fc, Fg); C6 (kcl/math 018, kklass 143 — Ac, Fc, Fg); C7 (dateutils 024 — Ac);
      the secondary causes in tfile 043 (wc) and thttpserver 004 (shebang). Causes: §1 C4-C7, C11.
Fix rules:
  R1 (wc) a count compared or printed as a string goes through $(( )):
       tdictionary/tests/009_KeysValues.sh:55   "$(d.Keys | wc -l)" == "3"  → $(( $(d.Keys | wc -l) )) -eq 3
       tfile/tests/042_G6_IO.sh:238,:246 and 043_G6_ReturnContract.sh:102
                                                "$(wc -c < "$X")" == "4"   → "$(( $(wc -c < "$X") ))" == "4"
       tfile 042:241,:249, 043:105 (the fail messages) → $(( $(wc -c < "$X") ))
       kkore/tests/001_KKLibTests.sh:175,:194   line_count=$(… | wc -l)    → line_count=$(( $(… | wc -l) ))
       kkore/tests/015_DocExamples.sh:95        home=$(ls -A "$HOME" | wc -l) → home=$(( $(ls -A "$HOME" | wc -l) ))
       kklass/tests/139_ClassDeclarationSites.sh:644,:645  lines=$(wc -l <F) → lines=$(( $(wc -l <F) ))
       kklass/tests/141_UnitHeaders.sh:182      err=$(wc -c < compile10.log) → err=$(( $(wc -c < compile10.log) ))
  R2 (sed -i) no `sed -i` in these tests; the edit goes through a temp file in the same directory:
       sed -i 'S' F    →  sed 'S' F > F.kt && mv F.kt F
         (kklass 139:327, :621; kkore 013:127; kklass 141:317 `4d`)
       kklass 141:313  sed -i '4i return 6' F  →  { head -n 3 F; printf 'return 6\n'; tail -n +4 F; } > F.kt && mv F.kt F
       kklass/docs/kklass_book.md:1915 (the doctest)
         sed -i 's/property p/property q/' shape.sh      # edit the unit
       → sed 's/property p/property q/' shape.sh > shape.new && mv shape.new shape.sh   # edit the unit
  R3 (touch -d) a relative age becomes an absolute -t stamp computed in bash:
       touch -d '10 minutes ago' FILES → printf -v _st '%(%Y%m%d%H%M.%S)T' $(( EPOCHSECONDS - 600 )); touch -t "$_st" FILES
         (kcl/math/tests/018_DE1_ProgfileSweep.sh:46, :106, :127)
       touch -d '2 hours ago' FILES    → the same with 7200 (kklass/tests/143_CompilerTempCleanup.sh:89, :90)
  R4 (busybox timeout) kklass 143:69: before the call
       K143_PS=(--preserve-status); timeout --preserve-status 1 true 2>/dev/null || K143_PS=()
       and pass `timeout -s TERM "${K143_PS[@]}" 3` (busybox timeout has no such option and already
       returns the program's own status, 143 — measured `rc=1` with the option).
  R5 (perl) dateutils/tests/024_IsoWeekSweep.sh: when `command -v perl` fails, each of the four
       perl-dependent cases (:38, :55, :83, :105) is `kt_test_start "<same title>"; kt_test_pass
       "SKIP: no perl on PATH (the reference oracle)"`; the fifth (:135) unchanged; count stays 5.
  R6 (shebang) thttpserver/tests/004_Server.sh:776: the once_nc fake starts `#!/usr/bin/env bash`
       (FreeBSD has no /bin/bash). The fake_nc with `#!/no/such/interp` stays as it is.
Write scope: kcl/tdictionary/tests/009_KeysValues.sh, kcl/tfile/tests/042_G6_IO.sh,
   kcl/tfile/tests/043_G6_ReturnContract.sh, kkore/tests/001_KKLibTests.sh,
   kkore/tests/015_DocExamples.sh, kkore/tests/013_SystemUnitHeaders.sh,
   kklass/tests/139_ClassDeclarationSites.sh, kklass/tests/141_UnitHeaders.sh,
   kklass/docs/kklass_book.md (the one example line), kklass/tests/143_CompilerTempCleanup.sh,
   kcl/math/tests/018_DE1_ProgfileSweep.sh, kcl/dateutils/tests/024_IsoWeekSweep.sh,
   kcl/thttpserver/tests/004_Server.sh (line 776 only). Repos: kcl, kklass, kkore.
Acceptance: repros: FreeBSD clean + clean-gnu: tdictionary -n 9, tfile -n 42, kkore -n 1, -n 13,
   -n 15, kklass -n 139, -n 141, -n 142, -n 143, math -n 18 PASS (tfile 043 needs L3.5-1 too);
   Alpine clean: math -n 18, kklass -n 143, dateutils -n 24 PASS;
   Windows: `bash $G kcl/tdictionary kcl/tfile kcl/math kcl/dateutils kcl/thttpserver kklass kkore`
   PASS both runtimes, totals unchanged; VMs: the same suites gated on kb-alpine clean, kb-ubuntu
   clean and kb-freebsd clean-gnu — no row of this card left (tfile/tdirectory C1 rows until L3.5-1/2).
Timebox: 2 h. Executor S (test-only and mechanical in kklass/kkore, as D8 of L2.5).
```

### L3.5-4 — tregex `\b` per C library [S]

```
CARD: L3.5-4
Goal: the `\b` rows expect what this platform's ERE does; the README names the delta.
Rows: C8 — tregex 002 (Fc, Fg), tregex 011 (Ac, Ag, Fc, Fg). Cause/repro: §1 C8.
Fix rule: near the top of 002_IsMatch.sh and 011_T3_T4_LocaleAndAnchors.sh, after the unit is
   sourced, with the comment `# platform probe (launch L3.5-b): how this C library's ERE treats \b`:
       __re='\b'; TRE_WB=0; [[ x =~ $__re ]] 2>/dev/null && TRE_WB=1          # 0: FreeBSD/macOS libc reject \b
       TRE_WB_END=0; (( TRE_WB )) && [[ '' =~ $__re ]] && TRE_WB_END=1        # 1: musl matches \b on ''
   002: the rows at :57 and :58 run unchanged when TRE_WB=1; else each is `kt_test_start "<same
     title>"; kt_test_pass "N/A: this C library's ERE has no \\b (rc 2); use \\< \\>"`.
   011: `_scan '\b' "ab cd" 5 "0 1 2 3 4" …` → TRE_WB=0: N/A pass as above; TRE_WB_END=1:
     `_scan '\b' "ab cd" 6 "0 1 2 3 4 5" …`; else unchanged.
     `_rep "ab cd" '\b' "|" "|a|b| |c|d" …` → TRE_WB=0: not called; TRE_WB_END=1: want "|a|b| |c|d|".
     the `\b` split → TRE_WB=0: not checked; TRE_WB_END=1: want "[][a][b][ ][c][d][]".
     Case counts unchanged.
   README.md (after the sentence at :140 "The engine is the C library's ERE …"): "`\b` is an extension
     of the C library: glibc, newlib and musl accept it (musl also matches it on an empty remainder,
     so a scan with `\b` reports one more offset), FreeBSD and macOS libc reject it (rc 2) — `\<` and
     `\>` work everywhere."
Write scope: kcl/tregex/tests/002_IsMatch.sh, kcl/tregex/tests/011_T3_T4_LocaleAndAnchors.sh,
   kcl/tregex/README.md.
Acceptance: repros `kcl/tregex … -n 2`, `-n 11` PASS on kb-freebsd clean, kb-alpine clean and
   clean-gnu, kb-ubuntu clean; Windows `bash $G kcl/tregex` PASS both runtimes, totals unchanged.
Timebox: 1 h.
```

### L3.5-5 — kcl/math on BWK awk [O]

```
CARD: L3.5-5
Goal: the engine answers IEEE results on BWK awk (FreeBSD, macOS) where BWK can; 019's fixtures work
      on an awk without -W; the subnormal limitation is handled per D5.
Rows: C9 — math 014 (Fc), 019 (Fc, Fg). Cause/repro: §1 C9.
Fix rules:
  R1 math.sh BEGIN (:269): `_NZ=_dv(-1,_INF);` → `_NZ=_dv(-1,_INF); _NZOK=(atan2(0,_NZ) > 3);`;
     the dispatch rewrite (:272) `else if (c=="0" && $i+0==0) $i=_NZ` →
     `else if (c=="0" && $i+0==0 && _NZOK) $i=_NZ`; extend the comment at :221-231: "BWK awk
     (one-true-awk: FreeBSD, macOS) stores every computed -0 as +0 (tran.c setfval) but reads a field
     `-0` as -0, so the rewrite runs only where _NZ really is -0 (launch L3.5-b)". Verified: §1 C9.
  R2 tests/019_L27_AwkEngine.sh:56 LINEWISE: gawk if present; else `"$REAL_AWK" -W interactive` only
     when `LC_ALL=C "$REAL_AWK" -W version </dev/null 2>&1` starts with `mawk`; else plain
     `"$REAL_AWK"` (BWK and busybox answer a pipe line-wise without a flag). Verified with R1: 019 16/16
     on kb-freebsd clean.
  R3 per D5 (recommended a): README "Engine" section: "BWK awk reads an operand below
     2.2250738585072014e-308 (a subnormal) as 0; results that are subnormal are computed correctly";
     014's `5e-324` row asserts `0.5 -1073`, except when the engine's awk identifies as BWK
     (`awk --version` prints `awk version 2…`) where it asserts `0 0` and says so in the pass text.
Write scope: kcl/math/math.sh, kcl/math/README.md, kcl/math/tests/014_M1_EngineDomain.sh,
   kcl/math/tests/019_L27_AwkEngine.sh.
Acceptance: repros math -n 14, -n 19 on kb-freebsd clean + clean-gnu PASS; Windows `bash $G kcl/math kcl`
   PASS both runtimes, totals unchanged; VMs gate kcl/math on kb-ubuntu (mawk), kb-debian (mawk
   20250131), kb-fedora (gawk), kb-alpine clean (busybox), kb-freebsd clean (BWK) PASS.
Timebox: 1.5 h.
```

### L3.5-6 — wrapper bench ceilings with an absolute floor [S]

```
CARD: L3.5-6
Goal: the 007 bench ceilings stay order-of-magnitude guards on a fast-fork platform.
Rows: C12 — tgrep 007, tsed 007 (Ag). Cause/evidence: §1 C12 (fail alone 4/5 and 5/5).
Fix rule: every ratio ceiling `lim=$(( BARE * 10 ))` in kcl/tgrep/tests/007_Bench.sh (:145, :247,
   :256) and kcl/tsed/tests/007_Bench.sh (:171 `__lim`, :315) becomes
       lim=$(( BARE * 10 )); (( lim < BARE + 30000 )) && lim=$(( BARE + 30000 ))
   and the header comments (tgrep 007:13-24, tsed 007:11-20) gain one sentence: "On a platform
   where a process start is ~1 ms (Alpine, measured L3.5-b: grep 1.3 ms, search 14 ms) the wrapper's
   fixed bash cost alone is 10x; the ceiling is therefore never below bare + 30 ms — still far below
   what a per-line instance or an extra process per call costs."
Write scope: kcl/tgrep/tests/007_Bench.sh, kcl/tsed/tests/007_Bench.sh.
Acceptance: repros tgrep -n 7 and tsed -n 7 ×5 each on kb-alpine clean-gnu PASS 5/5; Windows
   `bash $G kcl/tgrep kcl/tsed` PASS both runtimes, totals unchanged; gate kcl/tgrep kcl/tsed on
   kb-alpine clean-gnu and kb-fedora clean PASS.
Timebox: 45 min.
```

### L3.5-7 — FIFO process substitutions on FreeBSD pkg bash [O, design]

```
CARD: L3.5-7
Goal: no `sh-np.*` FIFO is left in TMPDIR by thttpserver's relay listener (C11) or the math
      co-process start (L3.5-a-o5) on a bash whose `<( )` is a FIFO.
Rows: C11 — thttpserver 004 (fact 4), 009 (Fg); math: none (the leak is not asserted today).
Cause: §1 C11 — the shell that created the FIFO `exec`s and never unlinks it.
Options (decide in the card's first step, report before coding):
  (a) the relay as a FIFO thttpserver owns: mkfifo "$__ths_dir/relay$s", `cat fifo$s > relay$s &`
      (pid recorded and stopped with the slot), `exec "${ths_argv[@]}" < relay$s`; removed with the
      slot dir. `$!` stays the listener. Math: open the program substitution in a shell that does not
      exec (the co-process's outer shell), or use the existing temp-file path on such bashes.
  (b) no `exec` after the inner substitution: the listener is a child of the procsub shell; _stopPid
      and _state must then target that child (pid via a pid file) — larger change to the slot model.
  (c) document the leak for FIFO-procsub bashes and relax the tests — not recommended (a server
      leaks one file per connection).
  Recommended (a). Detect a FIFO-procsub bash once (`[[ $(echo <(:)) == /dev/fd/* ]]`) only if the
  chosen fix costs more than today's path on /dev/fd bashes.
Write scope: kcl/thttpserver/thttpserver.sh, kcl/thttpserver/README.md, kcl/thttpserver/tests/
   (a new case: no sh-np.* left after N spawns, N/A where `<( )` is /dev/fd), kcl/math/math.sh,
   kcl/math/tests/ (the same check for feStart/feStop), docs/dev/PORTING.md H44 "still open" line.
Acceptance: FreeBSD clean-gnu gate kcl/thttpserver kcl/math PASS and `ls -A` of each test TMPDIR
   free of sh-np.*; Windows `bash $G kcl/thttpserver kcl/math` PASS both runtimes; kb-debian (socat)
   gate kcl/thttpserver PASS.
Timebox: 3 h. Critic after.
```

### L3.5-8 — tpipe EOF-path `wait` 127 under load [O, investigation]

```
CARD: L3.5-8
Goal: explain `wait: pid N is not a child of this shell` at tpipe.sh:1037 (C13) and fix it in tpipe,
      or show it is a bash defect and work around it.
Rows: C13 — tutil 002 (Ac), tpipe 003 (Ag); 2 hits in 4 Alpine full gates, 0 alone (10/10 each),
      0 in a 3×2000-loop minimal repro.
Steps: reproduce under load on kb-alpine (the fork-storm harness in ktests/tools, or 8 parallel
   copies of tpipe 003 / tutil 002 — inside the VM, bounded); record whether the producer was
   already reaped (bash 5.3 procsub bookkeeping: `$!` of a `<( )`, `wait` after a later `$( )`/`<( )`);
   then fix in tpipe._close (e.g. keep the status of a producer bash reports as "not a child" from a
   SIGCHLD-safe source, or wait by a recorded job) — the rule is the card's own result.
Write scope: kcl/tpipe/tpipe.sh, kcl/tpipe/tests/ (a regression case if a deterministic repro is
   found), kcl/tpipe/README.md; scratch.
Acceptance: the repro under load: before ≥1 hit in K runs, after 0 in ≥10×K; Windows `bash $G kcl/tpipe
   kcl/tutil kcl/tgrep kcl/tsed kcl/tawk` PASS both runtimes; gate kcl/tpipe kcl/tutil on kb-alpine
   clean ×3 PASS. Timebox 3 h; PARTIAL with the findings if not found.
```

### L3.5-9 — TAwk inPlace finds gawk's inplace.awk [S, after OG1 = A or B]

```
CARD: L3.5-9   (or a rule inside L3.4)
Goal: `inPlace = 1` works with a gawk whose data dir is not /usr/share/awk; no cwd lookup.
Rows: C10 — tawk 005, 006 (Fg). Cause/repro: §1 C10.
Fix rule: tawk.sh:690 `-i /usr/share/awk/inplace.awk` → `-i "$__taw_ip"` where __taw_ip is the first
   ABSOLUTE directory of gawk's default AWKPATH containing a readable inplace.awk:
       $( unset AWKPATH; exec "$GAWK" 'BEGIN { print ENVIRON["AWKPATH"] }' )   # e.g. .:/usr/local/share/awk
   (GAWK = the binary TAwk runs), entries not starting with `/` skipped, cached per gawk path in a
   unit global; none found → the member is rc 2 with LastError "TAwk: gawk's inplace.awk not found
   in <AWKPATH value>". Header comments :77, :99, :147 follow.
Write scope: kcl/tawk/tawk.sh, kcl/tawk/README.md, kcl/tawk/tests/006_Contract.sh (the builder
   assertion that pins the old path, if any).
Acceptance: repros tawk -n 5, -n 6 on kb-freebsd clean-gnu PASS; Windows `bash $G kcl/tawk` PASS both
   runtimes, totals unchanged; gate kcl/tawk on kb-fedora and kb-alpine clean-gnu PASS.
Timebox: 1 h.
```

## 4. Decisions for the supervisor

1. **D1 — OG1: option A** (§2.3). Consequence for this plan: L3.5-9 joins L3.4; the 577 FreeBSD
   `clean-gnu` cases start running in L3.4 and will produce new rows there (budget an L3.4 triage).
2. **D2 — tpath's core rewrite as one O batch (L3.5-1) plus a mechanical S batch (L3.5-2).**
   Alternative: keep GNU in tpath and resolve `gnustat`/`gdate`/`gtouch`/`grealpath` through the L3.3
   resolver — makes the core depend on GNU coreutils on BSD/macOS, contradicting A's "core tool-free".
3. **D3 — accepted date strings in the setters**: `YYYY-MM-DD HH:MM:SS` everywhere, any other form
   only where `date -d` parses it (GNU, busybox) — no change on Windows/Linux. Alternative: parse only
   the canonical form in bash everywhere (identical behaviour on all platforms, rejects strings that
   work today on Windows/Linux: a behaviour change).
4. **D4 — `getFullPath` fallback only** (L3.5-1 R5: `realpath -m` stays first where it exists).
   Consequence: with a symlink in the path the answer differs by platform (GNU resolves it, the
   fallback does not). Alternative: lexical everywhere (FPC `ExpandFileName` semantics, fork-free,
   identical on all platforms; a behaviour change for symlinked paths on Windows/Linux).
5. **D5 — subnormal operands on BWK awk**: (a, recommended) document and make 014's row
   engine-aware; (b) the engine rewrites a subnormal operand itself (`m * 10^(e+300) * 1e-300`,
   ~5 lines in the dispatch, a cost on every line that contains `e-3`); (c) prefer another awk when
   one is installed (none is on stock FreeBSD/macOS).
6. **D6 — bench ceilings get an absolute floor of bare + 30 ms** (L3.5-6). Alternative: per-platform
   ratio (Alpine 20×), which keeps the ratio form but needs a platform switch in two tests.
7. **D7 — FIFO-procsub leak: fix (L3.5-7, option a)** rather than document. Also closes
   L3.5-a-o5 and PORTING H44's open item.
8. **D8 — C13 as an O investigation**, not a test retry. The gate already reports it as FLAKY (not a
   PASS); L3.6 on Alpine may show it again until L3.5-8 lands.
9. **D9 — C14 (tinifile 011)**: no change; watch in L3.6.
10. **D10 — Alpine `clean-gnu` has no socat**: thttpserver's 75 socket cases SKIP there (and in both
    `clean` snapshots, by design). Add `socat` to `tools/vmlab/provision/apk.sh` GNU list and retake
    the snapshot (a provisioning card), or accept the SKIPs for L3.6.

## 5. Expected effect

Predicted non-PASS files per gate on this tree's L3 runs (today → after the batches named):

| run | today | after L3.5-1..-8 | after L3.5-9 / L3.4 | what may remain |
|---|---|---|---|---|
| kb-alpine `clean` | 17 | 0 | 0 | C13 if L3.5-8 is PARTIAL |
| kb-alpine `clean-gnu` | 4 | 0 | 0 | the same |
| kb-freebsd `clean` | 52 | 0 | 0 | C14 flake |
| kb-freebsd `clean-gnu` | 54 | 2 (C10) | 0 + new rows from the 577 un-skipped wrapper cases | — |

Partial states: the S batches alone (L3.5-3, -4, -6) take Alpine `clean` 17 − (C6 2 + C7 1 + C8 1)
= **13**, Alpine `clean-gnu` 4 − (C8 1 + C12 2) = **1** (C13), FreeBSD `clean` 52 − (C4 4 + C5 4 +
C6 2 + C8 2) = **40**, FreeBSD `clean-gnu` 54 − 12 = **42** (tfile 043 stays, in C1, until L3.5-1).
With L3.5-1 but before L3.5-2: FreeBSD keeps the 16 L3.5-2 files. Without L3.5-5: FreeBSD
keeps 014/019 (Fc 2, Fg 1). Without L3.5-7: Fg keeps thttpserver 004, 009. The FreeBSD predictions
assume the tpath rewrite passes the existing time tests unchanged in substance — verified only
piecewise (stat map, `printf '%(…)T'`, `touch -t` round trip, `date -j -f`), the biggest
uncertainty here; the math prediction is verified end to end on the VM's copy (019 16/16, 014 50/51).
