# Portability: what kbool handles for you

kbool is written so that a script behaves the same on every system its CI runs on: bash 5.1,
5.2 and 5.3; glibc, musl, FreeBSD libc, macOS and cygwin (Git for Windows, MSYS2); GNU, BSD
and busybox userlands. The thirteen CI rows are listed in the
[README](../README.md#platforms). Before CI existed, the same test suite ran in lab virtual
machines (Ubuntu, Debian, Fedora, Alpine with busybox only and with GNU packages, FreeBSD with
and without GNU packages) and on Windows. The variants below are the ones those runs found.

This page lists each variant: what goes wrong there, what kbool does about it, and the test
that pins the fix. Every test named here is part of the suite that runs on every CI row. Where
the variant is not on the machine running the test, the test usually stands in for it (a fake `stat`, a forced mode, a
recorded tool banner), so the fallback code runs everywhere and not only where it is needed.
A row marked **limit** is a difference kbool documents instead of hiding.

The short version, by layer:

* **The core** (kkore, kklass, the kcl units other than the wrappers and `thttpserver`) needs
  no GNU tool. It uses bash and the POSIX utilities every system in the matrix has, and gives
  the same results on every row.
* **The wrappers** (`TGrep`, `TSed`, `TAwk`, `TFind`, `THead`, `TTail`) drive the GNU tool and
  give its behaviour everywhere. Where no GNU tool can be found, every call returns rc 2 with
  a reason that names the package to install.
* **`thttpserver`** runs on GNU netcat or socat and refuses every other netcat by name.

## bash versions

| you meet | what goes wrong | what kbool does | pinned by |
|---|---|---|---|
| bash older than 5.1: macOS's `/bin/bash` is 3.2 | newer syntax (`${x@a}`, namerefs, `EPOCHREALTIME`) fails part-way through loading | `kbool.sh` checks `BASH_VERSINFO` first, using only bash 3.2 syntax, and refuses: exit 2 and `kbool: bash >= 5.1 is required, this is …`. It also refuses a shell that is not bash and bash in POSIX mode | the "bash 3.2 guard" step of the `macos (bsd tools …)` row in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml); [`tools/vmlab/checks/guard.sh`](../tools/vmlab/checks/guard.sh) (bash 3.2, 4.4, 5.0, 5.1 in the lab) |
| bash 5.1's function printer | `declare -f` (also `export -f` and `set -a`) prints `>&"$fd"` as `&> "$fd"`. After a round trip the command writes stdout **and** stderr into a file named like the descriptor. kklass round-trips every method body this way | the code never quotes the target of a descriptor duplication; the descriptor is checked to be a number first | [`kkore/tests/018_Bash51Hazards.sh`](../kkore/tests/018_Bash51Hazards.sh), [`kklass/tests/148_Bash51Hazards.sh`](../kklass/tests/148_Bash51Hazards.sh), [`kcl/tests/002_Bash51Hazards.sh`](../kcl/tests/002_Bash51Hazards.sh), [`ktests/tests/058_Bash51Hazards.sh`](../ktests/tests/058_Bash51Hazards.sh): a static scan of all non-test code |
| bash 5.1's array subscripts | `[[ -v a["$k"] ]]` and `unset a["$k"]` expand the key twice: a key holding a quote, `]` or `$` is not found or not removed, and the key `@` or `*` empties the whole array | `${a[$k]+x}` and `unset 'a[$k]'` throughout | the same four `*_Bash51Hazards.sh` scans |
| bash 5.1: the EXIT trap after a `set -e` exit inside a method | 5.1 runs the trap in the method's scope; 5.2 and later unwind the method's locals first | **limit**: documented in the [kklass book](../kklass/docs/kklass_book.md) (`kk.frameReset` is a no-op there, as after an explicit `exit`); the test expects whichever outcome the running bash gives | [`kklass/tests/147_Round6.sh`](../kklass/tests/147_Round6.sh) |

## C library and locale

| you meet | what goes wrong | what kbool does | pinned by |
|---|---|---|---|
| a decimal-comma locale (`de_DE`, `ru_RU`) | bash prints `EPOCHREALTIME` with the locale's decimal point, `1788676658,546051`; `$(( ))` reads the comma as the comma operator | timings take the digits only, never split at a `.` | [`kcl/tstopwatch/tests/006_G3_BooleansAndLocale.sh`](../kcl/tstopwatch/tests/006_G3_BooleansAndLocale.sh) (runs under `C.UTF-8`, `de_DE.UTF-8`, `ru_RU.UTF-8`) |
| word boundaries in POSIX regular expressions: `\<` `\>` `\b` are spelled differently by glibc, musl, FreeBSD libc, macOS and cygwin (newlib), and some lack them | the same `TRegEx` pattern matches on one system, fails on another and is a syntax error on a third | `TRegEx` probes the C library once per process and rewrites the pattern to the spelling it accepts, keeping your group numbers. **Limit**: on macOS a `\b` must stand next to a word-only atom, else the pattern is rc 2. The engine is bash's POSIX ERE, not PCRE (no lazy quantifiers, no lookaround) | [`kcl/tregex/tests/015_WordEdges.sh`](../kcl/tregex/tests/015_WordEdges.sh) (every rewrite mode forced on every host) |

## Userland tools

| you meet | what goes wrong | what kbool does | pinned by |
|---|---|---|---|
| mawk, the default `awk` on Debian and Ubuntu | `Math`'s float engine failed silently: mawk's parser overflowed on a long `else if` chain, it answers a pipe only under `-W interactive`, and `nan == 0` is true in it | a flat dispatch; gawk preferred when present; any other awk started with `-W interactive` first, then without; NaN-guarded compares; `MATH_FE_ERROR` and a debug line when no awk can run the engine | [`kcl/math/tests/019_L27_AwkEngine.sh`](../kcl/math/tests/019_L27_AwkEngine.sh) (runs the engine on the system `awk`) |
| mawk dated before 20250131 | `-W interactive` never answers a request line of 4096 characters or more, and blocks every call after it | such a request is refused with rc 1 instead of hanging; newer mawk gets no limit | [`kcl/math/tests/019_L27_AwkEngine.sh`](../kcl/math/tests/019_L27_AwkEngine.sh) |
| gawk's NaN ordering | gawk 5.0 orders NaN above every number, so an integer power with a NaN exponent looped for ever (an infinite one on every gawk) | a loop whose bound comes from an argument is entered only for a finite value | [`kcl/math/tests/019_L27_AwkEngine.sh`](../kcl/math/tests/019_L27_AwkEngine.sh) |
| BWK awk ("one true awk": FreeBSD, macOS) and busybox awk | BWK awk takes `-W interactive` as its program; it reads the subnormal `5e-324` as 0 | the engine falls back to starting the awk without `-W`; the test names the BWK difference in that row instead of failing it | [`kcl/math/tests/020_L357_ProcsubFifo.sh`](../kcl/math/tests/020_L357_ProcsubFifo.sh), [`kcl/math/tests/014_M1_EngineDomain.sh`](../kcl/math/tests/014_M1_EngineDomain.sh) |
| BSD `stat` (no `-c`), BSD `date` (no `-d`), `touch -d @EPOCH` (GNU only) | every file time getter, `GetAttributes` and every time setter of `TPath`, `TFile` and `TDirectory` failed on FreeBSD and macOS | `TPath` probes the `stat` flavour once (GNU `-c` or BSD `-f`); dates are formatted with bash's `printf '%(…)T'`; setters use POSIX `touch -t` under `TZ=UTC0`; a date string goes through BSD `date -j -f` when `date -d` fails | [`kcl/tpath/tests/021_L35_Portable.sh`](../kcl/tpath/tests/021_L35_Portable.sh) |
| no birth time: busybox `stat` prints `W`, GNU and BSD print 0, cygwin and BSD may print -1 | the creation-time getters answered garbage or failed | the getter falls back to the write time | [`kcl/tpath/tests/021_L35_Portable.sh`](../kcl/tpath/tests/021_L35_Portable.sh) |
| no `realpath -m` / `readlink -m` (BSD, busybox) | `TPath.getFullPath` returned the raw join: `..` and `.` not collapsed | a lexical normaliser in bash as the last fallback | [`kcl/tpath/tests/021_L35_Portable.sh`](../kcl/tpath/tests/021_L35_Portable.sh) |
| GNU, BSD and busybox `sed`, `grep`, `awk`, `find`, `head`, `tail`; GNU tools installed under g-names (`gsed`, `gawk`, `ggrep`, `gfind`, `ghead`, `gtail`) on FreeBSD and macOS | GNU options (`sed --sandbox`, `grep -Z`, `find -print0` …) are refused or mean something else: on macOS `grep -Z` decompresses | `ktool` finds the tool by name (an override variable, then the g-name, then the plain name) and accepts it only when its `--version` banner is GNU. busybox ("This is not GNU sed version 4.0") and BSD answers are refused, with the package to install in the reason | [`kkore/tests/017_GnuTools.sh`](../kkore/tests/017_GnuTools.sh) |
| uutils coreutils, the default on newer Ubuntu releases | its `head` / `tail` are not GNU | accepted for `head` and `tail` from version 0.2.2; an older one is refused with its version, the floor and Ubuntu's `coreutils-from-gnu` package | [`kkore/tests/017_GnuTools.sh`](../kkore/tests/017_GnuTools.sh) |
| gawk's `inplace.awk` lives in a different folder per system (`/usr/share/awk`, `/usr/local/share/awk` on FreeBSD, Homebrew's prefix on macOS) | a hard-coded path broke `TAwk` in-place edits; `-i inplace` would search `AWKPATH`, whose default starts with `.`, and load a planted `./inplace.awk` | the extension is located once from gawk's own default `AWKPATH` and loaded by its absolute path | [`kcl/tawk/tests/006_Contract.sh`](../kcl/tawk/tests/006_Contract.sh), [`kcl/tawk/tests/004_Argv.sh`](../kcl/tawk/tests/004_Argv.sh) |
| netcat flavours: GNU netcat 0.7.1, OpenBSD nc (Ubuntu, Debian, FreeBSD, macOS), ncat (Fedora), busybox nc, traditional nc | the listener fails, and on ncat and traditional nc `-c` means "run the next argument as a shell command". OpenBSD nc keeps its listening socket open while serving, so every second client was lost | `thttpserver` detects the flavour by probing (never by listening) and uses GNU netcat or socat ≥ 1.7.4; the others are refused by name | [`kcl/thttpserver/tests/008_Contract.sh`](../kcl/thttpserver/tests/008_Contract.sh) |

## Kernels and runtimes

| you meet | what goes wrong | what kbool does | pinned by |
|---|---|---|---|
| FreeBSD's pkg bash: `/dev/fd/N` is emulated by bash itself | kklass's fork-free capture of method bodies appends through `/dev/fd`; there that is a copy of a read-only descriptor, and every append failed with `Bad file descriptor` on stderr | where the descriptor directory is `/dev/fd` and not `/proc/PID/fd`, the fast capture is switched off before it creates anything; classes build through `$( )`, silently | [`kklass/tests/145_ForkFreeBuild.sh`](../kklass/tests/145_ForkFreeBuild.sh) |
| FreeBSD's pkg bash: `<( )` is a FIFO in `$TMPDIR` | its writer blocks in `open()` until a reader comes; an awk that never opens it left the writer blocked for ever; a shell that `exec`s never unlinks the FIFO, so `sh-np.*` files piled up | the co-process's shell opens the substitution itself, hands awk `-f /dev/fd/N`, and unlinks a FIFO right after opening it. Without fdescfs mounted on `/dev/fd`, the engine falls back to a temp file | [`kcl/math/tests/020_L357_ProcsubFifo.sh`](../kcl/math/tests/020_L357_ProcsubFifo.sh), [`kcl/thttpserver/tests/005_Lifecycle.sh`](../kcl/thttpserver/tests/005_Lifecycle.sh) §5 |
| FreeBSD: a FIFO reused by the next listener | a relay that had not yet seen EOF read the first write of the next response | a fresh FIFO per listener, never reused | [`kcl/thttpserver/tests/005_Lifecycle.sh`](../kcl/thttpserver/tests/005_Lifecycle.sh) §6 |
| FreeBSD has no `/bin/bash` | a `#!/bin/bash` script run directly says "not found" (on macOS it gets bash 3.2) | every unit and every generated file starts with `#!/usr/bin/env bash` | [`kcl/tests/001_UnitFiles.sh`](../kcl/tests/001_UnitFiles.sh), [`kklass/tests/141_UnitHeaders.sh`](../kklass/tests/141_UnitHeaders.sh) |
| Linux under load | bash can lose the exit status of a `<( )` producer (about 0.3 % of fast producers under an 8-way load); `TPipe` would report success for a failed command | on Linux with `/proc`, every producer reports its status through a status pipe and `TPipe` recovers it | [`kcl/tpipe/tests/007_StatusPipe.sh`](../kcl/tpipe/tests/007_StatusPipe.sh) |
| cygwin (Git for Windows, MSYS2) tools drop the CR of a CRLF line in text mode; Linux, BSD and macOS tools keep it | `TGrep`, `TSed` and `TAwk` delivered different records for the same file | in text mode the CR is dropped on every platform, by kbool where the tool keeps it; `binary = 1` keeps every byte everywhere | [`kcl/tutil/tests/005_TextMode.sh`](../kcl/tutil/tests/005_TextMode.sh) (both platform paths on any host) |
| cygwin: bash does not translate `\` in a path | an INI file path written with `\` was a different file | `TIniFile` turns `\` into `/` for every file operation | [`kcl/tinifile/tests/007_T1_Persistence.sh`](../kcl/tinifile/tests/007_T1_Persistence.sh) |
| a parent that starts bash with SIGPIPE ignored (some CI runners) | a signal ignored when bash starts cannot be trapped or reset by it or its children: `sed` prints `stdout: Broken pipe` and returns 2 where a terminal gives 0 | **limit** for library callers: kbool cannot undo it. The test gate resets SIGPIPE for its own cells | [`ktests/tests/056_PlatformHarness.sh`](../ktests/tests/056_PlatformHarness.sh) (H4) |

## The test harness

The same differences hit the test runner and the gate, which have to find and stop the
processes a test leaves behind on every system.

| you meet | what goes wrong | what the harness does | pinned by |
|---|---|---|---|
| process tables: cygwin's `/proc/PID/ppid`, Linux's `/proc/PID/stat` (start time in clock ticks), no `/proc` on FreeBSD and macOS, no session id in macOS `ps` | the stray check was blind off Windows and said "none" | backends for cygwin, Linux and `ps`; macOS session ids come from python3 `os.getsid`; with no process table at all `strays.sh` says UNKNOWN (rc 3), never "none" | [`ktests/tests/056_PlatformHarness.sh`](../ktests/tests/056_PlatformHarness.sh) (H1, H2) |
| FreeBSD's `timeout(1)` is the reaper of everything below it | an orphan is re-parented to `timeout`, not to pid 1 | a deliberate orphan is still listed and stopped from under such a `timeout` | [`ktests/tests/056_PlatformHarness.sh`](../ktests/tests/056_PlatformHarness.sh) (H1) |
| a decimal-comma locale in the runner | the KILL deadline of a group stop was never reached | digits-only `EPOCHREALTIME` | [`ktests/tests/056_PlatformHarness.sh`](../ktests/tests/056_PlatformHarness.sh) (H7) |
| BSD `sed`: no `\r` escape, `-i` takes a suffix | the output filter stripped a trailing letter `r`; a result rewrite failed | both done in bash | [`ktests/tests/056_PlatformHarness.sh`](../ktests/tests/056_PlatformHarness.sh) (H5, H6) |
| `env --default-signal` is GNU coreutils ≥ 8.31 only | no gate segment could start on busybox, FreeBSD or macOS | GNU `env`, else perl, else `set -m`; INT and QUIT stay trappable in every mode | [`ktests/tests/056_PlatformHarness.sh`](../ktests/tests/056_PlatformHarness.sh) (H4) |
