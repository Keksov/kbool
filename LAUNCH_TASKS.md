# kbool launch — task cards for Sonnet 5.5 (effort high)

Companion of [LAUNCH_PLAN.md](LAUNCH_PLAN.md) §3–§4. **An S brief = §0
verbatim + one card verbatim** + the line `SCRATCH=<dir>` (a fresh scratch
dir for this dispatch). Cards marked **draft** are completed by the
supervisor (SV) before dispatch; a ready card has no "TBD".

Card fields: **Goal** · **Read** (the only files needed) · **Write scope**
(the only paths you may create/change) · **Steps** · **Do not** ·
**Acceptance** (commands + expected result; all must hold) · **Stop if**
(→ BLOCKED) · **Timebox**.

---

## §0 — common preamble (paste verbatim into every S brief)

**Project.** kbool is a Free-Pascal-flavoured toolkit for bash (units with
`uses`, classes, ports of FPC classes). Root `C:\projects\kkbot\kbool`
(Git-bash: `/c/projects/kkbot/kbool`), Windows 11. Five git repos: the root
(kbool) and its submodules `kcl`, `kklass`, `kkore`, `ktests`. Two bash
runtimes on this machine: Git-bash 5.2.37 (`C:/bin/Git/usr/bin/bash.exe`,
what the Bash tool runs) and MSYS2 5.3.9 (`C:/bin/msys64/usr/bin/bash.exe`).
Since L0.1 the tree is LF-only (`.gitattributes` `eol=lf`); keep it so.
Check CRs with `git -C R ls-files --eol` (column `w/lf`) or
`tr -cd '\r' < FILE | wc -c` — **not** with `grep -c $'\r'`, which misses CRs
under Git-bash (found 2026-10-21). Python on Windows writes CRLF in text mode:
use `newline='\n'`.

**You execute exactly ONE task card.** Do only what it says. Write only
inside its *Write scope*; a needed change outside it → stop, report BLOCKED.

**You make no design decisions.** If the card does not decide something you
need (a name, a format, a rule, which of two behaviours), stop and report
BLOCKED with the options and their consequences. Never "pick something
reasonable". A card instruction that turns out to be wrong (a command fails,
a path does not exist) is also BLOCKED, not improvised around — unless the
card itself gives the fallback.

**Git.** Never commit, push, tag, stash, reset, checkout, restore, rebase,
clean, amend, or run `gh` commands that write. `git mv` and
`git update-index --chmod` only when the card says so. Other sessions may
have uncommitted work: run `git status --short` in all five repos at the
start and at the end; files dirty at the start that your card does not
name are not yours — never touch or revert them.

**Testing.** The test driver is `ktests/tools/gate.sh`. Before your first
gate read `ktests/docs/GATE_FOR_AGENTS.md` and follow it exactly (calls,
`run_in_background`, reading the `__GATE__` line, hygiene). Never write your
own loops over runtimes or suites. One gate at a time on the machine; no
Windows gate while a lab VM runs.

**Lab VMs.** Only VMs whose name starts with `kb-` and is listed in
`tools/vmlab/vms.conf` (once it exists). Never start, stop, modify, snapshot
or delete any other VM — the owner's "Ubuntu 24.02.2", "OLHCV" and an
`<inaccessible>` entry exist and are off limits. `VBoxManage` is
`"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"`; it wants Windows
paths (`cygpath -w`). Every VM you start is powered off before you finish.

**Process hygiene.** No `&` job outliving its tool call. Every `timeout` gets
a kill fallback (`timeout -k 30 N …`). A script you write that starts
children traps EXIT/TERM/INT and stops them. Stop only processes you started
(by recorded pid) — **never by a name pattern or regex over the process list**
(L1.2 attempt 2 killed its own tool shells that way; a pattern can just as
well hit another session's work). Record every pid you start at start time.
This includes orphans of your own runs: an orphan you did not record is
REPORTED (pid, cmdline, how it arose) and left for the supervisor — even
when you are sure it is yours (broken twice more in L2.1). At the end list strays in both
runtimes and the running VMs:

```bash
bash ktests/tools/strays.sh list --all
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe ktests/tools/strays.sh list --all
"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" list runningvms
```

Each strays listing must say `strays: none (…)`; no `kb-*` VM may be running.

**Downloads.** Only from the URLs/hosts the card names, into the folder it
names; verify the checksum the card names before use; never execute a
downloaded file on the host.

**Secrets.** Never print, copy or commit a private key or a password. The lab
key is `~/.ssh/kbool_vmlab` (+ `.pub`).

**Scratch.** Temporary files go to `$SCRATCH` (given in the brief), never
into the tree. Remove what the report does not reference.

**Report** (your final message, English, exactly these headings):

```
STATUS: DONE | PARTIAL | BLOCKED
CARD: <id>
CHANGED: <git status --short of each repo — your files only>
ACCEPTANCE: <each check: the command, its literal output (relevant lines), PASS/FAIL>
DEVIATIONS: <anything done differently from the card, and why — or "none">
BLOCKED ON: <the question, the options, their consequences — or "-">
OPEN: <things noticed outside your scope, not fixed — or "none">
HYGIENE: <the three listings above, literal>
```

Literal command output, not summaries. "Should work" is not evidence.
At the timebox report PARTIAL with what is done and what is left.

---

## L0 — inventory + repository basics

### L0.1 — LICENSE + .gitattributes  [S] ready

**Goal.** MIT license in the three repos that lack one; LF protection in all five.
**Read.** `kcl/LICENSE`.
**Write scope.** `LICENSE`, `kkore/LICENSE`, `ktests/LICENSE`; `.gitattributes` in
`.`, `kcl`, `kklass`, `kkore`, `ktests`.
**Steps.**
1. Copy `kcl/LICENSE` byte for byte to the three LICENSE paths (`cp`).
2. Write each `.gitattributes` with exactly these lines:
   ```
   * text=auto eol=lf
   *.png binary
   *.gif binary
   *.ico binary
   *.gz binary
   *.xz binary
   ```
3. *(amended 2026-10-20 after the first dispatch found 32 CRLF files — the
   tdirectory tests start with `#!/bin/bash\r` and cannot run on Linux)*
   Convert to LF in the working tree, with `sed -i 's/\r$//' FILE`, exactly
   the files `git -C R ls-files --eol` shows as `i/crlf` or `i/mixed`
   (2026-10-20: root `optimization_ledger.json`; kcl `LICENSE`,
   `tdictionary/tdictionary_ledger.json`, `tfile/docs/TFileAttribute.md`,
   26 × `tdirectory/tests/*.sh`; kklass `LICENSE`, `examples/.gitignore`);
   then copy the LF `kcl/LICENSE` again. No `git add --renormalize`
   (its `--dry-run` lists every path, so it proves nothing).
**Acceptance.**
- `cmp kcl/LICENSE LICENSE && cmp kcl/LICENSE kkore/LICENSE && cmp kcl/LICENSE ktests/LICENSE && echo same` → `same`; `grep -c $'\r'` of the five LICENSE files → all 0
- the five `.gitattributes` identical (`md5sum */.gitattributes .gitattributes`)
- per repo `git -C R ls-files --eol | awk '$2!="w/lf" && $2!="w/none" && $2!="w/"'` → empty
- per repo `git -C R diff --ignore-cr-at-eol --stat` → empty (only CRs changed)
- `bash $G kcl/tdirectory` on both Windows runtimes → PASS.
**Timebox.** 15 min.

### L0.2 — portability scanner + inventory  [S] ready

**Goal.** A re-runnable scanner and the inventory it produces.
**Read.** This card only.
**Write scope.** `tools/porting/scan.sh`, `tools/porting/patterns.tsv`,
`docs/dev/launch/inventory.tsv`, `docs/dev/launch/inventory_summary.txt`.
**Steps.**
1. `tools/porting/patterns.tsv`: header `id<TAB>name<TAB>regex<TAB>note`, then
   the rows below (ERE for `grep -E`; tune a regex only to remove an obvious
   false-positive class, and say so in DEVIATIONS):

   | id | name | regex (ERE) |
   |---|---|---|
   | P01 | shebang /bin/bash | `^#!/bin/bash` |
   | P02 | sed -i | `\bsed\b[^|;&]*[[:space:]]-[a-zA-Z]*i` |
   | P03 | sed GNU options | `\bsed\b[^|;&]*[[:space:]](-r\b|-z\b|--[a-z])` |
   | P04 | stat GNU | `\bstat\b[^|;&]*(-c\b|--format|--printf)` |
   | P05 | date GNU | `\bdate\b[^|;&]*(-d\b|--date|-r\b|--iso)` |
   | P06 | readlink -f / realpath | `readlink[[:space:]]+-[a-z]*f|\brealpath\b` |
   | P07 | find GNU | `\bfind\b.*(-printf|-regextype|-maxdepth|-mindepth|-delete|-readable|-writable|-executable)` |
   | P08 | grep GNU | `\bgrep\b[^|;&]*(-P\b|--perl|-z\b|--null-data|--color)` |
   | P09 | sort -V / GNU sort | `\bsort\b[^|;&]*(-V\b|--version-sort|-h\b|-z\b)` |
   | P10 | mktemp | `\bmktemp\b` |
   | P11 | timeout | `\btimeout\b` |
   | P12 | netcat | `(^|[^a-zA-Z_.-])nc\b` |
   | P13 | /proc | `/proc/` |
   | P14 | Windows branches | `cygpath|MSYSTEM|OSTYPE|[Mm][Ss][Yy][Ss]|[Cc]ygwin|[Mm]ingw` |
   | P15 | Windows paths | `/c/|[Cc]:[/\\]` |
   | P16 | gawk-only | `gensub|strftime|systime|asort|PROCINFO|@include|BEGINFILE|ENDFILE|--re-interval|\bgawk\b` |
   | P17 | xargs GNU | `\bxargs\b[^|;&]*(-d\b|-r\b|--)` |
   | P18 | head/tail GNU | `\b(head|tail)\b[^|;&]*(-n[[:space:]]*-[0-9]|-c[[:space:]]*-[0-9]|--[a-z])` |
   | P19 | cp/mv/ln GNU | `\b(cp|mv|ln)\b[^|;&]*(-T\b|-r\b.*\bln\b|--[a-z])` |
   | P20 | GNU-only tools | `\b(tac|shuf|stdbuf|nproc|md5sum|sha1sum|sha256sum|flock|setsid|truncate|numfmt)\b` |
   | P21 | base64 options | `\bbase64\b[^|;&]*(-w\b|-d\b|--)` |
   | P22 | ps/pgrep/pkill | `\b(ps|pgrep|pkill|killall)\b` |
   | P23 | wc output parse | `\$\([[:space:]]*wc\b` |
   | P24 | touch GNU | `\btouch\b[^|;&]*(-d\b|--date)` |
   | P25 | du/df/ls GNU | `\b(du[^|;&]*-b\b|df[^|;&]*--output|ls[^|;&]*--)` |
   | P26 | other interpreters | `\b(python3?|perl|node|ruby|php)\b` |
   | P27 | /dev special | `/dev/(shm|fd/|tcp/|udp/|stdin|stdout|stderr)` |
   | P28 | hardcoded /tmp | `/tmp\b` |
   | P29 | fractional sleep | `\bsleep[[:space:]]+[0-9]*\.[0-9]` |
   | P30 | tput/stty | `\b(tput|stty)\b` |
   | P31 | uname/hostname/id | `\b(uname|hostname|whoami|id[[:space:]]+-[a-z])\b` |
   | P32 | CR handling | `\\r|\$'\\r'` |

2. `tools/porting/scan.sh` (plain bash, `#!/usr/bin/env bash`, no kbool):
   - input: the tree root (default: the folder two levels above the script);
   - files: for `.` and each of `kcl kklass kkore ktests`, `git -C R ls-files`
     → keep files ending in `.sh` or whose first line starts with `#!`;
     paths reported relative to the kbool root (`kcl/tsed/tsed.sh`);
   - skip comment-only lines (first non-blank char `#`), except for P01;
   - output TSV to stdout, header
     `pattern<TAB>file<TAB>line<TAB>unit<TAB>class<TAB>text`
     (`text` = the line, tabs→spaces, trimmed to 160 chars);
   - `unit` = `kkore` | `kklass` | `ktests` | `kbool` (root files) |
     `kcl/<dir>` (first folder under kcl);
   - `class` by the first matching rule: path contains `/tests/` → `test`;
     `/bench` or a file named `bench*.sh` → `bench`; `/docs/` or `/examples/`
     → `docs`; `ktests/tools/` → `harness`; unit is one of
     `kcl/tsed kcl/tawk kcl/tfind kcl/tgrep kcl/thead kcl/ttail kcl/tpipe kcl/tutil`
     → `wrapper`; otherwise → `core`;
   - `--summary` prints counts: one line per pattern
     `P01 shebang /bin/bash  core=N wrapper=N harness=N test=N bench=N docs=N`.
3. Run it: `bash tools/porting/scan.sh > docs/dev/launch/inventory.tsv` and
   `bash tools/porting/scan.sh --summary > docs/dev/launch/inventory_summary.txt`.
**Do not.** Fix anything the scan finds.
**Acceptance.**
- `awk -F'\t' '$1=="P01"' docs/dev/launch/inventory.tsv | wc -l` → 813 (±
  files added since 2026-10-20; explain any difference)
- the scan runs under both runtimes with identical output:
  `diff <(bash tools/porting/scan.sh) <(PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe tools/porting/scan.sh)` → empty
- runtime of a full scan (`time`) reported
- 10 random rows of `inventory.tsv` (`shuf -n 10 --random-source=<(yes)`) shown and checked by eye that `class` follows the rules.
**Timebox.** 60 min.

### L0.3 — external-tool table  [S] ready

**Goal.** Which external binaries each unit calls (unit code vs its tests).
**Read.** `tools/porting/scan.sh` (L0.2).
**Write scope.** `tools/porting/tools.sh`, `docs/dev/launch/tools.tsv`.
**Steps.**
1. `tools/porting/tools.sh`, same file set and `unit`/`class` rules as scan.sh
   (source a shared function file only if you put it inside `tools/porting/`).
   Candidate commands: `awk gawk sed grep egrep find xargs head tail cat tac sort uniq cut tr wc
   paste join comm fold column split stat date touch mktemp mkdir rmdir rm mv cp ln
   readlink realpath basename dirname chmod chown ls du df env timeout sleep nc ncat
   ps pgrep pkill kill od xxd hexdump base64 md5sum sha1sum sha256sum cksum openssl
   iconv diff cmp patch tar gzip xz curl wget git python python3 perl node ruby
   tput stty uname hostname whoami id getconf flock setsid nohup stdbuf seq shuf
   printf echo test true false yes tee`.
   A **direct** hit = the word at a command position: after line start, `;`,
   `|`, `&`, `(`, `$(`, `` ` ``, `then`, `do`, `else`, `if`, `elif`, `while`,
   `until`, `!`, `{`, `&&`, `||`, `exec`, `command`, optionally preceded by
   `VAR=value ` assignments; comment lines skipped.
   An **indirect** hit *(amended 2026-10-20: thttpserver runs `"$__ths_nc"`,
   tsed its sed through a variable)* = the word as the whole right-hand side
   of an assignment (`NAME=cmd`, quoted or not, also after
   `local`/`declare`/`readonly`/`export`), as a `${X:-cmd}` / `${X-cmd}` /
   `${X:=cmd}` / `${X=cmd}` default, or as an argument of `type -P|-p|-t`,
   `command -v|-V`, `hash`, `which`.
   `printf echo test true false` are bash builtins — count them but mark
   `builtin=yes`. The table is a candidate list: lexical, false positives
   expected (no quote stripping — it would lose `"$(…)"` calls).
2. Output `docs/dev/launch/tools.tsv`, header
   `unit<TAB>class<TAB>command<TAB>via<TAB>builtin<TAB>hits<TAB>files` (via =
   `direct`|`indirect`; files = up to 5 paths, `;`-separated, `+N` if more);
   `class` collapsed to `code` (core, wrapper, harness) and `test` (test,
   bench, docs).
**Acceptance.**
- `awk -F'\t' '$1=="kcl/tsed" && $2=="code" && $3=="sed"' docs/dev/launch/tools.tsv` → rows shown
- `awk -F'\t' '$1=="kcl/thttpserver" && $3=="nc" && $4=="indirect"' docs/dev/launch/tools.tsv` → at least one row
- list of every `(unit, command)` with `class=code`, `builtin=no` for units
  `kkore`, `kklass` shown in the report (expected short; SV reads it)
- identical output under both runtimes (as in L0.2).
**Timebox.** 60 min.

### L0.4 — bash feature map  [S] ready

**Goal.** Where version-dependent bash features are used.
**Read.** `tools/porting/scan.sh`.
**Write scope.** `tools/porting/bashfeatures.tsv`, `tools/porting/bashfeat.sh`,
`docs/dev/launch/bashfeatures.tsv`, `docs/dev/launch/bashfeatures_summary.txt`.
**Steps.**
1. `tools/porting/bashfeatures.tsv` (`id<TAB>min<TAB>feature<TAB>regex`), rows:

   | id | min | feature | regex (ERE) |
   |---|---|---|---|
   | F01 | 4.0 | associative arrays | `declare[[:space:]]+-[a-zA-Z]*A|local[[:space:]]+-[a-zA-Z]*A` |
   | F02 | 4.0 | case modification | `\$\{[^}]*(,,|\^\^)` |
   | F03 | 4.0 | coproc | `\bcoproc\b` |
   | F04 | 4.0 | ;& / ;;& | `;;&|;&` |
   | F05 | 4.0 | BASHPID | `BASHPID` |
   | F06 | 4.1 | {var}> fd allocation | `\{[a-zA-Z_][a-zA-Z0-9_]*\}[<>]` |
   | F07 | 4.2 | declare -g | `declare[[:space:]]+-[a-zA-Z]*g` |
   | F08 | 4.2 | test -v | `\[\[?[[:space:]]+-v[[:space:]]` |
   | F09 | 4.2 | printf %(fmt)T | `%\([^)]*\)T` |
   | F10 | 4.2 | lastpipe | `lastpipe` |
   | F11 | 4.3 | namerefs | `(declare|local|typeset)[[:space:]]+-[a-zA-Z]*n` |
   | F12 | 4.3 | wait -n | `wait[[:space:]]+-n` |
   | F13 | 4.3 | negative subscripts | `\[-[0-9]+\]` |
   | F14 | 4.4 | @Q @E @P @A @a transforms | `@[QEPAa]\}` |
   | F15 | 4.4 | local - | `local[[:space:]]+-([[:space:]]|$)` |
   | F16 | 4.4 | mapfile -d / readarray -d | `(mapfile|readarray)[^;|&]*-d` |
   | F17 | 4.4 | inherit_errexit | `inherit_errexit` |
   | F18 | 5.0 | EPOCHREALTIME / EPOCHSECONDS | `EPOCH(REALTIME|SECONDS)` |
   | F19 | 5.0 | BASH_ARGV0 | `BASH_ARGV0` |
   | F20 | 5.0 | localvar_inherit / assoc_expand_once | `localvar_inherit|assoc_expand_once` |
   | F21 | 5.1 | wait -p | `wait[[:space:]][^;|&]*-p` |
   | F22 | 5.1 | @U @u @L @K transforms | `@[UuLK]\}` |
   | F23 | 5.1 | SRANDOM | `SRANDOM` |
   | F24 | 5.2 | @k transform | `@k\}` |
   | F25 | 5.2 | patsub_replacement | `patsub_replacement` |
   | F26 | 5.2 | globskipdots / varredir_close / noexpand_translation | `globskipdots|varredir_close|noexpand_translation` |
   | F27 | 5.3 | ${ cmd; } / ${| cmd; } funsub | `\$\{[[:space:]|]` |
   | F28 | 5.3 | BASH_MONOSECONDS / GLOBSORT / array_expand_once | `BASH_MONOSECONDS|GLOBSORT|array_expand_once|BASH_TRAPSIG` |

2. `tools/porting/bashfeat.sh`: same file set, unit and class rules as
   scan.sh; output `feature<TAB>min<TAB>file<TAB>line<TAB>unit<TAB>class<TAB>text`
   and `--summary`: per feature `F18 5.0 EPOCH… core=N wrapper=N harness=N test=N bench=N docs=N`.
3. Write the two output files.
**Acceptance.**
- `awk -F'\t' '$1=="F18" && $6!="test"' docs/dev/launch/bashfeatures.tsv | cut -f3 | sort -u | wc -l` reported (2026-10-20 probe: 22 files with EPOCHREALTIME, tests excluded)
- every F21–F28 row with class `core`/`wrapper`/`harness` printed in the report (SV reads them)
- identical output under both runtimes.
**Note.** Static matching cannot find behaviour differences; L4 measures those.
**Timebox.** 45 min.

### L0.5 — PORTING.md  [O]

Opus: from L0.2–L0.4 write `docs/dev/PORTING.md` — hazards ranked
(core first), the netcat question (what thttpserver needs from nc; which nc
flavours exist on each target), OG1 options with numbers, and the **final
package lists** per OS for L1 (`apt`, `dnf`, `apk` for `clean-gnu`, `pkg`
for `clean-gnu`). SV pastes the package lists into cards L1.2–L1.4.

### L0.7 — comma-locale fix for EPOCHREALTIME  [S] ready (run with no lab VM running)

**Goal.** Under a locale whose decimal separator is a comma (`ru_RU`, `de_DE`)
bash prints `EPOCHREALTIME` as `1792492915,887987`; every split on `.` then
computes garbage (PORTING.md H7). Make every split locale-proof.
**Read.** `docs/dev/PORTING.md` (H7 only), `ktests/docs/GATE_FOR_AGENTS.md`.
**Write scope.** tracked `*.sh` files of the five repos — only the
expressions the rules below name.
**Rules** (the tree already uses the safe forms `${EPOCHREALTIME/[.,]/}` ×13
and `${EPOCHREALTIME//[!0-9]/}` ×30 — keep them):
- R1 `${EPOCHREALTIME/./}` → `${EPOCHREALTIME/[.,]/}` (28 sites at kbool 2817b2b).
- R2 for a variable NAME assigned from `$EPOCHREALTIME` / `${EPOCHREALTIME}`
  in the same file: `${NAME/./}` → `${NAME/[.,]/}`, `${NAME//./}` →
  `${NAME//[.,]/}`, `${NAME%.*}` → `${NAME%[.,]*}`, `${NAME#*.}` → `${NAME#*[.,]}`,
  `${NAME%%.*}` → `${NAME%%[.,]*}`.
- R3 `${EPOCHREALTIME%.*}` / `${EPOCHREALTIME#*.}` / `%%.*` → the `[.,]` forms as in R2.
- Anything else where the separator of an EPOCHREALTIME value matters
  (passed to `printf %f`, awk, bc, compared as a string, `${X/,/.}`
  conversions, a NAME assigned in another file) → **do not change**; list it
  (file:line, the line) in the report under OPEN.
**Steps.**
1. Red first: with no change yet, run the gate under the comma locale on the
   suites `ktests kcl/tstopwatch kcl/thttpserver kcl/dateutils`:
   `LC_ALL=ru_RU.UTF-8 bash $G --out "$SCRATCH/g_red" ktests kcl/tstopwatch kcl/thttpserver kcl/dateutils`
   (first check that the gate passes `LC_ALL` into its cells — read gate.sh's
   env handling; if it scrubs it → BLOCKED). Record the verdict and the
   [FAIL] lines (a red result is expected but not required — record what is).
2. Apply R1–R3; list every change (file:line, before → after).
**Acceptance.**
- `git grep -nE 'EPOCHREALTIME/\./|EPOCHREALTIME%\.|EPOCHREALTIME#\*\.'` in all five repos → no hits
- full phase gate, both runtimes, English/C locale: `bash $G --rerun-failed 1 --compare LAST all` → PASS, totals unchanged
- full phase gate, both runtimes, comma locale: `LC_ALL=ru_RU.UTF-8 bash $G --rerun-failed 1 all` → PASS (any FAIL: report it with its [FAIL] lines; do not fix beyond R1–R3)
- the red-first record from step 1 next to the green results.
**Timebox.** 1 h + three gates (~1.5 h).

---

## L1 — the VM lab

### L1.1 — vmlab.sh core  [S] ready

**Goal.** One host-side script that drives the lab VMs safely; testable without VMs.
**Read.** This card; `ktests/docs/GATE_FOR_AGENTS.md` (how gate is called and read).
**Write scope.** `tools/vmlab/vmlab.sh`, `tools/vmlab/vms.conf`,
`tools/vmlab/README.md`, `tools/vmlab/tests/run.sh`.
**Spec.**
- Plain bash (`#!/usr/bin/env bash`), no kbool, runs under Git-bash.
  `VBOXMANAGE` env, default `"/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"`.
  Paths given to VBoxManage pass through `cygpath -w`.
- `vms.conf` — TSV with a header line, exactly:
  ```
  name	os	port	mem	cpus	disk_gb	bash	user
  kb-ubuntu	ubuntu-24.04	2221	4096	4	20	/usr/bin/bash	kb
  kb-debian	debian-13	2222	4096	4	20	/usr/bin/bash	kb
  kb-fedora	fedora	2223	4096	4	20	/usr/bin/bash	kb
  kb-alpine	alpine	2224	2048	4	12	/bin/bash	kb
  kb-freebsd	freebsd	2225	4096	4	20	/usr/local/bin/bash	kb
  ```
- **Safety:** every command that takes NAME refuses (rc 2, message) a name
  that is not a `name` row of vms.conf or does not match `^kb-[a-z0-9]+$`.
- SSH: `ssh -i ~/.ssh/kbool_vmlab -p PORT -o BatchMode=yes -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=~/.ssh/kbool_vmlab_known_hosts
  USER@127.0.0.1`; every ssh/scp call wrapped in `timeout -k 30 N`.
- Commands (`vmlab.sh CMD NAME [args]`):

  | cmd | behaviour |
  |---|---|
  | `status` (no NAME) | one line per vms.conf row: name, `VMState` from `showvminfo --machinereadable` (or `absent`), snapshots list |
  | `up NAME` | if not running: `startvm NAME --type headless`; wait ≤ `VMLAB_BOOT_WAIT` (180) s until `ssh … true` succeeds; rc 0 / 11 (timeout) |
  | `down NAME` | `controlvm NAME acpipowerbutton`; wait ≤ 60 s for `VMState="poweroff"`; else `controlvm NAME poweroff`; rc 0 |
  | `reset NAME [SNAP]` | `down`; `snapshot NAME restore SNAP` (default `clean`); rc 12 if SNAP absent |
  | `snapshot NAME SNAP [--replace]` | `down`; `snapshot NAME take SNAP`; existing SNAP → rc 13 unless `--replace` (then `snapshot NAME delete SNAP` first) |
  | `run NAME -- CMD…` | ssh, runs CMD (as one string, `printf %q`-joined), timeout `VMLAB_TIMEOUT` (600) s; rc = CMD's rc |
  | `shell NAME` | interactive ssh (for the owner; not used by agents) |
  | `sync NAME [--from-github [--ref R]]` | default: tar of the working tree → `~/kbool` in the VM (below); `--from-github`: `git clone --recurse-submodules [--branch R] https://github.com/Keksov/kbool.git ~/kbool` in the VM (removes an old `~/kbool` first) |
  | `fetch NAME REMOTE_DIR HOST_DIR` | `ssh … tar -cf - -C REMOTE_DIR .` piped into `tar -xf - -C HOST_DIR` |
  | `gate NAME [--snapshot S] [--from-github] [--out DIR] [-- GATE_ARGS…]` | `reset NAME S` → `up` → `sync` → write `~/vm.txt` (`uname -a`, `/etc/os-release` or `freebsd-version`, `BASH --version` first line, host repo SHAs passed in) → `run`: `KT_GATE_BASHES=<bash col> timeout -k 120 9000 bash ktests/tools/gate.sh --out ~/gate-out GATE_ARGS` (default GATE_ARGS `--rerun-failed 1 all`) with `VMLAB_TIMEOUT=9300` → `fetch ~/gate-out` and `~/vm.txt` into OUT → `down`; rc = the gate's rc |

- Working-tree tar (`sync`): for the root and each submodule path (from
  `git submodule status`): `git -C R ls-files -co --exclude-standard -z`,
  dropping entries that are not regular files (deleted files, submodule
  gitlinks), prefixed with the submodule path; `tar --null -T - -cf -` from
  the root; remote side:
  `rm -rf ~/kbool.new && mkdir ~/kbool.new && tar -xf - -C ~/kbool.new && rm -rf ~/kbool && mv ~/kbool.new ~/kbool`.
  The host SHAs (`git -C R rev-parse HEAD` + `-dirty` if `git -C R status --porcelain` is non-empty) go into vm.txt.
- OUT default: `${TMPDIR:-$LOCALAPPDATA/Temp}/kb-vmlab/<YYYYmmdd-HHMMSS>-<name>-<snap>`; printed as the first output line `vmlab out=OUT`.
- **Cleanup trap**: on EXIT/INT/TERM, `down` every VM this invocation started
  (not ones that were already running). `shell` excluded.
- `VMLAB_DRY=1`: every VBoxManage/ssh/tar call is printed as one line
  `DRY: <argv>` instead of executed; VBoxManage queries answer from
  `VMLAB_DRY_STATE` (default `poweroff`), ssh `true` succeeds, snapshot list
  is `clean` — so all commands can be tested without VMs.
- rc table in `--help` and README: 0 ok, 2 usage/refused name, 10 VBoxManage
  failed, 11 boot wait timeout, 12 snapshot absent, 13 snapshot exists, else
  the remote command's rc.
**Tests.** `tools/vmlab/tests/run.sh` (plain bash, prints `PASS n/n` or the
failures, rc 0/1), all under `VMLAB_DRY=1`: refused names (`Ubuntu 24.02.2`,
`OLHCV`, `kb-unknown`, `../x`); `status` lines; `up` order of calls; `down`
fallback to poweroff when state stays `running`; `reset` restores `clean`;
`snapshot` rc 13 and `--replace`; `gate` call order (reset→start→ssh sync→ssh
gate→ssh fetch→acpipowerbutton) and the GATE_ARGS default; the file list of
`sync` contains `kbool.sh`, `kcl/tsed/tsed.sh`, an untracked non-ignored test
file you create in `$SCRATCH`-backed temp repo (build a tiny temp git repo with
one submodule in `$SCRATCH` for this — never modify the real tree), and no
`.git` entries; the trap powers off a VM started by the invocation.
**Do not.** Create, start or touch any real VM (no VM exists yet).
**Acceptance.**
- `bash tools/vmlab/tests/run.sh` → `PASS n/n` under both runtimes
- `bash tools/vmlab/vmlab.sh up 'Ubuntu 24.02.2'; echo rc=$?` → refusal message, `rc=2`, and `VBoxManage list runningvms` unchanged
- `VMLAB_DRY=1 bash tools/vmlab/vmlab.sh gate kb-ubuntu` output shown in full.
**Timebox.** 2 h.

### L1.1b — vmlab run: single-string commands  [S] ready

**Goal.** `vmlab.sh run NAME -- 'cmd1 | cmd2; cmd3'` must run that string as a
remote shell command line (today every word is `printf %q`-quoted, so one
string becomes one command name — found in L1.2).
**Read.** `tools/vmlab/vmlab.sh` (`cmd_run`), `tools/vmlab/README.md`, `tools/vmlab/tests/run.sh`.
**Write scope.** those three files.
**Rule.** After `--`: exactly ONE argument → sent verbatim as the remote
command line (no quoting); TWO OR MORE arguments → as today (`printf %q`
per word, joined by spaces). No other behaviour change; `gate`'s internal
calls stay as they are.
**Steps.** Implement in `cmd_run`; update the README table row and the
"Note:" paragraph (≈ line 200) to state the rule with one example of each
form; DRY tests: one-string form → the DRY ssh line ends with the string
unchanged (e.g. `echo a | tr a b; true`); multi-word form with an argument
containing a space and a `;` → quoted as before.
**Acceptance.** `bash tools/vmlab/tests/run.sh` → `PASS n/n` (n > 124) on
both runtimes; the two new test names; `VMLAB_DRY=1 bash tools/vmlab/vmlab.sh run kb-ubuntu -- 'uname -a; echo $0'` output shown.
**Timebox.** 30 min.

### L1.1c — vmlab: gate --env, down via ssh  [S] ready

**Goal.** (1) A gate run in a VM under a given environment (L2.4's comma-locale
run). (2) `down` without the 60-s ACPI wait when the guest is reachable.
**Read.** `tools/vmlab/vmlab.sh`, `tools/vmlab/README.md`, `tools/vmlab/tests/run.sh`.
**Write scope.** those three files.
**Spec.**
- `gate NAME … --env NAME=VALUE` (repeatable, before `--`): NAME must match
  `^[A-Za-z_][A-Za-z0-9_]*$` (else rc 2); the pairs are prepended to the
  remote gate command as `NAME=<printf %q of VALUE>` right before
  `KT_GATE_BASHES=…`; they are also written into `~/vm.txt` (`env: NAME=VALUE`).
- `down NAME`: if the VM is running and `ssh … true` answers within the
  normal connect timeout, first run `sudo -n poweroff || doas -n poweroff || sudo -n shutdown -p now`
  (whichever works; ssh exit status ignored — the connection drops), then
  wait ≤ `VMLAB_DOWN_WAIT` for `poweroff` as today; only then ACPI, then hard
  poweroff, as today.
- DRY tests: `--env LC_ALL=de_DE.UTF-8` appears %q-quoted in the remote gate
  line and in vm.txt; a bad NAME → rc 2; `down` order: ssh poweroff → wait →
  (no ACPI when state becomes poweroff); `down` when ssh fails → ACPI path as before.
**Acceptance.** `bash tools/vmlab/tests/run.sh` PASS n/n (n > 127) on both
runtimes; live: `vmlab.sh up kb-alpine && time vmlab.sh down kb-alpine` and
the same for kb-freebsd (both < 20 s, literal output); `VMLAB_DRY=1 … gate kb-debian --env LC_ALL=de_DE.UTF-8 -- kkore` shown.
**Timebox.** 45 min.

### L1.2 — kb-ubuntu: create + provision  [S] ready after L0.6 (package list)

**Goal.** A clean Ubuntu 24.04 lab VM with SSH key access and snapshot `clean`.
**Read.** `tools/vmlab/README.md`, `tools/vmlab/vms.conf`.
**Write scope.** `tools/vmlab/create/ubuntu.sh`, `tools/vmlab/provision/apt.sh`,
`tools/vmlab/README.md` (section "kb-ubuntu"); outside the tree:
`C:\var\vbox\kb-lab\` (VM + ISO), `~/.ssh/kbool_vmlab*`.
**Steps.**
1. If `~/.ssh/kbool_vmlab` does not exist: `ssh-keygen -t ed25519 -N '' -C kbool-vmlab -f ~/.ssh/kbool_vmlab`.
2. ISO: the newest `ubuntu-24.04.*-live-server-amd64.iso` listed at
   `https://releases.ubuntu.com/24.04/`; download it and `SHA256SUMS` from
   the same folder into `C:\var\vbox\kb-lab\iso\`; `sha256sum -c --ignore-missing`
   must say `OK`.
3. `create/ubuntu.sh` (idempotent: refuses if `kb-ubuntu` exists, rc 13):
   `createvm --name kb-ubuntu --ostype Ubuntu_64 --basefolder C:\var\vbox\kb-lab --register`;
   `modifyvm kb-ubuntu --memory 4096 --cpus 4 --nic1 nat --nat-pf1 "ssh,tcp,127.0.0.1,2221,,22" --audio-enabled off --usb off`;
   a 20 GB dynamic VDI (`createmedium disk --size 20480 --variant Standard`) on a SATA controller;
   `unattended install kb-ubuntu --iso=<iso> --user=kb --password-file=<a file in $SCRATCH with a random 20-char password, deleted after> --full-user-name=kb --hostname=kb-ubuntu.lab --time-zone=UTC --locale=en_US --install-additions --start-vm=headless`.
4. Wait (bounded: 45 min, poll `showvminfo` every 30 s) until the guest
   additions report `GuestAdditionsRunLevel=2` or higher.
5. With `guestcontrol kb-ubuntu run --username kb --passwordfile <file> --exe /bin/sh -- -c '…'`:
   install `~/.ssh/kbool_vmlab.pub` into `/home/kb/.ssh/authorized_keys` (700/600), then
   `vmlab.sh run kb-ubuntu -- true` must succeed.
6. `provision/apt.sh` (copied with scp, run as `sudo -S` once with the password,
   later NOPASSWD): `kb ALL=(ALL) NOPASSWD:ALL` in `/etc/sudoers.d/kb` (0440,
   `visudo -cf`); `DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y <PKG>`;
   `systemctl disable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer`;
   sshd `PasswordAuthentication no`; `apt-get clean`; the login shell of `kb`
   is bash (`chsh -s /usr/bin/bash kb` if `getent passwd kb` shows another) —
   on EVERY lab VM, because `vmlab.sh run` quotes with `printf %q`.
   PKG (final, from PORTING.md §7 at L0.6):
   `bash git coreutils sed grep findutils diffutils gawk procps util-linux perl curl openssl netcat-openbsd tzdata locales socat ncat netcat-traditional nodejs python3 uuid-runtime`
   — a missing name among the last six is recorded, not substituted; any other
   missing name → BLOCKED. mawk stays the default `awk`. `nc` must still
   resolve to OpenBSD nc after ncat/netcat-traditional are installed
   (`update-alternatives --set nc /bin/nc.openbsd` if not; record it).
   Locales: `locale-gen en_US.UTF-8 de_DE.UTF-8 ru_RU.UTF-8`.
7. Record versions into the README section: `lsb_release -d`, `bash --version | head -1`,
   `dpkg-query -W` of every installed package of the list, `locale -a`,
   `readlink -f "$(command -v nc)"`, and the output of
   `LC_ALL=ru_RU.UTF-8 bash -c 'echo $EPOCHREALTIME'` (must show a comma).
8. `vmlab.sh snapshot kb-ubuntu clean`.
**Stop if.** Unattended install fails twice (VM never reaches step 4/5 in
45 min) → delete only `kb-ubuntu` (`unregistervm kb-ubuntu --delete`), write
`tools/vmlab/README.md` section "kb-ubuntu — manual install" as a numbered
checklist for the owner (ISO path, VM settings as in step 3, installer
choices, then steps 5–8 as commands), report BLOCKED.
**Acceptance.**
- `bash tools/vmlab/vmlab.sh status` shows `kb-ubuntu poweroff … clean`
- `bash tools/vmlab/vmlab.sh reset kb-ubuntu && bash tools/vmlab/vmlab.sh up kb-ubuntu && bash tools/vmlab/vmlab.sh run kb-ubuntu -- 'bash --version | head -1; sudo -n true && echo sudo-ok' ; bash tools/vmlab/vmlab.sh down kb-ubuntu`
- `bash tools/vmlab/vmlab.sh sync kb-ubuntu` then `run kb-ubuntu -- 'ls ~/kbool; grep -rlI $(printf "\r") ~/kbool --include=*.sh | wc -l'` → the tree listing and `0`
- the password file is gone; `VBoxManage list runningvms` shows no kb-*.
**Timebox.** 2 h (most of it waiting).

### L1.3 — kb-debian, kb-fedora  [S] ready after L1.2

As L1.2 with these differences; reuse `create/ubuntu.sh` structure as
`create/debian.sh`, `create/fedora.sh`; provisioning `provision/apt.sh`
(Debian) and `provision/dnf.sh` (Fedora).

| | kb-debian | kb-fedora |
|---|---|---|
| ISO | newest `debian-13.*-amd64-netinst.iso` from `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/` + `SHA256SUMS` there | newest Fedora Server `*-x86_64-*.iso` (netinst) from `https://download.fedoraproject.org/pub/fedora/linux/releases/<newest>/Server/x86_64/iso/` + its `*-CHECKSUM` |
| ostype | `Debian_64` | `Fedora_64` |
| port | 2222 | 2223 |
| packages | as kb-ubuntu (same list and rules; locales through `/etc/locale.gen` + `locale-gen`; minimal installs lack `sudo` — install it first via `su -` on the console or the unattended post-install), without `unattended-upgrades` handling (disable `apt-daily*` timers only) | `bash git-core coreutils sed grep findutils diffutils gawk procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru socat nodejs python3` (last three: record if missing); record which binary `nc` is; `systemctl disable --now dnf-makecache.timer` |
| versions recorded | `cat /etc/debian_version`, `dpkg-query -W …` | `cat /etc/fedora-release`, `rpm -q …` |

Write scope, stop rule, acceptance: as L1.2 per VM. **Timebox.** 3 h.

### L1.3b — kb-fedora from the cloud image  [S] ready

**Why.** VBox 7.1.12 `unattended install` rejects Fedora 44 ("Unknown guest OS
major version '44'", deterministic — L1.3). No installer: boot the official
cloud image; cloud-init takes its config from a host HTTP server named in the
VM's SMBIOS serial number (NoCloud datasource).
**Read.** `tools/vmlab/README.md` (kb-ubuntu, kb-debian sections),
`tools/vmlab/create/debian.sh`, the untracked drafts
`tools/vmlab/create/fedora.sh` + `tools/vmlab/provision/dnf.sh` (L1.3, never run).
**Write scope.** `tools/vmlab/create/fedora.sh` (rewrite), `tools/vmlab/provision/dnf.sh`,
`tools/vmlab/README.md` (section kb-fedora; keep "kb-fedora -- manual install"
as the fallback); outside: `C:\var\vbox\kb-lab\` (`kb-fedora\`, `img\`), the
lab known_hosts entry for port 2223, `$SCRATCH`.
**Steps.**
1. Image: from `https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/`
   the `Fedora-Cloud-Base-Generic-44-*.x86_64.qcow2` and its `*-CHECKSUM`;
   `sha256sum -c --ignore-missing` → OK; into `C:\var\vbox\kb-lab\img\`.
2. Convert to VDI: first `VBoxManage clonemedium <qcow2> <vdi> --format VDI`.
   If VirtualBox cannot read it: convert inside **kb-ubuntu** —
   `vmlab.sh reset kb-ubuntu && up`, `sudo apt-get install -y qemu-utils`,
   copy the qcow2 in (scp with the lab key, port 2221), `qemu-img convert -O vdi`,
   copy the VDI back, then `vmlab.sh reset kb-ubuntu` (restores `clean`, so
   kb-ubuntu is unchanged) and `down`. No other converter; no binaries
   downloaded to the host.
3. VM: `createvm --name kb-fedora --ostype Fedora_64 --basefolder C:\var\vbox\kb-lab --register`;
   4096 MB, 4 CPUs, BIOS firmware, `--nic1 nat --nat-pf1 "ssh,tcp,127.0.0.1,2223,,22"`,
   audio/usb off; serial console to a file for debugging:
   `--uart1 0x3F8 4 --uart-mode1 file <$SCRATCH win path>\fedora-serial.log`;
   the VDI moved into the VM folder, `modifymedium --resize 20480`, attached on SATA.
4. Seed: `$SCRATCH/seed/meta-data` (`instance-id: kb-fedora-1`, `local-hostname: kb-fedora`)
   and `$SCRATCH/seed/user-data`:
   ```
   #cloud-config
   users:
     - name: kb
       shell: /bin/bash
       sudo: "ALL=(ALL) NOPASSWD:ALL"
       lock_passwd: true
       ssh_authorized_keys:
         - <the line of ~/.ssh/kbool_vmlab.pub>
   ssh_pwauth: false
   ```
   `VBoxManage setextradata kb-fedora "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial" "ds=nocloud;s=http://10.0.2.2:8099/"`.
   Host server (the only background process of this card): one
   `run_in_background` call `timeout -k 5 1800 python -m http.server 8099 --bind 127.0.0.1 --directory <seed dir>`;
   record its pid; stop it (by that pid) as soon as cloud-init has fetched the
   seed (its log shows `GET /user-data` and `GET /meta-data`).
5. `vmlab.sh up kb-fedora` (raise `VMLAB_BOOT_WAIT` to 900 for this first
   boot); check VBox.log for `AMD-V`; then over ssh: `provision/dnf.sh` with
   sudo (the L1.3 list: `bash git-core coreutils sed grep findutils diffutils gawk procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru socat nodejs python3`
   — last three recorded if missing; `systemctl disable --now dnf-makecache.timer`);
   record which binary `nc` is; SELinux mode (`getenforce`, leave as shipped);
   then `sudo cloud-init clean` is NOT run (keep the instance); remove the
   DMI serial extradata (`setextradata kb-fedora "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"` with no value) so later boots do not look for the seed; `vmlab.sh snapshot kb-fedora clean`.
6. README section "kb-fedora": the recipe, versions (`cat /etc/fedora-release`,
   kernel, `bash --version`, `rpm -q` of the list, `locale -a`, the ru_RU
   `EPOCHREALTIME` line, `getenforce`), the VBox.log engine line.
**Stop if.** cloud-init never fetches the seed within 15 min of boot (read
`fedora-serial.log` and the HTTP server log) after one retry with a fixed
cause → delete only kb-fedora, report BLOCKED with the serial-log excerpt.
**Acceptance.** As L1.2 for kb-fedora (status `kb-fedora poweroff clean`;
reset/up/run `'echo "$0 $BASH_VERSION"; sudo -n true && echo sudo-ok'`/down;
up/sync/run `'ls ~/kbool; grep -rlI $(printf "\r") ~/kbool --include=*.sh | wc -l'`/down);
the HTTP server pid is gone; kb-ubuntu still `poweroff clean` (if step 2's
fallback was used: `run kb-ubuntu -- 'command -v qemu-img || echo absent'` after
reset → `absent`).
**Timebox.** 2 h.

### L1.4 — kb-freebsd, kb-alpine  [S] ready after L1.2

**Goal.** The two non-GNU VMs, each with snapshots `clean` (no GNU tools
beyond bash+git) and `clean-gnu` (GNU tools added).
**Write scope.** `tools/vmlab/create/freebsd.sh`, `tools/vmlab/create/alpine.sh`,
`tools/vmlab/provision/pkg.sh`, `tools/vmlab/provision/apk.sh`,
`tools/vmlab/README.md` (their sections); `C:\var\vbox\kb-lab\`.
**kb-freebsd.**
1. Image: newest `FreeBSD-15.*-RELEASE-amd64-ufs.vmdk.xz` from
   `https://download.freebsd.org/releases/VM-IMAGES/<newest 15.x>-RELEASE/amd64/Latest/`
   + `CHECKSUM.SHA256` there; verify; `xz -dk`.
2. `createvm` (`--ostype FreeBSD_64`), `--nat-pf1 "ssh,tcp,127.0.0.1,2225,,22"`,
   attach the VMDK after `clonemedium … --format VDI` into the VM folder and
   `modifymedium --resize 20480`; start headless.
3. Console scripting: wait 120 s; `controlvm kb-freebsd keyboardputstring`
   `root` + Enter (no password in the official image), then one command per
   call, Enter after each, 5 s apart:
   `sysrc sshd_enable=YES` · `pw useradd kb -m -G wheel -s /bin/sh` ·
   `mkdir -p /home/kb/.ssh` · `echo '<the .pub line>' > /home/kb/.ssh/authorized_keys` ·
   `chown -R kb:kb /home/kb/.ssh && chmod 700 /home/kb/.ssh && chmod 600 /home/kb/.ssh/authorized_keys` ·
   `service sshd start`.
   Check with `vmlab.sh run kb-freebsd -- true`. Screenshots for debugging:
   `controlvm kb-freebsd screenshotpng $SCRATCH/fb.png` (read it with the Read tool).
4. Still in the root console session of step 3 (kb has no sudo yet), type:
   `env ASSUME_ALWAYS_YES=yes pkg bootstrap && pkg install -y sudo bash git` ·
   `echo 'kb ALL=(ALL) NOPASSWD: ALL' > /usr/local/etc/sudoers.d/kb && chmod 440 /usr/local/etc/sudoers.d/kb` ·
   `pw usermod kb -s /usr/local/bin/bash` · `exit`. Then over ssh run
   `provision/pkg.sh` with `sudo` (sshd
   `PasswordAuthentication no`, `pkg clean -y`); check `sudo -n true`;
   `vmlab.sh snapshot kb-freebsd clean`.
   **Before** the `clean` snapshot: add `fdesc /dev/fd fdescfs rw 0 0` to
   `/etc/fstab` and `sudo mount /dev/fd` (process substitution needs it, H14);
   check `bash -c 'cat <(echo ok)'` → `ok`.
5. `clean-gnu`: from `clean`, `sudo pkg install -y coreutils gsed gawk findutils gnugrep diffutils netcat curl perl5 socat`;
   a package that does not exist is recorded, not substituted; record the
   binary names (`ghead gstat gsed gfind ggrep`/`grep`, the netcat binary);
   `vmlab.sh snapshot kb-freebsd clean-gnu`.
**kb-alpine.**
1. ISO: newest `alpine-virt-*-x86_64.iso` from
   `https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/` + its `.sha256`.
2. `createvm` (`--ostype Linux_64`), 2048 MB, 12 GB disk, `--nat-pf1 "ssh,tcp,127.0.0.1,2224,,22"`, ISO on the DVD slot, boot.
3. Console: `root` + Enter; type an answer file with `cat > /tmp/a <<'EOF'` …
   `EOF`, content:
   ```
   KEYMAPOPTS="us us"
   HOSTNAMEOPTS="-n kb-alpine"
   INTERFACESOPTS="auto lo
   iface lo inet loopback
   auto eth0
   iface eth0 inet dhcp"
   DNSOPTS="-d lab 10.0.2.3"
   TIMEZONEOPTS="-z UTC"
   PROXYOPTS="none"
   APKREPOSOPTS="-1"
   USEROPTS="-a -u kb"
   USERSSHKEY="<the .pub line>"
   SSHDOPTS="-c openssh"
   NTPOPTS="-c busybox"
   DISKOPTS="-m sys /dev/sda"
   ```
   then `ERASE_DISKS=/dev/sda setup-alpine -e -f /tmp/a`; answer any
   remaining prompt only if its screenshot shows a yes/no about erasing
   `/dev/sda` (`y`); `poweroff`; detach the ISO; boot from disk.
4. `provision/apk.sh` via ssh + `doas` (setup-alpine `-a` makes kb an admin
   with doas): `apk add bash git`; kb's login shell → `/bin/bash`
   (`doas sed -i 's#^\(kb:.*:\)[^:]*$#\1/bin/bash#' /etc/passwd`, checked with
   `grep '^kb:' /etc/passwd`); `clean`. Then `apk add coreutils sed grep findutils diffutils gawk procps-ng util-linux perl curl openssl netcat-openbsd tzdata`
   (`procps-ng` missing → try `procps` and record it) → `clean-gnu`.
**Stop if.** Either VM is not reachable by SSH after 90 min of attempts →
delete only that VM, write its manual checklist section, report BLOCKED
(the other VM may still be DONE).
**Acceptance.** For each VM and each snapshot: `reset NAME SNAP`, `up`,
`run -- 'echo "$0 $BASH_VERSION"; bash --version | head -1; command -v gsed gawk gfind sed awk find'`
(the first line must show a bash login shell), `down`.
**Timebox.** 4 h.

---

## L2 — Linux

### L2.2 — shebangs + exec bit  [S] ready

**Goal.** Scripts run where bash is not `/bin/bash`; entry points are executable.
**Read.** `docs/dev/launch/inventory.tsv` (P01 rows).
**Write scope.** line 1 of every tracked file whose line 1 is exactly
`#!/bin/bash`, in all five repos; the index mode of every tracked file whose
first two bytes are `#!`; *(added at L0.6 from PORTING.md)* the literal
string `#!/bin/bash` → `#!/usr/bin/env bash` in: the header assertions
`kcl/tests/001_UnitFiles.sh:67`, `kklass/tests/141_UnitHeaders.sh:85`,
`kkore/tests/013_SystemUnitHeaders.sh:46`, and the emitted shebangs in
`kklass/kklass_compiler.sh:260`, `kklass/kklass_kkp.sh:336`, `:346` (line
numbers as of kbool 2817b2b — locate by content). Any OTHER test that fails
after the change because it expects `#!/bin/bash` → BLOCKED with the list.
**Steps.**
1. Per repo R (`.`, `kcl`, `kklass`, `kkore`, `ktests`):
   `git -C R ls-files -z` → files with a line that is exactly `#!/bin/bash`
   (line 1 **or any other line** — *amended 2026-10-21*: 25 such lines sit in
   heredocs that tests write out and execute directly) →
   `sed -i 's|^#!/bin/bash$|#!/usr/bin/env bash|' FILE`.
   Lines `#!/bin/bash <args>`: do not change, list them.
2. Per repo: every tracked file whose first two bytes are `#!` →
   `git -C R update-index --chmod=+x FILE` (already +x: skip).
**Do not.** Change any other line or file; touch submodule pointers.
**Acceptance.**
- `bash tools/porting/scan.sh --summary | grep '^P01'` → all counts 0
- per repo: `git -C R diff -U0 | grep -E '^[-+][^-+]' | sort | uniq -c` → only
  `-#!/bin/bash` and `+#!/usr/bin/env bash` lines, equal counts
- per repo: `git -C R diff --summary | grep -c 'mode change 100644 => 100755'` and
  `git -C R ls-files -s | awk '$1=="100755"' | wc -l` reported
- phase gate on both Windows runtimes: `bash $G --rerun-failed 1 --compare LAST all` → PASS, totals unchanged.
**Timebox.** 1 h + gate.

### L2.3 — bash version guard  [S] DONE — *amended twice in review (2026-10-21): POSIX-mode refusal added; the loaded fast-path moved before the guard (`[ "${__KK_BASH_OK-}" = 1 ] && [[ …@a… ]]`) because parsing the guard block cost +40–80 µs per re-source. The code below is the first draft; the final text is in kbool.sh.*

**Goal.** A clear refusal on an unsupported shell, before any newer syntax runs.
**Read.** `kbool.sh` lines 1–60.
**Write scope.** `kbool.sh`; `kkore/README.md` (one sentence in the limitations section, given below).
**Steps.**
1. Insert this block into `kbool.sh` **directly after the header comment and
   before** the comment line `# The loader guard (C3): …`, unchanged:
   ```bash
   # The bash guard: POSIX syntax only, so it runs (and refuses) under any sh
   # and any old bash before a line of newer syntax is reached. The floor is
   # __KK_BASH_MIN (major.minor); every later command may assume it.
   if [ -z "${BASH_VERSION-}" ]; then
       echo "kbool: bash is required (this shell is not bash)" >&2
       return 2 2>/dev/null || exit 2
   fi
   __KK_BASH_MIN=5.2
   if [ "${BASH_VERSINFO[0]}" -lt "${__KK_BASH_MIN%.*}" ] || {
          [ "${BASH_VERSINFO[0]}" -eq "${__KK_BASH_MIN%.*}" ] &&
          [ "${BASH_VERSINFO[1]}" -lt "${__KK_BASH_MIN#*.}" ]; }; then
       echo "kbool: bash >= $__KK_BASH_MIN is required, this is $BASH_VERSION ($BASH)" >&2
       echo "kbool: on macOS install a current bash (brew install bash) and run scripts with it" >&2
       return 2 2>/dev/null || exit 2
   fi
   ```
2. `kkore/README.md` §6 (limitations): add the sentence
   "`kbool.sh` refuses (rc 2, two lines on stderr) a shell that is not bash and a bash older than `__KK_BASH_MIN` (5.2)."
**Acceptance.**
- `bash -c 'source ./kbool.sh && echo ok'` → `ok` (both runtimes)
- `sh -c '. ./kbool.sh; echo rc=$?'` under Git-bash → `rc=0` (Git-bash `sh` is bash in POSIX mode, so the guard passes) — report literal output; a failure AFTER the guard (POSIX mode vs the rest of kbool) goes to OPEN, it does not fail this card
- the existing kkore suite + phase gate on both runtimes: PASS, totals unchanged
- time of a repeated `source kbool.sh` (already loaded) before/after, 1000×, both runtimes (`time (for i in {1..1000}; do source ./kbool.sh; done)` after one initial source) — report both numbers.
**Note.** Real old-bash checks happen in L4.2.
**Timebox.** 45 min + gate.

### L2.4 — Linux gate runs, no fixes  [S] ready (finalized 2026-10-21 after L2.1)

**Goal.** Every Linux failure recorded with a minimal reproduction — the
input for the L2.5 triage.
**Read.** `tools/vmlab/README.md` (gate, run, fetch), `ktests/docs/GATE_FOR_AGENTS.md`
(reading `__GATE__`, cells.tsv, fails.txt), `docs/dev/PORTING.md` §2 (to
quote a hazard id in `notes` when one obviously matches — no other analysis).
**Write scope.** `docs/dev/launch/L2_failures.tsv`, `docs/dev/launch/L2_runs.md`; `$SCRATCH`.
**Steps.**
1. Full gates, one VM at a time, each `run_in_background`, nothing else running:
   `bash tools/vmlab/vmlab.sh gate kb-ubuntu -- --rerun-failed 1 all`, then
   kb-debian, then kb-fedora; then on kb-debian once more with the comma locale:
   `bash tools/vmlab/vmlab.sh gate kb-debian --env LC_ALL=de_DE.UTF-8 -- --rerun-failed 1 all`
   (L1.1c).
2. `L2_runs.md`: per run the OUT dir, the `gate:` header lines (bash, segment
   start), the two counts lines, the `__GATE__` line, total wall time.
3. `L2_failures.tsv`, header
   `vm<TAB>locale<TAB>suite<TAB>file<TAB>verdict<TAB>first_fail_line<TAB>repro<TAB>repro_ok<TAB>notes`;
   one row per failing (or FLAKY / STRAY / TIMEOUT) test FILE per run.
   `first_fail_line` = the first `[FAIL]` line of that file (from the cell's
   fails.txt / log), tabs→spaces, ≤ 200 chars.
   `repro` = the shortest command that shows it inside the VM, e.g.
   `cd ~/kbool && bash kcl/tpath/tests/tests.sh -n 7` (find the per-suite
   runner options in `ktests/docs`), executed once via
   `vmlab.sh up VM` + `sync` + `run VM -- '<repro>'` + `down`;
   `repro_ok` = `yes` (failure shown), `no` (passed when run alone), `n/a`
   (STRAY/TIMEOUT that needs the full gate). Batch the repros per VM (one up/down).
   `notes` = a PORTING.md hazard id if one obviously matches, the known
   items (`L2.1-o5` thttpserver 004, `L2.1-o6` tpipe 002 orphan,
   `kkore/011 Windows-path tests`), or empty. **No cause analysis, no fixes.**
4. Sort rows by suite, file, vm; a file failing on all three VMs gets
   `notes` prefix `ALL3;`.
**Acceptance.** The four `__GATE__` lines in L2_runs.md; `L2_failures.tsv`
rows = the sum of non-PASS files over the four runs (show the arithmetic);
every row has `repro_ok` filled; every lab VM `poweroff` at the end; hygiene.
**Timebox.** 3 h.

### L*.fix — fix batch template  [S] (filled per batch by O/SV)

```
CARD: L2.6-<n>  (or L3.5-<n>, L4.5-<n>, L5.4-<n>, L8.2-<n>)
Goal: the rows below pass on <targets> and nothing else changes behaviour.
Rows: <paste: vm, suite, file, failing line, repro, cause (from triage)>
Fix rule (decided by triage — apply exactly): <e.g. "replace `stat -c %s F` with
          `wc -c < F` and strip blanks"; "test X assumes C:/ paths: build the path from $TMPDIR">
Write scope: <exact files>
Acceptance:
  - each row's repro passes on its VM (vmlab.sh run, literal output)
  - the suites touched: gate on both Windows runtimes PASS, totals unchanged
  - the suites touched: vmlab.sh gate on each target VM with `-- <suite ids>` PASS
Stop if: a row's fix needs a change outside the write scope, or the rule does
         not fit what you see in the code → BLOCKED with the evidence.
Timebox: <n>
```

---

## L3–L8 — draft cards

These depend on earlier outcomes; SV completes each before dispatch.

- **L3.1 [S] draft** — as L2.4 for kb-alpine and kb-freebsd, each with
  `--snapshot clean` and `--snapshot clean-gnu` → `L3_failures.tsv` (column
  `snapshot` added).
- **L3.4 [S] draft** — call-site list from `tools.tsv` (`class=code`, wrapper
  units) × the helper's API from L3.3; one mechanical replacement rule per
  tool; tests of an absent tool SKIP with the helper's reason.
- **L4.1 [S] draft** — in kb-debian from `clean`: `apt-get install -y build-essential bison`;
  tarballs + `.sig` from `https://ftp.gnu.org/gnu/bash/` (`bash-5.1.16`,
  `bash-5.0.18`… note 5.0/4.4/3.2 need the official patch series from
  `bash-X-patches/` — final list fixed by SV), GNU keyring check with `gpg --verify`;
  `./configure --prefix=/opt/bash-X && make && sudo make install`; 3.2 may need
  `CFLAGS=-std=gnu89`; `bash --version` of each; snapshot `clean-bashes`.
- **L4.2 [S] draft** — `vmlab.sh gate kb-debian --snapshot clean-bashes` with
  `KT_GATE_BASHES=/opt/bash-5.1.16/bin/bash` (vms.conf override via env, to be
  added to vmlab by this card) → `L4_failures.tsv` with a `feature` column
  (from `bashfeatures.tsv`, or `unknown`); `tools/vmlab/checks/guard.sh`:
  for each `/opt/bash-*`, `bash -c 'source ~/kbool/kbool.sh; echo rc=$?'` and
  a unit file sourced directly — expected the two guard lines + rc=2 below
  the floor.
- **L5.1 [S] draft** — `.github/workflows/ci.yml`; matrix fixed by SV from L2–L4:
  `ubuntu-latest` (system bash) · containers `debian:13`, `fedora:latest`,
  `alpine:latest` (+GNU packages), `ubuntu:26.04` · `macos-latest` (`brew install
  bash coreutils gnu-sed gawk findutils grep` + the netcat choice; plus one step
  running `/bin/bash -c 'source kbool.sh'` expecting the guard) · FreeBSD via
  `vmactions/freebsd-vm` (exact pinned version) · `windows-latest` Git-bash and
  `msys2/setup-msys2`; `actions/checkout` with `submodules: recursive`; each
  job runs gate and uploads `summary.json`; all actions pinned to a version
  ≥ 2 weeks old. Validate: `python -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/ci.yml` (install PyYAML into `$SCRATCH` venv if absent).
- **L5.3 [S] draft** — `gh run list --branch launch-ci`, `gh run view <id> --log-failed`
  → `L5_failures.tsv` (job, step, test file, first fail line); read-only `gh` only.
- **L6.1 [S] draft** — `tools/porting/mdlinks.sh`: every `[..](relative)` and
  `[..](#anchor)` / `(file.md#anchor)` in tracked `*.md` of the five repos is
  checked (file exists; anchor = GitHub slug of a heading in the target);
  output `file:line: broken: <link>`; rc 0/1; tests on a fixture dir.
- **L6.2 [S] draft** — the move list (SV fixes it from `git ls-files`): every
  `PLAN.md`, `*_PLAN.md`, `*_ledger.json`, `REVIEW.md`, `OPTIMIZATION_PLAN.md`,
  `TEST_COVERAGE_NOTES.md`, `kklass/OPTIMIZATION.md`, `kcl/docs/review-2026-09-06/`,
  `ktests/docs/GATE_FOR_AGENTS.md`, `LAUNCH_*.md`, `launch_ledger.json` →
  `<repo>/docs/dev/<same relative dir>/`; precheck `grep -rn` of each moved
  name in `*.sh` (a script that reads one → BLOCKED); `git mv` only; then every
  link fixed until `mdlinks.sh` is clean.
- **L6.3 [S] draft** — the README sections SV lists move verbatim to
  `docs/reference.md`; README keeps a link per moved section; doctest blocks
  still run (the README doctest suite PASS).
- **L6.4 [S] draft** — `numbers.json`: fields and their exact sources (gate
  `summary.json` path, `git rev-list --count`, ledger fields) listed by SV.
- **L6.6 [S] draft** — list of stale strings (`lib/kklass`, …) from a grep SV
  runs; one replacement each.
- **L6.7 [S] draft** — `CHANGELOG.md` per repo from `git log --format='%h %ad %s' --date=short`, grouped by the round/phase prefixes of the subjects; newest first; no invented text.
- **L7.2 / L7.3 / L7.4 [S] draft** — after L7.1 (demo spec), recording script
  (`asciinema rec -c`, `agg`), bench commands and the output table format.
- **L8.1 [S] draft** — literal fresh install: from `clean`, `sync --from-github`,
  then execute only what README says, in its order, with nothing else
  installed; every deviation needed = a row (`step, what README says, what
  happened, what was needed`). No fixes.
- **L8.4 [S] draft** — tag names, release notes source, and the exact
  `git tag -a` / `git push --tags` / `gh release create` lines prepared in a
  file for the owner; executed only after the owner's explicit go, by SV.
