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
| `imgcases.sh ROOT CASE [N]` | one image case (kkore's `kk.image`, ROOT's `kcl/fv.dlg`): starts in fresh processes; prints `LABEL MICROSECONDS` lines and `# note` lines |
| `bench.sh [opts] NAME=ROOT... -- SUITE...` | the driver: suites `call`, `drift`, `fv`, `fvviews`, `image`; a Markdown report |
| `prepare.sh DEST SPEC...` | builds sides: kbool copies with kklass, kcl and/or kkore at a ref (`pointer` = as checked out), optionally patched from `variants/` |
| `ci.conf` | what `.github/workflows/bench.yml` runs on a push to the `perf` branch |

Local use, from the kbool root:

```bash
bash tools/bench/bench.sh --rounds 3 cur=. -- call drift
bash tools/bench/prepare.sh /tmp/sides old=main cur=pointer   # prints the side arguments
bash tools/bench/bench.sh old=/tmp/sides/old cur=/tmp/sides/cur -- call
```

`--n N` sets the calls (call, drift), actions (fv, fvviews) or starts (image) per
measurement; without it call and drift take 2000, fv and fvviews 10, image 5.

## Sides: `prepare.sh` specs

```
SPEC = NAME=PIN[,PIN...]      PIN = [SUB@]REF[+PATCH]
```

* `SUB` is `kklass` (the default: a bare `REF` pins kklass, as before), `kcl` or
  `kkore` (the image suite);
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

Each side's `.bench_rev` names its kklass (line 1), its kcl (line 2,
`kcl <sha> <subject>`) and its kkore (line 3, `kkore <sha> <subject>`); the
report's header shows them.

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
| `W.list.down.KIND` | kcl P3 stage 3b's list scene (design P3 §8, §9.2): the application `TListApp` (as `TMyApp`, and F12 / F11 move the list to a **fresh page** — `TopItem` 400 items further than before, the focus on its top / bottom row — rows fv.video's text cache never saw), the left window a `TListViewer` of 60 000 items with its standard vertical bar (FV's file panel; a plain window's palette, D25), the right one the stand-in. KIND = the names: `ascii` `file_report_N.txt   4096`, `cyr` `Отчёт_квартал_N.txt   4096`, `cjk` 4 CJK characters + `_N.txt   4096`. `down`: prefix F12, Down inside the page (rule 4: one `drawPart` over the two rows) |
| `W.list.down-edge.KIND` | prefix F11, Down at the bottom row: a scroll by one (one fresh row; the bar's indicator when it moves) |
| `W.list.pgdn.KIND` | prefix F11, PgDn: every page fresh |
| `W.list.wheel.KIND` | prefix F12, a wheel-down report over the list: a scroll by one |
| `W.list.click.KIND` | prefix F12, a press + release on the list's row 3 / row 8 alternately |
| `W.list.end-home.KIND` | End / Home alternately (the last and the first page, cached) |
| `W.list.pgdn-marks` | prefix F11, PgDn (ascii) with every other item marked (`Marks`, D26: read inline; design §5 wants ≤ 1.05 × `list.pgdn.ascii`) |
| `W.standin.down`, `W.standin.pgdn` | after F6 (untimed) to the stand-in window: its Down / PgDn, the D21 numbers in the list's process (the design's same-process calibration) |
| `W.standin.pgdn-cjk` | the stand-in's PgDn while the list beside it shows the `cjk` names (kcl P3 3v): the stand-in's rows share the screen rows with wide cells, so its writes and the frame take the wide paths (needs a UTF-8 locale, as `cyr` / `cjk`) |
| `dlg.80x24.open-close` | kcl P3 stage 3c's dialog scene (design P3 §8.3, §9.2): the `views-80` scene with `TDlgApp` (as `TMyApp`; F2 runs the pre-built test dialog modally in the desktop, F3 the pre-built paint dialog, F4 builds the 8-control dialog, runs it and destroys it). The test dialog is 60 × 14, the design's 8-control dialog: two input lines (MaxLen 255) with their labels, check boxes (3), OK (default), Cancel, Help (kcl P3 3d; before 3d a static text and radio buttons stood in the input lines' places: the row names stayed, the numbers are not comparable across that change). `open-close`: F2 + Ctrl+F4 (cmCancel), the pre-built dialog opened and closed |
| `dlg.80x24.tab` | prefix F2, Tab between the dialog's controls (the focus, the labels' Light, the default button's look), suffix Ctrl+F4 |
| `dlg.80x24.key` | prefix F2, a plain key nobody takes (`x`: the focused check boxes have no `x` item, the labels and buttons are skipped by the hot-key map), suffix Ctrl+F4 |
| `dlg.80x24.fkey` | the same with F9 (no hot letter at all: every mapped control skipped) |
| `dlg.80x24.paint` | prefix F3, F3 inside the paint dialog (a `TDialog` class whose `HandleEvent` override draws it on F3: `drawView`, the dialog's full draw), suffix Ctrl+F4 |
| `dlg.80x24.build-run-destroy` | F4 + Ctrl+F4: the 8-control dialog built (9 objects), run, closed and destroyed |
| `dlg.80x24.type` | kcl P3 3d (design P3 §8.3's typing rows): prefix F2 with the first input line the dialog's Current, typing `a` / `b`, suffix Ctrl+F4. The line's text is selected as the dialog opens (FV's SelectAll on focus), so each Run's first key replaces it. `# calls` 0, `# writes` 1 (one `writeLine` per key) |
| `dlg.80x24.type-cyr` / `type-cjk` | the same with `ж` / `ы` and `中` / `文` (a UTF-8 locale needed; none: a note, no rows) |
| `dlg.80x24.type-back` | prefix F2, `a` and Backspace alternately |
| `dlg.80x24.type-scrolled` | prefix F2 + End over a 70-character line (set before each measurement): typing `a` / `b` into a scrolled line |
| `dlg.80x24.shift-left` | the same line: Shift+Left, extending the selection (`# writes` 1) |
| `dlg.80x24.tab-20` / `type-20` | kcl P3 3g (design P3 R1): the 20-control dialog (76 × 21: a labelled input line, check boxes, labelled radio buttons, six more labelled input lines, OK / Cancel / Help; pre-built, F12 runs it): prefix F12, Tab between its controls / typing `a` / `b` into its first input line, suffix Ctrl+F4. Compare with `tab` / `type`: the hot-key map keeps keys off the extra controls (kcl `fv.dialogs/tests/013_CallBudget.sh` checks the counts against the 8-control dialog); a focus change still reaches every label (FV's focus broadcasts), without a write |
| `dlg.80x24.history-open-close` | kcl P3 3h (design P3 §15): prefix F7 (the pre-built history dialog: an input line with its `THistory`, 10 strings in its list), Down on the line (the line's text recorded, the history window built — window, frame, two bars, viewer — and run modal), Esc (closed, destroyed), suffix Ctrl+F4. Esc goes in as its CSI u form `ESC [ 27 u` (a bare ESC followed by the next key's ESC reads as Alt + that key). `# calls` 10 (the constructors), `# writes` 16 |
| `dlg.80x24.msgbox.e2e` | kcl P3 3e (design P3 §6, §9.2): F8 makes `TDlgApp` call `fv.msgbox.messageBox` (Error, OK: the 40 × 9 box centred on the desktop, its text and button built, run modal, closed by Ctrl+F4, destroyed) — a real message box end to end. `# calls` 13, `# writes` 15 (design §8.1's limit 16 / 20) |
| `dlg.80x24.msgbox.standin` | F11: the design's stand-in of the same box (M3: the dialog, the text and the OK button built by hand, `execView`, Ctrl+F4, destroyed), kept beside `msgbox.e2e` for comparison: the difference is fv.msgbox's own work (checks, the name, the format) |
| `menu.80x24.open-drop-close` | kcl P3 3f (design P3 §8.4, §9.2): FV's layout with a bar (D23: `fv.menus.menuBar` before the windows, the desktop from row 1), the `views-80` scene's two stand-in windows below it, `TMyApp`. The File box is 28 × 12 with a shadow (10 items, each with a help context and a hint in the status line's table; Exit is Alt+X `cmQuit`, so the Runs' Alt-X quits through the bar as in FV). F9 stands for "the user pauses": the case's event hook turns it into an idle tick (evNothing + the application's Idle, as fv.app's GetEvent does on a timeout), so the status line's hint follows the menu. The unit: F10, F9, Down, F9, Esc (`ESC [ 27 u`), F9 — the status line → `cmMenu` → the bar run modal by the application → the box dropped by the bar's owner and destroyed → Esc closes the box and the bar (FV). `# calls` 22 (2 F10 + 2 `cmMenu` + the focus broadcasts to `TMyApp` + the box's constructor / destructor), `# writes` 11 (design §8.1's limit 24 / 28) |
| `menu.80x24.down` | prefix Alt+F F9 (the File box at once: the bar's Default moves from Run to Run), a highlight move (Down, F9: two one-row `drawPart`s + the status line's new hint), suffix Esc F9. `# calls` 0, `# writes` 3 (limit 2 / 3) |
| `menu.80x24.down-nohint` | the same in the Edit box (prefix Alt+E F9): no hint change, no status line redraw. `# writes` 2 |
| `menu.80x24.idle` | prefix Alt+F F9, an F9 alone: the idle tick's own cost (the key, Idle, the status line's Update without a change), the part of `down` / `down-nohint` that is not the move. `# writes` 0 |
| `paint.80x24.paint`, `.paint+init` | the two-panel scene with a real list in each window (60 000 items, standard bars; the inactive panel's bar hidden: FV ShowSBar) at 80×24: **F-1's P3 number** (design §8.5, D31: ≤ 15 ms on CI; `p2.80x24.paint` with the stand-ins is the "today" number) |
| `paint.200x50.paint`, `.paint+init` | the same scene at 200×50 |

The cases are `views-80` and `views-200` (every `W.*` action at 80×24 /
200×50), `views-overlap-80`, `views-resize`, `views-p2-80`, and (kcl P3
3b) `views-list-80` / `views-list-200` (the `W.list.*` and `W.standin.*`
actions at 80×24 / 200×50; `cyr` / `cjk` need a UTF-8 locale, else a note)
and `views-paint-80` / `views-paint` (`paint.80x24.*` / `paint.200x50.*`),
and (kcl P3 3c) `views-dialog-80` (`dlg.80x24.*`), and (kcl P3 3f)
`views-menu-80` (`menu.80x24.*`).
A kcl without `TListViewer` (before P3 3b) prints a note
and no rows for those four; a kcl without `fv.dialogs` (before P3 3c) a
note and no rows for `views-dialog-80`; a kcl without `TInputLine` (before
P3 3d) no typing rows (nor `tab-20` / `type-20`); a kcl without `THistory` (before P3 3h) no
history row; a kcl without `fv.msgbox` (before P3 3e) no msgbox rows; a kcl
without `TMenuBar` (before P3 3f) a note and no rows for `views-menu-80`. The list actions' check pass counts what follows
the prefix only (F12 / F11 zero the counters: the jump's own draws differ
from run to run, the bar's indicator moving or not). Before the
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

## The image suite

kkore's load image (`kk.image`, `kklass/docs/dev/IMAGE_PLAN.md` §11) with
`kcl/fv.dlg` as the request. A **start** is a fresh process, `bash SCRIPT ROOT`,
whose script sources `kbool.sh`, runs the load and prints `$EPOCHREALTIME`:
**launch → return** is that mark minus the time taken before the spawn (bash's
own start included, its exit not). Every image lives in a temp folder
(`KBOOL_IMAGE_DIR`; bench.sh makes one with `mktemp -d` and removes it at the
end, a case run alone makes its own): the user's image cache is never read or
written. The caller's `KBOOL_IMAGE*` and `VERBOSE_KKLASS` are dropped; the
caller's locale is kept and named in a note (the hit path's text work costs
more under a UTF-8 locale). Before timing, an image is warmed (up to three
starts) and checked valid with `kk.image --path`; after a hit row, the image's
nonce shows that no start wrote it again.

| row | what is timed (mean of N, one process each unless said) |
|---|---|
| `image.hit.fvdlg` | `source kbool.sh; kk.image fv.dlg` through a valid image |
| `image.load.fvdlg` | the same with `KBOOL_IMAGE=off`, interleaved with the hits |
| `image.hit.fvdlg.dates` | Linux / macOS / BSD: the hit with `KBOOL_IMAGE_CHECK=dates` beside the default `stat` (the derived row shows the fork's share) |
| `image.bash`, `image.kbool` | references: a bare bash start; a start that only sources `kbool.sh` |
| `image.hit.chain` | `kk.uses tstringlist; kk.image fv.dlg` through a valid chained image |
| `image.load.chain` | the same with `KBOOL_IMAGE=off` |
| `image.load.tstringlist` | `kk.uses tstringlist` alone |
| `image.check` | in a fresh process after `source kbool.sh`: the first `kk.image --path fv.dlg` — the hit path's checks (kimghit.sh parsed, prep, key, header, edges, staleness, the clash and base checks) without the source of the image and the hooks |
| `image.check.warm` | the same call repeated in one process (calls 2..N+1) |
| `image.check.chain` | the first call after `kk.uses tstringlist` |
| `image.check.dates` | Linux / macOS / BSD: `image.check` with `KBOOL_IMAGE_CHECK=dates` |
| `image.miss.fvdlg` | a first start with an empty image folder: the normal load, then the writer (one start per measurement); `image.miss.fvdlg.PART` = the writer's own profile (before, load, delta, simulation, text, write, rename, total; through the `__KK_IMG_PROF` seam of `kkore/kimage.sh`) |
| `image.miss.chain` | the same on top of `kk.uses tstringlist` (`.PART` adds the fresh-process simulation) |
| `image.alt.first`, `image.alt.start` | two scripts in two folders alternate over 10 starts (the second folder holds a copy of `fv.dlg.sh`, so its request is another image): the mean of starts 1–2 (the two misses) and of starts 3–10 (hits); a note counts the images written in starts 3–10 (must be 0) |

Derived rows (from the medians, per side): `image.hit.fvdlg / image.load.fvdlg`,
`image.hit.chain - image.load.tstringlist` and its ratio to `image.hit.fvdlg`,
and `image.hit.fvdlg - image.hit.fvdlg.dates` (the `stat` fork) where measured.
Notes: `image.forks.MODE` — the forks of one hit per check mode (`dates`,
`stat`, `hash`), counted from an xtrace whose `PS4` holds `$BASHPID` (a traced
line with another pid is a fork; a main-shell command word that is a file on
`PATH` is listed too), as `kkore/tests/023` counts them.

```bash
bash tools/bench/bench.sh --rounds 3 cur=. -- image
bash tools/bench/prepare.sh /tmp/sides i3=kkore@849161d cur=pointer   # kkore refs
bash tools/bench/bench.sh --rounds 5 i3=/tmp/sides/i3 cur=/tmp/sides/cur -- image
bash tools/bench/imgcases.sh . img-check 2                            # one case
```

A kbool without `kk.image` (no `kkore/kimghit.sh`) stops each case with rc 2.

## CI

On GitHub, `bench.yml` runs the same on Linux (host and containers, bash 5.1 to
5.3, musl and glibc), macOS and Windows (Git-bash, MSYS2, Cygwin). `ci.conf`
holds the default sides and suites (`SUITES` may include `fv`, `fvviews` and `image`; for kcl
comparisons pin kcl in `SIDES`, e.g. `main=kcl@main cur=pointer`, for the image suite
kkore, e.g. `i3=kkore@<full sha> cur=pointer`); a manual run
overrides them with its inputs. Runner timings vary by 10–30% between machines:
compare the sides of one row (the ratio columns), not absolute numbers across
runs. Benchmarks give no pass/fail verdict.
