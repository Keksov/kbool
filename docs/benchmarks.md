# Benchmarks: what kbool costs

The entry page is [../README.md](../README.md). This page answers one question: is kbool fast
enough for your script, and what does it cost? Every number below comes from two measurement
files kept in the tree, [bench-ubuntu.json](dev/launch/bench-ubuntu.json) and
[bench-windows-gitbash.json](dev/launch/bench-windows-gitbash.json), and you can reproduce them
with one command (see [Method](#method)).

## Summary

Work that stays inside the shell is cheap: a method call costs 266.6 µs on the Linux VM and
212.9 µs on Windows, a property read 45.9 µs and 34.8 µs, a dictionary `Add` 337 µs and 235 µs.
Loading is paid once per script: `source kbool.sh` takes 12.6 ms (Linux) and 32.8 ms (Windows),
and with a unit such as `tstringlist` or `dateutils` the total is 152.4 ms to 431.5 ms. A fork is
what costs: one `x=$(true)` takes 750.395 µs on Linux and 16008.55 µs (16 ms) on Windows. That
is why kbool keeps forks off its hot paths: members return values in variables, not on stdout,
and an external command runs once per call, never once per record.

## The figures

Medians of 3 runs. "VM" is Ubuntu 24.04 in VirtualBox; "Windows" is Git-bash on the host.
The first two rows are plain bash with no kbool loaded: they give the scale.

| figure | what it measures | VM (bash 5.2.21) | Windows (bash 5.3.15) |
|---|---|---|---|
| empty function call | calling `f() { :; }` in a loop (the loop's cost included) | 7.018 µs | 5.032 µs |
| one fork | `x=$(true)` in a loop: one subshell per iteration | 750.395 µs | 16008.55 µs |
| method call | `o1.m1`, a method whose body is one `echo` | 266.6 µs | 212.9 µs |
| property read | `o1.a`, a plain property | 45.9 µs | 34.8 µs |
| computed property read | `o1.area`, a property whose getter computes `a*b`, with 1000 live instances | 785.2 µs | 673 µs |
| `.new` | creating an instance of a class with 2 properties, a computed one and 10 methods (first 60) | 256.4 µs | 126.7 µs |
| `.delete` | destroying an instance while 1000 instances (~19281 shell functions) exist | 199.9 µs | 166.7 µs |
| `TDictionary.Add` | inserting a new key (instance dispatch included) | 337 µs | 235 µs |
| `TDictionary.GetItem` | reading a key with the direct call (no `$(...)`) | 362 µs | 257 µs |
| `TRegEx.isMatch` | one regex test through the class (a static method) | 141.7 µs | 107.4 µs |
| Pascal class build | `class … end` with 2 fields and 15 methods, then `build`, per class | 22.8 ms | 24 ms |
| `source kbool.sh` | a fresh `bash -c` that loads kbool (bash start-up included) | 12.6 ms | 32.8 ms |
| `+ kk.uses tstringlist` | the same plus `tstringlist` and the units it uses | 152.4 ms | 171.7 ms |
| `+ kk.uses dateutils` | the same plus `dateutils` and the units it uses | 431.5 ms | 383.7 ms |

**Why a fork dominates.** A function call, a property read or a dictionary lookup stays inside
the running bash process. `$(...)`, a pipe or an external command starts a new process, which
copies the shell; the bigger the shell, the more it costs. The tdictionary bench shows it: the
same `GetItem` captured as `v=$(d.GetItem k)` took 2756 µs on Linux and 31617 µs on Windows, in
the same run in which the direct call took 370 µs and 253 µs. kbool members therefore return
through `RESULT` and print nothing on a direct call
([kcl/README.md, Returning a value](../kcl/README.md#11-returning-a-value)); use `$(...)` only when
you want a subshell.

## Method

* **Hardware.** One machine: AMD Ryzen 7 8845H. The Linux column runs in a VirtualBox VM on it
  (4 vCPU, Ubuntu 24.04.5 LTS, kernel 6.8.0-147, bash 5.2.21). The Windows column runs on the
  host itself (Windows 11, Git-bash with msys 3.6.10, bash 5.3.15). Both were measured on
  2026-10-31 with the same tree (root `cf0a246-dirty`, kcl `41d9c25`, kklass `5ccd7fc`, kkore
  `7e5729c`, ktests `ba743bb`, as recorded in `kbool_head`).
* **Timing.** Every figure is wall time read from bash's `EPOCHREALTIME` (microseconds) around a
  loop; the kcl benches read it through `TStopwatch.getTimeStamp`. No measured loop forks unless
  the row is about a fork or a child shell.
* **Medians.** [tools/porting/benchrun.sh](../tools/porting/benchrun.sh) makes 3 runs and reports
  the median for each figure; the `runs` field of each figure keeps all three values, and
  `source` says how it was measured. Per run: 100000 empty calls; 200 `$(true)`; the kklass bench
  (1000 method calls and property reads, 200 computed reads, 60 `.new`, 10 `.delete`); the
  tdictionary bench (300 calls); the tregex bench (2000 calls).
* **Load figures** (`source kbool.sh`, `kk.uses …`) are the mean of 5 fresh `bash -c` children per
  run, then the median of 3. They include the child's bash start-up, so they are what a script pays
  from its first line to a loaded unit.
* **The Pascal class build** is the mean over 10 generated classes per run, built in a fresh child
  shell that has already loaded `kklass_pascal`; generating the class text is not timed.
* **Raw outputs.** After the 3 runs, `benchrun.sh` runs every bench once more (the kklass bench
  and all 18 `kcl/*/bench.sh`) and stores each one's full output, exit code and wall time under
  `raw` in the JSON. The wrapper ratios below are quoted from there.

To reproduce, run from the kbool root with the bash you want to measure:

```bash
bash tools/porting/benchrun.sh --runs 3 --out my.json
```

It needs `node` (it writes the JSON) and changes no library code. Every bench runs under
`timeout -k 10 600`; a figure that could not be measured gets `"value": null` and a `reason`,
never a guess. In a copy of the tree without `.git/`, pass the commits in `BENCH_HEADS`
(`bash tools/porting/benchrun.sh --help`).

## Caveats

**The two columns are not a Linux-versus-Windows comparison.** The Linux figures come from a
virtual machine, with its own overhead, and the two columns use different bash versions (5.2.21
and 5.3.15). Most in-shell rows come out slower in the VM than on the Windows host, while the fork
row goes the other way by a wide margin. Compare rows within one column, not across.

**Single runs vary.** The median hides outliers that the `runs` field keeps: on Windows one
`$(true)` run measured 21803.575 µs and one `source kbool.sh` run 59.5 ms.

**Wrapper units add a fixed cost per call.** `TGrep`, `TFind`, `TSed`, `TAwk`, `THead` and `TTail`
build the tool's command line in bash, run the tool once, and clean up. That work costs the same
whatever the input size: 2.9 ms to 6.4 ms per call (the "wrapper's own cost" column below). On
Linux, where the tool itself starts in a few milliseconds, this makes the wrapper 2x to 7x slower
than calling the tool directly. On Windows the tool's own process start dominates, and the same
wrapper costs 1.19x to 1.38x the bare tool. Medians of 20 or 21 runs, from the raw outputs:

| wrapper vs the bare tool | case | VM: bare tool | VM: ratio | Windows: bare tool | Windows: ratio | wrapper's own cost, VM / Windows |
|---|---|---|---|---|---|---|
| `TAwk.apply` vs `gawk --sandbox -e` | 10000 lines / 1 line | 8.69 / 3.89 ms | 2.07x / 3.13x | 27.87 / 27.02 ms | 1.19x / 1.22x | 4474.8 / 3100.5 µs |
| `TFind.byName` vs `find -name` | 400 matches / 1 match | 2.89 / 2.20 ms | 3.29x / 4.08x | 25.99 / 24.23 ms | 1.22x / 1.27x | 4824.1 / 3494.6 µs |
| `TGrep.search` vs `grep -r` | 101 hits | 2.33 ms | 7.41x | 25.48 ms | 1.24x | 3522.6 / 2913.4 µs (construction only) |
| `THead.take` vs `head -n` | `-n 1` / `-n 5000` | 1.77 / 2.14 ms | 4.88x / 4.05x | 23.90 / 22.19 ms | 1.27x / 1.38x | 4430.6 / 3439.9 µs |
| `TSed.edit` vs `sed --sandbox -e` | 10000 lines / 1 line | 6.34 / 2.73 ms | 2.46x / 4.27x | 24.70 / 21.20 ms | 1.21x / 1.27x | 6126.6 / 4219.9 µs |
| `TTail.take` vs `tail -n` | `-n 1` / `-n 5000` | 2.31 / 2.76 ms | 4.33x / 3.76x | 19.58 / 20.59 ms | 1.25x / 1.26x | 6387.2 / 3119.1 µs |

These benches print a ratio gate (1.5x, 1.3x for `TGrep`) with PASS or FAIL. The gates were set
on Windows; on Linux every one of them prints FAIL. Read the ratios above as the per-platform cost,
not as a test result.

**The HTTP server's network part did not run.** The thttpserver bench has a part without sockets,
which ran: one request served through the replay transport took 37.98 ms on the VM and 29.66 ms on
Windows. Its network parts were skipped on both platforms in these measurements, so this page
gives no figure for serving over a socket.

## When not to use kbool

Bash is slow at looping over large data, with or without kbool. If a script handles thousands of
records, an external command per record makes the fork row the whole cost: multiply it by the
record count. Reading each record into the shell is cheaper but not free: `THead`'s `count` over
5000 lines took 420.83 ms on Linux against 2.94 ms for `head -n 5000 | wc -l`, about 83 µs per
line read into bash. When all you need is a number or a filtered file, a pipeline of `grep`, `awk`
or `sort` is the right tool. kbool pays off where a script spends its time in logic, structure and
error handling rather than in a per-record loop.
