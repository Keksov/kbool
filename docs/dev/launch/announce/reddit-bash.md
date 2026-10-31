**Title:** kbool 0.1.0: classes, units and a portability layer for bash 5.1+

**Body:**

kbool is a toolkit for bash scripts that have outgrown functions and globals but have to stay bash.
It was developed with AI assistance (I make the design decisions and review what goes in; the
process is in the README). Repo: https://github.com/Keksov/kbool (MIT).

**The language part.** Classes are declared Pascal-style, with the method bodies as plain bash
functions, so your editor still highlights them:

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
sections. Building a class forks nothing (FreeBSD's pkg bash falls back to `$( )`). Units load by name, once: `kk.uses tdictionary tregex`.
Every library member returns in `RESULT` (rc 0 / 1 / 2) instead of stdout, because one `x=$(true)`
measured about 750 µs on Linux and 16 ms on Windows, against 266.6 µs and 212.9 µs for a method call.

**The portability part.** The test suite runs on 13 CI configurations: bash 5.1, 5.2 and 5.3 on Linux
(glibc and musl), macOS, FreeBSD, Git-bash and MSYS2. Things it absorbs, each pinned by a test:

* bash 5.1's `declare -f` turning `>&"$fd"` into `&> "$fd"`, and `unset a["$k"]` expanding the key twice
* `EPOCHREALTIME` printed as `1788676658,546051` under `de_DE` / `ru_RU`
* `\<` `\>` `\b` spelled differently by glibc, musl, FreeBSD libc, macOS and cygwin
* FreeBSD pkg bash: `/dev/fd` emulated, `<( )` a FIFO that blocks its writer
* bash losing the exit status of a `<( )` producer under load on Linux (about 0.3 %)
* mawk, BWK awk and busybox awk running the same float engine

The full list: https://github.com/Keksov/kbool/blob/main/docs/portability.md. A bash older than 5.1
(macOS `/bin/bash` 3.2) is refused at load with exit 2 and one line. Costs, including when not to use
it: https://github.com/Keksov/kbool/blob/main/docs/benchmarks.md.

Feedback on the API and on the portability list is welcome.
