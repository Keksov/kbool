**Title:** A notes HTTP service in about 175 lines of bash, and GNU tool wrappers that behave the same on Linux, macOS, FreeBSD and Windows

**Body:**

kbool is a class library and module system for bash 5.1+, developed with AI assistance (I make the
design decisions and review what goes in; how is in the README). Version 0.1.0:
https://github.com/Keksov/kbool (MIT). Two parts of it that may interest this sub.

**The demo.** `examples/notes.sh` is a small HTTP service: notes kept in an INI file, whole-word
search, one class whose methods are the routes. `bash examples/notes_session.sh` starts it on a free
port and plays a curl session:

```text
$ curl -s localhost:39218/notes -d 'buy milk'
1
$ curl -s localhost:39218/notes -d 'call Alice about the milk'
2
$ curl -s 'localhost:39218/search?q=milk'
1: buy milk
2: call Alice about the milk
$ curl -s -X POST localhost:39218/quit
bye
```

It needs curl and socat (or GNU netcat 0.7.1). It is a demo, not a web server: one request at a
time, plain HTTP, keep it on 127.0.0.1.

**The tool wrappers.** `TGrep`, `TSed`, `TAwk`, `TFind`, `THead` and `TTail` build the command line
from typed options and hand the records back to your shell:

```bash
kk.uses tgrep || exit
TGrep.new g TODO src/
g.ignoreCase = 1
g.recursive  = 1
g.include    = '*.sh'
g.toArray hits; echo "$RESULT hits"
g.delete
```

They always drive the GNU tool, found by name (`gsed`, `gawk`, `ggrep`, `gfind`, `ghead`, `gtail`
first, then the plain name if it is GNU), so the options mean the same on every system. Without one,
every call returns rc 2 with a reason that names the package to install. `TSed` and `TAwk` run with
`--sandbox` on by default, and in `TGrep`, `TSed` and `TAwk` CRLF input gives the same records on Windows and Linux.

The cost is honest: the wrapper's own work is 2.9 to 6.4 ms per call, which makes it 2x to 7x slower
than calling the tool directly on Linux and 1.19x to 1.38x on Windows
(https://github.com/Keksov/kbool/blob/main/docs/benchmarks.md). A pipeline is still the right tool
for bulk data.
