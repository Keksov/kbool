# Prepared answers

Short, factual answers for the threads. Figures are from the repo: `docs/benchmarks.md`,
`docs/portability.md`, `README.md`, `docs/dev/launch/numbers.json`. Links are absolute so an answer
can be pasted as it is.

## Why not Python?

Where Python is available and the team writes it, use Python. kbool is for scripts that have to
stay bash: they run where only bash and the base utilities can be assumed (containers, CI images,
FreeBSD and Alpine boxes, Git-bash on Windows), or they are maintained by people who write bash.
Those scripts still grow, and kbool gives them units, classes and a tested library instead of
`source "$(dirname …)"` and global variables. It does not try to make bash fast at bulk data; for
that, see the next answer.

## Is it slow?

Work that stays inside the shell is cheap: a method call measured 266.6 µs on a Linux VM and
212.9 µs on Windows Git-bash, a property read 45.9 µs and 34.8 µs. A fork is what costs: one
`x=$(true)` took 750.395 µs on Linux and 16008.55 µs (16 ms) on Windows. That is why every member
returns its value in `RESULT` instead of stdout, and why an external tool runs once per call, never
once per record. Loading is paid once per script: `source kbool.sh` takes 12.6 ms on Linux and
32.8 ms on Windows, 152.4 ms to 431.5 ms with a unit such as `tstringlist` or `dateutils`. For
thousands of records, use a pipeline: `THead`'s `count` over 5000 lines took 420.83 ms against
2.94 ms for `head -n 5000 | wc -l`. Method and figures:
<https://github.com/Keksov/kbool/blob/main/docs/benchmarks.md>.

## Why Pascal?

Pascal's structure maps well onto a shell script that needs some order: units you `uses` by name, a
class declared first and implemented after, constructors, destructors and `inherited`. A whole
generation of programmers learned Pascal, and the FPC and Delphi class names (`TStringList`,
`TDictionary`, `TIniFile`, `TRegEx`) tell you what a class does before you read its documentation.
The FPC ports keep FPC's semantics where bash allows, and each unit's README lists its deviations. kbool is also a
tribute to Niklaus Wirth (1934–2024).

## AI-written code: can I trust it?

Judge it by the process and the evidence, both public. The maintainer decides scope and every design
question with more than one reasonable answer; a supervisor session writes a task card for each
step (goal, the files it may touch, the acceptance checks), a worker model executes it, and the
supervisor reviews the report against the actual tree before anything is committed. Changes to the
core also get an independent critic, a fresh session without the worker's context. Every commit is
gated on two bash runtimes: the full gate of 2026-10-31 ran 30 suites, 9694 tests on bash 5.3.15
and 9695 on 5.3.9, 19389 in total, all passing; every push to `main` and every pull request also
runs 13 CI configurations. The plans, every decision with its reason and 27 phase logs are in
`docs/dev/` (<https://github.com/Keksov/kbool/blob/main/docs/dev/README.md>). As with any MIT
code, read the tests for the parts you rely on.

## Does it work on macOS's bash 3.2?

No. kbool needs bash 5.1 or newer, and `kbool.sh` refuses an older bash before it loads anything:
exit 2 and the line `kbool: bash >= 5.1 is required, this is …`. On macOS install a current bash
with `brew install bash` and run your scripts with it (`#!/usr/bin/env bash`). The CI row
`macos (bsd tools, brew bash)` runs the whole suite on Homebrew bash and also checks that
`/bin/bash` 3.2 is refused.

## Why GNU tools for the wrappers?

The wrappers (`TGrep`, `TSed`, `TAwk`, `TFind`, `THead`, `TTail`) promise one behaviour on every
system, and GNU options such as `sed --sandbox`, `grep -Z` or `find -print0` are refused by BSD
and busybox tools or mean something else there (on macOS `grep -Z` decompresses). So they drive the GNU tool, found by name (`gsed`, `gawk`, `ggrep`, `gfind`, `ghead`, `gtail` first,
then the plain name if its `--version` banner is GNU; uutils `head` / `tail` 0.2.2 or newer are
accepted too). Without one, every call returns rc 2 with a reason that names the package to install.
The core (kkore, kklass and every other kcl unit) needs no GNU tool.

## License?

MIT, in all five repositories (kbool and its submodules kcl, kklass, kkore, ktests); each carries
its own `LICENSE` file.

## How do I contribute?

Clone with `git clone --recurse-submodules https://github.com/Keksov/kbool.git`, run the tests with
`bash ktests/tools/gate.sh all`, and send a pull request against `main` to the repository that owns
the file. Every pull request runs the 13 CI configurations, and only the maintainer merges. One
topic per pull request, with the suites you ran and the gate's `__GATE__` line; the house rules
(bash 5.1 floor, no forks in hot paths, a test for every change) are in
<https://github.com/Keksov/kbool/blob/main/CONTRIBUTING.md>. Security problems go through GitHub's
private vulnerability reporting, not public issues
(<https://github.com/Keksov/kbool/blob/main/SECURITY.md>).
