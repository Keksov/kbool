# kbool portability analysis (L0.5)

Status: analysis, 2026-10-20, tree at kbool `2817b2b`. Nothing here has been
run off Windows; every claim is from reading the code at the cited line plus
known platform behaviour. Inputs: [`launch/inventory.tsv`](launch/inventory.tsv)
(scanner P01–P32), [`launch/tools.tsv`](launch/tools.tsv),
[`launch/bashfeatures.tsv`](launch/bashfeatures.tsv). It drives L1 (package
lists, §7), L2.1 (harness, §3), L2.5 (netcat, §4), L3.2 (OG1, §5) and L4 (§6).

Legend.
**Confidence**: *certain* (the code path cannot work there), *likely* (known
platform behaviour, not observed), *unknown* (only a run shows it).
**Fix class**: `portable` (rewrite that works everywhere), `detect`
(feature-detect at run time), `GNU` (require the GNU tool, by name),
`win-ok` (Windows-only branch, fine as is), `test` (test-only assumption),
`env` (environment/provisioning requirement), `design` (needs an Opus design).
Hazard ids `H*` are stable for triage rows.

## 1. Targets

| target | bash | userland | differs from today (Git-bash/MSYS2) |
|---|---|---|---|
| Ubuntu 24.04 | 5.2.21 `/bin/bash` | GNU; **awk = mawk**; `nc` = OpenBSD nc (netcat-openbsd) | real Linux `/proc` (no `ppid`/`pgid`/`sid`/`winpid` files); no `cygpath`; locales must be generated; case-sensitive FS; `gawk` absent |
| Debian 13 | 5.2.37 | GNU; awk = mawk; no `nc` in a minimal install | as Ubuntu; `curl`, `sudo`, locales not in minimal |
| Fedora (current) | 5.2.x | GNU; awk = gawk; `nc` = nmap **ncat** (nmap-ncat) | as Ubuntu; perl split into modules (`perl-POSIX`) |
| Alpine (current) | 5.2.x from `apk add bash` | **busybox** for everything; musl (no numeric locales); no tzdata | `env`, `sed`, `stat`, `find`, `xargs`, `timeout`, `nc` are busybox applets (config-dependent options); with GNU packages they shadow busybox in `/usr/bin` under the same names |
| FreeBSD 15 | `/usr/local/bin/bash` (pkg) | BSD; awk = one-true-awk; base `nc` (OpenBSD-derived); GNU tools g-prefixed (`gsed`, `gfind`, `ghead`, `gstat`, …) | **no `/bin/bash`**; **no /proc** (procfs not mounted, different format); bash pkg needs **fdescfs on /dev/fd** or `<( )` fails; no `setsid(1)`, no perl in base; `/home` → `/usr/home` symlink |
| macOS (CI only, DL5) | `/bin/bash` **3.2**; brew bash 5.3 at `/opt/homebrew/bin` | BSD (Apple); LibreSSL `openssl`; no `timeout`; brew GNU tools g-prefixed | no /proc; `/dev/fd/N` open = `dup()`; `$TMPDIR` under `/var` → `/private/var`; APFS case-insensitive |
| Windows Git-bash 5.2.37 / MSYS2 5.3.9 | current | GNU (MSYS); MSYS2 has GNU netcat 0.7.1 | the reference: all of today's gates are green here |

## 2. Hazards, ranked

Order: core layers (kkore, kklass runtime, ktests harness incl.
`ktest_runner.sh` / `ktest_fixtures.sh` and `ktests/tools/`), then kcl units,
then the wrapper family, then tests. All 188 non-test, non-shebang,
non-docs inventory rows were triaged; the sites below were read in context.

### 2.1 ktests harness (blocks every gate off Windows)

| id | sites | what breaks, where | conf. | fix |
|---|---|---|---|---|
| H1 | process table from **cygwin-only** files `/proc/PID/{ppid,pgid,sid,winpid}`: ktest_runner.sh:711-719 (group_scan), 782-790 (group_members); strays.sh:214-234 (`_kt_strays_table`), 301 (self chain); gate.sh:843, 986, 1840 (`winpid`), 2473 (`sid`, `winpid`) | Linux: those files do not exist (Linux has `stat`/`status`) → table empty. FreeBSD/macOS: no /proc at all. Effect is **silent blindness**: `strays.sh list` always prints `strays: none`, `kt_strays_group_settle` (strays.sh:593) returns "empty" at once, the gate's final stray check and watchdog session stop (gate.sh:2615) find nothing, descendants outside the run group (GNU `timeout`'s own group, `set -m` subgroups) are never tracked or killed, `kt_runner_group_suspend`'s CONT-by-pid loop (ktest_runner.sh:870-875) is a no-op, the parent watch is off ("no cygwin parent to watch", gate.sh:1905) | certain | design (§3) |
| H2 | `/proc/PID/stat` field 22 read as **ms**: strays.sh:249-252 (`_KTS_ST = BOOT_MS + a[19]`); boot from `/proc/uptime` (strays.sh:218) | Linux: starttime is in clock ticks (USER_HZ, normally 100/s) → start times ×10 off → `--since` windows and AGE wrong once H1 is fixed | certain | detect (Linux backend: ticks + `/proc/stat` `btime`) |
| H3 | the orphan rule (strays.sh header, lines 59-74): detached = root's parent gone or ppid 1, and `sid != pid` | cygwin-specific session semantics. Linux: orphans are re-parented to pid 1 **or a subreaper** (`systemd --user` on desktops, the container init in CI); FreeBSD likewise (reaper via procctl) | certain | design (§3) |
| H4 | gate.sh:1104 `env --default-signal=INT,QUIT -i …` starts **every** segment and cell | GNU coreutils ≥ 8.31 only. busybox `env` (Alpine clean), FreeBSD and macOS `env` reject the option → no segment starts | certain | design (§3: `set -m` start or detect GNU `env`/`genv`) |
| H5 | gate.sh:2520 `sed -i "s|…|…|; s|…|…|" "$f"` | BSD sed takes the script as the backup suffix and the file as the script → the STRAY verdict rewrite fails (FreeBSD, macOS) | certain | portable (`_kt_gate_readkv` + `_kt_gate_put`) |
| H6 | ktest_runner.sh:1097 `… \| sed -e 's/\r$//'` | BSD sed has no `\r` escape: it strips a trailing literal **`r`** from every captured error line (FreeBSD, macOS); busybox: unknown | certain (BSD) | portable (`${line%$'\r'}` in the loop) |
| H7 | ktest_runner.sh:625, 627, 635, 638, 640, 663, 671: `${EPOCHREALTIME/./}` | bash formats `EPOCHREALTIME` with the **locale's decimal point** (kcl/tstopwatch/tests/006 documents `1788676658,546051` under de_DE on this box). The gate keeps `LANG`/`LC_*` (gate.sh:279, 1026). Under a comma locale (`ru_RU`, `de_DE`) the value keeps its comma and `$(( … ))` treats it as the **comma operator**: `__kt_end` becomes ~3.5e6, `__kt_t` the µs part (< 1e6) → the KILL deadline is never reached → `kt_runner_group_end` waits for ever on a TERM-ignoring member. Silent; never seen on Windows because the lab locale is English | likely | portable (`${EPOCHREALTIME//[!0-9]/}`, as gate/strays already do) |
| H8 | bare `bash` from PATH: ktest_runner.sh:990 (per-file shell), 1228 (xargs workers), tests/tests.sh:119 (master sweep) | under the gate PATH is prefixed with the target bash's directory (gate.sh:1104) → fine; a direct `ktests.sh` / `tests/tests.sh` on macOS runs every test under `/bin/bash` 3.2, on any box with two bashes under the wrong one | likely | portable (`"$BASH"`) |
| H9 | gate.sh:1162-1167 session isolation needs `setsid` (util-linux) or `perl` | FreeBSD base and macOS have no `setsid(1)`; FreeBSD/Alpine `clean` have no perl → `[WARN] no setsid/perl` and the segment shares the caller's session (its stray checks see the caller's processes). Linux: fine (util-linux `setsid`; busybox has an applet) | certain (FreeBSD) | design (§3) |
| H10 | busybox options: `xargs -P N -I {}` (ktest_runner.sh:1228), `find -mmin` (ktest_runner.sh:536, ktest_fixtures.sh:168, gate.sh:899), `grep -r --include` (gate.sh:552, `--changed` only) | all are config-dependent busybox features (`FEATURE_XARGS_SUPPORT_PARALLEL`/`_REPL_STR`, `FEATURE_FIND_MMIN`); without `-P` every threaded run fails | unknown | L3.1 run; then detect or `GNU` |
| H11 | `kill -0 -- -PGID`, `/dev/ptmx` naps (ktest_runner.sh:634, strays.sh:190), FIFO `exec {fd}<>` (ktest_runner.sh:809) | Linux/FreeBSD: supported. macOS `O_RDWR` on a FIFO: works on Darwin | likely OK | — |
| H12 | `/proc/mounts` root source as the runtime id (gate.sh:307, 792; ktest_runner.sh:558; ktest_fixtures.sh:132; timing_check.sh:182) | Linux: a device name — fine (one pid namespace). FreeBSD/macOS: "none" everywhere — consistent, fine | certain OK | — |

### 2.2 kkore, kklass runtime

| id | sites | what breaks, where | conf. | fix |
|---|---|---|---|---|
| H13 | kklass.sh:874-875, 828-829, 904-972: `kk._fn_text` (fork-free `declare -f` capture) appends through `FDDIR/R` (`/proc/PID/fd` else `/dev/fd`) to a deleted scratch file opened read-only | Linux: reopen via `/proc/PID/fd` = a fresh open → works. FreeBSD without fdescfs: `/dev/fd` has only 0-2 → `-f /dev/fd/$p` false → setup refused → `$( )` fallback. FreeBSD with fdescfs and macOS: open of `/dev/fd/N` = `dup(N)`, an append on a read-only fd fails → three out-of-step captures → off → `$( )`. Correct by design (markers), but class builds lose the round-5 fork-free speed-up there | likely (perf only) | design + measure at L3/L5 |
| H14 | process substitution `<( )`: none in kkore or the kklass runtime; kklass_compiler.sh:33, 136, 212, 307, 316; 9 kcl unit files (math, tcustomapplication, tfind, tgrep, thead, thttpserver, tpipe, ttail, tutil); ktests 5 files (gate.sh 3, ktest_runner.sh 7 uses); 40 test files | FreeBSD: the bash package needs `fdesc /dev/fd fdescfs rw 0 0` (its pkg-message); without it every `<( )` fails | certain (FreeBSD w/o fdescfs) | env (L1: fstab in both snapshots; README requirement) |
| H15 | generated files start with `#!/bin/bash`: kklass_compiler.sh:260 (compiled cache), kklass_kkp.sh:336, 346 (.kkp output) | harmless when sourced or run as `bash file`; executed directly on FreeBSD → "not found", on macOS → bash 3.2 | likely | portable (`#!/usr/bin/env bash`, with L2.2) |
| H16 | kbool.sh:32 `${__KK_UNITS[@]@a}` is the first statement | bash 3.2/4.3: "bad substitution" before any guard → the L2.3 guard must be placed above line 32 and use 3.2 syntax only (`BASH_VERSINFO`, `return`) | certain | (L2.3 card) |
| — | kklass_autoload.sh:140-141 `stat -c %Y \|\| stat -f %m`; kklass_autoload.sh:225 `grep \| sed 's/…//'`; kkore/kerr.sh:98 POSIX awk; kkore/klib.sh:343 `realpath` with fallback | portable as written (macOS < 13 lacks `realpath`: the fallback prints the unresolved path) | certain OK | — |

kkore and the kklass runtime need **no external tool beyond POSIX** and no
`EPOCHREALTIME` (see §6). Their only platform-sensitive pieces are H13 (speed)
and H15/H16.

### 2.3 kcl units (non-wrapper)

| id | sites | what breaks, where | conf. | fix |
|---|---|---|---|---|
| H20 | tpath.sh:389, 391 (`stat -c FMT`, `%X/%Y/%W`), 466, 468 (`stat [-L] -c %a`) | BSD stat has no `-c` (`-f` with other letters: `%a`→atime is `%a`, mtime `%m`, birth `%B`, mode `%Lp`) → every TFile/TDirectory time getter and `GetAttributes` return rc 1 (FreeBSD, macOS). busybox: `-c` works, `%W` unsupported (non-numeric → rc 1, already handled) | certain (BSD) | detect (GNU/BSD format map, probed once) |
| H21 | tpath.sh:397, 399 `date [-u] -d "@E" "+%Y-%m-%d %H:%M:%S"` | BSD date uses `-r E`; busybox OK | certain (BSD) | portable: `printf -v __tp_r '%(%Y-%m-%d %H:%M:%S)T' "$E"` (UTC: under `TZ=UTC0`) — fork-free too |
| H22 | tpath.sh:425, 427 `date [-u] -d "STRING" +%s` (setters given a date string) | GNU free-form parsing; BSD needs `date -j -f FMT`; busybox accepts a few fixed formats | certain (BSD) | design (define the accepted formats; parse in bash or via dateutils) |
| H23 | tpath.sh:433-437 `/usr/bin/touch FLAG -d "@E"` (hard-coded path first) | `-d @epoch` is GNU-only; on FreeBSD `/usr/bin/touch` is BSD even when coreutils is installed → every time setter fails | certain (BSD) | portable: `TZ=UTC0` for both `printf '%(%Y%m%d%H%M.%S)T'` and `touch FLAG -t STAMP` (POSIX) |
| H24 | tpath.sh:686-697 `realpath -m`, then `readlink -m`, then `$PWD/$path` | BSD/busybox have neither `-m` → the raw join: `..`/`.` are not collapsed — a different answer, not an error | certain | portable (lexical normaliser in bash) |
| H25 | tfile.sh:169 `openssl enc … -pbkdf2` | needs OpenSSL ≥ 1.1.1; LibreSSL (macOS `/usr/bin/openssl`): unknown; absent on Alpine clean → rc 1 (fine) | unknown (macOS) | test (SKIP when absent) |
| H26 | thttpserver.sh:401 argv `nc -l -c -vv -n -w TTL -s ADDR -p PORT`; stderr parser thttpserver.sh:517-545 | GNU netcat 0.7.1 only. On every other flavour the listener fails, and on ncat / nc.traditional `-c` means **"run the next argument as a shell command"** (§4) | certain | design (§4) |
| H27 | kcl/math awk engine (math.sh:189-310 program; 760, 785 co-process) | the awk on PATH is mawk (Ubuntu/Debian), gawk (Fedora), busybox awk (Alpine), BWK awk (FreeBSD/macOS). The program is POSIX + `fflush()`, but `printf "%.17g"` of inf/nan (glibc prints `-nan` for `inf-inf`), `%d` of values ≥ 2^31 and `srand()` seeding differ per implementation | unknown | test across in L2/L3; normalise in bash if needed |
| H28 | thttpserver tests' `/dev/tcp` client (tests/_ths_socket.sh) | needs bash built with net redirections (Debian/Ubuntu/Alpine/FreeBSD/brew: yes) | likely OK | — |

Checked and fine: tfile.sh:255 and tpath.sh:43-58 are `win-ok` Windows branches
(`$OSTYPE`; Alpine's `linux-musl` and `freebsd15.0` fall into the POSIX branch);
math.sh:717 / kklass_compiler.sh:136 `find -maxdepth 1 -mmin` (GNU, BSD,
busybox-with-MMIN); tfile/tdirectory/tinifile `cp`/`mv`/`ln -s`/`mkdir`/`rmdir`
are POSIX forms; `mktemp` templates (tfile.sh:168, thttpserver.sh:587,
tpath.sh:795, kklass_compiler.sh:179) are portable; tpath `uuidgen` output is
lower-cased (macOS prints upper case).

### 2.4 wrapper family (tsed tawk tfind tgrep thead ttail tpipe tutil)

The tool name is a constructor argument (tsed.sh:270 `sed`, tawk.sh:437 `gawk`,
tfind.sh:192 `find`, tgrep.sh:157 `grep`, thead.sh:162 `head`, ttail.sh:187
`tail`), resolved by tutil.sh:299/433 (`command -v`). The GNU options are added
by `__x_v+=( … )` lines that carry no tool word, so the scanner missed them.

| id | sites | what breaks | conf. | fix |
|---|---|---|---|---|
| H40 | tsed.sh:403 `--sandbox` **by default** (owner Q1); 404-411 `-E -n -s -z -b -i…`; `--posix -u -l --debug` | `--sandbox` is GNU sed ≥ 4.3: every TSed call fails on BSD and busybox sed | certain | GNU (OG1) |
| H41 | tawk.sh:437 `gawk` by name; `--sandbox`, `-e` chunks | gawk is not installed by default on Ubuntu, Debian, Alpine, FreeBSD, macOS | certain | GNU (OG1) |
| H42 | tawk.sh:640 `-i /usr/share/awk/inplace.awk` | hard-coded data dir: FreeBSD `/usr/local/share/awk`, Homebrew `/opt/homebrew/share/awk` → inPlace fails even with gawk installed. (`-i inplace` would search AWKPATH, whose default starts with `.` — a cwd hijack; presumably why it is absolute) | certain | design |
| H43 | tgrep.sh:310-315 `--include/--exclude/--exclude-dir/-U/-z/-Z`; thead/ttail `-q -v -z`, negative counts; tfind `-print0 -maxdepth -mindepth -iname -newer` | on demand only (defaults are POSIX-ish), but macOS grep `-Z` = *decompress*; tfind's defaults are portable; all six test suites pin GNU messages and exit codes | certain (tests) | GNU (OG1) |

### 2.5 tests (summary by pattern)

Counts are test-class rows of inventory.tsv; "typical cause" is from sampling.

| pattern | hits | units | typical cause → fix |
|---|---|---|---|
| P01 shebang `/bin/bash` | 677 | all | runner runs `bash FILE`, so harmless under the gate; L2.2 |
| — shebang **pinned** by a test | 3 | kcl/tests/001_UnitFiles.sh:67, kklass/tests/141_UnitHeaders.sh:85, kkore/tests/013_SystemUnitHeaders.sh:46 | they assert line 1 == `#!/bin/bash` → **must change with L2.2** |
| — generated scripts with `#!/bin/bash`, executed directly | 53 lines | tcustomapplication 008/019/021, tpipe 001-005, tutil 002, thttpserver 004, kklass 137 | FreeBSD: not found; macOS: 3.2 → test (`#!/usr/bin/env bash`) |
| P03 sed GNU options | 88 | tsed | intended (wrapper reference) → SKIP per OG1 |
| P16 gawk extensions | 173 | tawk 171, dateutils 2 | intended → SKIP per OG1 |
| P04 `stat -c` | 58 | tfile 34, tdirectory 23, ktests 1 | GNU stat in assertions → test helper |
| P05 `date -d` | 28 | tdirectory 14, tfile 12, dateutils 2 | → `printf %()T` / helper |
| P24 `touch -d` | 17 | kklass 11, ktests 3, math 3 | GNU date strings → `touch -t` |
| P02 `sed -i` | 14 | tsed 7 (intended), kklass 5 (135/139/141), kkore 1 (013), ktests 1 (044) | BSD `-i` needs a suffix → `sed -i.bak … && rm` or bash |
| P11 `timeout` | 170 | 14 suites | macOS has none (`gtimeout`); 9 sites use `--foreground`/`--preserve-status` (not busybox) → helper `kt_timeout` |
| P13 `/proc` | 70 | ktests 49, thttpserver 16, kklass 3, math 2 | harness self-tests of cygwin process semantics (with H1); `_ths_socket.sh:224` child lookup via `/proc/*/ppid` (cygwin-only); kklass 145:311-349 `/proc/$BASHPID/fd` (Linux OK, BSD absent) |
| P14/P15 Windows | 76 / 167 | kkore 91, ktests 64, … | most are guarded (`$OSTYPE`/`cygpath` checks) or false positives (fixture dirs named `c/`); **unguarded**: kkore/tests/011_ConfigProject.sh:64-86, 209 (`uf_win` needs a `/<drive>/` path) → test (SKIP off MSYS/Cygwin) |
| P23 `$(wc …)` | 36 | kklass 8, tfile 7, … | BSD `wc` left-pads → fails only where compared as a string → per-site `$(( ))` |
| P29 fractional sleep | 93 | — | false positive (GNU, BSD, macOS, Alpine busybox accept fractions) |
| P26 interpreters | 27 | dateutils 024 (**perl**, FAILs if absent), tcustomapplication 018 (python3, has fallback), kklass 131 (node, SKIPs) | → SKIP when absent |
| other tools | — | thttpserver: **curl** (FAILs if absent); tfile 042: **openssl** (FAILs if absent, test line 226) | → SKIP when absent |
| locales / TZ | 10 de_DE, 2 ru_RU, en_US, 13 C.UTF-8; TZ=Asia/Tokyo 3 | dateutils, math, stopwatch, tinifile, tstringhelper, thttpserver | glibc needs generated locales; musl has no numeric locale (comma tests pass vacuously); Alpine needs tzdata |

Surprising single sites: ktests/ktest_runner self-tests 044, 045, 049, 052
read cygwin-only `/proc` files (rewrite with L2.1); kcl/ttail/tests/005_Run.sh:1035
parses cygwin `ps` columns (`$2 == $$`) — on Linux procps the check is vacuous
(always passes); 4 test files assume a non-root user (`chmod a-w` then expect a
write to fail: tdirectory 035, tpath 012, ktests 017, 022) — CI containers run
as root; FreeBSD `/home` → `/usr/home` and macOS `/var` → `/private/var` break
tests comparing `$HOME`/`$TMPDIR` strings with `pwd -P` output (count unknown
until run).

### 2.6 false positives checked (grouped)

* **P28 `/tmp`** (20 core/harness): all `${TMPDIR:-/tmp}` fallbacks or option
  text (gate.sh:2120-2128 are `$cd/tmp`).
* **P10 `mktemp`**, **P07 `find -maxdepth/-mmin`**, **P29 fractional sleep**:
  portable across GNU/BSD/busybox (busybox `-mmin` → H10).
* **P11 `timeout`** in core/harness: option names (`--timeout`), the word in
  messages, `TMOUT` (kklass_decl.sh:276); real uses only timing_check.sh:371
  and strays.sh:168 (a name match).
* **P12** strays.sh:260-284 and tools.tsv `ktests nc direct`: a local
  variable `nc` (nocasematch flag).
* **P32 CR** (26 core/harness): defensive `${x%$'\r'}` — portable; the one
  real hazard is H6.
* **P14** core: Windows branches (`win-ok`); every gate/timing_check `cygpath`
  is behind `command -v cygpath`.
* **P02/P03/P16 wrapper rows**: tsed.sh:152, 254, 342 and tawk.sh:158-766
  (except 437, 640) are messages, comments and keyword tables.
* **P04/P06 core**: kklass_autoload.sh:140-141 and klib.sh:343 already fall back.
* tools.tsv: `ls` in dateutils/tstringhelper is a variable named `ls`; the 4
  `sed` hits in tsed.sh are strings; bashfeatures F23 kklass_decl.sh:261, F28
  kklass_decl.sh:267, F19/F23/F28 in kklass/tests/147 are reserved-name lists.
* Case sensitivity: every literal `*.sh` name referenced in code was checked
  against the tracked files (1038): no case-only mismatch (14 candidates, all
  comments or generated fixture names).

### 2.7 hazards the lexical scan cannot see

H4 (`env --default-signal`), H1's real nature (P13 found the paths, not that
Linux lacks those files), H7 (decimal comma), H8 (bare `bash`), H13 (`/dev/fd`
reopen semantics), H14 (fdescfs), H15 and the 53 generated shebangs, H40-H42
(argv built in arrays), H27 (awk flavour), root in CI, path canonicalisation.
L2.8's re-scan diff will not show these; L2/L3 gates will.

## 3. The ktests harness on Linux and FreeBSD (input for L2.1)

### 3.1 what it relies on today

| mechanism | where | cygwin (today) | Linux | FreeBSD | macOS |
|---|---|---|---|---|---|
| process table (ppid, pgid, sid, cmdline) | strays.sh:214-234 | `/proc/PID/{ppid,pgid,sid,cmdline}` ~0.1 ms each | only `/proc/PID/stat` + `cmdline` (stat is µs, not 20 ms) | none (procfs optional; `/proc/PID/status` other format) | none |
| state + start time | strays.sh:239-253, ktest_runner.sh:764-773 | `stat` f3, f22 in ms; boot = now − `/proc/uptime` | f3, f22 in ticks; `btime` in `/proc/stat` | `ps -o state,etimes` | `ps -o state,etime` |
| group members / descendants | ktest_runner.sh:706-795 | `/proc/*/pgid` + `ppid` | `stat` f4 (ppid), f5 (pgrp) | `ps -o pid,ppid,pgid` | same |
| session of the segment | gate.sh:2472-2476 | `/proc/$$/sid` | `stat` f6 | `ps -o sid` (verify keyword) | no `sid` keyword (`sess` is a pointer) |
| parent watch | gate.sh:982-988, 1836-1841 | `/proc/PPID/winpid` (pid reuse + Windows-level kill) | off today; (pid, starttime) pair would do | off; (pid, `lstart`) via ps | same |
| session isolation | gate.sh:1162-1167, 1833 | `setsid` (msys) / perl | util-linux `setsid` (forks when it is a group leader; `-w` waits) | none in base; perl not in clean | perl present, no setsid |
| INT/QUIT reset for `&` children | gate.sh:1104 | GNU `env --default-signal` | GNU env OK; **busybox env no** | **no** | **no** |
| fork-free naps | ktest_runner.sh:634, strays.sh:190 | `read -t` on `/dev/ptmx` | OK | OK | OK |
| runtime id | `/proc/mounts` root (H12) | install folder | root device | "none" | "none" |
| paths | `cygpath` behind `command -v` (gate.sh:1798) | mixed `C:/…` | native; OUT default `/tmp` (gate.sh:439) | native | native |
| watchdog FIFO, `set -m` groups, `kill -- -PGID` | ktest_runner.sh:800-890, suitejob.sh | OK | OK | OK | OK |
| fork-failure signatures | ktest_env_signatures.sh:14 | cygwin texts | `fork: retry: Resource temporarily unavailable` matches; add `Cannot allocate memory` | similar | similar |

### 3.2 what must change

Linux: a second process-table backend (one `stat` read per pid gives state,
ppid, pgrp, session, starttime; `cmdline` for the marker rule; ticks →
ms via `btime` and USER_HZ, the latter read once with `getconf CLK_TCK` or
assumed 100 with a check); the orphan rule (H3) restated without "ppid 1";
the parent watch as (pid, starttime); H5-H8 fixed in passing; `setsid` used
without `set -m` as today (or `setsid -w` if a leader). FreeBSD: no /proc →
a `ps`-based backend (one fork per scan is cheap on a real kernel); no
`setsid` → isolation by process group instead of session; H4 must be solved
before any FreeBSD/Alpine-clean/macOS gate can start; `<( )` needs fdescfs
(H14, provisioning).

### 3.3 proposed approach (not code)

1. **One process-table API**, owned by strays.sh and used by the runner
   (today ktest_runner.sh duplicates the /proc parsing): `kt_proc_table`
   fills pid → ppid/pgid/sid/state/start_ms/cmd; backends chosen once at load:
   `cygwin` (today's code, byte-identical, so Windows behaviour is unchanged),
   `linux` (`/proc/PID/stat`), `ps` (FreeBSD, macOS, and any Linux without
   /proc: `ps -ax -o pid=,ppid=,pgid=,sid=,state=,etimes=,args=`; macOS
   without `sid`). The fork-free promise stays for cygwin and Linux.
2. **Never silently blind.** With no working backend `strays.sh list` prints
   `strays: UNKNOWN (no process table: <why>)` and exits non-zero, and the
   gate marks the segment's stray check `n/a` in its reports instead of
   "none". The hygiene listings in every brief depend on this line.
3. **Strays by session/group, not by ppid 1**: in strict mode (`--session`,
   used by the gate and the master) a stray is any process of the segment's
   session (Linux) or process-group set (FreeBSD/macOS, where no `setsid`)
   that started after SINCE and is not in the caller's live tree — no
   reliance on re-parenting, so subreapers and container inits do not
   matter. The unfiltered mode (human/agent `list --all`) stays list-only and
   treats "parent is 1 or a known subreaper" as detached.
4. **Segment start**: detect a GNU `env` (`env --default-signal` probe, else
   `genv`); without one start the segment under `set -m` (bash does not
   ignore INT/QUIT for async jobs when job control is on) and accept process
   group isolation instead of a session. Decide in L2.1 whether perl is
   required on FreeBSD for `setsid`.
5. **Identity = (pid, start time)** everywhere winpid is used today
   (parent watch, seg-N.pid record, rescue watchdog).
6. Tests: 044, 045, 049, 052 read cygwin files directly → move them onto the
   API; 041-055 get backend-neutral expectations; a new test proves the
   UNKNOWN path. Windows runs of all ktests suites must stay identical.

## 4. The netcat question (input for L2.5)

### 4.1 what TNetcatTransport needs (thttpserver.sh:262-560)

One `nc` per connection, pre-spawned (two alternating slots), so the tool must:
(a) listen on ADDR:PORT, accept **exactly one** client, then exit; (b) relay
socket ↔ stdin/stdout; (c) on **EOF of stdin** finish sending, close the
connection, exit, so the server's drain (`_closeSlot`, 463-512) sees EOF on
stdout; (d) give up waiting for a client after `-w TTL` (orphan time-to-live)
and say so; (e) report on stderr, parsed by `_state` (517-545): `Listening on`
(bound), `Connection from A:P` (accepted, remote address), `Listen mode
failed: Connection timed out` (TTL), anything else = fatal; (f) bind with
reuse while the other slot's connection on the same port is still open.
Argv today: `-l -c -vv -n -w TTL -s ADDR -p PORT` (thttpserver.sh:401); `-c`
is GNU's "close on stdin EOF".

### 4.2 flavours

| flavour | where it is `nc` / installable | (a) one-shot | (c) close on stdin EOF | (d) accept TTL | (e) `-v` events | `-c` means |
|---|---|---|---|---|---|---|
| GNU netcat 0.7.1 | MSYS2 (`gnu-netcat`); FreeBSD pkg `netcat` (verify name/binary); Homebrew `netcat`; Arch. **Not packaged in Debian/Ubuntu/Fedora** (verify at L1) | yes | `-c` | `-w` | exact strings above | close on EOF |
| OpenBSD nc | Ubuntu default, Debian `netcat-openbsd`, Fedora `netcat`, Alpine `netcat-openbsd`, FreeBSD base, macOS base (Apple variant) | yes (no `-k`) | `-N` (Debian/FreeBSD; macOS: unknown) | **none** (`-w` ignored with `-l`) | Debian: `Listening on A P` / `Connection received on A P`; upstream/FreeBSD/Apple: differ (verify) | Debian/FreeBSD: invalid option; OpenBSD: TLS |
| nmap ncat | Fedora default (`nmap-ncat`), Debian `ncat` | yes (no `-k`) | default half-close (`--no-shutdown` off) | none (`-w` is connect) | `Ncat: Listening on A:P`, `Ncat: Connection from A:P.` | **`--sh-exec CMD`**: runs the next argument via `/bin/sh` |
| nc.traditional (Hobbit) | Debian `netcat-traditional` | yes | `-q 0` | `-w` in listen mode | `listening on [any] P …`, `connect to [A] from …` | **shell command** (Debian builds with it) |
| busybox nc | Alpine clean | small: `-l -p -s -w -v -e`; options config-dependent | unknown | `-w` (verify) | different | unknown |
| socat (not nc) | packaged everywhere (Debian, Fedora, Alpine, FreeBSD, brew) | yes | yes (shutdown on EOF, `-t` drain) | `accept-timeout=` (verify) | `-d -d`: `listening on …`, `accepting connection from …` | n/a |

Consequence today: on Ubuntu the GNU argv makes OpenBSD nc exit with "invalid
option" → `Accept` rc 2 and the thttpserver suite **fails** (it does not
SKIP: tests/_ths_socket.sh:31 takes any `nc` on PATH). On Fedora (ncat) and
nc.traditional the next argument `-vv` is handed to `/bin/sh -c`: not
exploitable with today's fixed argv, but it shows the rule: **never start an
unidentified nc with GNU flags**.

### 4.3 options

| option | cost | consequence |
|---|---|---|
| A. support several flavours (subclasses overriding `BuildArgv` + `_state`, the class already allows it, thttpserver.sh:359) | per flavour: argv, stderr dialect, a TTL emulated by the server where the tool has none (kill + respawn an idle listener), tests ×flavours | works out of the box on Ubuntu/FreeBSD/macOS (OpenBSD nc preinstalled); the OpenBSD dialect itself varies by vendor — highest test/maintenance load |
| B. require GNU netcat and document it | docs + a clear error | Linux users must build netcat 0.7.1 from source; thttpserver unusable on the first-impression target |
| C. detect + SKIP | identify the flavour once per transport (one fork of `nc -h`/`--version`: "GNU netcat 0.7.1", "OpenBSD netcat", "Ncat:", "BusyBox"); refuse non-GNU with LastError naming the found flavour and the package; tests SKIP visibly with that reason | honest and cheap; zero coverage on Linux VMs unless one VM gets GNU netcat |

**Recommendation: C now, plus exactly one second backend.** C (detection,
refusal, SKIP) is the floor and must land in L2.7 regardless — it also closes
the `-c` hazard. For the second backend L2.5 decides by a probe on kb-ubuntu
and kb-freebsd: if OpenBSD nc on both prints usable bind/accept events under
`-v` and supports `-N`, add a `TOpenBsdNetcatTransport` (preinstalled on
Ubuntu, FreeBSD, macOS; TTL done by the server); otherwise add a socat backend
(one program, identical semantics on every target, but never preinstalled).
ncat, nc.traditional and busybox: refused with a message, no backend.

## 5. OG1 — GNU-tool policy

### 5.1 what each option touches (numbers from tools.tsv / inventory.tsv)

| | A. core tool-free; wrappers require GNU by name | B. native BSD/busybox flavours in the wrappers | C. GNU required everywhere |
|---|---|---|---|
| wrapper code | 6 constructor lines (tsed.sh:270, tawk.sh:437, tfind.sh:192, tgrep.sh:157, thead.sh:162, ttail.sh:187) + tutil.sh:299, 433 messages + tawk.sh:640 | per wrapper an argv builder and an rc/message map per flavour; tsed `--sandbox/--debug/-s/-z/--posix` and tawk (gawk-only by design) have no BSD equivalent | none |
| wrapper tests (41 files) | ~348 direct tool calls (tools.tsv: sed 82, gawk 60, grep 63, head 49, tail 49, find 45) go through the same resolver; SKIP with reason when absent | the 348 calls plus 88 GNU-sed and 171 gawk lines split per flavour | none |
| core | the GNU-specific core sites rewritten portably: tpath 11 (H20-H24), gate.sh 2 (H4, H5), ktest_runner.sh 1 (H6) | same | those 14 sites keep GNU — and the core then needs coreutils/sed on BSD/macOS just for them |
| user-visible | "TSed needs GNU sed: FreeBSD `pkg install gsed`, macOS `brew install gnu-sed`, Alpine `apk add sed`" | works with what is installed, behaviour differs per OS | kbool needs GNU userland on BSD/macOS/Alpine to load at all |

### 5.2 recommendation

**A, with a portable core.** The resolver (L3.3, kkore) per tool T: try `gT`
then `T`; accept only a GNU identity from one `--version` probe per process
(`(GNU sed)`, `(GNU grep)`, `(GNU findutils)`, `(GNU coreutils)`, `GNU Awk` —
busybox prints "This is not GNU sed version 4.0", so the name alone is not
proof); cache; on failure rc 1 with the package names per OS (§7). On GNU
Linux and Alpine-with-GNU the plain names win; on FreeBSD/macOS the g-names.
Tests of the wrapper units SKIP with the resolver's reason.

Non-wrapper GNU flags: kcl/tpath (`stat -c`, `date -d`, `touch -d @`,
`realpath/readlink -m`) → portable or detect (H20-H24); kklass_autoload `stat`
and klib `realpath` → already portable; ktests gate/runner → portable (H4-H6).
Test-side GNU commands (`stat -c` 58, `date -d` 28, `touch -d` 17, `timeout`
170) → a ktests helper that resolves through the same kkore resolver
(`gstat`, `gdate`, `gtouch`, `gtimeout`) and SKIPs without it — or rewrites
with `printf %()T` / `touch -t` where cheap.

## 6. Bash floor

Static map (bashfeatures.tsv; name lists excluded):

| layer | highest feature used | notes |
|---|---|---|
| kkore | 4.4 (`@Q`/`@a` 41, `local -`) | no 5.x feature |
| kklass runtime | 4.4 (namerefs 118, `@a` 41); 5.1 `SRANDOM` gated (kklass.sh:940-946, falls back to `$( )`); 5.3 funsub gated (kklass.sh:1665 `BASH_VERSINFO`, generated text at 1694) | statically 4.4-clean |
| kcl units | 4.4 for 17 of 19 units; **5.0** `EPOCHREALTIME` without fallback: tstopwatch.sh:106, 115, 127; thttpserver.sh:483, 609, 618, 643, 758, 1118, thttpmessage.sh:127; dateutils.sh:624 has a fallback | the two timing units set 5.0 |
| ktests harness | **5.0** `EPOCHREALTIME`: ktest_runner.sh 8, gate.sh 12, strays.sh 7, suitejob.sh 3, timing_check 2, forkstorm 2, tests/tests.sh:30 | the harness sets 5.0 |
| 5.1 | only `SRANDOM`, gated | 5.1 statically free |
| 5.2 | none (`patsub_replacement` not set anywhere; replacement strings avoid `&`) | — |

What blocks: **4.4** — `EPOCHREALTIME` in the harness and in tstopwatch/
thttpserver (fallbacks via `printf '%(%s)T'` lose sub-second precision);
**5.0** — nothing static; **5.1** — nothing static. **3.2** (macOS) — everything:
only the L2.3 guard matters (H16).

Only L4 can measure: 5.1 vs 5.2 behaviour (backslash/`&` handling in
`${x//p/r}`, `unset 'a[$k]'` and `assoc_expand_once`, nameref edge cases,
`wait`/job-control under `set -m`, `read -N` buffering, `BASH_ARGV`/`extdebug`,
`local -` restore order), speed (fork-free paths), and whether the library
(kkore + kklass + most kcl) really runs on 5.0/4.4 although the harness does
not. Suggestion for L4.2: run the kkore and kklass suites (not only the full
gate) on 5.0.18 and 4.4.23 as well — it decides whether the library floor can
be lower than the test-harness floor.

## 7. Package lists for L1 provisioning

Baseline (all VMs): openssh-server, sudo, git, bash ≥ 5.2. "verify" = name not
certain, check at L1. Locales: generate `en_US.UTF-8`, `de_DE.UTF-8`,
`ru_RU.UTF-8` (tests use all three, plus `C.UTF-8`).

| OS | install | notes |
|---|---|---|
| Ubuntu 24.04 (apt) | `bash git coreutils sed grep findutils diffutils gawk procps util-linux perl curl openssl netcat-openbsd tzdata locales` then `locale-gen en_US.UTF-8 de_DE.UTF-8 ru_RU.UTF-8` | mawk stays the default `awk` (keep it: H27 coverage); GNU netcat: no package (verify) |
| Debian 13 (apt) | same list as Ubuntu; locales via `/etc/locale.gen` + `locale-gen` | minimal install lacks curl, sudo, netcat-openbsd, locales |
| Fedora (dnf) | `bash git-core coreutils sed grep findutils diffutils gawk procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru` | `netcat` = OpenBSD nc (verify); `nmap-ncat` provides `nc` |
| Alpine `clean` (apk) | `bash git` | busybox for the rest; no tzdata/perl/curl/openssl/gawk: those tests must SKIP (record ENV rows otherwise) |
| Alpine `clean-gnu` (apk) | `bash git coreutils sed grep findutils diffutils gawk procps-ng util-linux perl curl openssl netcat-openbsd tzdata` | GNU packages shadow busybox in `/usr/bin` under plain names; `procps-ng` (verify; older `procps`); `gnu-netcat` (verify — probably absent) |
| FreeBSD `clean` (pkg) | `bash git sudo` + `/etc/fstab`: `fdesc /dev/fd fdescfs rw 0 0` (mounted) | fdescfs belongs to "bash installed" (H14): put it in **both** snapshots |
| FreeBSD `clean-gnu` (pkg) | `coreutils gsed gawk findutils gnugrep diffutils netcat curl perl5` | g-prefixed binaries (`ghead`, `gstat`, `gsed`, `gfind`, `ggrep` — verify gnugrep's binary name); `netcat` = GNU 0.7.1 (verify port/binary name); base has openssl, timeout, tzdata, locales |
| macOS (CI, brew) | `bash coreutils gnu-sed gawk findutils grep netcat` | curl, perl, openssl (LibreSSL) present |

Optional, for named reasons: `socat` and `ncat`/`netcat-traditional` (L2.5
flavour probes, kb-ubuntu + kb-freebsd); `nodejs` (kklass/tests/131 JSON
cross-check, otherwise SKIP); `python3` (tcustomapplication 018 has a
fallback); `uuid-runtime` (Debian: `uuidgen` for tpath's GUID branch, has a
fallback). Not needed: `xxd`, `bc`, `jq`, `file`, `hostname` (checked: no test
calls them).

Also for L1: one gate run per Linux VM under `LC_ALL=de_DE.UTF-8` (H7 is
invisible under an English locale), and a non-root test user (4 tests assume
one).

## 8. Quick wins vs needs design

Quick wins — mechanical, each fits a card with exact old/new text. Those in
core layers (ktests harness, kklass) are O work under DL9 unless SV relaxes
that for one-liners:

| # | change | sites | layer |
|---|---|---|---|
| Q1 | `${EPOCHREALTIME/./}` → `${EPOCHREALTIME//[!0-9]/}` | ktest_runner.sh:625-671 (7); tests kkore 006/007, kklass 120, tstringhelper 061/066, ktests 044 | harness + tests |
| Q2 | runner CR strip in bash, no sed | ktest_runner.sh:1097 | harness |
| Q3 | STRAY verdict rewrite without `sed -i` | gate.sh:2520 | harness |
| Q4 | `bash` → `"$BASH"` | ktest_runner.sh:990, 1228; tests/tests.sh:119 | harness |
| Q5 | `date -d @E` → `printf '%(…)T'` | tpath.sh:397, 399 | kcl |
| Q6 | `touch -d @E` → `TZ=UTC0 touch -t` | tpath.sh:433-437 | kcl |
| Q7 | generated shebangs → `#!/usr/bin/env bash`; shebang-pinning tests updated | kklass_compiler.sh:260, kklass_kkp.sh:336, 346; 53 test lines; 3 pinning tests (§2.5) | kklass + tests (with L2.2) |
| Q8 | tests: SKIP when perl / openssl / curl is absent | dateutils 024, tfile 042, thttpserver socket tests | tests |
| Q9 | tests: guard Windows-only sections | kkore/tests/011_ConfigProject.sh:64-86, 209 | tests |
| Q10 | tests: `sed -i` → portable form | kklass 135, 139, 141; kkore 013; ktests 044 | tests |
| Q11 | tests: string-compared `$(wc …)` → arithmetic | 36 sites, triage each | tests |

Needs design (O):

| # | topic | task |
|---|---|---|
| D1 | harness process-table backends, never-blind rule, strays by session/group, (pid, start) identity, segment start without GNU `env` (H1-H4, H9) | L2.1 |
| D2 | thttpserver: flavour detection + refusal + SKIP; the second backend (H26, §4) | L2.5 / L2.7 |
| D3 | the GNU-tool resolver in kkore + test helper (OG1, §5) | L3.3 |
| D4 | tpath: stat format map (GNU/BSD/busybox), accepted date-string formats, lexical `getFullPath` normaliser (H20, H22, H24) | L3.5 |
| D5 | tawk: locating gawk's `inplace.awk` without an AWKPATH/cwd hijack (H42) | L3.5 |
| D6 | kklass `kk._fn_text` where `/dev/fd/N` is `dup()` (FreeBSD, macOS): probe once, alternative or accept `$( )`; measure build speed (H13) | L3.5 / L5.4 |
| D7 | kcl/math engine across mawk / BWK / busybox awk, if L2/L3 show differences (H27) | L2.5 / L3.5 |
| D8 | locale/TZ test environment policy (which locales the lab provides; behaviour on musl) | L1 / L2.5 |

## 9. Impact on LAUNCH_PLAN

* **L2.2** must also update the 3 shebang-pinning tests and the generators
  (kklass_compiler.sh, kklass_kkp.sh — kklass core, so O per DL9); the 53
  generated test shebangs are its natural companions.
* **L2.3**: the guard goes above kbool.sh:32 and uses 3.2 syntax only (H16).
* **L1.4**: FreeBSD needs the fdescfs fstab line in both snapshots (not in
  the plan). L1 also needs locales, tzdata and a non-root user (§7).
* **L1.6 / L2.4**: until L2.1 lands, a Linux gate that "passes" is not
  evidence — its stray checks are blind (H1) and `strays.sh` says "none".
* **thttpserver coverage**: GNU netcat is not packaged on the three Linux
  VMs; without a backend decision (or a from-source build of netcat 0.7.1 on
  one VM) the suite only SKIPs on Linux.
* **§1 of the plan** ("5.0 EPOCHREALTIME (22 files)"): the 5.0 floor is set
  by the test harness and two kcl units, not by kkore/kklass (§6); L4 could
  measure the library separately.
* **L2.1 scope** should include H5-H8 (harness one-liners) and H4, which
  blocks FreeBSD/Alpine-clean/macOS gates entirely — L3.1 depends on it.

## 10. Status after L2.7 (2026-10-22)

Implemented since this document was written (details: `docs/dev/launch/L2_triage.md`
§7–§8 and the ledger):

- **H1/H4–H8 (harness)**: `ktests/ktest_proc.sh` process table with cygwin / linux / ps
  backends; gate segments start via `env --default-signal` | perl | `set -m`; the stray
  check is real on Linux and FreeBSD (L2.1, L2.7-K).
- **H7 (comma locale)**: fixed (L0.7); the group-stop deadline has a regression test.
- **Netcat (§4)**: D2 — GNU netcat 0.7.1 stays the first backend (packaged as Homebrew
  `netcat`, FreeBSD `net/gnetcat`, Arch `gnu-netcat`, MSYS2 `gnu-netcat`; not by
  Debian/Ubuntu/Fedora/Alpine); **socat** is the second backend (`TSocatTransport`,
  L2.7-N2); OpenBSD nc / ncat / busybox nc are refused by name — OpenBSD nc keeps its
  listening socket open while serving and sets SO_REUSEPORT, so the two-slot model loses
  every second client (measured 10/20, §8 of the triage). Detection precedence: explicit
  nc (`NcBinary`/`KCL_NC`) > explicit socat (`SocatBinary`/`KCL_SOCAT`, must support
  `accept-timeout`, socat ≥ 1.7.4) > auto (GNU nc on PATH, else socat on PATH); the exact
  refusal texts are in `kcl/thttpserver/README.md` "Network backend".
- **CR (§2, wrappers)**: DL11 — TGrep/TSed/TAwk strip the trailing CR in text mode on
  every platform (input-side for sed/awk, output-side for grep); `binary = 1` keeps bytes
  everywhere (L2.7-C).
- **kcl/math under mawk**: the engine is mawk-compatible (flat dispatch, `-W interactive`,
  NaN guards — gawk orders NaN greater than numbers, mawk's `x!=x` is false), gawk preferred
  when present, `MATH_FE_ERROR` on a failed start, the 4095-character request limit only for
  mawk dated before 20250131 (L2.7-M, M2).
- **TPipe.stop** stops the producer's whole tree (DL13, L2.7-P).
- Linux after L2.6/L2.7: Ubuntu/Debian/Fedora full gates are expected clean except
  the flakes listed in the ledger's `open`; the closing measurement is L2.8.
