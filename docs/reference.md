# kbool reference

Moved verbatim from the README on 2026-10-22; the entry page is [../README.md](../README.md).

- [Units](#units)
- [`kk.uses`](#kkuses)
- [Namespaces and defines](#namespaces-and-defines)
- [Configuration](#configuration)
- [Projects: `kk.project`](#projects-kkproject)
- [Reloading during development](#reloading-during-development)
- [Messages](#messages)

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
#!/usr/bin/env bash
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
#!/usr/bin/env bash
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
#!/usr/bin/env bash
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
#!/usr/bin/env bash
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
#!/usr/bin/env bash
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
instances of a forgotten class are yours to delete (their names are no longer
protected from a class declaration). For one class of a file
without a header: `kk.class --forget CLASS` (kklass; a WARNING names its live
instances).

<!-- doctest -->
```bash
cat > counter.sh <<'EOF'
#!/usr/bin/env bash
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
`VERBOSE_KKLASS=debug`) is [kcl/README.md §1](../kcl/README.md#1-the-kcl-contract).
