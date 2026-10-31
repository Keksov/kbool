# Changelog — kbool

> Draft: reviewed before the first release.

kbool is a Free Pascal flavoured toolkit for bash: units with `uses`, classes
with dot notation, and ports of FPC/Delphi classes. This repository is the
umbrella: `kbool.sh` (the entry point), the master test runner, the lab and
portability tooling, CI, and the four submodules. There is no tag or release yet;
this file groups the whole history by phase, newest first, and tells the
cross-repo story. Each component has its own changelog:

* kcl (the class library): <https://github.com/Keksov/kcl/blob/main/CHANGELOG.md>
* kklass (the object system): <https://github.com/Keksov/kklass/blob/main/CHANGELOG.md>
* kkore (the system units): <https://github.com/Keksov/kkore/blob/main/CHANGELOG.md>
* ktests (the test framework and gate): <https://github.com/Keksov/ktests/blob/main/CHANGELOG.md>

Phase names such as "launch L5.4" refer to
[docs/dev/LAUNCH_PLAN.md](docs/dev/LAUNCH_PLAN.md). Commit hashes in parentheses
point at the change for readers who want the diff.

## Unreleased — first public release (draft)

### Documentation (2026-10-22 .. 2026-10-31, launch L6)

* README rewritten as the front door: the Pascal DSL first, requirements,
  platforms, the portability layer, a comparison with other projects and how
  kbool is built; the reference part moved to [docs/reference.md](docs/reference.md)
  (bbfc86d, 2306958).
* Internal plans, ledgers and reviews moved to `docs/dev/` in every repository
  ([docs/dev/README.md](docs/dev/README.md)) (56180c6).
* `tools/porting/mdlinks.sh` checks markdown links and anchors (bcdaf0f);
  `numbers.sh` produces the project's numbers as data (14ae044).

### CI on 13 platforms (2026-10-29 .. 2026-10-30, launch L5)

* **CI**: every push to `main` runs the full test suite on 13 rows: Linux (host
  Ubuntu, Ubuntu 24.04, Debian 13, Fedora 44, Alpine with bash 5.1, 5.2 and 5.3),
  macOS (BSD tools and GNU tools with Homebrew bash), FreeBSD 15.1 (clean and with
  GNU tools) and Windows (Git-bash and MSYS2). One verdict script reads all rows
  ([.github/workflows/ci.yml](.github/workflows/ci.yml)).
* The first runs failed on 5 rows with 72 failing cases in 14 causes; they were fixed
  in the components and the matrix was green twice in a row on all 13 rows
  (cf02408). The fixes include: bounded FIFO waits on macOS, a word-edge rewrite for
  regexes where the C library lacks `\b`, session ids and pipe identity on macOS,
  suspend handling on Windows runners, a start probe that cannot kill its caller.
* The CI workflow is reusable (`workflow_call`): each submodule has a workflow that
  runs this matrix with its own commit (9e894d7).
* README: CI badge, tested bash versions and platforms; `CONTRIBUTING.md` in all five
  repositories; `diag.yml`, a manual read-only diagnostics workflow.

### Minimum bash is 5.1 (2026-10-29 .. 2026-10-30, launch L4)

* kbool was measured on bash 5.1.16, 5.0.18 and 4.4.23 (built from signed GNU
  sources in a lab VM) and its guard on 3.2 to 5.2. The cost report named three
  causes for 5.1 incompatibility and a ten-line prototype passed the full suite on
  5.1.16 and 5.2.37.
* **The minimum bash is 5.1** (was 5.2): `kbool.sh` refuses non-bash, POSIX-mode
  bash and bash older than 5.1 with rc 2; fixes landed in kcl, kklass, kkore and
  ktests, with static checks that keep 5.1 hazards out (2b0ad7f).
* The lab driver's gate honours `KT_GATE_BASHES`, and phases touching the core run a
  5.1 "bash-floor" gate (efa12ee).

### Alpine, FreeBSD and the GNU-tool policy (2026-10-26 .. 2026-10-29, launch L3)

* Gate runs on Alpine (musl, busybox) and FreeBSD, each with and without GNU tools
  installed (240 failing rows), triaged into 14 clusters and nine fix batches.
* **GNU tools are resolved, not assumed**: the wrapper units (`TGrep`, `TSed`, `TAwk`,
  `TFind`, `THead`, `TTail`) find a real GNU tool through `ktool`, including the
  `g`-prefixed names on FreeBSD; with none they answer rc 2 with the reason. uutils
  coreutils `head` and `tail` from 0.2.2 are accepted.
* `TFile.encrypt` moved to an authenticated format; `TPipe` recovers exit statuses
  that bash loses; `TPath` has portable time and path helpers; `math` runs on BSD awk;
  `thttpserver` runs on socat where GNU netcat is missing.
* Lab: a kernel-parameter fix for timer stalls in the Alpine VM, with `tools/vmlab/checks/timer.sh`.
* Closing gates: 8 of 8 configurations pass (five VMs including both Alpine/FreeBSD
  snapshots, and Windows with two runtimes).

### Linux: first gate runs and fixes (2026-10-20 .. 2026-10-28, launch L2)

* The first Linux gate (Ubuntu, Debian, Fedora, and Debian under `de_DE`) found 111
  failing rows; triage turned them into decisions and fixes (b4ca088, b144365).
* The test harness runs on Linux and busybox (ktests); wrapper tests run on Linux
  tool versions; `#!/usr/bin/env bash` and exec bits in all five repositories.
* **`kbool.sh` has a bash guard**: not bash, POSIX mode, or too old: rc 2 and a
  message instead of an obscure error.
* One CR contract for the wrappers, `TPipe.stop` stops a whole process tree, a
  portable `math` engine, `TSed` literal-replace helpers.
* Comma-locale fix: `EPOCHREALTIME` splits are safe under `ru_RU`/`de_DE`.
* Closing gates for Linux passed (b3a8374).

### The VM lab (2026-10-20 .. 2026-10-26, launch L1)

* **`tools/vmlab/vmlab.sh`** drives dedicated lab VMs from Git-bash: `status`, `up`,
  `down`, `reset`, `snapshot`, `run`, `sync`, `fetch` and `gate`. See
  [tools/vmlab/README.md](tools/vmlab/README.md).
* Five VMs created by script: Ubuntu, Debian, Fedora, Alpine, FreeBSD, each with a
  `clean` snapshot (no GNU tools) and a `clean-gnu` snapshot where it applies; a
  Debian snapshot with extra bash builds (5.1, 5.0, 4.4, 3.2).

### Portability inventory and repository basics (2026-10-20 .. 2026-10-22, launch L0)

* MIT `LICENSE` in all five repositories; `.gitattributes` with LF line endings.
* A portability scanner, an external-tool table per unit and a bash-feature map by
  version ([tools/porting/README.md](tools/porting/README.md)), feeding the ranked
  hazard list in [docs/dev/PORTING.md](docs/dev/PORTING.md).

### The test gate (2026-10-17 .. 2026-10-20)

* **`ktests/tools/gate.sh`**: one command runs the suites on both bash runtimes in
  hermetic cells and prints one verdict; the master sweep checks for stray processes.
* Rounds 5 and 6: class building forks nothing (loading a class-heavy unit is 17 to
  32 times faster) and method bodies are isolated from their caller's variables.

### `kbool.sh` and `uses` (2026-10-06 .. 2026-10-15)

* **`kbool.sh`**, the loader entry point: it loads the system units, reads the
  configuration chain, declares the namespaces and boots the headered system
  units. `kk.uses tlist` loads a unit by name; `KBOOL_HOME` names the loaded tree.
* All 26 kcl unit folders became kbool units.
* The design is [kklass/docs/dev/USES_PLAN.md](kklass/docs/dev/USES_PLAN.md).

### Review rounds 2 to 4 (2026-10-01 .. 2026-10-05)

* kklass: the `$this.NAME` text rewrite was removed, serialization and declaration
  checks hardened, instance/static property clashes refused, one shared identifier
  rule; ktests: an aborted test file can no longer report green. See the component
  changelogs for the breaking changes.

### New units and the CLI-tool wrappers (2026-09-09 .. 2026-09-30)

* kcl grew `THashSet`, `TPipe`, `TUtil` and the GNU-tool wrappers `TGrep`, `THead`,
  `TTail`, `TFind`, `TSed`, `TAwk`, then the `thttpserver` package (a small HTTP
  server on kklass).
* Timing tests no longer fork inside timed windows (8854319).

### Reviews of kklass and kcl (2026-09-05 .. 2026-09-09)

* kklass: 12 review findings closed; `.new` 4.8 times faster, `.delete` no longer
  scans every shell function.
* kcl: a deep review of all units and a ten-phase fix plan (P0-P10) produced the
  kcl contract (results in `RESULT`, silent rc 1, no forks in hot paths); `fpjson`
  was re-planned.

### FPC/Delphi ports (2026-07-11 .. 2026-07-18)

* kcl gained `dateutils`, `math`, `tdictionary`, `tstopwatch`, `tregex`, `tarray`,
  `tobjectlist`, `tinifile` and `tqueuestack`; kklass got a Pascal DSL front-end.

### Hardening and first documentation (2026-07-08 .. 2026-07-09)

* A security hardening and performance pass over the whole tree (02cc5fa); kklass
  JSON escaping and the kklass book corrected.

### Origin (2025-12-01 .. 2026-06-01)

* The repository was created on 2025-12-01 with kkore, kklass, kcl and ktests as
  submodules; the next months were prototype work in the components (the oldest
  components date from October and November 2025).
