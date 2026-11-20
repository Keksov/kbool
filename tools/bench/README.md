# tools/bench — kklass call-path and kcl fv screen benchmarks

Measures what one kklass method call costs (plain function, 1 and 14 fields,
a long body, `inherited`, a nested call, a property read, `new` + `delete`),
whether a long process slows down (the drift cases), and what the screen
actions of a kcl `fv` TUI cost (the fv suite: the screen buffer; the fvviews
suite: the application, inside `app.Run`). Every measurement runs in a
fresh bash process; several kbool trees ("sides") can be measured side by side,
with rounds interleaved over the sides so that machine noise hits all of them
alike.

| file | what |
|---|---|
| `cases.sh ROOT CASE [N]` | one kklass case in this process; prints `NAME MICROSECONDS` lines |
| `fvcases.sh ROOT CASE [N]` | one fv case in this process (ROOT's `kcl/fv.video`); prints `LABEL MICROSECONDS` lines and `# note` lines |
| `fvviewcases.sh ROOT CASE [N]` | one fvviews case in this process (ROOT's `kcl/fv.app`, `fv.views`, `fv.menus`); prints `LABEL MICROSECONDS` lines and `# note` lines (`# calls` / `# writes`) |
| `bench.sh [opts] NAME=ROOT... -- SUITE...` | the driver: suites `call`, `drift`, `fv`, `fvviews`; a Markdown report |
| `prepare.sh DEST SPEC...` | builds sides: kbool copies with kklass and/or kcl at a ref (`pointer` = as checked out), optionally patched from `variants/` |
| `ci.conf` | what `.github/workflows/bench.yml` runs on a push to the `perf` branch |

Local use, from the kbool root:

```bash
bash tools/bench/bench.sh --rounds 3 cur=. -- call drift
bash tools/bench/prepare.sh /tmp/sides old=main cur=pointer   # prints the side arguments
bash tools/bench/bench.sh old=/tmp/sides/old cur=/tmp/sides/cur -- call
```

`--n N` sets the calls (call, drift) or actions (fv, fvviews) per measurement; without
it call and drift take 2000, fv and fvviews 10.

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
| `W.paint` | cold first paint: `initScreen` + the whole scene + `updateScreen`; initScreen empties the text caches, and before each run (untimed) the bench also empties the caches initScreen keeps — fv.video's private class cache `__FV_VS_CC`, 16-colour map `__FV_VS_N16` and stored default palette `__FV_VS_CPAL` / `CSG16` / `CSG256` |
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

## The fvviews suite

The application layer of the `kcl` `fv` TUI (`fv.views`, `fv.menus`,
`fv.app`; kcl fv P2), headless (`FV_APP_HEADLESS=1`, frames to `/dev/null`).
The scene is the P2 design's (§3.1): `TMyApp` (a `TApplication` whose
`HandleEvent` override calls `inherited`, as FV programs do; it also takes
Ctrl+L as "redraw everything"), the desktop, two windows side by side (half
the screen wide, the desktop's height), each with a list stand-in
`TTestList` (a `TView` with TView's default `EventMask`: `Draw` = one
`fv.views.writeLines` call for its visible rows, as kcl P3's lists draw;
kbDown = two `drawPart`s, kbPgDn = a new page and `drawView`), and the status
line. A kcl without `writeLines` (before kcl fv D21 stage E) gets the old
stand-in, one `writeLine` per row. **Every action runs inside `app.Run`**: its
keys (xterm bytes, SGR mouse reports) are written to a file read through
`FV_KEY_FD` and `fv.drivers.getEvent`, as a program reads its terminal. One
measurement is one Run over the action's keys repeated N times, minus a Run
without them (the Run, Alt-X and any prefix / suffix cancel out), divided by
N.

| action | what is timed |
|---|---|
| `W.paint` | the first paint from `Run` (decision D18): before each Run, untimed, the application's `InitScreen` (a fresh buffer, nothing shown) and its "not shown yet" state (fv.app private state, reached into on purpose) |
| `W.paint+init` | the same with `InitScreen` inside the timed window and fv.video's per-process caches emptied before it (the fv suite's cold paint) |
| `W.redraw` | Ctrl+L → `fv.views.redraw $FV_APP` (every cell sent again) |
| `W.down` | kbDown to the focused stand-in: two rows |
| `W.pgdn` | kbPgDn: every row of the stand-in with new texts |
| `W.tab` | F6 → the status line → `cmNext` → the other window (both frames change; the window brought to the front is repainted where the other's shadow covered it) |
| `W.tab-in` | kbTab between two controls inside the focused window (a one-row second stand-in is inserted for this action only) |
| `W.click` | a mouse press + release on the other window, alternately on each |
| `W.move` | one keyboard drag step: Ctrl+F5 (`cmResize`) once, then Right / Left alternately, Enter after. A mouse drag read from a file is not measured per step: fv.views drains the waiting moves and draws the last (design R10) |
| `W.grow` | the same with Shift+Right / Shift+Left |
| `W.pgdn-cyr`, `W.pgdn-cjk` | `W.pgdn` with non-ASCII names on fresh pages (kcl fv P3 design §8.2): `Отчёт_квартал_N.txt   SIZE`, or 4 CJK characters + `_N.txt   SIZE`, padded with blanks to the row's cells; every PgDn shows rows fv.video's text cache never saw (the P3 levers 10.11 / 10.12). Timed after every other action of the case, so that theirs stay comparable with runs from before these two |
| `overlap.80x24.*` | `tab`, `click`, `move` with the second window over half of the first (the window brought to the front is repainted whole) |
| `resize.A-B` | `cmResizeApp` 80×24 ↔ 200×50 through the real event path: fv.video's resize flag set before the Run, its size source `fv.video.querySize` overridden (the documented hook), one resize per Run |
| `p2.80x24.paint`, `.paint+init` | the P2 scene of D18's first-paint gate: the tests' two overlapping windows (2 1 40 20, 30 5 70 22) with a plain `TView` leaf each, no lists |

The cases are `views-80` and `views-200` (every `W.*` action at 80×24 /
200×50), `views-overlap-80`, `views-resize` and `views-p2-80`. Before the
timing each action runs once with kklass's dispatchers and fv.video's writes
wrapped in counting shims (as `kcl/fv.views/tests/fvw_testlib.sh` does), and
its effect is checked (the focused row moved, the other window focused, the
bounds changed, ...): the report lists `# calls ACTION N` and `# writes
ACTION N` per side under the table (`# writes` counts one write per list a
Draw paints since D21 stage E — `fv.video._wrows`, the call under
`writeLines` — where the old stand-in counted one per row: at 80×24 paint /
redraw 49 → 9, pgdn 21 → 1, move 27 → 7; at 200×50 paint / redraw 101 → 9,
pgdn 47 → 1; `# calls` unchanged; `pgdn-cyr` / `pgdn-cjk` count 1 write
since kcl fv P3 stage 3a-1, where an older kcl adds one `writeBuf` per fresh
non-ASCII row); an error output, a missing effect or a
Run ended by the end of input stops the case (rc 3, `!!` in the report).
Keys waiting in a file leave no idle tick between them, so the Idle work a
window switch causes at the terminal's next pause (the `cmCommandSetChanged`
broadcast, 2 dispatches through `TMyApp`) is not part of `tab` / `click`.

```bash
bash tools/bench/bench.sh --rounds 5 cur=. -- fvviews
bash tools/bench/prepare.sh /tmp/sides old=kcl@main cur=pointer
bash tools/bench/bench.sh --rounds 5 old=/tmp/sides/old cur=/tmp/sides/cur -- fvviews
```

A kcl without `fv.app` (before kcl fv P2) stops each case with rc 2.

## CI

On GitHub, `bench.yml` runs the same on Linux (host and containers, bash 5.1 to
5.3, musl and glibc), macOS and Windows (Git-bash, MSYS2, Cygwin). `ci.conf`
holds the default sides and suites (`SUITES` may include `fv` and `fvviews`; for kcl
comparisons pin kcl in `SIDES`, e.g. `main=kcl@main cur=pointer`); a manual run
overrides them with its inputs. Runner timings vary by 10–30% between machines:
compare the sides of one row (the ratio columns), not absolute numbers across
runs. Benchmarks give no pass/fail verdict.
