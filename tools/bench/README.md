# tools/bench — kklass call-path and kcl fv screen benchmarks

Measures what one kklass method call costs (plain function, 1 and 14 fields,
a long body, `inherited`, a nested call, a property read, `new` + `delete`),
whether a long process slows down (the drift cases), and what the screen
actions of a kcl `fv` TUI cost (the fv suite). Every measurement runs in a
fresh bash process; several kbool trees ("sides") can be measured side by side,
with rounds interleaved over the sides so that machine noise hits all of them
alike.

| file | what |
|---|---|
| `cases.sh ROOT CASE [N]` | one kklass case in this process; prints `NAME MICROSECONDS` lines |
| `fvcases.sh ROOT CASE [N]` | one fv case in this process (ROOT's `kcl/fv.video`); prints `LABEL MICROSECONDS` lines and `# note` lines |
| `bench.sh [opts] NAME=ROOT... -- SUITE...` | the driver: suites `call`, `drift`, `fv`; a Markdown report |
| `prepare.sh DEST SPEC...` | builds sides: kbool copies with kklass and/or kcl at a ref (`pointer` = as checked out), optionally patched from `variants/` |
| `ci.conf` | what `.github/workflows/bench.yml` runs on a push to the `perf` branch |

Local use, from the kbool root:

```bash
bash tools/bench/bench.sh --rounds 3 cur=. -- call drift
bash tools/bench/prepare.sh /tmp/sides old=main cur=pointer   # prints the side arguments
bash tools/bench/bench.sh old=/tmp/sides/old cur=/tmp/sides/cur -- call
```

`--n N` sets the calls (call, drift) or actions (fv) per measurement; without
it call and drift take 2000, fv 10.

## Sides: `prepare.sh` specs

```
SPEC = NAME=PIN[,PIN...]      PIN = [SUB@]REF[+PATCH]
```

* `SUB` is `kklass` (the default: a bare `REF` pins kklass, as before) or `kcl`;
* `REF` is `pointer` (the submodule as checked out here) or any ref of the
  submodule's origin (a commit already present is used without a fetch). A
  short sha works only where that commit is already present: CI's submodules
  are shallow, so there give a branch, a tag or a full 40-character sha;
* `PATCH` is a file under `tools/bench/variants/`, applied to that submodule
  with `patch -p1`;
* a submodule no pin names stays as checked out.

```bash
bash tools/bench/prepare.sh /tmp/sides old=v0.1.1 cur=pointer                 # kklass refs
bash tools/bench/prepare.sh /tmp/sides p1a=kcl@848c725 cur=pointer            # kcl refs (fv; short sha: local only)
bash tools/bench/prepare.sh /tmp/sides both=v0.1.1,kcl@main                   # both pinned
```

Each side's `.bench_rev` names its kklass (line 1) and its kcl (line 2,
`kcl <sha> <subject>`); the report's header shows both.

## The fv suite

Screen-level scenes on the `kcl/fv.video` screen buffer, fv.video calls only
(rows are formatted before the timing). Frames go to `/dev/null` through
`FV_VIDEO_OUT_FD`; `initVideo` is never called, the terminal is not touched.
The scene is a two-panel file manager: per panel a box-drawing frame with a
title (`writeCStr`) around a list of 400 names, one `writeBuf` per row (name,
size, at 200 columns a date; every sixth name Cyrillic), the active panel's
selected row, and a status line (`writeCStr`).

| action | what is timed (mean of N, one process) |
|---|---|
| `W.paint` | cold first paint: `initScreen` + the whole scene + `updateScreen`; initScreen empties the text caches, and before each run (untimed) the bench also empties the caches initScreen keeps — fv.video's private class cache `__FV_VS_CC` and 16-colour map `__FV_VS_N16` |
| `W.down` | the selection one row down: 2 `writeBuf` + `updateScreen` (partial) |
| `W.scroll` | the selection on the last row, the list moves one name: every row of the panel written again + `updateScreen` |
| `W.tab` | the selection to the other panel: 2 `writeBuf` + `updateScreen` |
| `resize.A-B` | `resizeScreen` to the other size + the whole scene + `updateScreen` (80×24 ↔ 200×50, both painted once before) |
| `wide.W.*` | `paint`, `down`, `scroll` with every other name CJK, Hangul or emoji (2 cells per character) |

`W` is `80x24` or `200x50`. The cases (fresh processes) are `fv-80`, `fv-200`,
`fv-resize`, `fv-wide-80`, `fv-wide-200`. Before the timing each case runs the
scene and every action once in a subshell with fv.video's error output on; an
error stops the case (rc 3, shown as `!!` in the report). A kcl whose fv.video
has no wide characters (before kcl P1b; checked by behaviour: `strWidth` of a
CJK character is not 2) gives `-` and a note for the wide rows. The caller's
locale does not matter (widths come from `fv.video.strWidth`, in fv.video's own
locale); ASCII mode (`FV_ASCII=1` in the environment, or no UTF-8 locale at
all) is measured, every row included, with a note. A caller locale that does
not exist (an uninstalled `LANG`) is replaced by `LANG=C`, with a note: bash
keeps the previous locale when a restore of `LC_ALL` to such a name fails, so
fv.video's own locale switches would leave the shell's locale changing from
call to call. The report shows ms
per action, the median of the rounds (min-max), and every side's ratio to the
first.

Compare kcl refs:

```bash
bash tools/bench/prepare.sh /tmp/sides old=kcl@main cur=pointer
bash tools/bench/bench.sh --rounds 5 old=/tmp/sides/old cur=/tmp/sides/cur -- fv
```

## CI

On GitHub, `bench.yml` runs the same on Linux (host and containers, bash 5.1 to
5.3, musl and glibc), macOS and Windows (Git-bash, MSYS2, Cygwin). `ci.conf`
holds the default sides and suites (`SUITES` may include `fv`; for kcl
comparisons pin kcl in `SIDES`, e.g. `main=kcl@main cur=pointer`); a manual run
overrides them with its inputs. Runner timings vary by 10–30% between machines:
compare the sides of one row (the ratio columns), not absolute numbers across
runs. Benchmarks give no pass/fail verdict.
