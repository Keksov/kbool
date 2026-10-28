# L34-F — the L3.4 gates and the triage of the un-skipped cases

Date 2026-10-28. Card L34-F of [`L3_4_design.md`](L3_4_design.md) §3. Tree: kcl `609747a`, kklass
`0626d32`, kkore `83e750b`, ktests `9c8cc3c`; kbool `7f2d8cf` for the first gate and `f7c4ef3` for
the rest (the two commits between them touch only `docs/dev/launch_ledger.json`); no `-dirty`. Input:
seven full VM gates and one Windows gate on this tree (the runs, literal: [`L3_runs.md`](L3_runs.md)
§ "L34-F"), one wrapper `SKIP:` count per (VM, snapshot), and plain-bash probes in kb-alpine
`clean-gnu` and kb-debian `clean`. Format model: [`L3_triage.md`](L3_triage.md). Every mechanism
below was reproduced in a lab VM under `ulimit -v 1000000` and `timeout -k`; the probe scripts and
their literal output are in the L34-F scratch folder of the supervisor session, not in the tree.

## 0. Summary

Eight gates: kb-freebsd `clean-gnu` and `clean`, kb-alpine `clean` and `clean-gnu`, kb-debian, kb-ubuntu,
kb-fedora, Windows (Git-bash 5.3.15 and MSYS2 5.3.9). **Five PASS, two FLAKY** (kb-alpine `clean-gnu`,
kb-debian), **Windows PASS** (`__GATE__:PASS:60:60:0:0:0:0:0:19031:19031`).

| cluster | rows | cause (one line) | class | card |
|---|---|---|---|---|
| F1 lost exit status of an external `<( )` producer | 2 (Ag 1, De 1) | the C13 bash race (L3.5-8) also hits a producer bash **execs** (every wrapper's GNU tool); L3.5-8's status pipe covers only function/builtin producers | T-core (tpipe) | L34-F1 |
| F2 `tfile.decrypt` accepts a wrong password | 1 (De 1) | `openssl enc -d -aes-256-cbc` has no authentication: a wrong key passes the padding check ~1/256 of the time and decrypt reports success | T-core (tfile) | L34-F2 |

Ag = kb-alpine `clean-gnu`, De = kb-debian `clean`. Rows: **3**, all FLAKY (failed once, passed on
the gate's rerun); 0 FAIL, 0 TIMEOUT, 0 STRAY, 0 ENV on the seven VMs. Each row is in exactly one
cluster. The un-skipped wrapper cases (577 on FreeBSD `clean-gnu` before L3.4) produced **no** row
of their own: FreeBSD `clean-gnu` passes all six wrapper suites with 0 tool SKIPs (§2).

## 1. The gates

| (VM, snapshot) | bash | `__GATE__` | non-PASS rows |
|---|---|---|---|
| kb-freebsd `clean-gnu` | 5.3.20 pkg | `__GATE__:PASS:30:30:0:0:0:0:0:9477:9477` | — |
| kb-freebsd `clean` | 5.3.20 pkg | `__GATE__:PASS:30:30:0:0:0:0:0:9477:9477` | — |
| kb-alpine `clean-gnu` | 5.3.9 musl | `__GATE__:FLAKY:30:29:0:1:0:0:0:9477:9478` | kcl/tgrep 005 (F1) |
| kb-alpine `clean` | 5.3.9 musl | `__GATE__:PASS:30:30:0:0:0:0:0:9478:9478` | — |
| kb-debian `clean` | 5.2.37 | `__GATE__:FLAKY:30:28:0:2:0:0:0:9498:9500` | kcl/tawk 005 (F1), kcl/tfile 007 (F2) |
| kb-ubuntu `clean` | 5.2.21 | `__GATE__:PASS:30:30:0:0:0:0:0:9500:9500` | — |
| kb-fedora `clean` | 5.3.9 | `__GATE__:PASS:30:30:0:0:0:0:0:9500:9500` | — |
| Windows, Git-bash + MSYS2 | 5.3.15 / 5.3.9 | `__GATE__:PASS:60:60:0:0:0:0:0:19031:19031` (5.3.15 9515/9515, 5.3.9 9516/9516) | — |

Command per VM: `bash tools/vmlab/vmlab.sh gate VM --snapshot S --out "$SCRATCH/<vm>-<snap>" --
--rerun-failed 1 --timeout 900 all`, one VM at a time; Windows: `bash ktests/tools/gate.sh --out
"$SCRATCH/win" --rerun-failed 1 all` with `KT_GATE_BASHES` = Git-bash and MSYS2, no VM running.

The totals differ per platform but not per run: 9500 on the glibc VMs (kklass 855), 9478 on Alpine
(kklass 833, ktests 664), 9477 on FreeBSD (kklass 833, ktests 663) — the same suite list, test files
that add cases per platform; no case failed because of it (not investigated further).

## 2. Wrapper `SKIP:` lines per (VM, snapshot)

How counted: after each gate, a separate VM session on the same snapshot and the same synced tree
(`reset`, `up`, `sync`), then in one `vmlab run`: `bash kcl/<unit>/tests/tests.sh -v info` for each
of the six wrappers, `grep -c "SKIP:"` of its output, the distinct reasons (`grep -o "SKIP:.*" | sort
| uniq -c`), and the `cmd` of a fresh instance of each wrapper. The gate's cell logs carry no
`SKIP:` lines (the gate does not pass `-v info`), so they cannot be counted there. All 42 suite runs
were rc 0 with `Failed: 0`.

| (VM, snapshot) | §2.1 of L3_triage | now | tsed | tawk | tgrep | tfind | thead | ttail | tool SKIPs |
|---|---|---|---|---|---|---|---|---|---|
| kb-alpine `clean` | 763 | **764** | 166 | 187 | 108 | 96 | 96 | 111 | 764 |
| kb-alpine `clean-gnu` | 0 | **1** | 0 | 0 | 0 | 1 | 0 | 0 | **0** |
| kb-freebsd `clean` | 763 | **764** | 166 | 187 | 108 | 96 | 96 | 111 | 764 |
| kb-freebsd `clean-gnu` | **577** | **1** | 0 | 0 | 0 | 1 | 0 | 0 | **0** |
| kb-debian `clean` | — | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| kb-ubuntu `clean` | — | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| kb-fedora `clean` | — | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |

* The one SKIP on every GNU box is tfind's `SKIP: no cygpath on this box` (a Windows-only case), as
  the card expects. **FreeBSD `clean-gnu`: 577 → 0 tool SKIPs**, every wrapper resolved to its
  g-name: `sed=[/usr/local/bin/gsed] awk=[/usr/local/bin/gawk] grep=[/usr/local/bin/ggrep]
  find=[/usr/local/bin/gfind] head=[/usr/local/bin/ghead] tail=[/usr/local/bin/gtail]`.
* Alpine `clean-gnu` resolves the plain names: `sed=[/bin/sed] awk=[/usr/bin/gawk] grep=[/bin/grep]
  find=[/usr/bin/find] head=[/usr/bin/head] tail=[/usr/bin/tail]`; the glibc VMs `/usr/bin/sed`,
  `/usr/bin/gawk`, `/usr/bin/grep`, `/usr/bin/find`, `/usr/bin/head`, `/usr/bin/tail`.
* `clean` on FreeBSD and Alpine: every SKIP carries the package hint, one distinct reason per unit,
  `cmd` empty for all six. FreeBSD: `… FreeBSD: pkg install gsed` (166), `pkg install gawk` (187),
  `pkg install gnugrep` (108), `pkg install findutils` (96), `pkg install coreutils` (96 + 111).
  Alpine: `… Alpine: apk add sed` (166), `apk add gawk` (187), `apk add grep` (108), `apk add
  findutils` (96), `apk add coreutils` (96 + 111). Example, literal:
  `SKIP: no GNU grep: ggrep not on PATH; /usr/bin/grep is not GNU grep (--version: "grep (BSD grep,
  GNU compatible) 2.6.0-FreeBSD"); FreeBSD: pkg install gnugrep`.
* 763 → 764: tawk 186 → 187. The tawk suite grew 609 → 622 in L34-C; one more of its cases sits
  behind the GNU gate. No other unit's count changed.

## 3. Clusters

### F1 — lost exit status of an external `<( )` producer (2 rows: Ag 1, De 1)

Rows:

* kcl/tgrep 005 (kb-alpine `clean-gnu`, FLAKY): `[FAIL] rc=1 lastRc='127' ourLines=1 toolLines=2
  first='Error: TGrep.mapRc: command not found (raw rc 127)' recs=0 (005_Search.sh)` — case "G6:
  `extended = 1` with pattern `(` is rc 1, `lastRc` 2 and ONE line" (`005_Search.sh:310-325`).
* kcl/tawk 005 (kb-debian `clean`, FLAKY): `[FAIL] run rc=0 od='0000000   a   \   t   b|0000004'
  want='0000000   a   \   t   b|0000004' stderr=''; toArray rc=1 got=a\tb  (005_Run.sh)` — case "A5:
  setVar round-trips byte-exact — backslash-t" (`005_Run.sh:459-486`), the `nullData` `toArray` half.
  This is the known open flake the card names (L34-C round 1: kb-alpine `clean-gnu`, the same case
  family, "nullData toArray rc 1"); it now shows on Debian too.

Mechanism: the records are right in both (tawk got `a\tb`; tgrep's own error line was passed
through) — only the producer's exit status is wrong. TUtil runs every sink as `TPipe.<sink> … --
"${argv[@]}"` (`tutil/tutil.sh`, header :19-20), and argv word 0 is the resolved GNU tool, an
**external** command. TPipe starts an external producer as `exec {__tpi_fd}< <( "$@" )`
(`tpipe/tpipe.sh:693`) and closes it with `wait "$__tpi_pid" || __TPIPE_RC=$?` (`:1243`, the stop
path `:1296`), stderr not discarded. When bash loses the child's status (the race of L3_triage C13 /
launch L3.5-8), `wait` answers 127 plus `wait: pid N is not a child of this shell` (bash 5.3.9) or a
silent -1 (5.2.37). In tgrep that is `lastRc` 127, mapped to "command not found", and bash's line is
the second "tool" line on stderr (`toolLines=2`); in tawk `lastRc` -1 → member rc 1. L3.5-8 fixed
the race only for **function and builtin** producers (the status pipe, `tpipe.sh:131-185`) on the
premise, in the code comment `:144` and `tpipe/README.md` §4, that an exec'd producer "does not lose
the race in practice (0 in 24000 measured)". The probes contradict that premise.

Repro (plain bash, no kbool; `ext.sh N MODE`: `exec {fd}< <( "$@" )`, read to EOF, close, `wait
$!`, count statuses other than the producer's own; 8 copies in parallel are the load; each copy under
`timeout -k 5 300`, the driver under `ulimit -v 1000000`):

```
### kb-alpine clean-gnu
### bash: 5.3.9(1)-release; grep: /bin/grep grep (GNU grep) 3.12
### is the external producer exec'd? (<( sleep 2 ): $! and its comm)
pid=2250 comm=sleep ppid_of_pid=2245 self=2245
### ext.sh 5000 grep x8 parallel (load = the 8 copies)
mode=grep hits=2 n=5000
mode=grep hits=4 n=5000
mode=grep hits=2 n=5000
mode=grep hits=6 n=5000
mode=grep hits=7 n=5000
mode=grep hits=2 n=5000
mode=grep hits=5 n=5000
mode=grep hits=2 n=5000
### ext.sh 5000 false x8 parallel (load = the 8 copies)
mode=false hits=0 n=5000
mode=false hits=1 n=5000
mode=false hits=1 n=5000
mode=false hits=3 n=5000
mode=false hits=1 n=5000
mode=false hits=0 n=5000
mode=false hits=1 n=5000
mode=false hits=1 n=5000
### ext.sh 5000 fn x8 parallel (load = the 8 copies)
mode=fn hits=2 n=5000
mode=fn hits=7 n=5000
mode=fn hits=3 n=5000
mode=fn hits=3 n=5000
mode=fn hits=8 n=5000
mode=fn hits=14 n=5000
mode=fn hits=7 n=5000
mode=fn hits=8 n=5000

### kb-debian clean
### bash: 5.2.37(1)-release; grep: /usr/bin/grep grep (GNU grep) 3.11
### ext.sh 5000 grep x8 parallel
sum hits=35 n=40000
  lost:      35 rc=-1
### ext.sh 5000 false x8 parallel
sum hits=19 n=40000
  lost:      19 rc=-1
### ext.sh 5000 fn x8 parallel
sum hits=24 n=40000
  lost:      24 rc=-1
```

(Alpine sums: grep 30, false 8, fn 52 of 40000 each. The Alpine copies' per-hit rc lines were lost to a redirection slip in the first version of the
script; the Debian run prints them. The exec is real: `$!` is the `sleep` itself, its parent the
shell.) The same file under load, through kbool, kb-alpine `clean-gnu`:

```
### tgrep 005 alone x10
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
Passed: 60 Failed: 0 
### tgrep 005 x4 parallel, 5 rounds
round 1: Failed: 0 Failed: 0 Failed: 0 Failed: 0  
round 2: Failed: 0 Failed: 0 Failed: 0 Failed: 0  
round 3: Failed: 0 Failed: 0 Failed: 0 Failed: 0  
round 4: Failed: 0 Failed: 0 Failed: 0 Failed: 0  
round 5: Failed: 1 Failed: 0 Failed: 0 Failed: 0  [FAIL] rc=1 SGOT=alpha\ needle\ here needle\ again  (005_Search.sh)
```

The round-5 hit is a different case (G12, `005_Search.sh:722-736`, a `toArray` with exit 0 and the
two right records, member rc 1): any sink of any wrapper can be hit, the case is chance. Rate: 0.02-
0.09 % of the calls under an 8-way load for an exec'd producer, about the same order as a function
producer — so every wrapper sink on Alpine, Debian and Ubuntu (L3.5-8 measured the race there; not on
Fedora, FreeBSD or cygwin) can report a wrong rc under load. Class **T-core** (tpipe; a bash race
behind it, shown in the gate as FLAKY).

### F2 — `tfile.decrypt` accepts a wrong password (1 row: De 1)

Row: kcl/tfile 007 (kb-debian `clean`, FLAKY): `[FAIL] Decrypt with wrong password (should have
failed) (007_Decrypt.sh)` — Test 4 (`007_Decrypt.sh:54-66`): encrypt with `right-password`,
decrypt with `wrong-password`, expect a non-zero rc.

Mechanism: `tfile._crypt_file` (`tfile/tfile.sh:158-176`) runs `openssl enc [-d] -aes-256-cbc -salt
-pbkdf2 -in FILE -out TMP -pass env:TFILE_CRYPTO_PASSWORD` and treats rc 0 as success (the TMP file
replaces FILE). CBC with PKCS#7 padding has no authentication: with a wrong key the last block
decrypts to random bytes, and openssl reports success whenever they happen to end in a valid
padding (`01`, `02 02`, …) — about 1/256 per decrypt, independent of the platform. The salt is fresh
per encryption, so every run of 007 draws again. On such a hit `tfile.decrypt` returns 0 and replaces
the file with garbage. Repro (kb-debian `clean`, the unit's exact command lines, a fresh encryption
each time):

```
### openssl: wrong-password decrypt of a fresh encryption, 2000 times (tfile._crypt_file's command line)
OpenSSL 3.5.7 9 Jun 2026 (Library: OpenSSL 3.5.7 9 Jun 2026)
first rc-0 decrypt at i=359, output bytes:  3d c8 7c fa 9a d5 e0 7f 2b e6 10 f9 15 89 6e
wrong password accepted (rc 0): 7 / 2000; output == plaintext: 0
```

7/2000 = 0.35 % (1/256 = 0.39 %). The test is right about the contract; the unit cannot keep it.
Class **T-core** (tfile; shown as FLAKY). Not a regression of L3.4: the code is older than the
launch work; it surfaces now only because each gate is one more draw.

## 4. Fix cards

Common: Write scope = the files listed; LF only; `git -C <repo>` only for the repos named; never
commit. A rule that does not fit the code → BLOCKED with the evidence. Gates per
`ktests/docs/GATE_FOR_AGENTS.md`; VM gates `bash tools/vmlab/vmlab.sh gate VM --snapshot S --
--rerun-failed 1 <suites>`; risky loops only inside a VM under `ulimit -v` + `timeout -k`.

### L34-F1 — TPipe recovers a lost status of an external producer [O, critic]

```
CARD: L34-F1
Goal: TPipe.lastRc and every sink's rc are the producer's real exit status for EXTERNAL producers
      too, on the Linux bashes that lose it (kb-alpine 5.3.9, kb-debian 5.2.37, kb-ubuntu 5.2.21).
Rows: F1 — tgrep 005 (Ag), tawk 005 (De); every TUtil-based wrapper sink is exposed.
Cause/repro: §3 F1 (ext.sh: exec'd grep 30/40000 Alpine, 35/40000 Debian; /bin/false 8 and 19).
Options (decide in the card's first step with a cost measurement, report before coding):
  (a) recommended: on __TPIPE_ST (Linux with /proc) start an external producer in the reporting
      form as well — `<( builtin trap "…" EXIT; "$@" )` (tpipe.sh:689-691), so tpipe._close takes
      the reported rc when wait answers 127 / outside 0-255, exactly as for a function today. Cost:
      bash no longer execs the producer — one more fork per call (measure TPipe.count -- /bin/true
      before/after on kb-alpine and kb-debian, unloaded, median of 5, as L3.5-8 did). The subshell
      is then $!; the stop path already walks the producer's tree (DL13), check that TERM/SIGPIPE
      still give 143/141 through `wait` (the "report does not simply win" rule, tpipe.sh:161-166).
  (b) only the wrappers: TUtil asks for the reporting form (a TPipe flag word), plain TPipe callers
      keep the exec — narrower, but a plain `TPipe.count -- grep …` caller keeps the race.
  (c) no workaround, documented: README §4 states that an external producer's rc can be lost
      under load on these bashes, and the wrapper tests accept 127/-1 — not recommended (a wrapper
      then reports "command not found" for a tool that ran).
Write scope: kcl/tpipe/tpipe.sh, kcl/tpipe/README.md (§4: the "0 in 24000" sentence and the
   "external producers pay nothing" cost line), kcl/tpipe/tests/007_StatusPipe.sh (the "an external
   producer keeps wait's answer" case becomes the recovered one, plus one external case per sink
   with the existing `wait` stand-in), kcl/tpipe/bench* only if the cost table names the external
   path; scratch.
Acceptance: ext.sh-shaped repro through TPipe (`TPipe.count -- /bin/false`, 8 x 5000 in parallel)
   on kb-alpine clean-gnu and kb-debian: before >= 1 lost (lastRc 127 / -1), after 0 in >= 10 x
   that volume; tgrep 005 x4 parallel x20 rounds on kb-alpine clean-gnu 0 FAIL; Windows
   `bash $G kcl/tpipe kcl/tutil kcl/tsed kcl/tawk kcl/tgrep kcl/tfind kcl/thead kcl/ttail` PASS
   both runtimes; full VM gates on kb-alpine clean-gnu, kb-debian, kb-ubuntu, kb-fedora, kb-freebsd
   clean-gnu PASS (FreeBSD and cygwin paths unchanged: __TPIPE_ST is 0 there).
Timebox: 3 h.
```

### L34-F2 — `tfile.decrypt` detects a wrong password [O, design, owner decision]

```
CARD: L34-F2
Goal: tfile.decrypt with a wrong password always fails (rc 1, file unchanged), on every platform.
Rows: F2 — tfile 007 (De). Cause/repro: §3 F2 (7 of 2000 wrong-password decrypts rc 0).
Options (owner decides the format; each changes what tfile.encrypt writes):
  (a) recommended: a fixed magic line inside the ciphertext — encrypt `KBOOL-TFILE-1\n` + the
      content; decrypt to TMP, check and strip the first line, fail (rc 1, TMP removed, FILE
      untouched) when it is missing. A wrong key garbles the first block, so the check fails with
      certainty for practical purposes. No integrity against deliberate tampering.
  (b) encrypt-then-MAC: an HMAC-SHA256 of the ciphertext (key derived from the password, e.g. a
      second PBKDF2 run with another salt) appended as a trailer, checked before decrypting —
      detects a wrong password AND tampering; two more openssl calls per operation.
  (c) document only: README states that a wrong password is detected 255 times in 256 and 007's
      Test 4 is relaxed to "rc != 0 OR output != plaintext" — not recommended: decrypt would still
      replace the user's file with garbage and report success.
  For (a)/(b): files written by today's tfile.encrypt have no magic/trailer — decide whether
  decrypt accepts them (legacy path, keeps the 1/256 hole for old files) or refuses them.
Write scope: kcl/tfile/tfile.sh (_crypt_file, encrypt, decrypt), kcl/tfile/README.md (the
   encryption section: format, what is and is not protected), kcl/tfile/tests/009_Encrypt.sh and
   007_Decrypt.sh (a wrong-password loop of 300 decrypts: 0 accepted; the legacy-file rule).
Acceptance: inside a VM, 2000 wrong-password decrypts through tfile.decrypt: 0 rc 0 and the file
   byte-identical afterwards; Windows `bash $G kcl/tfile` PASS both runtimes; VM gates kcl/tfile on
   kb-debian, kb-alpine clean, kb-freebsd clean PASS.
Timebox: 2 h after the decision.
```

## 5. Notes

* Watch item from the card: the alpine `clean-gnu` tawk 005 A5 `nullData` `toArray` rc 1 flake is
  F1 (it showed on kb-debian in this run, not on Alpine); it closes with L34-F1.
* The 577 FreeBSD `clean-gnu` cases now run (§2) and pass; no new FreeBSD row. Both FreeBSD gates
  and both Alpine gates show no row from L3_triage's clusters C1-C14.
* Open from the L34-D ledger entry, outside this card's write scope (not done): `kcl/README.md` and
  the tgrep/tfind `TEST_COVERAGE_NOTES` counts and banner wording.
