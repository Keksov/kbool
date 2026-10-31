**Title** (61 characters):

Show HN: kbool – Free Pascal-style classes and units for bash

**URL:** https://github.com/Keksov/kbool

**First comment** (plain text; HN does not render Markdown):

First, so you can judge the code accordingly: kbool is developed with AI assistance. Claude
sessions plan the work and write the code from task cards (627 of the 795 commits across the five
repos carry a Co-Authored-By: Claude trailer). I make the design decisions, and every change
reaches main only through me, after review against the tree and a test gate on two bash runtimes.
The plans and every decision with its reason are in the repo under docs/dev/.

What it is: a toolkit for bash scripts that have outgrown functions and globals but must stay bash.
Units loaded by name (kk.uses tstringlist), classes declared as class ... end with the method
bodies as ordinary bash functions, and a class library of 29 units: ports of Free Pascal and Delphi
classes (TStringList, TDictionary, TIniFile, TRegEx ...) and wrappers for grep, sed, awk, find,
head and tail. Members return values in a variable, not on stdout, because a $( ) fork costs
0.75 ms on Linux and 16 ms on Windows, while a method call costs 0.21-0.27 ms.

It needs bash 5.1+ and is tested on 13 CI configurations: Linux (glibc and musl, bash 5.1 to 5.3),
macOS, FreeBSD, Windows Git-bash and MSYS2. docs/portability.md lists the differences between them
that broke something (mawk, BSD stat, FreeBSD's emulated /dev/fd, \b per C library) and the test
that pins each fix.

Demo: a small HTTP notes service, examples/notes.sh. Costs, including when not to use it:
docs/benchmarks.md. This is 0.1.0; the API may still change in 0.x.
