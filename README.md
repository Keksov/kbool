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

The design of units and `uses` — every decision, with its reasons — is
[kklass/USES_PLAN.md](kklass/USES_PLAN.md).

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
tree finds `kbool.sh` through it (see the header shapes below), so a child
shell started from a kbool script can load such a unit directly.

Sourcing a unit file directly — `source kcl/tlist/tlist.sh`,
`source kklass/kklass.sh` — still works: its first header line loads
`kbool.sh` when it is not loaded yet. `kk.uses` is the canonical way.

## Units

A **unit** is a file whose first lines (after an optional shebang, blank lines
and `#` comments, within the first 512 characters) are the two header lines.
Its name is its file stem (`kk.unit tlist` lives in `tlist.sh`; another name is
an error). A unit is loaded **once** per shell: `kk.uses` of a loaded unit and a
repeated plain `source` of its file are no-ops (~0.2 ms; `kk.uses` of a loaded
name ~30 µs). Two shapes:

```bash
# a unit INSIDE the kbool tree (kcl/tlist/tlist.sh; kkore and kklass use ../kbool.sh)
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tlist.sh}../../kbool.sh" || return
kk.unit tlist || return $__kk_unit_rc
```

```bash
# a unit OUTSIDE the tree (yours): kbool is found through KBOOL_HOME
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit myunit || return $__kk_unit_rc
```

Line 1 loads `kbool.sh` when it is not loaded yet; without kbool and without
`KBOOL_HOME` the user form fails the `source` with rc 2 (bash prints
`/kbool.sh: No such file or directory`) and the caller goes on. Line 2
registers the unit: `kk.unit` returns 0 (load it now), 1 (already loaded: the
source returns 0) or 2 (an error, printed: the source returns 2). A unit's own
name is a declared function namespace: it may define `myunit.*` helpers, and no
class or instance may take that name. Units take no arguments (`source unit.sh
x` prints a WARNING). A unit's dependencies are `kk.uses` lines in it. While
a unit loads, **`KK_UNIT_DIR`** is its own folder (absolute, as sourced) — the
way it finds its data files; read it at file scope (outside a load it means
nothing), and keep a copy if code needs the folder later.

<!-- doctest -->
```bash
cat > greet.sh <<'EOF'
#!/bin/bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit greet || return $__kk_unit_rc

echo "greet: loading"
greet.hello() { printf 'hello, %s\n' "$1"; }
EOF
source /path/to/kbool/kbool.sh || exit
kk.uses greet || exit                 # => greet: loading
kk.uses greet; source ./greet.sh      # both no-ops: loaded once
greet.hello world                     # => hello, world
# a child shell inherits KBOOL_HOME, so a direct source bootstraps kbool there
bash -c 'source ./greet.sh && greet.hello child'                 # => greet: loading
                                                                  # => hello, child
env -u KBOOL_HOME bash -c 'source ./greet.sh; echo "rc=$?"'      # => rc=2
# 2> /kbool.sh: No such file or directory
```

A unit finds its own data files through `KK_UNIT_DIR`, wherever the caller is:

<!-- doctest -->
```bash
mkdir -p lib/colors
printf 'red\ngreen\n' > lib/colors/names.txt
cat > lib/colors/colors.sh <<'EOF2'
#!/bin/bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit colors || return $__kk_unit_rc

mapfile -t COLORS < "$KK_UNIT_DIR/names.txt"     # the unit's own data file
EOF2
source /path/to/kbool/kbool.sh || exit
cd /                                 # the caller's cwd does not matter
kk.uses lib/colors/colors.sh || exit # relative to this file, not to $PWD
echo "${COLORS[*]}"                  # => red green
```

## `kk.uses`

    kk.uses [--optional] NAME|PATH ...

* An argument with `/` or `\`, or ending in `.sh`, is a **PATH** — relative to
  the folder of the file that calls `kk.uses`; without a calling file (a
  prompt, `bash -c`, `bash -s`, a pipe) relative to `$PWD`. Any other argument
  is a unit **NAME** — and a NAME is never looked up in `$PWD` by a
  non-interactive caller without a file (below).
* A NAME is looked up, first match wins: (1) the calling file's folder — a
  relative calling file against the `$PWD` it was loaded from, so a script that
  `cd`s keeps its folder; without a calling file only at an **interactive
  prompt** (`$PWD`), never from `bash -c`, `bash -s` or a pipe; (2) the project
  and config `unitpath` folders, in order; (3) the system paths `kkore`,
  `kklass`, `kcl/*` (`dir/*` = every subfolder). Only files that carry the
  header `kk.unit NAME` count (a `bench.sh` or a plain script is reachable by
  path only). A LOADED kkore or kklass unit is never resolved again: a
  `klib.sh` in your folder cannot replace kkore's. That protects loaded units
  only — for a name not loaded yet the calling file's folder still comes first
  (first match, silently): a script whose folder holds a headered `kklass.sh`
  loads that one on its first `kk.uses kklass`.
* A name is unique: a NAME that resolves to another file than the loaded unit
  of that name is an error (rc 2), and so is a second unit file of a loaded
  name.
* rc 0: everything loaded (or already loaded). Otherwise the first failure:
  rc 2 for a loader error (printed — not found, a bad name, a cycle
  `a -> b -> a`), else the unit's own rc. A failed load is forgotten, so a retry
  loads it again — and the failure **taints** the unit being loaded around the
  `kk.uses`: its next load (a plain `source` or `kk.uses`) runs it again
  instead of counting it complete.
* `--optional`: a failure neither taints nor prints; the rc still reports it —
  `kk.uses --optional fancy || plain_fallback`.
* A file without the header loaded by `kk.uses PATH` is loaded once too (by
  its normalised path). `kk.uses` sources each unit with no positional
  arguments; it never forks.

<!-- doctest -->
```bash
cat > needy.sh <<'EOF'
#!/bin/bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit needy || return $__kk_unit_rc

echo "needy: body"
kk.uses --optional fancy || echo "needy: no fancy, plain mode"
kk.uses missing || return
EOF
source /path/to/kbool/kbool.sh || exit
kk.uses needy; echo "rc=$?"       # => needy: body
                                  # => needy: no fancy, plain mode
                                  # => rc=2
# 2> kbool: error: kk.uses: unit 'missing' not found
# 2> kbool: error: kk.uses: loading unit 'needy' failed (rc=2)
kk.uses needy; echo "rc=$?"       # => needy: body
                                  # => needy: no fancy, plain mode
                                  # => rc=2
```

## Namespaces and defines

`kk.namespace X [Y …]` declares more function namespaces of the calling file
(a unit that defines `str.*` besides its own `myunit.*`). kklass refuses a class
or an instance named like a declared namespace, a DSL verb or a class. A
namespace another file declared may be shared only by a file in the **same
folder** (a package); anywhere else it is rc 2. `kk.defined NAME` tests a
define of the configuration (rc 0 / 1), in an ordinary `if`.

<!-- doctest -->
```bash
cat > strutil.sh <<'EOF'
#!/bin/bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit strutil || return $__kk_unit_rc

kk.namespace str || return
str.upper() { RESULT=${1^^}; }
EOF
source /path/to/kbool/kbool.sh || exit
kk.uses kklass strutil || exit
str.upper abc; echo "$RESULT"                         # => ABC
defineClass str "" property x; echo "class: rc=$?"    # => class: rc=1
# 2> kklass: Duplicate identifier: 'str' is a function namespace (str.* of unit strutil
if kk.defined DEBUG_BUILD; then echo "debug build"; else echo "release build"; fi   # => release build
```

## Configuration

`key = value` files, one setting per line; `#` lines are comments; nothing is
evaluated (no quotes, no `~` or `$VAR`); UTF-8, LF or CRLF. Keys:

| key | kind | meaning |
|---|---|---|
| `unitpath` | list, a folder per line | searched by `kk.uses NAME` after the caller's folder, before the system paths; `dir/*` = every subfolder; relative = relative to the config file's folder |
| `defines` | list, space-separated names | `kk.defined NAME` |
| `debug` | `quiet` / `default` / `debug` | sets `VERBOSE_KKLASS` — only when nobody else set it |
| `ckkdir` | folder | kklass's compiled-cache folder (`KKLASS_CKK_DIR` wins) |

A **list key repeats**: every line appends one entry. A scalar key takes the
last line. An **empty list value** (`unitpath =`) drops the entries above it in
its own file and every weaker *environment* level's — never the project's.
Unknown keys and bad lines print `kbool: WARNING: FILE:LINE: …` and are skipped.

The levels, strongest first:

1. `$KBOOL_CONFIG` — a config file path (set, non-empty and missing: `kbool.sh`
   fails with rc 2; an empty value is ignored);
2. the project file — `kk.project`;
3. the user config — `~/.kbool/config`, else `$USERPROFILE/.kbool/config`;
4. the system config — `/etc/kbool/config`, else `$ProgramData/kbool/config`;
5. built-in defaults: no defines, no debug level, no project folders; the
   system paths are always searched last.

A scalar takes the strongest level that sets it; a list takes every level's
entries, strongest first, without duplicates. No config at all is fine: the
kbool root is found from `kbool.sh`'s own location.

<!-- doctest -->
```bash
mkdir -p "$HOME/.kbool"
cat > "$HOME/.kbool/config" <<'EOF'
# the user level
unitpath = /opt/shared-units
defines  = USER_BOX
EOF
cat > my.conf <<'EOF'
unitpath =
unitpath = units/*
defines  = FAST
debug    = quiet
EOF
export KBOOL_CONFIG=$PWD/my.conf
source /path/to/kbool/kbool.sh || exit
kk.config unitpath; echo "${RESULT#"$PWD"/}"    # => units/*
kk.config defines d; echo "${d[*]}"             # => FAST USER_BOX
kk.defined FAST && echo "FAST is defined"       # => FAST is defined
echo "VERBOSE_KKLASS=$VERBOSE_KKLASS"           # => VERBOSE_KKLASS=quiet
```

## Projects: `kk.project`

    kk.project PATH|NAME

reads a project file (the same keys) as the second-strongest level: its
`unitpath` feeds `kk.uses NAME`, its `defines` `kk.defined`, its `debug` and
`ckkdir` take effect. A PATH (with `/` or `\`, or ending in `.conf`) is relative
to the calling file's folder; paths inside the file are relative to the file
itself, so a project is relocatable. A NAME is `~/.kbool/NAME/project.conf`
(else under `$USERPROFILE/.kbool`); there is no automatic discovery of a
project file. Rules: `kk.project` comes **before the first `kk.uses` of a
non-system unit** and before any unit is sourced — later it is rc 2. The
*system units* are only `kuse klib kerr kvar kcfg` (what `kbool.sh` loads):
`kk.uses kklass`, any kcl unit, a NAME that is not found and an `--optional`
one all count as the first use. It runs once — the same file again is an rc-0
no-op, another file rc 2.

<!-- doctest -->
```bash
mkdir -p app/lib
cat > app/lib/greet.sh <<'EOF'
#!/bin/bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit greet || return $__kk_unit_rc

if kk.defined LOUD; then
    greet.hello() { printf 'HELLO, %s!\n' "${1^^}"; }
else
    greet.hello() { printf 'hello, %s\n' "$1"; }
fi
EOF
cat > app/app.conf <<'EOF'
unitpath = lib
defines  = LOUD
EOF
cat > app/main.sh <<'EOF'
source /path/to/kbool/kbool.sh || exit
kk.project app.conf || exit          # relative to this file's folder
kk.uses greet || exit                # found on the project's unitpath
greet.hello world
kk.project app.conf; echo "same project again: rc=$?"
EOF
bash app/main.sh                     # => HELLO, WORLD!
                                     # => same project again: rc=0
bash -c 'source /path/to/kbool/kbool.sh; kk.uses tstopwatch; kk.project app/app.conf; echo "rc=$?"'   # => rc=2
# 2> too late, unit 'tstopwatch' is already in use
```

An empty list value in an *environment* level resets the user and system
entries, never the project's — even from `KBOOL_CONFIG`, the stronger level:

<!-- doctest -->
```bash
mkdir -p "$HOME/.kbool" proj/units
printf 'unitpath = /opt/user-units\n' > "$HOME/.kbool/config"
printf 'unitpath =\ndefines =\n' > env.conf
printf 'unitpath = units\ndefines = PROJ\n' > proj/project.conf
export KBOOL_CONFIG=$PWD/env.conf
source /path/to/kbool/kbool.sh || exit
kk.config unitpath; echo "before: rc=$?"          # => before: rc=1
kk.project proj/project.conf || exit
kk.config unitpath; echo "${RESULT#"$PWD"/}"      # => proj/units
kk.defined PROJ && echo "PROJ defined"            # => PROJ defined
```

## Reloading during development

A unit is loaded once; there is no reload. The escape hatch for a prompt is
`kk.unit --forget NAME`: the unit's registration — and the classes it declared —
are dropped, so the next `source` or `kk.uses` loads it again (rc 0 forgotten,
1 not registered, 2 a system unit or one being loaded right now). Live
instances of a forgotten class are yours to delete. For one class of a file
without a header: `kk.class --forget CLASS` (kklass).

<!-- doctest -->
```bash
cat > counter.sh <<'EOF'
#!/bin/bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2
kk.unit counter || return $__kk_unit_rc
echo "counter: loaded"
EOF
source /path/to/kbool/kbool.sh || exit
kk.uses counter                                    # => counter: loaded
kk.uses counter
kk.unit --forget counter; echo "forget: rc=$?"     # => forget: rc=0
kk.uses counter                                    # => counter: loaded
kk.unit --forget klib; echo "system unit: rc=$?"   # => system unit: rc=2
# 2> a system unit loaded by kbool.sh cannot be forgotten
```

## Messages

Loader errors and warnings are `kbool: error: …` / `kbool: WARNING: …` lines
on stderr, silenced only by `VERBOSE_KKLASS=quiet`; kklass prints
`kklass: Duplicate identifier: …` and `kklass: WARNING: …`. The member contract
of the libraries (rc 1 + `RESULT=''`, a diagnostic only under
`VERBOSE_KKLASS=debug`) is [kcl/README.md §1](kcl/README.md#1-the-kcl-contract).

## Running the tests

```bash
bash tests/tests.sh                          # every suite of the tree (the master sweep)
bash kkore/tests/tests.sh                    # one suite
bash kcl/tlist/tests/tests.sh --verbosity info
bash kklass/tests/tests.sh --mode single     # sequential; the default is threaded x8
bash kkore/tests/tests.sh -n 15              # only test file 015 (-n 1,3-5 lists, ranges)
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
