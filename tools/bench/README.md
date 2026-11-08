# tools/bench — kklass call-path benchmarks

Measures what one kklass method call costs (plain function, 1 and 14 fields,
a long body, `inherited`, a nested call, a property read, `new` + `delete`) and
whether a long process slows down (the drift cases). Every measurement runs in a
fresh bash process; several kbool trees ("sides") can be measured side by side,
with rounds interleaved over the sides so that machine noise hits all of them
alike.

| file | what |
|---|---|
| `cases.sh ROOT CASE [N]` | one case in this process; prints `NAME MICROSECONDS` lines |
| `bench.sh [opts] NAME=ROOT... -- SUITE...` | the driver: suites `call`, `drift`; a Markdown report |
| `prepare.sh DEST NAME=REF[+PATCH]...` | builds sides: kbool copies with kklass at a ref (`pointer` = as checked out), optionally patched from `variants/` |
| `ci.conf` | what `.github/workflows/bench.yml` runs on a push to the `perf` branch |

Local use, from the kbool root:

```bash
bash tools/bench/bench.sh --rounds 3 cur=. -- call drift
bash tools/bench/prepare.sh /tmp/sides old=main cur=pointer   # prints the side arguments
bash tools/bench/bench.sh old=/tmp/sides/old cur=/tmp/sides/cur -- call
```

On GitHub, `bench.yml` runs the same on Linux (host and containers, bash 5.1 to
5.3, musl and glibc), macOS and Windows (Git-bash, MSYS2, Cygwin). Runner timings
vary by 10–30% between machines: compare the sides of one row (the ratio
columns), not absolute numbers across runs. Benchmarks give no pass/fail verdict.
