# kbool

[![ci](https://github.com/Keksov/kbool/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Keksov/kbool/actions/workflows/ci.yml)

**Status:** 0.1.0 — the API may still change between minor versions (0.x).

kbool brings Free Pascal habits to bash: units you load by name with `uses`, classes written
as `class … end` with real function bodies, and a class library of 29 units: ports of Free
Pascal and Delphi classes (`TStringList`, `TDictionary`, `TIniFile`, `TRegEx`, …) and wrappers
for command-line tools (`TGrep`, `TSed`, `TAwk`, …). It is for scripts that have outgrown
functions and globals but must stay bash; it is not for POSIX `sh` or bash older than 5.1. It
offers **one API across bash versions and platforms**. CI runs the full test suite on
[13 platform rows](#platforms) for every push to `main` and every pull request: bash 5.1,
5.2 and 5.3 on Linux (glibc and musl), and the current bash on macOS, FreeBSD and Windows.

## A first look

A class in the Pascal DSL: the structure first, the bodies as plain bash functions, then
`build`:

<!-- doctest -->
```bash
source /path/to/kbool/kbool.sh || exit
kk.uses kklass_pascal || exit         # the Pascal DSL; it loads the kklass core itself

class TCounter
    public
        var         Name
        var         Count
        constructor Create
        proc        Add
        func        Report
end

TCounter.Create() { Name="$1"; Count=0; }
TCounter.Add()    { Count=$(( Count + ${1:-1} )); }
TCounter.Report() { RESULT="$Name: $Count"; }
build TCounter

TCounter.new basket apples
basket.Add
basket.Add 2
basket.Report; echo "$RESULT"         # => apples: 3
basket.Count                          # => 3
basket.Count = 10
echo "$(basket.Report)"               # => apples: 10
basket.delete
```

A `func` answers in `$RESULT` and prints only inside `$( )`; reading a property
(`basket.Count`) prints it; inside a body the fields are plain variables (`Name`, `Count`).

A class from the library, loaded by name:

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
# loading again is a no-op
kk.uses tstringlist; echo "again: rc=$?"     # => again: rc=0
```

Both blocks are run as written by the test suite (`kkore/tests/015_DocExamples.sh`). The
whole DSL is in [the kklass book](kklass/docs/kklass_book.md#pascal-dsl-class--end-with-real-function-bodies).

A small HTTP service: [examples/](examples/README.md)

![The notes demo: curl against a bash HTTP service](docs/media/notes.gif)

## Why

What a bash script gets from kbool that bash alone does not give it:

* **Classes**: fields, properties with getters and setters, constructors and destructors,
  inheritance with `inherited`, static members, visibility sections. Building a class forks
  nothing (FreeBSD's pkg bash falls back to `$( )`).
* **Units**: `kk.uses tlist tdictionary` loads each library once, by name, from a search
  path, with a configuration file and checked namespaces. There is no `source "$(dirname …)/…"`
  bookkeeping.
* **A class library with one contract**: every kcl unit returns its value in `RESULT`,
  not on stdout (a `$( )` call prints it; exceptions are listed in the kcl table), answers
  with rc 0 / 1 / 2, works under `set -eu`, and avoids forks on its hot paths
  ([the kcl contract](kcl/README.md#1-the-kcl-contract)).
* **A portability layer**: awk, sed, stat, regex word boundaries, netcat, decimal commas and
  `/dev/fd` differ between the systems in the matrix. kbool absorbs the differences or
  refuses with a clear message ([the zoo](#the-portability-layer-the-zoo)).

## Install

`kkore`, `kklass`, `kcl` and `ktests` are git submodules, so clone with them:

```bash
git clone --recurse-submodules https://github.com/Keksov/kbool.git
# an existing clone: git submodule update --init
```

Nothing is built or installed: scripts `source` `kbool.sh` from wherever the tree lives, then
name the units they need. How loading works (`KBOOL_HOME`, sourcing a unit file directly) is
described in [Loading kbool](docs/reference.md#loading-kbool).

## Requirements

**bash ≥ 5.1.** `kbool.sh` refuses an older bash (macOS's `/bin/bash` 3.2, for example) with
exit 2 and one line on stderr. Where the system has no bash that new: macOS `brew install bash`,
FreeBSD `pkg install bash` (FreeBSD has no `/bin/bash`; run scripts as `bash file`, or start them
with `#!/usr/bin/env bash`).

Installing packages needs root: `sudo apt install …`, `sudo pkg install …`.

What else a unit runs comes from the per-unit inventory of external commands (an internal
development file: [`docs/dev/launch/tools.tsv`](docs/dev/launch/tools.tsv)):

| units | external commands | which flavour |
|---|---|---|
| kkore, kklass | `awk`, `realpath` (kkore); `basename`, `cat`, `chmod`, `dirname`, `find`, `grep`, `kill`, `mkdir`, `mktemp`, `rm`, `sed`, `stat` (kklass) | any: GNU, BSD or busybox |
| the other kcl units | file tools (`cp`, `mv`, `rm`, `rmdir`, `mkdir`, `ln`, `cat`, `chmod`, `stat`, `touch`, `date`, `readlink`, `realpath`, `mktemp`, `ls`), `kill`; `awk` for `Math`; `openssl` for `TFile.encrypt` / `decrypt` | any; `Math` runs on gawk, mawk, BWK awk and busybox awk |
| `TGrep`, `TSed`, `TAwk`, `TFind`, `THead`, `TTail` | GNU `grep`, GNU `sed`, `gawk`, GNU findutils `find`, GNU coreutils `head` / `tail` | GNU only (uutils `head` / `tail` ≥ 0.2.2 are accepted too) |
| `thttpserver` | GNU netcat 0.7.1 or socat ≥ 1.7.4 | other netcats are refused by name |

The split:

* **The core needs no GNU tool.** kkore, kklass and every kcl unit except the wrappers and
  `thttpserver` use bash and the POSIX utilities every system in the matrix has. They give the same results
  on every [CI row](#platforms).
* **The wrappers give GNU behaviour everywhere, or a clear error.** They find the GNU tool
  by name (`gsed`, `gawk`, `ggrep`, `gfind`, `ghead`, `gtail` first, then the plain name if it
  is GNU). Without one, every call returns rc 2 with a reason that names the package to
  install: FreeBSD `pkg install gsed`, macOS `brew install gnu-sed`, Alpine `apk add sed`.
  Debian and Ubuntu need `gawk` (their default awk is mawk). The full table is in
  [kkore/README.md §7](kkore/README.md#7-the-gnu-tool-resolver-ktoolsh).
* **`thttpserver` needs GNU netcat or socat**: Homebrew `netcat`, FreeBSD `pkg install gnetcat` (not
  FreeBSD's `netcat` package: that is netcat 1.10 and is refused), MSYS2
  `gnu-netcat`, otherwise `socat` ([details](kcl/thttpserver/README.md#network-backend)).
  `KCL_NC=/path/to/nc` points kbool at a GNU netcat with another name or location.

## Platforms

Exactly what [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs: the whole test suite
on each row ([what CI checks](CONTRIBUTING.md#what-ci-checks)). The container rows install
their packages with [`.github/ci/linux.sh`](.github/ci/linux.sh).

| CI row | OS | userland | bash |
|---|---|---|---|
| `linux (ubuntu host, system bash)` | Ubuntu, GitHub's `ubuntu-latest` runner | glibc, GNU (+ gawk, OpenBSD nc, socat) | system bash |
| `linux (alpine, bash 5.1)` | Alpine 3.22 (`bash:5.1.16-alpine3.22`) | musl, busybox + the GNU tool packages | 5.1.16 |
| `linux (alpine, bash 5.2)` | Alpine 3.22 (`bash:5.2.37-alpine3.22`) | musl, busybox + the GNU tool packages | 5.2.37 |
| `linux (alpine, bash 5.3)` | Alpine 3.24 (`bash:5.3.20-alpine3.24`) | musl, busybox + the GNU tool packages | 5.3.20 |
| `linux (debian 13)` | Debian 13 | glibc, GNU; mawk stays the default awk | system bash |
| `linux (ubuntu 24.04)` | Ubuntu 24.04 | glibc, GNU; mawk stays the default awk | system bash |
| `linux (fedora 44)` | Fedora 44 | glibc, GNU | system bash |
| `macos (bsd tools, brew bash)` | macOS, `macos-latest` | Apple's BSD tools | Homebrew bash |
| `macos (gnu tools, brew bash)` | macOS, `macos-latest` | + Homebrew coreutils, gnu-sed, gawk, findutils, grep, diffutils, netcat, socat | Homebrew bash |
| `freebsd (clean, pkg bash)` | FreeBSD 15.1 | BSD base (+ git, curl, perl5) | pkg bash |
| `freebsd (gnu, pkg bash)` | FreeBSD 15.1 | + coreutils, gsed, gawk, findutils, gnugrep, diffutils, netcat, socat | pkg bash |
| `windows (git-bash)` | Windows, `windows-latest` | Git for Windows (GNU); GNU netcat from MSYS2 | Git for Windows' bash |
| `windows (msys2)` | Windows, `windows-latest` | MSYS2 (GNU) | MSYS2 bash |

The `macos (bsd tools …)` row also checks that `/bin/bash` 3.2 is refused. On the rows without
a GNU tool, each wrapper test case still passes, with a `SKIP: <reason>` text (visible with
`--verbosity info`), so the counts stay equal on every row.

## The portability layer ("the zoo")

The variants we met on the CI rows and in the lab VMs, what each one breaks, and what kbool does
about it. Each row names the test that pins the fix. Every row, with more detail, is in
**[docs/portability.md](docs/portability.md)**.

| you meet | what goes wrong | what kbool does | pinned by |
|---|---|---|---|
| bash older than 5.1 (macOS `/bin/bash` 3.2) | newer syntax fails part-way through loading | `kbool.sh` refuses first: exit 2, one line | `.github/workflows/ci.yml` (bash 3.2 guard), `tools/vmlab/checks/guard.sh` |
| bash 5.1 | `declare -f` prints `>&"$fd"` as `&> "$fd"`; `unset a["$k"]` expands the key twice | the code avoids both shapes; a static scan in each repo rejects them | `kkore/tests/018_Bash51Hazards.sh` (+ kklass 148, kcl 002, ktests 058) |
| decimal-comma locales (`de_DE`, `ru_RU`) | `EPOCHREALTIME` reads `1788676658,546051` | timings read the digits only | `kcl/tstopwatch/tests/006_G3_BooleansAndLocale.sh` |
| mawk (Debian, Ubuntu), BWK awk (FreeBSD, macOS), busybox awk | `Math`'s float engine failed silently or never answered | one engine program that runs on every awk; NaN-guarded compares | `kcl/math/tests/019_L27_AwkEngine.sh` |
| BSD and busybox `stat`, `date`, `touch`; no `realpath -m` | file times, modes and full paths fail or differ | `TPath` probes the flavour; POSIX `touch -t`; a lexical path normaliser | `kcl/tpath/tests/021_L35_Portable.sh` |
| FreeBSD pkg bash: `<( )` is a FIFO, `/dev/fd/N` is emulated | blocked writers, leftover `sh-np.*` files, failed captures | `<( )` is opened and unlinked explicitly; the fast capture switches itself off there | `kcl/math/tests/020_L357_ProcsubFifo.sh`, `kklass/tests/145_ForkFreeBuild.sh` |
| `\<` `\>` `\b` per C library (glibc, musl, FreeBSD, macOS, cygwin) | word boundaries match, fail or are a syntax error | `TRegEx` probes once and rewrites the pattern to the local spelling | `kcl/tregex/tests/015_WordEdges.sh` |
| GNU, BSD, busybox and uutils tools; g-prefixed names | wrapper options and messages differ | `ktool` finds the GNU tool by name and banner, or names the package | `kkore/tests/017_GnuTools.sh` |
| CRLF input: cygwin tools drop the CR, Linux and BSD keep it | different records on different systems | `TGrep`, `TSed`, `TAwk` drop the CR in text mode everywhere | `kcl/tutil/tests/005_TextMode.sh` |
| GNU netcat, OpenBSD nc, ncat, busybox nc, socat | `-c` means different things; lost clients | GNU netcat or socat; the others are refused by name | `kcl/thttpserver/tests/008_Contract.sh` |
| Linux under load | bash loses the exit status of a `<( )` producer | `TPipe` recovers it through a status pipe | `kcl/tpipe/tests/007_StatusPipe.sh` |
| gawk's `inplace.awk` in a different folder per OS | `TAwk` in-place edits fail, or `-i inplace` loads a planted `./inplace.awk` | the extension is found once and loaded by absolute path | `kcl/tawk/tests/006_Contract.sh` |

## Comparison with other projects

Other projects that bring objects or a standard library to bash. Each entry states only what its
own README and repository say[^checked].

| project | what it is | bash / platforms it states | last commit seen | how kbool differs |
|---|---|---|---|---|
| [niieani/bash-oo-framework](https://github.com/niieani/bash-oo-framework) ("Bash Infinity") | "a standard library and a boilerplate framework": exceptions and stack traces, named parameters, `import`, logging, unit tests, a type system with classes | "I test with bash 4"; some modules work on bash 3; references need ≥ 4.3; no platform list | 2020-08-01, last release 2.1 (2018-07-08) | Pascal-style `class … end`; needs bash ≥ 5.1; tested on 13 CI rows |
| [tomas/skull](https://github.com/tomas/skull) | "Object-oriented-like Bash framework": `Array`, `Hash`, `String`, `Numeric`, `File` and more, created with `Class.new var` | "written purely in Bash"; no version stated; notes Mac/Linux tool differences | 2018-08-10, no releases | user-defined classes with inheritance; ports of FPC classes |
| [Ad5001/BashOOP](https://github.com/Ad5001/BashOOP) | "OOP with constructors, properties and namespace system for bash": `.shc` class and `.shn` namespace files | none stated | 2022-01-07, no releases | classes declared in the script itself; units loaded by name |
| [elibs/ebash](https://github.com/elibs/ebash) | "enhanced bash": implicit error detection, logging, testing | its compatibility page lists Alpine, Arch, CentOS 7, Debian, Fedora, Gentoo, Rocky, Ubuntu and macOS 15.0 releases; no bash version | 2026-07-09, release v3.0.22 | a class system and FPC class ports; FreeBSD and Windows in CI |
| [labbots/bash-utility](https://github.com/labbots/bash-utility) | "utility functions and helpers for functional programming in Bash": array, string, file, date, validation functions | none stated | 2021-01-26 (default branch), no releases | objects with state; one return contract (`RESULT`, rc 0/1/2) |

[^checked]: Read on 2026-10-31 from each project's GitHub page, README and the GitHub API
    (latest commit on the default branch, latest release). Quotes are from their READMEs.

## How it was built

kbool is developed with AI assistance. The roles:

* **The maintainer (Keksov)** decides: the scope, every design question with more than one
  reasonable answer, and what gets released. Every change reaches `main` only through the
  maintainer (branch rules allow no one else to update it); commits written with Claude carry
  a `Co-Authored-By: Claude …` trailer.
* **A supervisor Claude session** plans each phase. For every step it writes a task card
  (goal, the files it may touch, the acceptance checks) and dispatches it to a worker model:
  Claude Opus for design, the core layers and prose, Claude Sonnet for well-specified tasks.
  It reviews every report against the actual tree before anything is committed.
* **An independent critic**, a fresh session without the worker's context, reviews changes
  to the core.
* **Every commit is gated** on two bash runtimes: Git-bash 5.3.15 and MSYS2 5.3.9 on
  Windows. The full gate of 2026-10-31 ran 30 suites: 9694 tests on 5.3.15 and 9695 on
  5.3.9 (MSYS2 runs one test more: it has `setsid`, Git for Windows does not), all passing
  (19389 in total). Since 2026-10-30 every push to `main` and every pull request also runs
  the 13 CI rows.
* **The record is public**: the plans, every decision with its reason, and 27 machine-readable
  phase logs ("ledgers") are kept in the repositories under `docs/dev/`. The index is
  [docs/dev/README.md](docs/dev/README.md).

## Reference

| folder | what it is | read |
|---|---|---|
| `kbool.sh` | the startup file: loads the system units and the configuration | [Loading kbool](docs/reference.md#loading-kbool) |
| [`kkore/`](kkore/README.md) | the system units (loaded by `kbool.sh`): the unit loader `kk.unit` / `kk.uses` / `kk.project` / `kk.config` / `kk.defined` / `kk.namespace` (`kuse.sh`), output and argument helpers (`klib.sh`), the error trap (`kerr.sh`), frames and unique names (`kvar.sh`), a key/value store (`kcfg.sh`) | [kkore/README.md](kkore/README.md) |
| [`kklass/`](kklass/docs/kklass_book.md) | classes: `defineClass`, the declarative API, the Pascal DSL (`class … end`), compiled caches, serialization | [the kklass book](kklass/docs/kklass_book.md), chapter [Units and uses](kklass/docs/kklass_book.md#units-and-uses) |
| [`kcl/`](kcl/README.md) | 29 units in 26 folders: ports of FPC/Delphi classes (`TList`, `TStringList`, `TDictionary`, `TIniFile`, `TPath`, …) and CLI-tool wrappers (`TGrep`, `TSed`, `TAwk`, …) | [kcl/README.md](kcl/README.md) |
| [`ktests/`](ktests/README.md) | the test framework and runner every suite uses | [ktests/docs/README.md](ktests/docs/README.md) |
| `tests/tests.sh` | the master runner: every `*/tests/tests.sh` of the tree | [Running the tests](#running-the-tests) |
| [`docs/dev/`](docs/dev/README.md) | the development history: plans, ledgers, reviews, coverage notes | [docs/dev/README.md](docs/dev/README.md) |

The design of units and `uses` — every decision, with its reasons — is in the internal design
notes [kklass/docs/dev/USES_PLAN.md](kklass/docs/dev/USES_PLAN.md).

- [Loading kbool](docs/reference.md#loading-kbool)
- [Units](docs/reference.md#units)
- [`kk.uses`](docs/reference.md#kkuses)
- [Namespaces and defines](docs/reference.md#namespaces-and-defines)
- [Configuration](docs/reference.md#configuration)
- [Projects: `kk.project`](docs/reference.md#projects-kkproject)
- [Reloading during development](docs/reference.md#reloading-during-development)
- [Messages](docs/reference.md#messages)
- [Portability](docs/portability.md)
- [Benchmarks](docs/benchmarks.md)
- [Changelog](CHANGELOG.md)

## Running the tests

From the kbool root, every suite under the bash you start it with:

```bash
bash ktests/tools/gate.sh all
```

With a single bash the gate prints `[WARN] one runtime only` — that is expected; CONTRIBUTING shows
how to run two runtimes.

More options (one suite, `--changed`, two runtimes at once, running a suite directly), what CI
checks and the house rules: [CONTRIBUTING.md](CONTRIBUTING.md#run-the-tests--one-command).

## In memory of Niklaus Wirth

kbool is a tribute to Niklaus Wirth (1934–2024), the brilliant creator of Pascal, Modula-2 and
Oberon, who is sadly no longer with us. A whole generation of IT people grew up on Pascal: it
was the first language of countless school and university courses, and through Turbo Pascal
and Delphi it became the first real tool of many more.

Had Pascal and Oberon received as much corporate money as TypeScript, Java and C#, humanity
would have colonized the Solar System long ago, if only on the time saved waiting for builds:
a full rebuild of a large Pascal project takes seconds, while a project of the same size in
those languages can keep its developers at the coffee machine for tens of minutes. Wirth
warned us; his law says that software gets slower faster than hardware gets faster.

But humanity still has a chance to put things right. The [Free Pascal](https://www.freepascal.org/)
project keeps patiently improving the language and its compiler, and it can use help to get
even better: [the sources, the issue tracker and merge requests](https://gitlab.com/freepascal.org/fpc/source)
are open to everyone.

## License

MIT: see [LICENSE](LICENSE). Each submodule carries its own `LICENSE`.
