# L3.4 — design: the wrapper units onto ktool

Card L3.4-0 (design pass, read-only for code). Date 2026-10-28, tree kbool `ee696c1` (all five
repos clean at start). Inputs: owner decision OG1 = A and OG8 (ledger `decisions`,
`pending_owner_decisions`), the resolver [`kkore/ktool.sh`](../../../kkore/ktool.sh) and its README
[§7](../../../kkore/README.md), [`L3_triage.md`](L3_triage.md) §2 and §3 (card L3.5-9),
[`tools.tsv`](tools.tsv), [`../PORTING.md`](../PORTING.md) rows H40-H43, ledger open item L3.3-o1.

Every `file:line` below is the tree named above; paths are relative to `kcl/` unless they start with
another repo name. Measurements in this doc were taken on the Windows host (Git-bash 5.3.15), with
bounded one-liners only.

## 1. Inventory

### 1.1 The units: where the tool name lives, how it is identified today

All six wrappers inherit `cmd` from TUtil. `cmd` is a public, settable `var`
(`tutil/tutil.sh:140`, header `:46` "executable / function / builtin name; '' = not runnable"),
assigned from the constructor's first argument (`tutil/tutil.sh:431`). Every wrapper hands TUtil a
**bare tool name** (`sed`, `gawk`, `grep`, `find`, `head`, `tail`), and every `buildArgv` copies `$cmd` into word 0. Nothing in any unit checks
which build of the tool that name reaches: no `--version` probe, no env knob, no version check.

| unit | name passed to TUtil | argv word 0 | `cmd`-empty rc 2 | statics that build an instance | GNU-only features it emits (PORTING) |
|---|---|---|---|---|---|
| TSed | `parent.constructor sed` `tsed/tsed.sh:392` | `__tsd_v=( "$cmd" )` `:653` | `:511` | `edit` `:791`, `replace` `:849`, `replaceInFile` `:870` | `--sandbox` by default `:658` (H40), `-s -z -b -i…` `:661-668` |
| TAwk | `parent.constructor gawk` `tawk/tawk.sh:443` | `__taw_v=( "$cmd" )` `:670` | `:541` | `apply` `:821` | `--sandbox` `:672`, `-e` chunks, `-i /usr/share/awk/inplace.awk` **hard-coded** `:690` (H41, H42) |
| TGrep | `parent.constructor grep` `tgrep/tgrep.sh:162` | `__tg_v=( "$cmd" )` `:327`; with the stdin CR filter the argv becomes `( tutil._crStdin grep … )` `:370-372` | `:224` | `search` `:437` | `--include/--exclude/--exclude-dir -U -z -Z` `:344-349` (H43) |
| TFind | `parent.constructor find` `tfind/tfind.sh:192` | `__tfd_v=( "$cmd" )` `:362` | `:243` | `byName` `:434` | `-maxdepth -mindepth -iname -print0` on demand (H43) |
| THead | `parent.constructor head` `thead/thead.sh:162` | `__th_v=( "$cmd" )` `:286` | `:208` | `take` `:372` | negative counts, `-z`, `-q/-v` (H43) |
| TTail | `parent.constructor tail` `ttail/ttail.sh:188` | `__tt_v=( "$cmd" )` `:306` | `:233` | `take` `:446` | `-z`, `-q/-v` (H43) |

Each unit's header pins the GNU dialect in words only: TSed "the GNU sed 4.9 wrapper"
(`tsed/tsed.sh:61`), TAwk "the GNU Awk wrapper" (`tawk/tawk.sh:59`), TGrep "GNU grep 3.0"
(`tgrep/tgrep.sh:31`), TFind "GNU findutils 4.10.0" (`tfind/tfind.sh:51`), THead/TTail "GNU
coreutils 8.32" (`thead/thead.sh:33`, `ttail/ttail.sh:34`).

**What TUtil does with `cmd` before it runs.** `tutil._prep` (every sink, `tutil/tutil.sh:393-417`)
and `TUtil.run` (`:542-573`) both call `buildArgv` first (virtual, silent), then pre-check
`command -v -- "$cmd"` (`:399`, `:548`): a missing command is `_lastRc=127`, ONE `kk.debug` line
(`Error: TUtil.<member>: command not found: '<cmd>'`), rc 1, nothing runs. `TUtil.argv`
(`:498-515`) calls `buildArgv` only — it never pre-checks and never runs. `TUtil.mapRc`
(`:590-601`) maps raw 127 to rc 1 with one line. That `command -v` check works unchanged on an
absolute path.

**Constructor failure in kklass.** `CLASS.new` materialises the instance from the template
**before** the constructor body runs and returns the constructor's rc (`kklass/kklass.sh:1826-1836`):
a failing constructor leaves a live, half-built instance that the caller must still `.delete`. The
kcl precedent is tqueuestack: "a rejected constructor token creates the instance with defaults and
answers rc 1" (`README.md:355`). None of the six statics checks the rc of its `.new` today
(`tsed/tsed.sh:791`, `:849`, `:870`; `tawk/tawk.sh:821`; `tgrep/tgrep.sh:437`;
`tfind/tfind.sh:434`; `thead/thead.sh:372`; `ttail/ttail.sh:446`).

**The precedent for resolving a tool inside kcl.** thttpserver's `TNetcatTransport` resolves nc at
**build time**, in `BuildArgv` (`thttpserver/thttpserver.sh:650-695`): property `NcBinary`
(settable) → `$KCL_NC` → `nc` on PATH; a GNU-netcat identity check (`ths._backend`, `:678`); rc 1
"nc not found" / rc 2 "not GNU netcat" with `LastError` and one `kk.debug` line. The ktool
override rule (`KCL_GNU_<F>`, a wrong override refused) was taken from it (`kkore/ktool.sh:17-20`).
The TUtil family has **no** `LastError` member (only thttpserver has one: `grep -rn lastError` over
`kcl/*/*.sh` outside tests hits thttpserver only); its error channel is rc + one `kk.debug` line.

### 1.2 TUtil's role

TUtil (`tutil/tutil.sh`) is the base and a generic runner (`TUtil.new u git log`), not a GNU
wrapper: it drives whatever `cmd` names. It drives one tool **itself** — plain `sed` for the CR
contract on platforms whose tools keep the line-end CR (`__TUTIL_TOOLS_STRIP_CR=0`, i.e. not
cygwin/msys, `:216-221`):

* `tutil._sedOpts` probes `command sed -u -e ''` once per process (`:253-263`);
* `tutil._crStdin` = `LC_ALL=C command sed [-u] -e 's/<CR>$//' | CMD …` (`:271-283`), used as
  TGrep's argv prefix when grep reads stdin (`tgrep/tgrep.sh:370-372`);
* `TUtil.run`'s output filter `… | LC_ALL=C command sed [-u] -e 's/<CR>$//'` when `_textMode == 1`
  (`:555-566`; TGrep with file operands, TAwk's `--posix` fallback).

The filter script is built with a RAW CR because "BSD sed does not know the backslash-r escape"
(`:222-230`), and `-u` is used only where the probe accepts it: it was written to be portable to
BSD and busybox sed. Messages that name the tool: `Error: tutil._crStdin: the CR filter (sed)
exited N` (`:277`), `Error: TUtil.run: the CR filter (sed) exited N` (`:562`), and the
command-not-found pair above. TSed reuses the filter text as its own prelude
(`tsed/tsed.sh:670-672`) — run by the sed TSed resolves, not by TUtil.

`tools.tsv` does not list TUtil's three `command sed` calls (it has no `kcl/tutil code` row): the
scanner misses the `command` prefix. They are the only tool calls in tutil.sh.

### 1.3 kcl units outside the wrappers

Searched: every `kcl/*/*.sh` outside `tests/`, `bench.sh`, `examples/` for `sed grep awk gawk find
head tail` in command position (with and without `command`/`LC_ALL=C`), plus the `tools.tsv` code
rows. Hits outside the six wrappers and TUtil:

* **kcl/math** — `command -v gawk`, else `awk` (`math/math.sh:979-985`), its own identity handling
  for mawk/BWK (`:889-890`, `:1015-1019`), and `command find … -maxdepth 1 … -mmin +5` for the
  temp-file sweep (`:767`). math is core (tool-free in the OG1 sense: it runs on any awk, the BWK
  rows are L3.5-5) and is **not** affected by L3.4. (`-maxdepth`/`-mmin` are not POSIX but exist in
  GNU, BSD and busybox find.)
* tpipe, tpath, the containers, thttpserver: no call of these six tools (thttpserver's own nc/socat
  resolution is separate, above).

So L3.4 touches the six wrappers, TUtil (one helper + `kk.uses ktool`) and their tests; no other
unit.

### 1.4 The tests: SKIP decision, oracles, argv pins

ktests has no SKIP verdict: a skipped case is `kt_test_pass "SKIP: …"`, and the triage counted the
`SKIP` lines of `tests.sh -v info` (`L3_triage.md` §2.1). Every behavioural file opens with a
**banner gate** of the same shape — `X_BIN="$(command -v X)"`, `X_VER="$(X --version | head -1)"`,
`GNU_OK=1` only when the banner starts with the GNU form, and a `tcase` helper that passes every
later case as `SKIP: non-GNU X` — so the case COUNT is the same either way:

| unit | gate (file:line) | banner required | oracle calls of the family tool (approx., by command position) | other plain tools in the bodies |
|---|---|---|---|---|
| TSed | `005_Run.sh:66-82`, `006_Contract.sh:190-205`, `007_Bench.sh:103-121`, `008_Helpers.sh:65-81` | `sed (GNU sed) ` | 005 ~15, 006 ~7, 007 ~7, 008 ~32 (`sed`; `bench.sh` 5) | `grep` 10, `head` 4, `tail` 3, `od`, `tr`, `wc`, `cmp`, `cp`, `ls`, `touch`, `timeout` |
| TAwk | `005_Run.sh:72-88`, `006_Contract.sh:210-225`, `007_Bench.sh:113-131` | `GNU Awk ` (on `gawk --version`) | 005 ~19, 006 1, 007 ~7 (`gawk`; `bench.sh` 5) | `grep` 11, `sed` 6 (006: source lint), `head` 6, `tail` 3, `find` 1 |
| TGrep | `005_Search.sh:70-89`, `006_Contract.sh:134-149`, `007_Bench.sh:85-103` (+`:279`) | `grep (GNU grep) ` | 005 ~14 (incl. `timeout -k 5 20 grep` `:1082`), 006 ~4, 007 ~7 (`grep`; `bench.sh` 5) | `sed` 3, `head` 4 |
| TFind | `005_Run.sh:72-91` (+`:379`), `006_Contract.sh:198-213`, `007_Bench.sh:98-116` | `find (GNU findutils) ` | 005 ~5, 006 1, 007 ~6 (`find`; `bench.sh` 5) | `grep` 11, `sed` 6, `head` 3 |
| THead | `005_Run.sh:59-78`, `006_Contract.sh:157-172`, `007_Bench.sh:91-109` | `head (GNU coreutils) ` | 005 ~8, 006 1, 007 ~6 (`head`; `bench.sh` 5) | `grep` 8, `sed` 5 |
| TTail | `005_Run.sh:62-78`, `006_Contract.sh:167-182`, `007_Bench.sh:99-117` | `tail (GNU coreutils) ` | 005 ~7, 006 ~2, 007 ~6 (`tail`; `bench.sh` 5) | `grep` 9, `sed` 6, `head` 2, `awk` 1 |

`tools.tsv` counts the family tool per unit's tests + bench (direct + indirect): tsed 79+3, tawk
57+3, tgrep 61+2, tfind 43+2, thead 47+2, ttail 47+2 = **348** — the triage's "~348 sites". Most
of them are **argv pins in 004**, not oracles: 004 never runs the tool (`tsed/tests/004_Argv.sh:5-11`
"it holds on a box without GNU sed") and pins whole argv arrays with the family name as word 0
(`check_argv … s1 sed --sandbox -e 's/a/A/'`, e.g. `tsed/tests/004_Argv.sh:401`, `:445`). Per 004:
TSed 29 `check_argv` + `one`/`sbx`/`deny`/`cr_case` helpers ≈ 60-100 lines naming `sed`; TAwk 36 +
helpers ≈ 60-90 lines naming `gawk`; TGrep 23 ≈ 30-45; TFind 20 ≈ 35-50; THead 19 ≈ 26-37; TTail
19 ≈ 25-34. The "other plain tools" column is almost entirely **incidental**: source-code lint in
006 (`grep -n … "$UNIT"`, `sed -n '/^TAwk.Create()/,/^}/p' "$UNIT"`,
`tawk/tests/006_Contract.sh:63-185`), `| head -1` on a banner, `grep -q` on an error file, `od -c`,
`wc`.

The places a test asserts the tool **name** (L3.3-o1):

* `cmd` defaults: `[[ "$(sA.cmd)" == "sed" ]]` `tsed/tests/004_Argv.sh:180`, `:213`;
  `tawk/tests/004_Argv.sh:184`, `:215` (`gawk`); `tgrep/tests/004_Argv.sh:193`;
  `tfind/tests/004_Argv.sh:186`, `:220`; `thead/tests/004_Argv.sh:177`, `:188`;
  `ttail/tests/004_Argv.sh:164`, `:175`.
* argv word 0 in every `check_argv`/`cr_case`/`one` expectation of the six 004 files (above).
* the inplace path: `IPA=/usr/share/awk/inplace.awk` `tawk/tests/004_Argv.sh:88`, `:1262`;
  `tawk/tests/005_Run.sh:102`, `:1189-1192`; `tawk/tests/006_Contract.sh:149-152`.
* source lint that will see the change: "the CONSTRUCTOR calls `parent.constructor X`"
  (`tsed/tests/006_Contract.sh:85-89`, `tawk/…:90-97`, `tgrep/…:84-90`, `tfind/…:94-100`,
  `thead/…:84-90`, `ttail/…:75-78`) and "the unit's only dependency is `kk.uses tutil || return`"
  (`006_Contract.sh` of tsed `:167`, tawk `:183-190`, tfind `:174`, thead `:144`, ttail `:105`;
  tgrep has none).
* GNU stderr wording pinned in THead/TTail: `"head: cannot open "*` `thead/tests/005_Run.sh:456`,
  `"head: invalid number of bytes"*` `:679`, `"tail: cannot open "*` `ttail/tests/005_Run.sh:445`.

kcl-level: `kcl/tests/kcl_units.sh:65-76` lists the wrappers with their kcl dependencies;
`kclt_order` skips names outside the table (`:117-120`), so a `kk.uses ktool` in tutil.sh is
invisible to the table and to `001_UnitFiles.sh`'s closure check (which only resolves names of
table units).

### 1.5 THead / TTail with uutils (OG8)

Code: neither unit reads the tool's stderr, version or any GNU-only hidden option (`grep -n
'inotify\|--pid\|presume\|stderr\|2>'` over `thead/thead.sh` and `ttail/ttail.sh`: no code line).
With ktool accepting `head (uutils coreutils) ≥ 0.2.2`, **the units need no change** beyond the
common rule.

Tests: **the OG8 measurement did not exercise THead/TTail behaviour.** The ledger records "kcl/thead
182/182 and kcl/ttail 200/200 pass" under a uutils PATH shim, but both suites gate on the banner
starting with `head (GNU coreutils) ` / `tail (GNU coreutils) ` (`thead/tests/005_Run.sh:63`,
`ttail/tests/005_Run.sh:66`; the same in 006/007), and uutils prints `head (uutils coreutils)
0.12.0` — every behavioural case of 005/006/007 passed as `SKIP: non-GNU head`. Only 004 (which
never runs head) was a real pass. The independent evidence is the round-2 direct diff (922 argument
sets: 866 identical, 56 differ in stderr wording and 20-digit counts). Once the gates move onto
ktool (§2.5), these suites run against uutils for the first time; the three stderr pins above and
any GNU message in an expectation may fail there. This is why the kb-ubuntu uutils run is an
acceptance step of card L34-E (§3) and decision D-L34-9 exists.

## 2. Design — one rule set for the six units

Names: FAMILY is ktool's family — TSed `sed`, TAwk **`awk`** (ktool's family is `awk`, its g-name
`gawk`; `kkore/ktool.sh:91`, `:96`), TGrep `grep`, TFind `find`, THead `head`, TTail `tail`. Each
rule below spells out the recommended option of the decision it names (§4); a different
supervisor choice changes only that rule.

### 2.1 Where `ktool.gnu` is called, where the path lives (D-L34-1, D-L34-2, D-L34-5)

* **G1 — in the constructor, through one TUtil helper.** Each wrapper's `Create` keeps its
  `parent.constructor <bare name>` line (the 006 lint pins it, §1.4) and adds ONE line right after
  it: `tutil._gnu FAMILY`. Nothing is resolved at unit load (D-L34-5).
* **G2 — the path lives in `cmd`** (D-L34-2). `tutil._gnu` sets `cmd` to ktool's absolute path. No
  new public property: `cmd` is already the public, settable source of argv word 0 in all six
  `buildArgv`s and of TUtil's `command -v` pre-check (§1.1). The class surface does not change.
* **G3 — one private TUtil var `_toolErr`** ('' = none), assigned '' in `TUtil.Create` with every
  other var (the "constructor assigns EVERY declared var" trap, `tutil/tutil.sh:118-122`). It holds
  ktool's reason when the constructor found no GNU build. It joins TUtil's reserved names
  (`tutil/tutil.sh:76-80`, README §4).
* **G4 — `kk.uses ktool || return` goes into tutil.sh only** (after `kk.uses tpipe`). The wrappers
  keep `kk.uses tutil || return` as their only dependency (their 006 checks it). Measured on
  Git-bash 5.3.15: `kk.uses ktool` 11 ms, no fork; the generic `TUtil.new u git …` pays that load
  and nothing else (it never calls the helper).
* **G5 — the helper** (plain function in tutil.sh, never a member body):

  ```bash
  # tutil._gnu FAMILY — called by a wrapper's Create right after parent.constructor:
  # cmd = the absolute path of a GNU FAMILY (ktool.gnu), _toolErr = ''; with none,
  # cmd = '' and _toolErr = ktool's reason (D-L34-3 option 2: creation succeeds).
  # rc 0 always. Writes the member frame's cmd/_toolErr by dynamic scoping (as
  # tutil._prep writes _lastRc).
  tutil._gnu() {
      if ktool.gnu "$1"; then
          cmd=$RESULT
          _toolErr=''
      else
          ktool.lastError
          cmd=''
          _toolErr=$RESULT
      fi
      return 0
  }
  ```

  Cost per `.new`, measured on Git-bash (`ktool.gnu` per family, one process): the **first**
  resolution of a family in a process 73-107 ms (two forks per candidate probed); every later one
  169-519 µs (ktool's warm path: string compares, no fork). The answer is ktool's, cached under
  `KCL_GNU_<F>` + PATH.
* **G6 — a resolved instance is frozen.** A PATH or `KCL_GNU_<F>` change after `.new` does not
  change an existing instance's `cmd` (the next `.new` sees it). `.new` over a live name re-runs
  `Create`, so it re-resolves.
* **G7 — a user-set `cmd` is used verbatim** (D-L34-4): `s.cmd = /opt/sed/bin/sed` after `.new`
  skips ktool — no identity check. The validated way to pick a build is `KCL_GNU_<F>` before
  `.new` (ktool refuses a wrong one, never skips it).
* **G8 — subshells.** A `.new` inside `$( … )` resolves in the child and the cache dies with it
  (`kkore/ktool.sh` header, "Subshells"): `out=$(TSed.edit 's/a/b/' f)` in a shell that never
  resolved sed pays the cold probe (~90 ms on msys, two forks elsewhere) on **every** call. Each
  wrapper README gains one line: "call `ktool.gnu sed` (or create one instance) once in the main
  shell before using TSed inside `$( )`". Not fixed in code (D-L34-5).

### 2.2 No GNU tool found (D-L34-3, D-L34-6)

Two options, the same box for both — FreeBSD without `gsed` (`/usr/bin/sed` is BSD sed):

**Option 1 — creation fails.**

```bash
TSed.new s 's/a/b/' notes.txt; echo "rc=$?"
# kk.debug: Error: TSed.Create: no GNU sed: gsed not on PATH; /usr/bin/sed is not GNU sed
#   (--version: "sed: illegal option -- -"); FreeBSD: pkg install gsed
# rc=1
s.run; echo "rc=$?"          # the instance EXISTS (kklass.sh:1826-1836), disarmed:
# kk.debug: Error: TSed.buildArgv: no GNU sed: … FreeBSD: pkg install gsed
# rc=2
s.delete                     # still required
```

**Option 2 — creation succeeds; the first member that needs the argv says why (recommended).**

```bash
TSed.new s 's/a/b/' notes.txt; echo "rc=$?"
# rc=0                                   (silent)
s.run; echo "rc=$?"                      # also argv, each, toArray, toList, first, count
# kk.debug: Error: TSed.buildArgv: no GNU sed: gsed not on PATH; /usr/bin/sed is not GNU sed
#   (--version: "sed: illegal option -- -"); FreeBSD: pkg install gsed
# rc=2                                   nothing ran; lastRc still -1
TSed.edit 's/a/b/' notes.txt; echo "rc=$?"   # the statics: the same line, rc 2
```

Trade-offs:

| | Option 1 (fail creation) | Option 2 (fail at first use) |
|---|---|---|
| scripts that create objects but never run them (a class that owns a TGrep, an `argv` dump) | break on a box without the tool | unaffected |
| caller code | every `X.new` needs `\|\| { …; x.delete; }` — kklass leaves a half-built instance (`kklass/kklass.sh:1826-1836`) | unchanged; the error arrives where the work would have been done |
| the six statics (`tsed.sh:791/849/870`, `tawk.sh:821`, `tgrep.sh:437`, `tfind.sh:434`, `thead.sh:372`, `ttail.sh:446`) | each needs an rc check + delete (6 sites) | unchanged (`.new` rc 0, `run` answers rc 2, `delete`) |
| kcl precedent | tqueuestack: rc 1 + an instance with defaults (`README.md:355`) | every wrapper `.new` today is rc 0 |
| how early the user learns | at `.new` | at the first `run`/sink/`argv` — the same text |
| tests | 004 must resolve a tool at `.new` (the §2.5 stub, needed either way) | same |
| `kk.uses` load cost | none (both resolve in `Create`, G1) | none |

Recommendation: **option 2**. Its rules:

* **N1** — `tutil._gnu` never fails (G5): `cmd=''`, `_toolErr` = ktool's text, `.new` rc 0, no
  output.
* **N2** — the `cmd`-empty branch of every `buildArgv` (`tsed.sh:511`, `tawk.sh:541`,
  `tgrep.sh:224`, `tfind.sh:243`, `thead.sh:208`, `ttail.sh:233`, and the base `tutil.sh:463`)
  prints `_toolErr` when it is set, else today's text — one line each:
  `kk.debug "Error: TSed.buildArgv: ${_toolErr:-cmd is empty; there is nothing to run}"`. rc 2,
  RESULT '', nothing runs, `_lastRc` untouched — today's contract for an unrunnable instance
  (D-L34-6: rc 2, not rc 1 + `_lastRc` 127).
* **N3** — the statics are not changed.
* **N4** — `cmd` set by hand later arms the instance (G7); `_toolErr` stays but is not printed
  while `cmd` is non-empty.

### 2.3 What `cmd` and `argv` show

* **A1** — `cmd` and argv word 0 are the **resolved absolute path** (`/usr/bin/sed` on Git-bash,
  `/usr/local/bin/gsed` on FreeBSD `clean-gnu`, `/usr/bin/gawk` for TAwk on Git-bash). `argv`
  stays "the single truth about what will run" (`tutil/tutil.sh:454-456`). TGrep's stdin form is
  `( tutil._crStdin /usr/bin/grep … )` — the helper stays word 0 there (`tgrep/tgrep.sh:370-372`).
* **A2** — with no GNU tool, `argv` is rc 2 with the N2 line (it cannot show what would run).
* **A3** — tests assert the path the test resolved (§2.5): `[[ "$(sA.cmd)" == "$SED_BIN" ]]`
  instead of `== "sed"`, and `check_argv … s1 "$SED_BIN" --sandbox -e 's/a/A/'` instead of
  `… s1 sed --sandbox …`.
* **A4** — headers and READMEs say "`cmd` = the GNU FAMILY ktool resolved (absolute path)" where
  they show `cmd = sed` today; the pinned-argv diagrams keep the bare name as notation
  (`sed [--sandbox] …`) with one sentence saying word 0 is the resolved path.

### 2.4 TAwk `inPlace` (L3.5-9 folded in)

* **I1** — `tawk.sh:690` `-i /usr/share/awk/inplace.awk` → `-i "$__taw_ip"`, where `__taw_ip` is
  the first **absolute** directory of gawk's **default** AWKPATH holding a readable `inplace.awk`.
* **I2** — the default AWKPATH comes from the gawk that will run (`$cmd`):
  `$( unset AWKPATH; LC_ALL=C exec "$cmd" 'BEGIN { print ENVIRON["AWKPATH"] }' </dev/null 2>/dev/null )`.
  Measured: Git-bash `/usr/bin/gawk` and MSYS2 `gawk.exe` both print `.:/usr/share/awk`;
  kb-freebsd `clean-gnu` prints `.:/usr/local/share/awk` (`L3_triage.md` C10). Entries not
  starting with `/` (`.`, relative, empty) are skipped — the cwd-hijack reason the include is
  absolute (`tawk/tawk.sh:97-99`) still holds.
* **I3** — in a plain function `tawk._inplace` (never a member body), cached per gawk path in a
  unit global associative array `__TAW_IPC` (declared once per process, kept across
  `kk.unit --forget tawk` like TUtil's registries, `tutil/tutil.sh:178-180`); a miss is cached
  too (''). One fork per gawk path per process, only when `inPlace = 1` reaches `buildArgv`.
* **I4** — none found → `buildArgv` rc 2, one line `Error: TAwk.buildArgv: gawk's inplace.awk not
  found in '<the AWKPATH value>' (<cmd>)`, nothing runs. (The L3.5-9 card says "LastError"; the
  TUtil family has none — §1.1 — its channel is this `kk.debug` line.)
* **I5** — the lookup runs after the existing `inPlace` rc-2 checks (`tawk.sh:574-592`), so a
  refused build never forks. Header (`:77`, `:97-99`, `:147`) and README (`:30`, `:106`, `:130`,
  `:428-430`) say "gawk's own `inplace.awk`, found through gawk's default AWKPATH, absolute
  entries only".
* **I6** — `AWKLIBPATH` (where `inplace.awk`'s `@load "inplace"` finds the extension) is not
  touched: its default has no `.` (`/usr/lib/gawk` on this host).

### 2.5 The test side (D-L34-7)

* **T1 — one shared helper file: `kcl/tutil/tests/gnu_helper.sh`.** Not `NNN_*.sh`, so the
  runner does not collect it — the precedent is `kcl/tdirectory/tests/symlink_helper.sh`, already
  sourced across units (`tgrep/tests/005_Search.sh:56`, `tfind/tests/005_Run.sh:54`). It lives
  with the family's base class, not in ktests: ktests is the framework of every repo and must not
  depend on a kkore unit. It loads ktool with `kk.uses ktool` (the test file has already sourced
  its unit, hence kbool).
* **T2 — `kt_gnu_gate FAMILY VAR`**, replacing each gate block (§1.4 table, 19 blocks): one
  `kt_test_start "GNU FAMILY: ktool resolves it"`; on success `VAR` = the path (the existing
  names: `SED_BIN`, `AWK_BIN`, `GREP_BIN`, `FIND_BIN`, `HEAD_BIN`, `TAIL_BIN`), `GNU_OK=1`,
  `GNU_WHY=''`, pass "PATH — banner"; on failure `VAR=''`, `GNU_OK=0`, `GNU_WHY` =
  `ktool.lastError`'s text, pass `SKIP: <GNU_WHY>`. It runs in the test's main shell (G8: the
  cache is then warm for every `.new` in the file). Each file's `tcase` keeps its shape; its SKIP
  text becomes `SKIP: $GNU_WHY` — on FreeBSD `clean`: `SKIP: no GNU sed: gsed not on PATH;
  /usr/bin/sed is not GNU sed (--version: "sed: illegal option -- -"); FreeBSD: pkg install gsed`.
* **T3 — the oracle rule.** In a test body or a `bench.sh`, a call of the unit's **own** family
  that produces a value compared with the unit's output, or that is timed against it, runs
  `"$X_BIN"` — the path the unit resolved. That is every own-family call inside an
  `if tcase …; then … fi` body and in 007/`bench.sh` timing loops, including the `timeout … grep`
  and `env … gawk` forms (`tgrep/tests/005_Search.sh:1082`).
* **T4 — what stays plain.** (a) Calls of **another** family (`grep -q` on an error file in tsed
  005, `| head -1` in a gate, `sed -n` over the unit source in tawk 006,
  `tawk/tests/006_Contract.sh:91-174`): plumbing, not oracles; the test's tool dependency stays
  its own family. (b) Own-family plumbing **outside** case bodies: source lint over `"$UNIT"`
  (`sed -n '/^TSed.Create()/,/^}/p' "$UNIT"` in tsed 006), banner trimming. Both must use POSIX
  options only; a plain call with a GNU-only option (`sed -i` without suffix, `head -n -K`,
  `grep -P`) is NOT routed through ktool — the card reports it (an L3.5-3-class idiom bug).
* **T5 — 004 runs everywhere, against a stub (D-L34-7).** `kt_gnu_stub FAMILY DIR VAR` writes
  `DIR/<family>` = `#!/bin/sh` + `case $1 in --version) echo '<GNU banner>';; *) echo
  '.:DIR/share/awk';; esac` (the second arm answers TAwk's AWKPATH probe), creates
  `DIR/share/awk/inplace.awk` (empty), `chmod +x`, sets the shell variable `KCL_GNU_<F>` to
  `DIR/<family>` (ktool reads it at call time; no export) and `VAR` to that path. 004 calls it
  before its first `.new` and pins `"$VAR"` as word 0 / `cmd` everywhere (`IPA` becomes
  `DIR/share/awk/inplace.awk` in tawk 004). 004 still never runs the real tool, keeps its case
  count on every box, and its argv pins become identical on all platforms. Banners:
  `sed (GNU sed) 4.9`, `GNU Awk 5.3.0`, `grep (GNU grep) 3.11`, `find (GNU findutils) 4.10.0`,
  `head (GNU coreutils) 9.4`, `tail (GNU coreutils) 9.4`.
* **T6 — the no-tool path, once per unit in 004**: `KCL_GNU_<F>=/nonexistent` → `X.new` rc 0,
  `cmd` '', `argv` rc 2 with exactly one line containing `KCL_GNU_<F>='/nonexistent' is not an
  executable file`; `x.cmd = "$VAR"` re-arms it (N4); the static (`TSed.edit` etc.) rc 2 with the
  same line, nothing run.
* **T7 — the pins that move**: the 004 `cmd` asserts and argv word 0 (§1.4); tawk's `IPA` in
  004/005/006 (005 `:1189-1192` uses `AWKPATH=".:/usr/share/awk"` → the AWKPATH the probe
  found); each wrapper 006 `RESERVED` list gains `_toolErr` (`006_Contract.sh` of tsed `:143`, tawk
  `:158`, tgrep `:106`, tfind `:150`, thead `:120`, ttail `:139`); `tutil/tests/001_Core.sh:1027-1033` (18 → 19 members). The 006
  checks "constructor calls `parent.constructor X`" and "only dependency is `kk.uses tutil`" stay
  (G1, G4); each 006 gains one assertion that `Create` calls `tutil._gnu FAMILY`.

### 2.6 THead / TTail with uutils

* **U1** — no unit change beyond G1-G8, N1-N4 (§1.5: no stderr parsing, no version logic).
* **U2** — after T2, the THead/TTail behavioural files run against uutils for the first time on a
  uutils box (the old gates SKIPped there, §1.5). Pins of GNU stderr wording
  (`thead/tests/005_Run.sh:456`, `:679`, `ttail/tests/005_Run.sh:445`) must accept the uutils
  wording or assert only the rc when `X_BIN`'s banner is uutils; card L34-E settles each pin from
  a kb-ubuntu uutils run (D-L34-9).

### 2.7 TUtil itself

* **C1** — TUtil's own CR filter (`tutil._sedOpts`, `tutil._crStdin`, `TUtil.run`'s pipe; §1.2)
  stays on plain `command sed` (D-L34-8): it was written for BSD and busybox sed (raw CR, probed
  `-u`), and routing it through ktool would make TGrep (and TAwk's `--posix` fallback) need GNU sed
  besides their own tool.
* **C2** — the generic runner is unchanged: `TUtil.new u CMD …` never calls `tutil._gnu`; `cmd` is
  what the caller gave.

## 3. Cards

Common to all cards: write scope = the files listed; LF only; no code outside them; never commit.
`G=ktests/tools/gate.sh` with `KT_GATE_BASHES` as in `ktests/docs/GATE_FOR_AGENTS.md`; Windows =
`bash $G <suites>` (both runtimes); VM = `bash tools/vmlab/vmlab.sh gate VM --snapshot S --
--rerun-failed 1 <suites>`, one VM at a time, powered off after. "VM set" below = kb-freebsd
`clean-gnu`, kb-freebsd `clean`, kb-alpine `clean`, kb-debian `clean`. Rules referenced: G1-G8,
N1-N4, A1-A4, I1-I6, T1-T7, U1-U2, C1-C2 (§2). A rule that does not fit the code → BLOCKED with
the evidence. Line counts are changed lines (added + removed), estimated from §1.4.

| order | card | exec | critic | scope | ~lines |
|---|---|---|---|---|---|
| 1 | L34-A | O | **yes** (TUtil member `_toolErr`; shared test infra) | TUtil + `gnu_helper.sh` | 200-260 |
| 2 | L34-B | S | **yes** (first wrapper: the template the others copy) | TSed | 230-290 |
| 3 | L34-C | S | **yes** (TAwk `inPlace` behaviour, I1-I6) | TAwk + inplace | 250-300 |
| 4 | L34-D | S | no (SV review against L34-B) | TGrep + TFind | 200-260 |
| 5 | L34-E | S | no (SV review) | THead + TTail (+ uutils run, D-L34-9) | 180-240 |
| 6 | L34-F | O | — (triage) | none (read-only + triage doc) | doc |

### L34-A — TUtil: ktool, `_toolErr`, `tutil._gnu`, the shared test helper [O, critic]

* Do: G3, G4, G5, N2 for the base branch (`tutil/tutil.sh:463`), C1/C2 (no change to the CR
  filter, a comment line saying why), the reserved-names comment (`:76-80`) and README §1 (surface
  table), §4 (reserved names), §5 (writing a descendant: "call `tutil._gnu FAMILY` right after
  `parent.constructor`; the `cmd`-empty branch prints `${_toolErr:-…}`") and §7 (tests: the helper).
  New `kcl/tutil/tests/gnu_helper.sh` with `kt_gnu_gate` (T2) and `kt_gnu_stub` (T5). Tests in
  `tutil/tests/001_Core.sh`: the member list 18 → 19 (`:1027-1033`); new cases — a TUtil
  descendant defined in the test file calling `tutil._gnu sed` with `KCL_GNU_SED` = a stub (cmd =
  stub path, `_toolErr` ''), = `/nonexistent` (`.new` rc 0, cmd '', `argv` rc 2, one line with
  ktool's text, `_lastRc` -1), re-armed by `x.cmd = …`; `tutil._gnu` with an unknown family (rc 0,
  `_toolErr` = ktool's rc-2 text); the generic `TUtil.new u printf …` never resolves (cmd
  `printf`). A helper self-test file is not added: the six wrapper suites exercise it from L34-B on.
* Write scope: `kcl/tutil/tutil.sh`, `kcl/tutil/README.md`, `kcl/tutil/tests/001_Core.sh`,
  `kcl/tutil/tests/gnu_helper.sh` (new).
* Acceptance: Windows `bash $G kcl/tutil kcl/tsed kcl/tawk kcl/tgrep kcl/tfind kcl/thead
  kcl/ttail kcl/tests` PASS on both runtimes (the wrappers do not call the helper yet: their totals
  are unchanged; tutil's total grows by the new cases only); VM: `kcl/tutil kcl/tests` on the VM
  set PASS.

### L34-B — TSed onto ktool [S, critic]

* Do: G1 (`tsed/tsed.sh:392` + `tutil._gnu sed`), N2 (`:511`), A4 (header `:61-80`, the
  constructor comment `:385-390`, the trap line `:149-150`), G8 line + requirement paragraph in
  `tsed/README.md` (§ tests `:623-630`: the gate is ktool's). Tests: T2 in 005/006/007/008 (gate
  blocks `005_Run.sh:66-83`, `006_Contract.sh:190-206`, `007_Bench.sh:103-122`,
  `008_Helpers.sh:65-82`); T3 on every own-family call in case bodies and in `bench.sh`; T4 list of
  plain calls with a GNU-only option (report, do not change); T5 + A3 in 004 (word 0 of every
  `check_argv`/`one`/`sbx`/`deny`/`cr_case`/`opts_before_e`/`derived_b` expectation, `:180`, `:213`);
  T6 in 004; T7 (006 `RESERVED` `:143`, one `tutil._gnu sed` assertion next to `:85-89`).
* Write scope: `kcl/tsed/tsed.sh`, `kcl/tsed/README.md`, `kcl/tsed/bench.sh`,
  `kcl/tsed/tests/004_Argv.sh` … `008_Helpers.sh`.
* Acceptance: Windows `bash $G kcl/tsed kcl/tutil` PASS both runtimes, tsed total = old + T6 cases
  + the one 006 assertion; VM set: `kcl/tsed` PASS — kb-freebsd `clean-gnu` with **0** `SKIP:` lines
  in `bash kcl/tsed/tests/tests.sh -v info` (166 today, `L3_triage.md` §2.1) and `cmd` =
  `/usr/local/bin/gsed`; kb-freebsd `clean` and kb-alpine `clean`: 005-008 SKIP with the package
  hint (`FreeBSD: pkg install gsed`, `Alpine: apk add sed`), 004 PASS in full; kb-debian PASS, 0 SKIP.
  New FAILs on FreeBSD `clean-gnu` are listed with their first failing line (they are L34-F input,
  not blockers for this card unless they are in 004).

### L34-C — TAwk onto ktool + `inPlace` (L3.5-9) [S, critic]

* Do: G1 (`tawk/tawk.sh:443` + `tutil._gnu awk`), N2 (`:541`), A4 (header `:58-80`, `:147`),
  I1-I6 (`:690`, helper + cache at file scope before `build TAwk`, README `:30`, `:106`, `:130`,
  `:428-430`, the 005 row `:513`). Tests: T2 (005 `:72-89`, 006 `:210-226`, 007 `:113-132`), T3,
  T4, T5 + A3 in 004 (word 0, `:184`, `:215`, `IPA` `:88` → the stub's `share/awk/inplace.awk`,
  `:1262`), T6; 005: `IPA` (`:102`) = the inplace path of the resolved gawk (the test computes it
  with the same AWKPATH probe), the planted-`./inplace.awk` case (`:1180-1195`) keeps proving the
  cwd is never searched, with `AWKPATH=` set to `.` + the probe's absolute entry; 006 `:149-152`:
  the built argv holds `-i <absolute path ending in /inplace.awk>`, never `-i inplace`; one new 004
  case for I4 (a stub whose AWKPATH arm prints `.:/nonexistent` → rc 2, one line naming the AWKPATH).
* Write scope: `kcl/tawk/tawk.sh`, `kcl/tawk/README.md`, `kcl/tawk/bench.sh`,
  `kcl/tawk/tests/004_Argv.sh` … `007_Bench.sh`.
* Acceptance: Windows `bash $G kcl/tawk kcl/tutil` PASS both; VM set: kb-freebsd `clean-gnu`
  `kcl/tawk` PASS including **005 and 006** (the two C10 rows, `L3_triage.md` C10); kb-freebsd
  `clean` / kb-alpine `clean`: SKIP with `pkg install gawk` / `apk add gawk`; kb-debian: PASS
  (gawk installed) or SKIP with `apt install gawk` — the card reports which; plus kb-fedora `clean`
  and kb-alpine `clean-gnu` `kcl/tawk` PASS (the L3.5-9 acceptance).

### L34-D — TGrep and TFind onto ktool [S]

* Do, for each unit, what L34-B did: TGrep `tgrep/tgrep.sh:162` (+ `tutil._gnu grep`), N2 `:224`,
  A4 (`:31`); tests 004 (`:193`; the `cr_case` stdin expectations keep `tutil._crStdin` as word 0
  and the stub path as word 1), 005 `:70-90` (+ `TG_BIN` oracle `:1082`), 006 `:134-150`, 007
  `:85-104` and its second gate `:279`. TFind `tfind/tfind.sh:192` (+ `tutil._gnu find`), N2 `:243`,
  A4 (`:51`); tests 004 (`:186`, `:220`), 005 `:72-92` (+ `:379`), 006 `:198-214`, 007 `:98-117`.
  T7 in both 006 files. The tgrep README's Embarcadero paragraph (`tgrep/README.md:526`) becomes
  "ktool skips a non-GNU grep earlier on PATH".
* Write scope: `kcl/tgrep/{tgrep.sh,README.md,bench.sh,tests/004..007}`,
  `kcl/tfind/{tfind.sh,README.md,bench.sh,tests/004..007}`.
* Acceptance: Windows `bash $G kcl/tgrep kcl/tfind` PASS both; VM set `kcl/tgrep kcl/tfind`:
  kb-freebsd `clean-gnu` 0 SKIP lines (108 + 96 today), `clean`/Alpine `clean` SKIP with
  `pkg install gnugrep` / `findutils`, `apk add grep` / `findutils`; kb-debian PASS.

### L34-E — THead and TTail onto ktool; the uutils run [S]

* Do, for each unit, what L34-B did: THead `thead/thead.sh:162` (+ `tutil._gnu head`), N2 `:208`,
  A4 (`:33`); tests 004 (`:177`, `:188`), 005 `:59-79`, 006 `:157-173`, 007 `:91-110`. TTail
  `ttail/ttail.sh:188` (+ `tutil._gnu tail`), N2 `:233`, A4 (`:34`); tests 004 (`:164`, `:175`),
  005 `:62-79`, 006 `:167-183`, 007 `:99-118`. U1. The stub banners stay GNU (T5).
* U2 (only if D-L34-9 = yes): on kb-ubuntu, the OG8 PATH shim with uutils 0.2.2 and 0.12.0 (the
  binaries and digests of the OG8 measurement), `kcl/thead kcl/ttail` gate; every failing pin is
  either widened to accept the uutils wording or reduced to the rc when `HEAD_BIN`/`TAIL_BIN`'s
  banner says uutils — one line per pin in the report with both wordings.
* Write scope: `kcl/thead/{thead.sh,README.md,bench.sh,tests/004..007}`,
  `kcl/ttail/{ttail.sh,README.md,bench.sh,tests/004..007}`.
* Acceptance: Windows `bash $G kcl/thead kcl/ttail` PASS both; VM set: kb-freebsd `clean-gnu` 0
  SKIP lines (96 + 111 today) with `cmd` = `/usr/local/bin/ghead`/`gtail`; `clean`/Alpine `clean`
  SKIP with `pkg install coreutils` / `apk add coreutils`; kb-debian PASS; (U2) kb-ubuntu uutils
  0.2.2 and 0.12.0: PASS with **0** SKIP lines in 005-007.

### L34-F — the L3.4 gates and the triage of the un-skipped cases [O]

* Do: one full gate per VM of the VM set and kb-ubuntu (`-- --rerun-failed 1 --timeout 900 all`),
  Windows `bash $G --rerun-failed 1 --compare LAST all`; count the wrapper `SKIP:` lines per
  (VM, snapshot) against `L3_triage.md` §2.1 (763 / 763 / **577 → 0** / 0); triage every new
  FAIL/FLAKY row in the L3_triage format (cluster, mechanism with a repro, class, fix card). The
  budget for new rows comes from OG1 ("Budget an L3.4 triage").
* Write scope: `docs/dev/launch/L3_4_triage.md` (new), `docs/dev/launch/L3_runs.md` (rows).
* Acceptance: the four VM gates + kb-ubuntu + Windows reported with their `__GATE__` lines; every
  non-PASS row in exactly one cluster with a card.

Order: L34-A → L34-B (template; the critic's remarks are folded into the card text of C-E before
they start) → L34-C → L34-D → L34-E → L34-F. One gate slot: the cards run one after another;
L34-D and L34-E have disjoint write scopes and may be written in parallel, gated in sequence.

## 4. Decisions for the supervisor

Each has options, a concrete example per option and a recommendation. Nothing is decided in code;
§2 spells out the recommended option of each.

1. **D-L34-1 — when the tool is resolved.**
   (a, recommended) **in `Create`** (G1): `TSed.new s …` runs `ktool.gnu sed` once; `s.argv w`
   shows `/usr/local/bin/gsed`; a later PATH change does not move `s`. Fills the cache in the shell
   that creates the object, so `$(s.run)` in a child forks nothing extra.
   (b) **at every `buildArgv`** (the thttpserver precedent, `thttpserver/thttpserver.sh:650-695`):
   `cmd` stays `sed`, word 0 becomes ktool's answer each build (warm: 0.17-0.52 ms); follows a PATH
   change between two runs, but `$(s.run)` in a shell that never built pays the cold probe in every
   child, and `cmd` no longer equals argv word 0.
   (c) **at the first run**, stored in `cmd`: like (b) for the first call, like (a) afterwards — but
   a first run inside `$( )` stores nothing (the child's assignment dies), so it degrades to (b).
2. **D-L34-2 — where the path is stored.** (a, recommended) **`cmd`** (G2): no surface change,
   argv word 0 and the `command -v` pre-check already read it; `s.cmd` → `/usr/bin/sed`.
   (b) a new read-only property `Binary`, `cmd` kept as the family name: `s.Binary` →
   `/usr/bin/sed`, `s.cmd` → `sed`, and `buildArgv` × 6 + `tutil._prep`/`run` switch to `Binary` —
   a new public member on seven classes, and `cmd` would no longer be what runs.
3. **D-L34-3 — no GNU tool found** (§2.2). (a) `.new` rc 1 + one line, a disarmed instance the
   caller must still delete: `TSed.new s 's/a/b/' f || echo no` prints `no`. (b, recommended)
   `.new` rc 0 silently; the first `run`/sink/`argv`/static is rc 2 with ktool's line:
   `TSed.new s 's/a/b/' f; s.run || echo "rc=$?"` → `Error: TSed.buildArgv: no GNU sed: …; FreeBSD:
   pkg install gsed` + `rc=2`.
4. **D-L34-4 — a `cmd` the user sets by hand.** (a, recommended) used verbatim, no identity check
   (G7): `s.cmd = /usr/bin/sed` on FreeBSD runs BSD sed, and `--sandbox` fails there as it does today
   — the caller asked for it; `KCL_GNU_SED=/path` is the validated route. (b) validated: an
   assignment to `cmd` goes through ktool's identity check (`s.cmd = /usr/bin/sed` refused with
   "is not GNU sed") — needs a property setter on TUtil (`property cmd read … write _setCmd`), which
   also changes the generic `TUtil.new u git …` unless the check is skipped for the base.
5. **D-L34-5 — warm the cache at unit load.** (a, recommended) **no**: `kk.uses tsed` stays
   fork-free; a script whose first TSed use is inside `$( )` pays ~90 ms (msys) per call until it
   resolves once in the main shell; the README says so (G8). (b) **yes**: each wrapper's load runs
   `ktool.gnu FAMILY` — 73-107 ms per wrapper on msys at `kk.uses`, also in scripts that never use
   it; `$( )` one-liners are then always warm.
6. **D-L34-6 — the rc of a member on an instance without a tool** (with D-L34-3 b). (a,
   recommended) **rc 2** from the `cmd`-empty branch of `buildArgv`, `_lastRc` untouched (N2):
   `s.run; s.lastRc` → `-1`; one mechanical line per unit; `argv` answers the same. (b) **rc 1 +
   `_lastRc` 127**, like TUtil's command-not-found (`tutil/tutil.sh:399-402`): `s.run; s.lastRc` →
   `127`; needs a new branch in `tutil._prep` and `TUtil.run` before `buildArgv` (buildArgv cannot
   set `_lastRc`: `argv` calls it too), and `argv` would still need its own answer.
7. **D-L34-7 — 004 (the argv pins) on a box without the tool.** (a, recommended) **a stub** via
   `KCL_GNU_<F>` (T5): 004 runs its full count on Alpine/FreeBSD `clean` too, word 0 =
   `$TMP/stub/sed` on every box. (b) **the real tool**: 004 pins `"$SED_BIN"` and SKIPs every case
   where ktool finds nothing — about 150-200 more SKIP lines per non-GNU box, and the argv model is
   untested there. (c) both: the stub for the pins, plus one 004 case comparing `cmd` with the real
   ktool answer when there is one.
8. **D-L34-8 — TUtil's own CR filter** (§1.2). (a, recommended) **plain `command sed`** (C1): TGrep
   on FreeBSD with ggrep but no gsed works. (b) **ktool's sed**: one identity everywhere, but TGrep
   (stdin form) and TAwk's `--posix` fallback then also need GNU sed, and the filter's portable
   design (raw CR, probed `-u`) is unused.
9. **D-L34-9 — THead/TTail under uutils** (§1.5, U2). The OG8 suite numbers came from SKIPped
   behavioural cases. (a, recommended) **re-run with the new gates** on kb-ubuntu under the OG8 PATH
   shim (0.2.2 and 0.12.0) inside L34-E — needs the owner's approval to run the uutils binaries again
   (the ledger: "no fresh approval to run its binary"). Example of what it can find: `head: cannot
   open 'x' for reading` (GNU) vs the uutils wording at `thead/tests/005_Run.sh:456`. (b) **rely on
   the round-2 direct diff** (922 argument sets, 56 stderr-only differences) and let the first
   uutils user find the test deltas; the suites stay unexercised on uutils. (c) **revisit OG8**
   (refuse uutils again until measured) — undoes an owner decision on new evidence.
10. **D-L34-10 — critics.** (a, recommended) on L34-A (new TUtil member, shared test infra), L34-B
    (the template) and L34-C (inPlace behaviour); SV review for L34-D/E. (b) a critic on every card
    (each changes the public default of `cmd`) — +2 critic rounds for mechanical copies of L34-B.

## 5. Expected effect

| (VM, snapshot) | wrapper `SKIP:` lines today (`L3_triage.md` §2.1) | after L3.4 | SKIP text after |
|---|---|---|---|
| kb-alpine `clean` (busybox) | 763 | 763 (004 was never skipped and still runs, T5) | `no GNU sed: … ; Alpine: apk add sed` etc. |
| kb-alpine `clean-gnu` | 0 | 0 | — |
| kb-freebsd `clean` | 763 | 763 | `FreeBSD: pkg install gsed` / `gawk` / `gnugrep` / `findutils` / `coreutils` |
| kb-freebsd `clean-gnu` | **577** (tawk already ran) | **0** — gsed, ggrep, gfind, ghead, gtail run | — |
| kb-debian, kb-ubuntu, kb-fedora | 0 (gawk present?) | 0, or tawk SKIP with `apt install gawk` where gawk is absent | — |
| Windows (both runtimes) | 0 | 0 | — |

New rows are likely on FreeBSD `clean-gnu` once the 577 cases run (GNU tools on a BSD host, test
idioms of the T4 kind); they are L34-F's triage, budgeted by OG1. The two C10 rows (tawk 005, 006
on FreeBSD `clean-gnu`) close with L34-C.
