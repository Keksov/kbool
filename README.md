# kbool

kbool is a Free Pascal–flavoured toolkit for bash: a unit system with `uses`,
an object system with classes and dot notation, and ports of Free Pascal
RTL/FCL classes. Pure bash (5.2 and 5.3 are tested), fork-free on its hot paths.

| folder | what it is | read |
|---|---|---|
| `kbool.sh` | the startup file: loads the system units and the configuration | this page |
| [`kkore/`](kkore/README.md) | the system units (loaded by `kbool.sh`): the unit loader `kk.unit` / `kk.uses` / `kk.project` / `kk.config` / `kk.defined` / `kk.namespace` (`kuse.sh`), output and argument helpers (`klib.sh`), the error trap (`kerr.sh`), frames and unique names (`kvar.sh`), a key/value store (`kcfg.sh`) | [kkore/README.md](kkore/README.md) |
| [`kklass/`](kklass/docs/kklass_book.md) | classes: `defineClass`, the declarative API, the Pascal DSL (`class … end`), compiled caches, serialization | [the kklass book](kklass/docs/kklass_book.md), chapter [Units and uses](kklass/docs/kklass_book.md#units-and-uses) |
| [`kcl/`](kcl/README.md) | 29 units in 26 folders: ports of FPC/Delphi classes (`TList`, `TStringList`, `TDictionary`, `TIniFile`, `TPath`, …) and CLI-tool wrappers (`TGrep`, `TSed`, `TAwk`, …) | [kcl/README.md](kcl/README.md) |
| `ktests/` | the test framework and runner every suite uses | `ktests/ktest.sh` |
| `tests/tests.sh` | the master runner: every `*/tests/tests.sh` of the tree | [Running the tests](#running-the-tests) |
| [`docs/dev/`](docs/dev/README.md) | the development history: plans, ledgers, reviews, coverage notes | [docs/dev/README.md](docs/dev/README.md) |

The design of units and `uses` — every decision, with its reasons — is
[kklass/USES_PLAN.md](kklass/docs/dev/USES_PLAN.md).

## Install

`kkore`, `kklass`, `kcl` and `ktests` are git submodules, so clone with them:

```bash
git clone --recurse-submodules https://github.com/Keksov/kbool.git
# an existing clone: git submodule update --init
```

Nothing is built or installed: scripts `source` `kbool.sh` from wherever the
tree lives. Prerequisites: bash ≥ 5.2 (tested: 5.2.37 under Git-bash and 5.3.9 under
MSYS2, on Windows); for some kcl units the GNU tools they wrap or call —
coreutils (`head`, `tail`, `stat`, `mktemp`), `grep`, `sed`, `gawk`,
findutils `find` — and GNU netcat (`nc`) for `thttpserver`.

## Quick start

<!-- doctest -->
```bash
source /path/to/kbool/kbool.sh || exit      # or `source kbool.sh` when its folder is on $PATH
kk.uses tstringlist || exit                  # a unit by NAME; it loads kklass itself
TStringList.new fruits
fruits.Add banana
fruits.Add apple
fruits.Sort
fruits.Get 0; echo "$RESULT"                 # => apple
fruits.delete
kk.uses tstringlist; echo "again: rc=$?"     # => again: rc=0
```

`kbool.sh` must be **sourced** (executed it prints an error and exits 2). It
loads the system units `kuse klib kerr kvar kcfg` — they are always there, like
FPC's `System` — then reads the configuration. Everything else is a unit you
name: `kk.uses kklass`, `kk.uses tlist tdictionary`. `source kbool.sh` finds the
file through `$PATH` (bash's `sourcepath`, on by default) when the kbool folder
is on it.

**`KBOOL_HOME`** is exported by `kbool.sh`: the folder it was loaded from (the
system search path is `$KBOOL_HOME/kkore`, `$KBOOL_HOME/kklass`, every folder of
`$KBOOL_HOME/kcl`). It means only that: a preset `KBOOL_HOME` naming another
folder is overwritten with one `kbool: WARNING:` line. Sourcing ANOTHER copy
of `kbool.sh` while one is loaded is a no-op with one
`kbool: WARNING: … is ignored: kbool is already loaded from …` line (the same
file in any spelling is silent). A unit outside the kbool
tree finds `kbool.sh` through it (see [the header shapes](docs/reference.md#units)), so a child
shell started from a kbool script can load such a unit directly.

Sourcing a unit file directly — `source kcl/tlist/tlist.sh`,
`source kklass/kklass.sh` — still works: its first header line loads
`kbool.sh` when it is not loaded yet. `kk.uses` is the canonical way.

## Reference

- [Units](docs/reference.md#units)
- [`kk.uses`](docs/reference.md#kkuses)
- [Namespaces and defines](docs/reference.md#namespaces-and-defines)
- [Configuration](docs/reference.md#configuration)
- [Projects: `kk.project`](docs/reference.md#projects-kkproject)
- [Reloading during development](docs/reference.md#reloading-during-development)
- [Messages](docs/reference.md#messages)

## Running the tests

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
* The examples on this page marked as runnable are run by
  `kkore/tests/015_DocExamples.sh`; the kklass book's by
  `kklass/tests/142_DocExamples.sh`.
