# Contributing to kbool

kbool is five git repos: this root (`kbool.sh`, CI, tools) and the submodules
[`kcl`](https://github.com/Keksov/kcl) (the class library),
[`kklass`](https://github.com/Keksov/kklass) (the object system),
[`kkore`](https://github.com/Keksov/kkore) (the system units) and
[`ktests`](https://github.com/Keksov/ktests) (the test framework and the gate).
Send a pull request to the repo that owns the file, against `main`. Work in a
full checkout either way — the tests need the whole tree:

```bash
git clone --recurse-submodules https://github.com/Keksov/kbool.git
cd kbool/kcl          # e.g. a kcl change: add your fork as a remote here, branch, commit, push
```

## Run the tests — one command

From the kbool root:

```bash
bash ktests/tools/gate.sh all                          # every suite
bash ktests/tools/gate.sh kcl/tregex kklass            # some suites
bash ktests/tools/gate.sh --changed                    # the suites your uncommitted changes touch
bash ktests/tools/gate.sh --rerun-failed 1 --timeout 900 all   # exactly what each CI row runs
```

* **Suites**: `all`, or a suite's folder without `/tests` — `kkore`, `kklass`,
  `ktests`, `kcl/<unit>` (`kcl/tregex`) — or a unique last part (`tregex`).
  `kcl` alone is only `kcl/tests` (the unit-shape checks of every kcl unit), not
  all the units. An unknown name lists the suites and runs nothing (exit 2).
  A change in `kkore/`, `kklass/`, `ktests/` or `kbool.sh` affects every suite: run `all`.
* Each suite runs in a sandbox of its own (its own `HOME`, temp dir, cwd and a
  deny-by-default environment): your `~/.kbool/config` does not change a result.
* The output is one line per suite and a last line
  `__GATE__:VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed_tests:total_tests`;
  the exit code says the same (below). The first line names the run's folder
  (`out=…`): `cells/NNN/log.txt` is one suite's full output.
* **Runtimes**: the bash that runs `gate.sh` (with a `[WARN] one runtime only`);
  more with `--bash PATH`, repeatable (e.g. a bash 5.1 build next to yours).
* In full: [ktests/tools/README.md](ktests/tools/README.md#gatesh--the-phase-gate).

While you work, run one suite or one file in your own shell (one suite at a
time — suites share `tests/.ckk`):

```bash
bash kcl/tregex/tests/tests.sh                 # one suite (threaded, 8 workers; --mode single: sequential)
bash kcl/tregex/tests/tests.sh -n 3,5-7        # only test files 003, 005-007
bash kcl/tregex/tests/003_Match.sh -v info     # one file directly, every assertion shown; exit 1 if a test failed
```

**What you need**

* **bash ≥ 5.1** (`kbool.sh` refuses an older one with exit 2). On macOS
  `/bin/bash` is 3.2: start the gate with Homebrew's bash
  (`"$(brew --prefix)/bin/bash" ktests/tools/gate.sh all`).
* A normal user, not root (some tests expect `chmod 000` to stop a read).
* The kcl wrappers `TSed`, `TAwk`, `TGrep`, `TFind`, `THead`, `TTail` need the
  GNU tool (`gsed`, `gawk`, … on FreeBSD and macOS; the package per platform:
  [kkore/README.md §7](kkore/README.md#7-the-gnu-tool-resolver-ktoolsh)),
  `thttpserver` needs GNU netcat or socat, some tests need `timeout` (macOS:
  brew coreutils' `gtimeout`). Without them those cases pass as `SKIP: <why>`.
* The reference package lists: `.github/workflows/ci.yml`, `.github/ci/linux.sh`.
* Windows: Git for Windows' bash or MSYS2. Never mix the two in one process
  tree — run a bash with its own folder first on `PATH`; for both at once:
  `KT_GATE_BASHES="C:/Program Files/Git/usr/bin/bash.exe;C:/msys64/usr/bin/bash.exe" bash ktests/tools/gate.sh all`.

## Running the tests by hand

Moved verbatim from the README on 2026-10-31 (only "on this page" became "in
README.md and docs/reference.md").

```bash
bash tests/tests.sh                          # every suite of the tree (the master sweep)
bash kkore/tests/tests.sh                    # one suite
bash kcl/tlist/tests/tests.sh --verbosity info
bash kklass/tests/tests.sh --mode single     # sequential; the default is threaded x8
bash kkore/tests/tests.sh -n 15              # only test file 015 (-n 1,3-5 lists, ranges)
```

To check a change on **both runtimes**, use the phase gate: each suite runs
in a hermetic sandbox under each bash, one line per (bash, suite), one verdict
and exit code; `--changed` picks the suites your uncommitted diff touches
(name suites instead, or `all`) — [ktests/tools/README.md](ktests/tools/README.md#gatesh--the-phase-gate):

```bash
bash ktests/tools/gate.sh --bash C:/bin/Git/usr/bin/bash.exe --bash C:/bin/msys64/usr/bin/bash.exe --changed
```

* Run suites **one at a time** (they share `tests/.ckk` and temp names), and
  read results by grepping **all** `[FAIL]` lines, not the tail.
* A second bash: the runner starts every test file with the `bash` found on
  `PATH`, so put that bash's folder FIRST on `PATH` and start the runner with
  it — `PATH="/opt/bash53/bin:$PATH" /opt/bash53/bin/bash tests/tests.sh` —
  otherwise the children run the other build. Environment variables set in one
  MSYS2 / Git-bash installation may not reach a bash of another: set them inside
  the second shell (`bash -c 'export X=…; …'`).
* The runner **isolates the configuration** of every test file: an empty
  `HOME` of its own, the `/etc/kbool` level pointed at a missing folder,
  `KBOOL_CONFIG`, `KBOOL_HOME`, `USERPROFILE` and `ProgramData` unset,
  `BASH_ENV` emptied — a developer's `~/.kbool/config` cannot change a
  result. A test that needs a config installs its own. A suite file run
  on its own (`bash kkore/tests/011_ConfigProject.sh`) sees the environment
  as it is.
* **No process may outlive a run**: the master sweep fails a suite that left
  any process of its session running whose parent is gone (named, then
  stopped); a TERM/Ctrl-C to the sweep stops the running suite too; and
  `bash ktests/tools/strays.sh list` / `stop` finds and ends leftovers of a
  killed run (once per bash runtime; unfiltered `stop` only touches orphans
  older than 120 min) — see `ktests/tools/README.md`.
* The examples in README.md and docs/reference.md marked as runnable are run by
  `kkore/tests/015_DocExamples.sh`; the kklass book's by
  `kklass/tests/142_DocExamples.sh`.

## What CI checks

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs the gate (`--rerun-failed 1
--timeout 900 all`) on 13 rows, one job each:

| job | rows |
|---|---|
| `linux` | `ubuntu host, system bash`; containers `alpine, bash 5.1` / `5.2` / `5.3` (bash 5.1.16, 5.2.37, 5.3.20), `debian 13`, `ubuntu 24.04`, `fedora 44` — the gate runs as a non-root user |
| `macos` | Homebrew bash with Apple's BSD tools (`bsd tools, brew bash`) and with the GNU tools (`gnu tools, brew bash`); the bsd row also checks that `/bin/bash` 3.2 is refused |
| `freebsd` | FreeBSD 15.1, pkg bash: `clean, pkg bash` (bash git curl perl5) and `gnu, pkg bash` (+ coreutils gsed gawk findutils gnugrep diffutils netcat socat) |
| `windows` | `git-bash` (Git for Windows' bash) and `msys2` |

A pull request to `kcl`, `kklass`, `kkore` or `ktests` runs the same 13 rows:
that repo's `ci.yml` calls kbool's workflow, which checks out kbool `main` with
every submodule at kbool's pointers and puts your PR in place of its repo. So a
change that needs a change in another repo first waits for that one to land.
The checks are named `linux (debian 13)` in kbool and
`kbool / linux (debian 13)` in a submodule repo.

Each row uploads the gate's run folder as the artifact `gate-<job>-<row>`
(`gate-linux-debian-13`, `gate-macos-bsd`, `gate-windows-msys2`, …; 14 days):
`progress.txt` (the gate's output), `cells/NNN/log.txt` (one suite's full
output), `cells.tsv`, `summary.json`. The job summary shows the `[FAIL]` lines.

## What the verdicts mean

| verdict | meaning | gate exit | CI |
|---|---|---|---|
| PASS | every test passed | 0 | green |
| FAIL | a test failed; the first `[FAIL]` lines are under the suite's line | 1 | red |
| FLAKY | it failed, and every failed file passed on the rerun (`--rerun-failed`) | 4 | green with a warning — if your change touched that suite, say so in the PR |
| ENV | the machine, not the test: the failed files all died of a fork failure; re-run once by the gate | 3 | green with a warning |
| TIMEOUT | stopped at `--timeout` | 1 | red |
| STRAY | the suite left a process running (stopped by the gate) — a bug in a test or the unit: fix it, do not re-run | 1 | red |
| CRASH | the runner itself did not finish (no summary) | 1 | red |
| NOTRUN | the suite has no test file — not a failure | 0 (1 if no suite ran at all) | green |

The worst cell decides. The CI rule ([`.github/ci/verdict.sh`](.github/ci/verdict.sh)):
exit 0 is green; exit 3 (ENV) and 4 (FLAKY) are green only when the gate printed
its `__GATE__` line; everything else is red — 1, 2 (usage), 5 (the platform setup
failed: packages, docker pull), 124 (timeout), and 3 or 4 without a `__GATE__` line.

## House rules

* **bash 5.1 is the floor.** The `*_Bash51Hazards.sh` tests (kcl, kklass, kkore, ktests) reject, in
  non-test code, a quoted redirect target `>&"$fd"` (write `>&$fd` after
  checking it is a number), `[[ -v a["$k"] ]]` (write `${a[$k]+x}`) and
  `unset a["$k"]` (write `unset 'a[$k]'`).
* **No forks in hot paths**: inside a member, no `$( )`, pipe or external
  command on a path that runs per element; an external tool once per call, and
  only for what bash cannot do ([kcl/README.md §1.8](kcl/README.md#18-no-forks-in-hot-paths)).
* **A kcl unit keeps the kcl contract** (`RESULT`, rc 0/1/2, `set -eu` clean,
  locale): [kcl/README.md §1](kcl/README.md#1-the-kcl-contract); a new unit:
  [Adding a unit](kcl/README.md#adding-a-unit).
* **No new external tool without a reason.** The same code runs on GNU, BSD
  (FreeBSD, macOS), busybox and Windows userlands; use bash where bash can, and
  say in the PR why a tool is needed. A GNU-only tool is found through `ktool`.
* **Tests for every change**, in the suite's `tests/` folder, named `NNN_Name.sh`
  (three digits; the next free number). Copy a sibling: `source` ktest.sh,
  `kt_test_init "Name" "$SCRIPT_DIR" "$@"`, then per case `kt_test_start "what"`
  and `kt_test_pass` / `kt_test_fail`. No `exit`, no file-scope `return`, no
  `trap … EXIT` of your own, and end every background process you start
  ([how the runner judges a file](ktests/docs/README.md#how-the-runner-judges-a-test-file)).
* **A case that cannot run here still counts**: `kt_test_pass "SKIP: <why>"`
  (a missing tool) or `kt_test_pass "N/A: <why>"` (the platform has no such
  thing), so a suite has the same total everywhere and a changed total means something.
* **LF line endings** (every repo has `* text=auto eol=lf`; check with
  `git ls-files --eol`). **Scripts are executable**: shebang
  `#!/usr/bin/env bash`, mode 100755 (on Windows `git update-index --chmod=+x FILE`).
* **Docs move with the code**: a kcl unit's API and contract are its
  `kcl/<unit>/README.md`; plans, ledgers and coverage notes live under
  `<repo>/docs/dev/` (`kcl/docs/dev/<unit>/TEST_COVERAGE_NOTES.md`). Examples
  under `<!-- doctest -->` are run by tests (kkore 015, kklass 142). Check links
  with `bash tools/porting/mdlinks.sh`.

## Pull requests

* One topic per PR. Say which suites you ran, on which bash and platform, and
  paste the `__GATE__` line.
* kbool itself is developed with AI assistance (planned, written and reviewed
  with AI agents, checked by the maintainer and the gate), and every
  contribution is reviewed the same way, whether or not AI tools helped write it.
* Security problems: [SECURITY.md](SECURITY.md). Licence: each repo's `LICENSE`.
