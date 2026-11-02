**Title:** kbool 0.1.0: one bash library, the same results on Linux, macOS, FreeBSD and Windows

**Body:**

The main goal of kbool's class library (kcl) is **portability**: a bash script that uses it should
behave the same on systems that differ a lot underneath, so you stop writing
`if [[ $OSTYPE == darwin* ]]` branches and stop discovering on a user's machine that `stat`, `sed -i`,
`awk` or `\b` mean something else there. Repo: https://github.com/Keksov/kbool (MIT, bash 5.1+). It was
developed with AI assistance (I make the design decisions and review what goes in; the process is in
the README).

**Where the differences are.** The test suite runs on 13 CI configurations: bash 5.1, 5.2 and 5.3 on
Linux with glibc and with musl (busybox), macOS with Apple's BSD tools and with GNU tools, FreeBSD with
and without GNU packages, Windows Git-bash and MSYS2. Things kcl absorbs so your script does not have to,
each pinned by a test:

* BSD `stat` has no `-c`, BSD `date` no `-d`, `touch -d @EPOCH` is GNU-only, BSD and busybox have no
  `realpath -m` — `TPath` / `TFile` probe the flavour once and give the same file times, modes and
  paths everywhere
* `\<` `\>` `\b` spelled differently (or missing) in glibc, musl, FreeBSD libc, macOS and cygwin —
  `TRegEx` rewrites the pattern to the local spelling
* mawk (Debian/Ubuntu default), BWK awk (FreeBSD/macOS) and busybox awk — `Math` runs one float engine
  on all of them
* CRLF input: cygwin tools drop the CR, Linux and BSD keep it — `TGrep`, `TSed` and `TAwk` give the
  same records on every platform
* `EPOCHREALTIME` printed as `1788676658,546051` under `de_DE` / `ru_RU`
* FreeBSD pkg bash: `/dev/fd` emulated, `<( )` a FIFO that blocks its writer
* bash losing the exit status of a `<( )` producer under load on Linux (about 0.3 %)
* bash 5.1's `declare -f` turning `>&"$fd"` into `&> "$fd"`, and `unset a["$k"]` expanding the key twice

The rule behind it: the core needs no GNU tool and gives the same results on every row; the wrappers
(`TGrep`, `TSed`, `TAwk`, `TFind`, `THead`, `TTail`) give GNU behaviour everywhere — they find `gsed`,
`gawk`, `ggrep`… by name — or refuse with rc 2 and the package to install, instead of silently doing
something else. A bash older than 5.1 (macOS `/bin/bash` 3.2) is refused at load with exit 2 and one
line. The full list, with the test for each row: https://github.com/Keksov/kbool/blob/main/docs/portability.md

**The language part.** On top of that, classes are declared Pascal-style, with the method bodies as
plain bash functions, so your editor still highlights them:

```bash
source kbool/kbool.sh || exit
kk.uses kklass_pascal || exit

class TCounter
    public
        var         Count
        constructor Create
        proc        Add
        func        Report
end
TCounter.Create() { Count=0; }
TCounter.Add()    { Count=$(( Count + ${1:-1} )); }
TCounter.Report() { RESULT="count=$Count"; }
build TCounter

TCounter.new c
c.Add 2
c.Report; echo "$RESULT"     # count=2
c.delete
```

Inheritance with `inherited`, properties with getters and setters, static members, visibility
sections. Building a class forks nothing (FreeBSD's pkg bash falls back to `$( )`). Units load by name,
once: `kk.uses tdictionary tregex`. Every library member returns in `RESULT` (rc 0 / 1 / 2) instead of
stdout, because one `x=$(true)` measured about 750 µs on Linux and 16 ms on Windows, against 266.6 µs
and 212.9 µs for a method call. Costs, including when not to use it:
https://github.com/Keksov/kbool/blob/main/docs/benchmarks.md

Feedback on the portability list is especially welcome: if you know a platform difference that bites
bash scripts and is not on it, I would like to hear about it.
