# L2.5 — triage of the Linux failures

Date 2026-10-21, tree kbool `b4ca088`. Input: [`L2_failures.tsv`](L2_failures.tsv) (111 rows) and
[`L2_runs.md`](L2_runs.md). Every cause below was read in the code and checked by a probe in a
lab VM (kb-ubuntu, kb-debian, kb-fedora; snapshot `clean`; the probe scripts and their raw output
are in the L2.5 scratch folder of the supervisor session, not in the tree). Hazard ids are from
[`../PORTING.md`](../PORTING.md).

Tool versions on the VMs (probed):

| VM | bash | awk | gawk | sed | grep | coreutils | nc | socat |
|---|---|---|---|---|---|---|---|---|
| kb-ubuntu | 5.2.21 | mawk 1.3.4 20240123 | 5.2.1 | 4.9 | 3.11 | 9.4 | OpenBSD 1.226-1ubuntu2 (+ ncat 7.94, nc.traditional 1.10) | 1.8.0.0 |
| kb-debian | 5.2.37 | mawk 1.3.4 20250131 | 5.2.1 | 4.9 | 3.11 | 9.7 | OpenBSD 1.229-1 (+ ncat 7.95, nc.traditional 1.10) | 1.8.0.3 |
| kb-fedora | 5.3.9 | gawk 5.3.2 | 5.3.2 | 4.9 | 3.12 | 9.10 | OpenBSD 1.237 (`netcat`, upstream dialect) + ncat 7.92 | 1.8.1.1 |
| Windows (reference) | 5.2.37 / 5.3.9 | gawk 5.0.0 / 5.4.0 | same | 4.9 | **3.0** | 8.32 | GNU 0.7.1 (MSYS2) | — |

## 0. Summary

| cluster | rows | cause (one line) | scope | executor | batch / task |
|---|---|---|---|---|---|
| C1 kcl/math (17 files) + kcl/tests 202 | 54 | mawk's parser overflows on the engine's 81-deep `else if` chain → the awk co-process never starts | mawk (Ubuntu, Debian) | O | L2.7-M |
| C1f kcl/math 018 on Fedora | 1 | FLAKY once in the full gate; not reproduced (30 solo runs + 3 suite runs) | — | — | watch at L2.8 |
| C2 kcl/thttpserver (5 files) | 20 | argv is GNU netcat 0.7.1 only; no Linux distro packages it | all non-Windows | O | L2.7-N (§3) |
| C3 CR text mode (tawk, tsed, tgrep) | 9 tcases | cygwin/msys tools drop the CR in text mode, Linux tools never do; tests pin the Windows behaviour | all non-Windows | S | L2.6-1 |
| C4 tool-version / race (tgrep K, thead H3, ttail T2, tsed S7) | 4 tcases | grep ≥ 3.5, coreutils ≥ 9.5, `tail -f` SIGPIPE, a kill race | GNU Linux | S | L2.6-1 |
| C5 backslash is not a separator (tawk A11 ×2, tfile 042) | 3 tcases | msys treats `\` as `/`; Linux does not | all non-Windows | S | L2.6-1, L2.6-2 |
| C6 tregex empty pattern | 4 | glibc `regcomp("")` succeeds (match-all), newlib refuses; S2 ("rc 2") is not enforced in code | glibc | S | L2.6-2 |
| C7 tpipe 002 `sleep 8` STRAY | 4 | the test producer is a function: TERM kills the subshell, its `sleep 8` is orphaned | all | S | L2.6-2 |
| C8 kkore 011 Windows paths | 4 | 7 cases need a `/<drive>/` path (`uf_win`) | all non-Windows | S | L2.6-3 |
| C9 ktests 045 under de_DE | 1 | stray attribution race: the Linux start estimate is up to 10 ms early (not locale) | Linux | O | L2.7-K |

Rows: **35** covered by an S fix rule (C3–C8: tawk 4, tsed 4, tgrep 4, thead 3, ttail 4, tregex 4,
tfile 4, tpipe 4, kkore 4), **1** by an O fix rule (C9), **74** need design (C1 54, C2 20),
**1** not a defect / unexplained flake (C1f). 35 + 1 + 74 + 1 = 111.

## 1. Clusters

### C1 — kcl/math under mawk (54 rows: 17 files × 3 runs on Ubuntu/Debian/Debian de_DE; kcl/tests/202 × 3)

**Cause 1 — parser depth.** The engine program (`kcl/math/math.sh:189-310`, `__MATH_AWK_PROG`)
dispatches with one chain `if (op=="sin") … else if … else printf "ERR\n"` of 81 links. mawk 1.3.4
nests every `else if` on its yacc stack and overflows at ~64 links:

```
kb-ubuntu$ echo pi | awk -f fe.awk
awk: fe.awk: line 102: syntax error at or near int
synthetic chain:  chain 50: 7 | chain 70: mawk: /tmp/ch.awk: line 66: syntax error at or near x64
```

No single line is wrong (deleting any one line does not make it parse; `2^int($3)` alone parses).
The coproc dies at once, the start probe (`math.sh:772-775`) gets no `pi`, the fallback file path
(`:786-805`) fails the same way, `math._fe_start` returns 1, and every Tier-B member is rc 1 with
`RESULT=''`. **"no awk on PATH"** in 014 is only that test's message for `math.feStart` failing
(`014_M1_EngineDomain.sh:28`) — awk is on PATH; the engine refused to start silently (the M10
degradation path cannot tell "no awk" from "an awk that cannot run the program").

**Cause 2 — input buffering.** With the chain flattened, plain mawk still answers nothing on a
pipe until its input buffer fills (it reads stdin in blocks); `-W interactive` makes it line-wise:

```
mawk -f:                [no answer in 3 s] [no answer in 3 s]
mawk -W interactive -f: [3.1415926535897931] [1]
```

**Cause 3 — NaN compares equal to 0 in mawk.** `mawk 'BEGIN{n=log(-1); print (n==0),(n!=n)}'` →
`1 0` (gawk `0 1`). `_pn` (`if (x == 0) x = 0`, :194) turns every NaN into `0`; `_dv` (`if (b ==
0)`, :190) treats a NaN divisor as zero. With causes 1+2 fixed this alone fails 014 (18 cases,
`math.sqrt -1: RESULT='0' expected 'nan'`) and 012; guarding the two lines with `!_isnan(x)` makes
012 5/5 and 014 51/51.

**Probe of the combined fix** (a patched copy of the tree inside kb-ubuntu, PATH `awk` = `mawk -W
interactive`): 001–009, 011, 013, 015–018 and kcl/tests 202 PASS; with the NaN guards 012 and 014
PASS; **left: 010 randG** (`randG distribution off: mean= stddev=` with `__MATH_FE_STRICT=1`,
a hang without it: 400 `$(math.randG 10 2)` subshells sharing the co-process; cause not found).
The same patched copy under gawk: **181/181** (kb-ubuntu, kb-debian) — the flattening is
behaviour-neutral for gawk. Unpatched, with gawk forced via a PATH shim: 181/181 on both mawk VMs.
Other mawk output deltas seen and harmless: `inf`/`+inf` spellings (normalised by `_fe_norm`),
bare `nan`/`inf` input parsed as values (gawk parses them as 0; the unit already sends signed
tokens). busybox awk on Ubuntu/Debian is built **without math** (`Math support is not compiled
in`) — an L3 (Alpine) item.

Scope: mawk (Ubuntu, Debian defaults). gawk (Fedora; Windows) unaffected. BWK awk (FreeBSD,
macOS) and busybox awk: unknown until L3.

Fix: **needs design** — §4.

### C1f — kcl/math 018 FLAKY on Fedora (1 row)

`[FAIL] out='' (018_DE1_ProgfileSweep.sh)` in the cell, then the sweep case found the dead pid's
file unswept: the child `bash -c "$SHIM …"` printed nothing at all (not even the `printf '%s|%s'`),
i.e. it died before its first command. Passed on rerun. Probe on kb-fedora: `018 failures: 0/30`
alone, the whole math suite 3× 181/181. Not a mawk issue (Fedora is gawk). **No fix**; watch it in
the L2.8 gates (if it recurs: keep the cell log and the gate's stray/watchdog records of that
second).

### C2 — kcl/thttpserver (20 rows: 004, 005, 006, 007, 009 × 4 runs)

`TNetcatTransport.BuildArgv` (`thttpserver.sh:401`) builds `nc -l -c -vv -n -w TTL -s ADDR -p
PORT` — GNU netcat 0.7.1's dialect (H26). Ubuntu/Debian `nc` is OpenBSD nc (`invalid option --
'c'`), Fedora's `nc` is upstream OpenBSD nc (`cannot use -s and -l`). Every server fails to listen;
the tests do not SKIP because `tests/_ths_socket.sh:31` takes any `nc` on PATH. 001/002/003/008
(no socket) pass. Also found while reading the tests, hidden today behind the listen failure: the
child counters and `ths_child_of` read cygwin-only `/proc/PID/ppid` (`_ths_socket.sh:224`,
004:449/470/690/727, 005:44/248/293, 006:670) — vacuous or broken on Linux; three tests start
`$THS_NC` with GNU flags themselves (004:683 blocker, 005:230, 006:780 bind probes) and
`ths_listening` greps `^Listening on`.

Fix: **needs design** — §3.

### C3 — CR text mode (tawk 005 ×3 tcases, tsed 005 ×3, tgrep 005 ×1)

Probe (all three VMs, identical): `printf 'a 1\r\n' | gawk '{print}'` → `a 1 \r \n`; sed → `A 1 \r
\n`; grep → `n e e d l e c r l f \r \n`. On Windows the cygwin/msys builds open input in text mode
and drop the CR; the units pass that through unchanged and their docs call it "measured on this
platform" (`tgrep.sh:77`, `tutil/README.md:238`, `tawk/README.md:378`, `tsed/README.md:325`,
`tgrep/README.md:292`). The wrappers are right (they mirror the bare tool, which is what the
`binary`/`crlf` properties are defined against); the tests pin the Windows result:

| file:line | tcase | what fails on Linux |
|---|---|---|
| tawk/tests/005_Run.sh:834 | A9 text mode STRIPS the CR | records are `a 1\r` `b 2\r`; the `!= *'\r'*` clause (got == bare holds) |
| tawk 005:877 | A9 inPlace keeps every CR; bare `-i inplace` does not | the **bare** oracle keeps the CR (`bwant` LF-only) |
| tawk 005:897 | A9 nullData keeps an embedded CR; bare strips it | bare oracle keeps `x\r\ny` |
| tsed/tests/005_Run.sh:681, :727, :746 | S9, the same three | the same three |
| tgrep/tests/005_Search.sh:747 | §2.6 a CRLF record carries NO CR | record `needle crlf\r`, length 12 |

Scope: every non-Windows target. Fix rule: L2.6-1 R1. Depends on decision D1.

### C4 — tool versions and two races (4 tcases)

| file:line | tcase | cause (probe) | fix |
|---|---|---|---|
| tgrep 005:927 | K: a file with a NUL yields the `Binary file … matches` RECORD | grep ≥ 3.5 moved the note to **stderr** and reworded it: `rc=0 out=[] err=[grep: …/nul: binary file matches]` (all VMs; Windows grep is 3.0) | R2 |
| thead/tests/005_Run.sh:666 | H3: 19-digit `bytes = -9999999999999999999` is head's own rc 1 | coreutils 9.4 (Ubuntu): `rc=1 … Value too large`; 9.7 (Debian), 9.10 (Fedora): `rc=0 bytes=0 err=[]` — head now accepts it. Explains "Debian + Fedora only" | R3 |
| ttail/tests/005_Run.sh:932, :951 | T2: `each`/`first` on a follow stream → lastRc 143 | GNU `tail -f` on Linux watches its stdout and raises SIGPIPE itself when the reader closes: `5 rc=141 selfexit` (no kill sent; all VMs). `tpipe._close` (`tpipe.sh:483`) closes, then TERMs: whichever lands first. Cygwin's tail cannot notice → always 143 | R4 |
| tsed 005:472 (and the same pattern, passing by luck, tawk 005:599) | S7/A7: `first` with a missing file → lastRc 2 | sed writes its buffered records and exits 2; `first` reads one record, closes, TERMs (`tpipe.sh:483`). Probe of exactly that sequence ×100: Ubuntu `1 143; 99 2`, Debian `2 143; 98 2`, Fedora `3 143; 97 2`. Member rc 0 and RESULT are right either way | R5 |

Scope: GNU Linux (versions), any fast kernel (races).

### C5 — `\` is a filename character (tawk 005 ×2 tcases, tfile 042 ×1)

Probe: `: > "$T/bsq\f"; [[ -e $T/bsq/f ]]` → `backslash is a filename char` (all VMs).

| file:line | tcase | on Linux |
|---|---|---|
| tawk 005:1045 | A11 backupSuffix `.b\k` names the backup exactly `FILE.b\k` | backup is the plain file `ipbs.txt.b\k` (listed in the failure); only the `-f "$FX/ipbs.txt.b/k"` clause fails (`ipbs.txt.b` is the empty directory the test made) |
| tawk 005:1066 | A11 `.b\k` with NO `FILE.b` dir — gawk's fatal link(): rc 1, lastRc 2 | link() succeeds: `rc=0 lastRc='0' err=''`, file upper-cased |
| tfile/tests/042_G6_IO.sh:202 | encrypt of a backslash-addressed path keeps its temp file next to the file [G6-26] | `"$bsdir\\bs.txt"` names a non-existent file → `tfile._crypt_file` rc 1 at `tfile.sh:161`; openssl itself works (the round trip at :179 passes) |

### C6 — tregex empty pattern (4 rows)

`tregex.sh:199` `[[ "$1" =~ $__re ]]` is the only engine call. Probe: `re=''; [[ abc =~ $re ]]` →
`rc=0` on all VMs (cygwin: rc 2). The header (`tregex.sh:33` "S2 empty pattern '' -> rc=2") and
the test (`002_IsMatch.sh:29` "our decision") make rc 2 the contract, but nothing enforces it.
Also probed: `re='a|'` → rc 0 on glibc (rc 2 on cygwin); no test pins it. Fix rule L2.6-2 R7.

### C7 — tpipe 002 `sleep 8` STRAY (4 rows)

`tpipe/tests/002_Stop.sh:98` `sigpipe_producer() { trap '' PIPE; printf 'a\n'; sleep 8; printf
'b\n'; }` runs in a process-substitution subshell; `$!` is that subshell, `tpipe._close` TERMs it
(`tpipe.sh:483`, by design not the group: `:466`), and its child `sleep 8` is re-parented to 1.
Probe (the same sequence, 0.3 s before the kill): `rc=143` then `39900 1 sleep 8`; the real test
run alone: 13/13 PASS and **8** `sleep 8` orphans with ppid 1 (the gate's count). With `exec sleep
8` in the producer: `rc=143`, `no sleep 8 left`. Scope: all (Windows' stray guard does not flag
them — not investigated). Fix rule L2.6-2 R8; the unit limitation is decision D5.

### C8 — kkore 011 Windows paths (4 rows)

`kkore/tests/unit_fixture.sh:155` `uf_win` refuses a non-`/<drive>/` path (`uf_win: not a
/<drive>/ path: …`), so `UF_WIN` stays stale/empty and 7 cases fail (011:73, 81, 86, 126, 144,
210, 500). Three more cases built on `uf_win` pass on Linux only vacuously (121, 139, 214: they
assert that the Windows value is NOT used, with an empty value). The code under test
(`kkore/kuse.sh:1050-1129, 1385-1486`) is portable; drive-letter spellings and
`USERPROFILE`/`ProgramData` are Windows concepts. Fix rule L2.6-3 R9.

### C9 — ktests 045 under de_DE (1 row; not locale)

`045_StrayGuard.sh:461` expects the orphan labelled `started during …/a_leaky/tests/tests.sh`; it
was labelled `(before the first suite)`. `suitejob.sh:237` attributes by
`KT_STRAYS_START[p] >= KT_SUITEJOB_T0[i]`; on Linux the start estimate (`ktest_proc.sh:289-302`,
(now − `/proc/uptime`) + ticks×10) truncates to 10 ms and can be **earlier** than the real start,
contradicting `strays.sh:88-89` ("never earlier"). Probe (fork right after taking t0, ×200):
Ubuntu `2 -10; 4 -9; 47 0; 142 1; 5 2`, Debian `8 -9; …`, Fedora `7 -9; 2 -5; …` — 3-5 % of
forks look 5-10 ms early. Both ms parsers already accept `,` (`strays.sh:169`,
`ktest_proc.sh:120`); the locale was a coincidence. Core harness → **O** (L2.7-K): compare with
`KT_STRAYS_START[p] + KT_PROC_START_EARLY_MS >= T0` where `KT_PROC_START_EARLY_MS` = 20 for the
linux backend, 0 for cygwin/ps; fix the "never earlier" sentence in `strays.sh:88-89` and the
ktest_proc.sh header ("linux: up to one tick early").

## 2. S batches

All batches: Write scope = the files listed; `git -C kcl` (or kkore) only; keep LF; no unit code
outside the files named. Stop if a rule does not fit the code you see → BLOCKED.
Common definitions used by the rules (put them once near the top of each test file, after its
fixtures exist, with the comment `# platform probe (launch L2.5)`):

```bash
# 1 when the tool keeps the CR of a CRLF line in text mode (Linux, BSD); 0 when it drops it (cygwin/msys builds)
TM_KEEPS_CR=0; [[ "$(timeout 20 <BARE-TOOL-ON "$FX/crlf.txt"> 2>/dev/null </dev/null | od -c)" == *'\r'* ]] && TM_KEEPS_CR=1
# 1 when '\' is a path separator (MSYS2, Cygwin)
BS_SEP=0; [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]] && BS_SEP=1
```

`<BARE-TOOL-ON …>`: tawk `gawk --sandbox -e '{print}' -- "$FX/crlf.txt"`; tsed `sed -e '' --
"$FX/crlf.txt"`; tgrep `grep -e needle -- "$FX/crlf.txt"`.

### L2.6-1 — kcl wrapper tests (C3, C4, C5-tawk) — 19 rows

Rows: kcl/tawk 005_Run ×4 runs, kcl/tsed 005_Run ×4, kcl/tgrep 005_Search ×4, kcl/thead 005_Run
×3 (debian, fedora, debian de_DE), kcl/ttail 005_Run ×4.

Files (11): `kcl/tawk/tests/005_Run.sh`, `kcl/tsed/tests/005_Run.sh`,
`kcl/tgrep/tests/005_Search.sh`, `kcl/thead/tests/005_Run.sh`, `kcl/ttail/tests/005_Run.sh`,
`kcl/tawk/README.md`, `kcl/tsed/README.md`, `kcl/tgrep/README.md`, `kcl/tutil/README.md`,
`kcl/ttail/README.md`, `kcl/ttail/ttail.sh` (a comment line only, R4).

- **R1 (CR, C3).** In each tcase of the C3 table: when `TM_KEEPS_CR=1` the expectation follows the
  bare tool. Exactly:
  - tawk :834 / tsed :681 — records: `arr_is SGOT 'a 1' 'b 2'` (tsed `a1 b2`) becomes
    `arr_is SGOT "a 1$CR" "b 2$CR"` when `TM_KEEPS_CR=1`; keep `"$got" == "$want"`; the clause
    `"$got" != *'\r'*` applies only when `TM_KEEPS_CR=0`. Title: replace "text mode STRIPS the CR"
    by "text mode = the bare tool's text mode (cygwin/msys drop the CR, Linux/BSD keep it)".
  - tawk :877 / tsed :727 — `bwant` = `printf 'A 1\r\nb 2\r\n' | od -c` (tsed `A1\r\nb2\r\n`) when
    `TM_KEEPS_CR=1`; the wrapper half unchanged. Title: "…; bare `-i inplace` keeps them only
    where the tool keeps the CR".
  - tawk :897 / tsed :746 — `arr_is SWANT a $'x\ny' last` becomes `arr_is SWANT a "x$CR"$'\n'"y"
    last` when `TM_KEEPS_CR=1`; the wrapper half unchanged.
  - tgrep :747 — when `TM_KEEPS_CR=1` expect `"$rec" == "needle crlf$CR" && ${#rec} -eq 12`.
    Title: "…a record from a CRLF file is the bare grep's record (no CR on cygwin/msys, CR kept on
    Linux/BSD)".
  - Docs: after the first sentence of `tawk/README.md` §"text mode" (:378), `tsed/README.md`
    (:325), `tgrep/README.md` §5 (:292) and in the `tutil/README.md` table row (:238) add exactly:
    "Measured on Windows (Git-bash/MSYS2): the cygwin/msys builds open input in text mode and
    drop the CR. On Linux and BSD the tool keeps the CR in every mode; there `crlf = 1` is the way
    to drop it." In the two "default | … arrives as …" table rows (tawk :383, tsed :330) append
    " (Windows; Linux/BSD: `a 1\r`)" / " (Windows; Linux/BSD: `a1\r`)".
- **R2 (grep binary note, C4).** tgrep :927: compute the oracle first —
  `TG_BIN="$(timeout 20 grep -e needle -- "$FX/bin.dat" 2>/dev/null </dev/null)"`. If `TG_BIN ==
  "Binary file "*" matches"` keep the assertion; else assert `rc -eq 0 && ${#SGOT[@]} -eq 0`
  (grep ≥ 3.5 prints the note on stderr). Title: "K: a file with a NUL: the bare grep's answer
  (grep < 3.5: one `Binary file … matches` RECORD; ≥ 3.5: no record, note on stderr), rc 0". Add
  to `tgrep/README.md` §"`Binary file X matches` is a record" (:198) the sentence "grep 3.5 and
  later write `grep: FILE: binary file matches` to stderr instead: no record, rc 0." Leave the
  `addArg -a` case (:938) as is.
- **R3 (thead H3, C4).** thead :666: oracle first —
  `head -c -9999999999999999999 -- "$FX/f5.txt" >/dev/null 2>&1 </dev/null; th_w=$?`. `th_w == 1`
  → current assertion. Else assert `TH_RC == 0 && TH_N == 0 && TOOL_N == 0 && lr == 0`. Title:
  "H3: a 19-digit `bytes = -9999999999999999999` reaches head unchanged and gets head's own answer
  (coreutils < 9.5: rc 1 'invalid number'; ≥ 9.5: rc 0, no output) — never rc 2".
- **R4 (ttail, C4).** ttail :946 `"rc=0 lastRc=143 N=1 rec=fol2"` → `"rc=0 lastRc=14"[13]" N=1
  rec=fol2"`; :965 `"rc=0 first=fol2 lastRc=143"` → `"rc=0 first=fol2 lastRc=14"[13]`; titles say
  "lastRc 141 or 143". Comment above them: "Linux `tail -f` notices the closed pipe and dies of
  SIGPIPE (141) before the TERM lands; cygwin's cannot (143)". Docs: `ttail/README.md:200`, `:210`,
  `:355` and `ttail/ttail.sh:97` (comment only): "143" → "143 (141 on Linux, where `tail -f`
  notices the closed pipe itself)".
- **R5 (first-race, C4).** tsed :476 `"$lr" == "2"` → `"$lr" =~ ^(2|141|143)$`; tawk :603 the same
  (preventive). Comment: "the consumer-stop TERM can hit sed/gawk between its last write and its
  exit; lastRc 2 itself is pinned by the S7/A7 count/toArray cases".
- **R6 (tawk backslash, C5).** tawk :1045: when `BS_SEP=0` the clause `-f "$FX/ipbs.txt.b/k"`
  becomes `! -e "$FX/ipbs.txt.b/k"`. tawk :1066: when `BS_SEP=0` assert instead `rc -eq 0 && lr ==
  0 && -z "$err" && odf ipbn.txt == UP_OD && -f "$FX/ipbn.txt.b${BS}k" && odf of it == F3_OD && !
  -e "$FX/ipbn.txt.bk"`, title suffix " (MSYS2/Cygwin; elsewhere `\` is a filename character and
  the backup `FILE.b\k` is written)". If the backup file is not there on a VM → BLOCKED with `ls`.

Acceptance: each row's repro passes on its VM (`vmlab.sh run VM -- 'cd ~/kbool && bash
kcl/<unit>/tests/tests.sh -n N'`, literal output; kb-ubuntu, kb-debian, kb-fedora; tawk/tsed/
tgrep/ttail on all three, thead on debian + fedora + ubuntu); Windows: `bash $G kcl/tawk kcl/tsed
kcl/tgrep kcl/thead kcl/ttail` on both runtimes PASS, totals unchanged; VMs: `vmlab.sh gate VM --
--rerun-failed 1 kcl/tawk kcl/tsed kcl/tgrep kcl/thead kcl/ttail` on kb-ubuntu, kb-debian,
kb-fedora PASS. Timebox 2.5 h.

### L2.6-2 — tregex, tfile, tpipe (C5-tfile, C6, C7) — 12 rows

Rows: kcl/tregex 002_IsMatch ×4, kcl/tfile 042_G6_IO ×4, kcl/tpipe 002_Stop STRAY ×4.

Files (5): `kcl/tregex/tregex.sh`, `kcl/tregex/README.md`, `kcl/tfile/tests/042_G6_IO.sh`,
`kcl/tpipe/tests/002_Stop.sh`, `kcl/tpipe/README.md`.

- **R7 (tregex S2, C6).** In `TRegEx._match1` (`tregex.sh:192`), directly after `__tre_rc=0`,
  insert:
  ```bash
      # S2 on every engine: glibc accepts '' (match-all), newlib/cygwin refuses it
      if [[ -z $__re ]]; then
          __tre_rc=2; __tre_g=(); __tre_m=''
          if (( __had )); then shopt -s nocasematch; else shopt -u nocasematch; fi
          return 0
      fi
  ```
  `tregex/README.md`: in the engine-delta/limitations text add "The engine is the C library's ERE
  (`regcomp`): glibc accepts some patterns newlib/cygwin rejects (`a|`, `()`), so their rc can
  differ by platform; the empty pattern is rc 2 everywhere (S2)." No test change.
- **R8 (tfile G6-26, C5).** `042_G6_IO.sh:202-223`: wrap the tcase in
  `if [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; then <unchanged> else kt_test_start "<same
  title>"; kt_test_pass "N/A off MSYS2/Cygwin: '\\' is a filename character here"; fi` (case count
  unchanged).
- **R9 (tpipe orphan, C7).** `002_Stop.sh:98` → `sigpipe_producer() { trap '' PIPE; printf 'a\n';
  exec sleep 8; }` and the comment above: "…`exec` so the TERM reaches the sleeper itself: a
  function producer's children are not signalled by TPipe.stop (README limitation)". README (per
  D5 recommended): add to the stop/limitations text: "`stop` TERMs the producer process only. A
  function or compound producer runs in a subshell; its own children (a `sleep`, a pipeline) are
  re-parented and live until they exit — end such producers with `exec`, or trap TERM and kill
  them."

Acceptance: repros: tregex/tfile on the three VMs (`… tests.sh -n 2` / `-n 42`); tpipe: on each
VM `bash kcl/tpipe/tests/tests.sh -n 2; sleep 1; ps -o pid=,ppid=,args= -C sleep | grep 'sleep 8'
|| echo none` → `none`; Windows: `bash $G kcl/tregex kcl/tfile kcl/tpipe` both runtimes PASS,
totals unchanged; VMs: `vmlab.sh gate VM -- --rerun-failed 1 kcl/tregex kcl/tfile kcl/tpipe` PASS
with 0 STRAY on the three VMs. Timebox 1.5 h.

### L2.6-3 — kkore 011 (C8) — 4 rows

Rows: kkore 011_ConfigProject ×4. File (1): `kkore/tests/011_ConfigProject.sh` (+
`kkore/tests/unit_fixture.sh` for the helper).

- **R10.** Add to `unit_fixture.sh` after `uf_win`:
  `uf_onwin() { [[ $OSTYPE == msys* || $OSTYPE == cygwin* ]]; }` and
  `uf_na() { kt_test_start "$1"; kt_test_pass "N/A off MSYS2/Cygwin: needs a drive-letter path"; }`.
  In 011, every block that calls `uf_win` (the 10 cases whose `uf_check` is at 73, 81, 86, 121, 126, 139, 144,
  210, 214, 500 — the `uf_win … uf_run … [[ ]] … uf_check "TITLE"` lines of each case) is wrapped
  as `if uf_onwin; then <unchanged block>; else uf_na "TITLE"; fi`, TITLE copied verbatim. A
  block whose setup (`cfg_clean`, `uf_cfg`, `mkdir`, `rm -f`) is needed by a later NON-wrapped
  case keeps that setup outside the `if`. Case count stays 75.

Acceptance: repro `bash kkore/tests/tests.sh -n 11` on the three VMs → 75/75 (10 as N/A);
Windows: `bash $G kkore` both runtimes PASS, totals unchanged (no N/A on Windows); VMs:
`vmlab.sh gate VM -- --rerun-failed 1 kkore`. Executor: S (test-only) unless SV applies DL9 to the
kkore repo strictly (D8). Timebox 45 min.

## 3. thttpserver: the network backend (L2.7-N, O)

### 3.1 what each flavour can do (probed on the VMs)

Per flavour: bind event, request received, connection event, behaviour on stdin EOF, accept TTL,
second listener on the same port while the first connection is open (the two-slot model, §4.1
(f) of PORTING). Literal markers from the probe output.

| flavour (VM) | argv that works | bound | connected | stdin EOF | accept TTL | 2nd slot |
|---|---|---|---|---|---|---|
| GNU netcat 0.7.1 (Windows) | `-l -c -vv -n -w TTL -s A -p P` | `Listening on` | `Connection from A:P` | `-c`: close + exit | `-w` | yes |
| OpenBSD nc, Debian patch 1.226 (Ubuntu) | `-l -N -v -n -s A -p P` | `Listening on A P` | `Connection received on A P` | `-N`: FIN, **lingers until the client closes**; `-q 0`: exit | **none** (`-w 2`: alive after 3.5 s) | yes |
| OpenBSD nc 1.229 (Debian) | same | same | same | same | **none** | **no** — B binds, the 2nd client queues on A's still-open listen socket (`B_out=[]`) |
| OpenBSD nc 1.237 upstream (Fedora `netcat`) | positional only (`cannot use -s and -l`), **no `-q`** | `Listening on A P` | `Connection received on A P` | `-N` lingers | **none** | **no** |
| ncat 7.92-7.95 (all) | `-l -v -n A P` | `Ncat: Listening on A:P` | `Ncat: Connection from A:P.` (Fedora: an extra `from A.` line) | half-close, lingers; `--send-only` drops the request | **none** (`-w`, `-i` no effect) | yes |
| nc.traditional 1.10 (Ubuntu, Debian) | `-l -v -n -q 0 -w TTL -s A -p P` | `listening on [A] P ...` | `connect to [A] from (UNKNOWN) [A] P` | `-q 0`: exit | `-w`: `no connection : Connection timed out` | yes — but `-c`/`-e` run shell commands (the H26 hazard) |
| busybox nc (Ubuntu, Debian builds) | — | no `-v`, no `-s` (`invalid option -- 'v'`) | — | — | — | — |
| socat 1.8.0.0 / 1.8.0.3 / 1.8.1.1 (all three; preinstalled in the lab snapshots) | `-d -d TCP-LISTEN:P,bind=A,reuseaddr,accept-timeout=TTL STDIO` | `N listening on AF=2 A:P` | `N accepting connection from AF=2 A:P on AF=2 A:P` | shutdown(WR), exits within `-t` (0.5 s default; Fedora: still alive at 0.5 s with the client open) | `W accept: Connection timed out` | yes |

**Decision against an OpenBSD-nc backend** (PORTING §4.3 preferred it "if the probe passes"): it
fails the probe — no accept TTL anywhere (an orphaned pre-spawned listener lives until a client
arrives; inferred, not probed: it keeps the port, or shares it with a new server's listener), the dialect differs per
vendor (`-s` with `-l`, `-q`), and on 1.229/1.237 the second slot never receives a connection.
socat passes every check with one dialect on all three distros (and is packaged on FreeBSD,
Alpine, Homebrew; FreeBSD not probed here — L3). ncat, nc.traditional, busybox nc: refused.

### 3.2 the design

**Detection (once per process, cached in `__THS_BACKEND` / `__THS_BACKEND_BIN` /
`__THS_BACKEND_WHY`, keyed by `$PATH|$KCL_NC|$KCL_SOCAT`), `ths._backend`:**

1. `Transport` set by the caller → untouched (no detection).
2. An explicit netcat (`NcBinary`, else `KCL_NC`) → it must identify as GNU netcat: one fork
   `"$nc" --version 2>&1` whose output contains `GNU Netcat` (0.7.1 prints `netcat (The GNU
   Netcat) 0.7.1`). Otherwise refuse (§ below) — an explicit binary is never replaced silently.
3. An explicit socat (`KCL_SOCAT`, or `SocatBinary` on a `TSocatTransport`) → must pass the socat
   probe (4).
4. Auto: `nc` on PATH identifying as GNU → `gnu`; else `socat` on PATH whose `socat -hhh 2>&1`
   lists `accept-timeout` → `socat`; else `none`.
5. The flavour of a refused nc for the message, from the same probe output plus one `-h`:
   `OpenBSD netcat`, `Ncat`, `BusyBox`, `[v1.10]` (traditional), else `unknown`.

**Never start an unidentified nc with GNU flags** — this closes the `-c`/`-e` hazard (ncat,
nc.traditional) as a side effect.

**Backend interface inside thttpserver:** the mechanism (two slots, FIFO + `cat` relay, drain,
`_spawn`, `_closeSlot`, `Accept`, `CloseConnection`, `Shutdown`) is backend-neutral and stays in
`TNetcatTransport`. A backend differs only in `BuildArgv` and `_state` (both already virtual,
`thttpserver.sh:359`, PLAN.md:698):

```
class TSocatTransport : TNetcatTransport
    public
        var SocatBinary          # '' -> $KCL_SOCAT -> socat on PATH
        override func BuildArgv  # SOCAT -d -d -t 0.5 TCP4-LISTEN:PORT,bind=ADDR,reuseaddr,accept-timeout=TTL STDIO
                                 # (TCP6-LISTEN:PORT,bind=[ADDR] for an address with ':')
    private
        override func _state     # 'N listening on '        -> listening
                                 # 'N accepting connection from AF=* A:P on ' -> connected, REPLY=A:P
                                 # 'W accept: Connection timed out'           -> ttl
                                 # a line whose severity field is E or F       -> failed:<text after it>
                                 # every other N/I/W line                      -> ignored
end
```

The server (`thttpserver.sh:1020`, `TNetcatTransport.new "${__inst__}_tr"`) becomes: `ths._backend
|| { LastError=$__THS_BACKEND_WHY; BeginServe rc 2; }`, then `gnu` → `TNetcatTransport.new`,
`socat` → `TSocatTransport.new`. `TNetcatTransport.BuildArgv` gains the identity check (rule 2;
rc 2 + LastError for a non-GNU nc). The `-t` value (0.5 s default; it bounds the drain of a client
that keeps the connection open) is measured in L2.7 against `CloseTimeout`; `StdinRelay` stays 1.

**No usable backend:** `BeginServe`/`Accept` rc 2 with LastError, e.g. `no usable network
backend: nc at /usr/bin/nc is OpenBSD netcat (refused: no accept timeout, per-vendor dialect);
no socat on PATH — install socat (apt/dnf/apk/pkg install socat) or GNU netcat 0.7.1`. Tests:
`_ths_socket.sh` resolves through the unit (`ths._backend`, with the existing
`/c/bin/msys64/usr/bin/nc.exe` fallback exported as `KCL_NC` on Windows), `ths_have_nc` →
`ths_have_backend`, and `ths_skip` passes each socket case as `SKIP: <__THS_BACKEND_WHY>` (case
count kept, as today).

**Windows:** MSYS2 `nc.exe` identifies as GNU 0.7.1 → `gnu` → today's argv, today's `_state`,
byte-identical behaviour. Cost: one extra fork per process for the identity (cached).

**Test changes (part of L2.7-N):** the cygwin `/proc/PID/ppid` walks (§1 C2 list) move onto
`ktests/ktest_proc.sh` (`kt_proc_snapshot`, `kt_proc_ppid`; sourced by `_ths_socket.sh`); the
three direct `$THS_NC -l …` starts (004:683, 005:230, 006:780) use a helper `ths_listen_argv PORT
TTL` that asks a throw-away transport's `BuildArgv`; `ths_listening` / `ths_listening_idle` use the
backend's bound/connected markers; 008_Contract's BuildArgv text assertions and the
`KCL_NC=…nc.exe` grep are updated; new cases: detection with fake `nc` scripts printing the
OpenBSD / Ncat / BusyBox / traditional banners → refused with the flavour named and nothing
started; a fake GNU banner → `gnu`; socat backend contract (argv, `_state` on recorded stderr
lines); no backend → every socket case SKIPs with the reason.

**Size:** `thttpserver.sh` +200-250 lines (detection ~60, `TSocatTransport` ~80, server factory
and identity check ~30, header docs); README/PLAN/TEST_COVERAGE_NOTES ~80 lines; tests ~250 lines
over `_ths_socket.sh`, 004, 005, 006, 008, 009 (007 only through the helpers). ≈ 10 files, ~550
lines; 1-1.5 days O work. Provisioning: socat is already in the three Linux snapshots (probed);
FreeBSD/Alpine `clean-gnu` need it at L3.

## 4. kcl/math under mawk (L2.7-M, O)

What mawk lacks (C1): a deep enough parser stack for an 81-link `else if` chain; line-wise input
on a pipe without `-W interactive`; IEEE NaN comparisons (`nan == 0` is true). Plus one open
failure (010 randG through 400 `$( )` subshells). "no awk on PATH" means only "`math.feStart`
failed"; the unit cannot tell a missing awk from an awk that cannot run the program — today both
are silent rc 1.

| option | change | effect | OG1 link |
|---|---|---|---|
| A. engine portable | (1) flatten the dispatch: every `if (op==X) S` / `else if (op==X) S` line → `if (op==X) { S; fflush(); next }`, the final `else printf "ERR\n"` → `printf "ERR\n"` (one sed rule, verified: 81 links, 0 `else if` left, gawk 181/181); (2) `!_isnan()` guards in `_pn` and `_dv`, then an audit of every other compare that can see a NaN (`_power` `e==0`, `iszero`, `samev`, `nper`); (3) mawk gets `-W interactive`: detect once per engine start (start with it; if the `pi` probe fails, restart without it — no identity fork), or `awk -W version` once; (4) find 010; (5) a mawk-specific start failure is reported (debug line + `math.feStart` rc 1 with a reason in a published variable) | works on Ubuntu/Debian out of the box; BWK/busybox awk still unknown (L3) | **independent of OG1** |
| B. prefer gawk | `_fe_start` uses `gawk` when `command -v gawk`, else `awk` (as today); tests that force paths through an `awk` function or PATH (001 "no awk", 015 M10, 018 SHIM) must hide/shadow `gawk` too | lab VMs green at once (gawk is provisioned; 181/181 probed); a user with only mawk still gets silent rc 1 | independent of OG1 only together with A (otherwise it is a GNU requirement in a non-wrapper unit) |
| C. require gawk | B + refuse any other awk with a clear error | simple, honest; costs the first impression on stock Ubuntu/Debian (gawk not installed by default) | **depends on OG1** (it is a GNU-tool requirement) |

**Recommendation: A + B** — B makes the lab green cheaply and uses the awk the engine was
developed against; A keeps stock Ubuntu/Debian working and is needed anyway for the BWK/busybox
question at L3. A alone is enough to close the 54 rows (verified except 010). Neither needs OG1.
Size: math.sh ~100 changed lines (81 of them the mechanical flattening) + ~30 new; tests 001,
010, 015, 018 adjustments ~40 lines; README (engine requirements, mawk note) ~15 lines. 5-6 files,
0.5-1 day O work (010 investigation open-ended; timebox it and report).

## 5. Decisions for the supervisor

1. **D1 — CR and other tool-native behaviour in the wrapper family.** Recommended: the wrappers
   stay transparent (what the bare tool does on that platform), tests take the expectation from a
   probe or oracle (L2.6-1 R1/R2), docs say "measured on Windows". Alternative: strip the CR in
   text mode on non-Windows so one contract holds everywhere — a unit change in TUtil + 3
   wrappers, breaks the "== bare tool" oracle rule, and still leaves `inPlace`/`nullData`
   semantics per platform. L2.6-1 is written for the recommendation.
2. **D2 — thttpserver second backend = socat, not OpenBSD nc** (§3.1 evidence). Consequence:
   Linux/BSD users need `socat` (or GNU netcat 0.7.1); ncat, OpenBSD nc, nc.traditional and
   busybox nc are refused with a named reason. Alternative (OpenBSD backend with a server-side TTL
   and per-vendor argv) is larger and still fails the two-slot check on Debian 13 / Fedora 44.
3. **D3 — kcl/math: A + B** (§4). Alternatives B alone (lab green, stock mawk users silent) or C
   (needs OG1 first). Also: should the engine's start failure stop being silent (a reason
   variable / debug line)? Recommended yes, inside A(5).
4. **D4 — math 010 randG under mawk**: timebox the investigation in L2.7-M; if not found, SKIP
   that one case under mawk with a reason (the test file then still checks everything else).
5. **D5 — TPipe.stop and a producer's children.** Recommended: document the limitation (L2.6-2
   R9). Alternative: kill the producer's tree (a `pkill -P`-like walk through the process table,
   or start the producer in its own process group under `set -m`) — portable only with care,
   a kcl/tpipe design task.
6. **D6 — tregex S2 enforced in code** (L2.6-2 R7) — implements the documented decision; the
   other glibc/newlib ERE deltas (`a|`, `()`) become a README note, not code. Alternative: leave
   the engine's answer per platform and change the test (S2 then documented as engine-dependent).
7. **D7 — Windows-only test cases off Windows become visible N/A passes** (kkore 011 ×10, tfile
   042 ×1), keeping case counts equal. ktests has no SKIP verdict; if SV prefers a real SKIP
   count, that is a ktests feature (O) first.
8. **D8 — executor for kkore/tests (L2.6-3):** test-only and mechanical → S; under a strict
   reading of DL9 (kkore is a core repo) → O.
9. **D9 — ttail 005:1035** parses cygwin `ps` columns (`$2 == $$`); on Linux `$2` is the TTY, so
   "no follower survived" checks nothing. Fix now (move onto `kt_proc_snapshot`, S, add to
   L2.6-1) or record for L2.8. Recommended: add to L2.6-1 as R4b.
10. **D10 — math 018 Fedora flake:** no action now; if it recurs in L2.8, an O investigation with
    the cell's watchdog/stray records.
11. **D11 — kkore honours `USERPROFILE` / `ProgramData` / `C:\` spellings on Linux too**
    (harmless, never set there). Keep as is (no row depends on it).

## 6. Expected effect

Predicted failing test files per gate after L2.6-1..3 and L2.7-N/-M/-K (today → after):

| VM run | today | after | what may remain |
|---|---|---|---|
| kb-ubuntu | 31 | 0 | thttpserver 004 `handled=7` flake (L2.1-o5, exists on Windows too) |
| kb-debian | 32 | 0 | the same |
| kb-fedora | 15 | 0 | the same; math 018 flake (C1f) |
| kb-debian de_DE | 33 | 0 | the same; 045 only if L2.7-K is not done |

Partial states: without L2.7-M the mawk VMs keep 18 files (17 math + kcl 202; 0 if only option
B lands); without L2.7-N every VM keeps the 5 thttpserver files failing — with only the
detect-and-refuse part of L2.7-N they become visible SKIPs (no FAIL); without L2.7-K the de_DE row
recurs at random. The thttpserver prediction assumes the socat backend passes the existing socket
suites unchanged in substance (not yet run — the biggest uncertainty here). The S batches alone
(no O work) take the counts to Ubuntu 23 (18 math+202, 5 thttpserver), Debian 23, Fedora 5 + flake,
Debian de_DE 24.

## 7. Decisions taken (supervisor + owner, 2026-10-21) — they override §2–§5 where they differ

| id | decision | effect on the batches |
|---|---|---|
| D1 | **owner: strip the CR everywhere.** In text mode (`binary = 0`) TGrep/TSed/TAwk deliver records without a trailing CR on every platform (Windows already does; Linux/BSD/macOS keep it in the bare tools). `binary = 1` keeps the bytes, identically everywhere | **R1 is dropped from L2.6-1.** New O task **L2.7-C**: the TUtil/TAwk/TSed/TGrep change + the C3 tests rewritten to the uniform expectation (no `TM_KEEPS_CR` branch); docs drop "measured on this platform" for the CR rows |
| D2 | **owner: socat** as the second thttpserver backend (§3) | L2.7-N as designed |
| D3 | A + B (portable engine + prefer gawk), and the engine-start failure gets a reason (not silent) | L2.7-M |
| D4 | timebox randG under mawk inside L2.7-M; if not found, SKIP that one case under mawk with a reason | L2.7-M |
| D5 | **owner: fix now.** `TPipe.stop` stops the producer's whole tree (portable: own process group under `set -m`, or a walk of the process table), not only the subshell | **R9 is dropped from L2.6-2.** New O task **L2.7-P**; `002_Stop.sh` stays as is and is the red-first proof (its orphan must disappear) |
| D6 | enforce S2 in code (R7) | L2.6-2 |
| D7 | Windows-only cases elsewhere = visible N/A passes (no new SKIP verdict) | L2.6-2, L2.6-3 |
| D8 | L2.6-3 (kkore tests, test-only, mechanical) → S | L2.6-3 |
| D9 | fix ttail 005:1035 now → **R4b** in L2.6-1: replace the cygwin `ps` column parse with ktests' process table (`kt_proc_*` from `ktests/ktest_proc.sh`, already sourced by the runner) so "no follower survived" checks real pids on every platform; if the helper API does not fit → BLOCKED | L2.6-1 |
| D10 | watch math 018 (Fedora) at L2.8 | — |
| D11 | keep kkore's USERPROFILE/ProgramData handling | — |

Execution order (one gate slot): L2.6-3 → L2.6-2 → L2.6-1 (S) → L2.7-K → L2.7-C → L2.7-P → L2.7-M → L2.7-N (O; an Opus critic after L2.7-K, L2.7-C and L2.7-N).

## 8. Re-verification of the netcat decision (owner's doubt, 2026-10-22)

The owner asked whether "nc under Windows can do something nc under Linux cannot" really
justifies a socat backend. Re-checked against primary sources and a repeated probe:

- The Windows `nc` is **GNU Netcat 0.7.1** (`nc.exe --version`), a portable program also packaged
  as Homebrew `netcat` 0.7.1, FreeBSD `net/gnetcat`, Arch `gnu-netcat`, MacPorts `gnetcat`,
  Guix — just not by Debian/Ubuntu/Fedora/Alpine. So the gap is "GNU netcat vs the netcats the
  mainstream Linux distros ship", not Windows vs Linux.
- OpenBSD nc, from the man page and `usr.bin/nc/netcat.c`: `-w` has no effect on `-l` (accept
  has no timeout); `local_listen()` sets `SO_REUSEPORT`; the listening socket stays open during
  `readwrite()` and is closed only at exit (without `-k`).
- Consequence, measured on kb-debian (OpenBSD nc 1.229, 20 runs): while A serves c1 there is
  1 LISTEN socket; after B starts there are 2; c2 is served by B in **10/20** runs and lands in
  A's backlog (never served) in **10/20** — the Linux `SO_REUSEPORT` load-balancing coin flip.
  §3.1's "works on 1.226, fails on 1.229/1.237" was luck of single samples, not a version
  difference: OpenBSD nc is unfit for the two-slot model on every version, and that cannot be
  fixed from bash. socat 1.8.0.3 and ncat 7.95 (10 runs each): 0 LISTEN sockets during A's
  connection, B binds, c2 → B 10/10 (the bind succeeding without SO_REUSEPORT is the proof that
  A closed its listener).
- ncat remains the only other candidate (no accept timeout → a bash-side `timeout` wrapper; it
  half-closes on stdin EOF and lingers until the client closes). socat matches GNU nc's one-shot
  STDIO semantics natively. **D2 stands**: GNU netcat first (documented as available on every
  platform, not "Windows"), socat second. An architectural alternative (one persistent
  `fork` listener + a relay to the server process, usable with any nc that has `-e`) is a
  redesign, not for the launch.
