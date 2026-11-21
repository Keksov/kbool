#!/usr/bin/env bash
# tools/bench/fvviewcases.sh ROOT CASE [N] -- one fvviews bench case (the kcl
# fv.views / fv.menus / fv.app application layer), run in this (fresh)
# process by tools/bench/bench.sh. ROOT is a kbool tree; `kk.uses fv.app`
# loads its kcl. Prints one line per measurement, `LABEL MICROSECONDS` (one
# decimal: the mean of one action), and `# TEXT` notes. Headless
# (FV_APP_HEADLESS=1): frames go to /dev/null, the terminal is never touched.
#
# The scene (P2 design §3.1): TMyApp (a TApplication whose HandleEvent, an
# override, calls inherited, as FV programs do; it also takes Ctrl+L as
# "redraw everything"), the desktop, two TWindows side by side (each half the
# screen wide, the desktop's height) with a TTestList list stand-in each (a
# TView with TView's default EventMask: Draw = one fv.views.writeLines call
# for its visible rows, as P3's lists draw (kcl D21 stage E; a kcl without
# writeLines: one writeLine per row, the old stand-in); kbDown = two
# drawParts, the old and the new focused row; kbPgDn = a new page and
# drawView), the status line (FV's StdStatusKeys). The overlap scene
# puts the second window over half of the first. The P2 scene (D18's first
# paint gate): the two windows of the tests (2 1 40 20, 30 5 70 22) with a
# plain TView leaf each, no lists.
#
# EVERY ACTION RUNS INSIDE app.Run: the keys (xterm bytes, SGR mouse reports)
# come from a file through FV_KEY_FD and fv.drivers.getEvent, as a program
# reads its terminal. One measurement = one Run over PREFIX + N x UNIT +
# SUFFIX + Alt-X minus one Run over PREFIX + SUFFIX + Alt-X, divided by N
# (the Run's own cost, the quit and the prefix / suffix cancel out). Keys
# waiting in a file leave no idle tick between them, so the Idle work a
# window switch causes at the terminal's next pause (the cmCommandSetChanged
# broadcast: 2 dispatches through TMyApp) is not part of tab / click:
#   W.paint      the first paint from Run (D18): before each Run (untimed) the
#                application's InitScreen (a fresh buffer, nothing shown) and
#                its "not shown yet" state -- fv.app PRIVATE state
#                (__FV_AP_SHOWN, the sfExposed bit), reached into on purpose
#   W.paint+init the same with the InitScreen inside the timed window and
#                fv.video's per-process caches emptied before it (untimed;
#                as fvcases.sh's cold paint: F-1 continuity)
#   W.redraw     Ctrl+L -> fv.views.redraw $FV_APP (every cell sent again)
#   W.down       kbDown to the focused stand-in (2 rows)
#   W.pgdn       kbPgDn (every row of the stand-in, new texts)
#   W.pgdn-cyr   the same with Cyrillic names (`Отчёт_квартал_N.txt   SIZE`),
#   W.pgdn-cjk   or 4 CJK characters + `_N.txt   SIZE`, padded to the row's
#                cells (kcl fv P3 design §8.2's fresh pages): every PgDn shows
#                rows fv.video's text cache never saw (P3 levers 10.11 /
#                10.12). Measured after every other action of the case (their
#                numbers stay comparable with older runs)
#   W.tab        F6 -> the status line -> cmNext -> the other window
#   W.tab-in     kbTab between two controls inside the focused window (a
#                second, one-row stand-in is inserted for this action only)
#   W.click      a mouse press + release on the other window, alternately on
#                each (focus + bring to front)
#   W.move       one keyboard drag step: PREFIX Ctrl+F5 (cmResize), UNIT an
#                arrow (Right / Left alternately), SUFFIX Enter. (A mouse drag
#                read from a file would coalesce: fv.views drains the waiting
#                moves and draws the last one, design R10)
#   W.grow       the same with Shift+Right / Shift+Left
#   resize.A-B   cmResizeApp 80x24 <-> 200x50 through the real event path:
#                fv.video's resize flag set before the Run and the size source
#                fv.video.querySize overridden (fv.video's documented hook),
#                one resize per Run
# The list scene (kcl P3 stage 3b, design P3 §8, §9.2): the application
# TListApp (as TMyApp, and F12 / F11 move the list to a FRESH page: TopItem
# 400 items further than before, the focus on its top / bottom row — the
# rows fv.video's text cache never saw, design H1), the left half a TWindow
# with a TListViewer of 60 000 items and its standard vertical bar (FV's
# file panel; the list's palette in a plain window, D25), the right half the
# stand-in window (TTestList) as in views-80. KIND = the names: ascii
# `file_report_N.txt   4096`, cyr `Отчёт_квартал_N.txt   4096`, cjk 4 CJK
# characters + `_N.txt   4096` (narrow / wide fresh rows: P3 10.11 / 10.12):
#   W.list.down.KIND       PREFIX F12, Down inside the page (rule 4: one
#                          drawPart over the two rows)
#   W.list.down-edge.KIND  PREFIX F11, Down at the bottom row: a scroll by one
#                          (one fresh row, the bar's indicator when it moves)
#   W.list.pgdn.KIND       PREFIX F11, PgDn: every page fresh
#   W.list.wheel.KIND      PREFIX F12, a wheel-down report over the list (a
#                          scroll by one)
#   W.list.click.KIND      PREFIX F12, a press + release on row 3 / row 8
#                          alternately
#   W.list.end-home.KIND   End / Home alternately (cached pages)
#   W.list.pgdn-marks      PREFIX F11, PgDn with every other item marked
#                          (Marks, D26: read inline, design §5: <= 1.05x)
#   W.standin.down, W.standin.pgdn
#                          F6 to the stand-in window first (untimed), then its
#                          Down / PgDn: the D21 numbers in the same process
#   W.standin.pgdn-cjk     the stand-in's PgDn while the list beside it shows
#                          the cjk names (kcl P3 3v: its rows share the screen
#                          rows with wide cells; needs a UTF-8 locale)
#   dlg.W.* (views-dialog-80, kcl P3 3c, design P3 §8.3 / §9.2): the scene of
#                          views-80 with TDlgApp (as TMyApp; F2 runs the
#                          pre-built test dialog modally in the desktop, F3
#                          the pre-built paint dialog, F4 builds the
#                          8-control dialog, runs it and destroys it). The
#                          test dialog: 60 x 14, the design's 8-control
#                          dialog — two input lines (MaxLen 255) with their
#                          labels, check boxes (3), OK (default), Cancel,
#                          Help (kcl P3 3d; a kcl before 3d: 3c's stand-ins,
#                          a static text and radio buttons in the input
#                          lines' places; the row names are the same, the
#                          dialog is not: 3c's numbers are not comparable):
#     dlg.W.open-close     F2 + Ctrl+F4 (cmCancel): open and close, pre-built
#     dlg.W.tab            PREFIX F2, Tab between the controls, SUFFIX Ctrl+F4
#     dlg.W.key            PREFIX F2, a plain key nobody takes (x: the focused
#                          check boxes have no x item; every label and button
#                          skipped by the hot-key map), SUFFIX Ctrl+F4
#     dlg.W.fkey           the same with F9 (no hot letter at all)
#     dlg.W.paint          PREFIX F3, F3 inside the paint dialog (a TDialog
#                          class whose HandleEvent, an override, draws the
#                          dialog on F3: drawView), SUFFIX Ctrl+F4
#     dlg.W.build-run-destroy  F4 + Ctrl+F4: the 8-control dialog end to end
#     dlg.W.type, .type-cyr, .type-cjk (kcl P3 3d, design §8.3's typing
#                          rows; the first input line the dialog's Current):
#                          PREFIX F2, typing a / b (ж / ы, 中 / 文: a UTF-8
#                          locale needed), SUFFIX Ctrl+F4 (the text is
#                          selected as the dialog opens: each Run's first key
#                          replaces it, FV's SelectAll on focus)
#     dlg.W.type-back      PREFIX F2, `a` and Backspace alternately
#     dlg.W.type-scrolled  PREFIX F2 End over a 70-character line (set before
#                          the Run), typing a / b
#     dlg.W.shift-left     the same line, Shift+Left (extending the selection)
#     dlg.W.history-open-close (kcl P3 3h) PREFIX F7 (TDlgApp runs the
#                          pre-built history dialog: an input line with its
#                          THistory, 10 strings in its list), Down on the
#                          line (the history window built and run modal),
#                          Esc (closed and destroyed), SUFFIX Ctrl+F4. Esc is
#                          sent in its CSI u form ESC [ 27 u: a bare ESC
#                          followed by the next key's ESC reads as Alt + that
#                          key
#     dlg.W.msgbox.e2e     (kcl P3 3e, design P3 §6 / §9.2) F8: TDlgApp calls
#                          fv.msgbox.messageBox (Error, OK; the 40 x 9 box
#                          built, run, closed by Ctrl+F4 and destroyed)
#     dlg.W.msgbox.standin F11: the design's stand-in (M3) of the same box —
#                          its dialog, text and OK button built by hand,
#                          execView, Ctrl+F4, destroyed — for comparison
#   paint.W.paint, paint.W.paint+init
#                          (views-paint-80, views-paint) the two-panel scene
#                          with a real list
#                          in each window, the inactive one's bar hidden (FV
#                          ShowSBar): F-1's P3 number (D31: 80x24, <= 15 ms on
#                          CI; p2.80x24.paint is the stand-ins' "today")
# CASE:
#   views-80, views-200  paint, paint+init, redraw, down, pgdn, tab, tab-in,
#                        click, move, grow, pgdn-cyr, pgdn-cjk (80x24 /
#                        200x50)
#   views-overlap-80     overlap.80x24.tab, .click, .move
#   views-resize         resize.80x24-200x50, resize.200x50-80x24
#   views-p2-80          p2.80x24.paint, p2.80x24.paint+init
#   views-list-80, views-list-200
#                        the list scene's actions (80x24 / 200x50); a kcl
#                        without TListViewer (before P3 3b): a note, no rows
#   views-dialog-80      dlg.80x24.open-close, .tab, .key, .fkey, .paint,
#                        .build-run-destroy, .type, .type-back,
#                        .type-scrolled, .shift-left, .type-cyr, .type-cjk,
#                        .history-open-close, .msgbox.standin, .msgbox.e2e;
#                        a kcl without fv.dialogs (before P3 3c): a note; a
#                        kcl without TInputLine (before 3d): no typing rows;
#                        without THistory (before 3h): no history row;
#                        without fv.msgbox (before 3e): no msgbox rows
#   views-paint-80       paint.80x24.paint, paint.80x24.paint+init
#   views-paint          paint.200x50.paint, paint.200x50.paint+init
# N (default 10) = actions per measurement. Before the timing every action runs
# once with the dispatch and write counters on (kklass's dispatchers and
# fv.video's writes wrapped in counting shims, as kcl/fv.views/tests'
# fvw_testlib.sh does) and its effect checked: `# calls ACTION N` and `#
# writes ACTION N` notes; an error output, a missing effect or a Run ended by
# the end of input stops the case (rc 3).
set -u
ROOT=${1:?usage: fvviewcases.sh ROOT CASE [N]}
CASE=${2:?usage: fvviewcases.sh ROOT CASE [N]}
N=${3:-10}

[[ -f $ROOT/kcl/fv.app/fv.app.sh ]] || { echo "fvviewcases.sh: no $ROOT/kcl/fv.app (before kcl fv P2)" >&2; exit 2; }
FV_COLORS=256
loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ -n $loc ]] && [[ -n $( { LC_ALL=$loc; } 2>&1 ) ]]; then
    echo "# the caller's locale '$loc' does not exist: measured with LANG=C"
    { unset LC_ALL LC_CTYPE; export LANG=C; } 2>/dev/null
fi
source "$ROOT/kbool.sh" || exit 2
kk.uses fv.app || exit 2

case $CASE in
    views-80|views-overlap-80|views-p2-80|views-list-80|views-paint-80|views-dialog-80) W=80 H=24 ;;
    views-200|views-list-200|views-paint) W=200 H=50 ;;
    views-resize) W=80 H=24 ;;
    *) echo "fvviewcases.sh: unknown case '$CASE'" >&2; exit 2 ;;
esac
if [[ $CASE == views-list-* || $CASE == views-paint* ]] && ! declare -F TListViewer.new >/dev/null; then
    echo "# note: no TListViewer in this kcl (before P3 3b): $CASE not measured"
    exit 0
fi
if [[ $CASE == views-dialog-* ]]; then
    if [[ ! -f $ROOT/kcl/fv.dialogs/fv.dialogs.sh ]]; then
        echo "# note: no fv.dialogs in this kcl (before P3 3c): $CASE not measured"
        exit 0
    fi
    kk.uses fv.dialogs || exit 2
    # (kcl P3 3e) fv.msgbox, when this kcl has it (the msgbox rows)
    if [[ -f $ROOT/kcl/fv.msgbox/fv.msgbox.sh ]]; then kk.uses fv.msgbox || exit 2; fi
fi

exec {OUTFD}>/dev/null
FV_VIDEO_OUT_FD=$OUTFD FV_APP_HEADLESS=1
KF=${TMPDIR:-/tmp}/fvviewcases.$$.keys
ERRF=${TMPDIR:-/tmp}/fvviewcases.$$.err
trap 'rm -f "$KF" "$ERRF"' EXIT

# ---- the classes ------------------------------------------------------------
class TMyApp : TApplication
    public
        override proc HandleEvent
end
TMyApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbCtrlL ]; then
        fv.views.redraw "$FV_APP"
        fv.views.clearEvent "$this"
    fi
}
build TMyApp

# (P3 3b) the list scene's application: TMyApp's Ctrl+L, and F12 / F11: the
# list w1l on a fresh page (fresh)
class TListApp : TApplication
    public
        override proc HandleEvent
end
TListApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbCtrlL ]; then fv.views.redraw "$FV_APP"; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF12 ] || [ "$FV_EV_KEY" = kbF11 ]; then fresh "$FV_EV_KEY"; fv.views.clearEvent "$this"; fi
    fi
}
build TListApp
# (P3 3c) the dialog scene's application: TMyApp's Ctrl+L, and F2 / F3 / F4
# (the header); the paint dialog draws itself on F3
if [[ $CASE == views-dialog-* ]]; then
class TDlgApp : TApplication
    public
        override proc HandleEvent
end
TDlgApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbCtrlL ]; then fv.views.redraw "$FV_APP"; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF2 ]; then fv.views.execView "$FV_DESKTOP" dlg; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF3 ]; then fv.views.execView "$FV_DESKTOP" pdlg; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF7 ]; then fv.views.execView "$FV_DESKTOP" hdlg; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF8 ]; then
            fv.msgbox.messageBox 'File not found: %s' $(( FV_MF_ERROR | FV_MF_OKBUTTON )) -- report.txt
            MBR=$RESULT
            fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF11 ]; then
            mkbox
            fv.views.execView "$FV_DESKTOP" sbox
            MBR=$RESULT
            sbox.delete
            fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF4 ]; then
            mkdlg dlg8 e TDialog
            fv.views.execView "$FV_DESKTOP" dlg8
            dlg8.delete
            fv.views.clearEvent "$this"
        fi
    fi
}
build TDlgApp
class TPaintDlg : TDialog
    public
        override proc HandleEvent
end
TPaintDlg.HandleEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbF3 ]; then fv.views.drawView "$this"; fv.views.clearEvent "$this"; return; fi
    inherited HandleEvent "$@"
}
build TPaintDlg
fi
# mkdlg NAME P CLASS -- the test dialog with its controls named P_in1,
# P_l1, ... (not inserted anywhere): the design's 8-control dialog (P3 §8):
# two input lines (MaxLen 255) with their labels, check boxes (3), OK
# (default), Cancel, Help (kcl P3 3d). A kcl without TInputLine (3c): 3c's
# stand-ins, a static text and radio buttons in the input lines' places
# (kcl fv.dialogs' tests: fvg_mkdlg)
mkdlg() {
    local p=${2}_ v
    "$3.new" "$1" 10 4 70 18 'Find'
    if declare -F TInputLine.new >/dev/null; then
        TInputLine.new "${p}in1" 15 1 57 2 255
        TLabel.new "${p}l1" 2 1 14 2 '~T~ext' "${p}in1"
        TCheckBoxes.new "${p}opts" 3 4 30 7 '~C~ase sensitive' '~W~hole words' 'Re~g~ex'
        TLabel.new "${p}l2" 32 3 46 4 '~R~eplace' "${p}in2"
        TInputLine.new "${p}in2" 32 4 57 5 255
        DLGV=(in1 l1 opts l2 in2 ok cn hp)
    else
        TStaticText.new "${p}st" 3 1 57 3 $'\x03''Search options'
        TLabel.new "${p}l1" 2 3 14 4 '~T~ext' "${p}opts"
        TCheckBoxes.new "${p}opts" 3 4 30 7 '~C~ase sensitive' '~W~hole words' 'Re~g~ex'
        TLabel.new "${p}l2" 32 3 46 4 '~D~irection' "${p}dir"
        TRadioButtons.new "${p}dir" 32 4 56 6 '~F~orward' '~B~ackward'
        DLGV=(st l1 opts l2 dir ok cn hp)
    fi
    TButton.new "${p}ok" 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    TButton.new "${p}cn" 26 10 38 12 'Cancel' cmCancel
    TButton.new "${p}hp" 40 10 50 12 '~H~elp' cmHelp
    for v in "${DLGV[@]}"; do fv.views.insert "$1" "$p$v"; done
    fv.views.select "${p}opts"
}
# mkbox -- the message box stand-in (design P3 §6, M3: the dialog, the text
# and the OK button of fv.msgbox.messageBox's Error / OK box, built by hand;
# not inserted anywhere)
mkbox() {
    local -n __b_dd=${FV_DESKTOP}_data
    local x=$(( (__b_dd[SizeX] - 40) / 2 )) y=$(( (__b_dd[SizeY] - 9) / 2 ))
    TDialog.new sbox "$x" "$y" $(( x + 40 )) $(( y + 9 )) 'Error'
    TStaticText.new sbox_t 3 2 38 6 'File not found: report.txt'
    TButton.new sbox_ok 15 6 25 8 'O~k~' cmOK
    fv.views.insert sbox sbox_t; fv.views.insert sbox sbox_ok
    fv.views.selectNext sbox 0
}
# fresh KEY -- w1l's TopItem 400 items further (FRESH_T; wrapping before the
# last 1000), the focus on that page's top row (kbF12) or bottom row (kbF11)
FRESH_T=0
fresh() {
    local -n __b_l=w1l_data
    local t=$(( (${__b_l[TopItem]:-0} + 400) % (${__b_l[Range]:-1001} - 1000) ))
    FRESH_T=$t
    if [ "$1" = kbF11 ]; then __b_l[Focused]=$(( t + ${__b_l[SizeY]:-1} - 1 )); else __b_l[Focused]=$t; fi
    fv.views.listSetTopItem w1l "$t"
    # (the check pass counts what follows the prefix only: the jump's own
    # draws differ from run to run, the bar's indicator moving or not)
    CALLS=0 WRITES=0
}
# listdata [ascii] -- the 60 000 names of each kind: LA, LC, LJ (header)
listdata() {
    LA=("file_report_"{0..59999}".txt   4096")
    [[ ${1-} == ascii ]] && return 0
    LC=("Отчёт_квартал_"{0..59999}".txt   4096")
    LJ=({报,告,文,件,数,据,项,目,系,统}{管,理,用,户,设,置,网,络,服,务}{图,像,音,乐,视,频,文,档,表,格}{演,示,代,码,测,试,结,果,版,本}_{0..5}.txt)
    LJ=("${LJ[@]/%/   4096}")
}
# lwin NAME AX AY BX BY TITLE NUM ARRAY -- a TWindow with a TListViewer over
# ARRAY on its interior and the standard vertical bar (FV's file panel)
lwin() {
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    fv.views.standardScrollBar "$1" "$FV_SB_VERTICAL"
    TListViewer.new "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 )) 1 '' "$RESULT"
    local -n __b_l=${1}l_data __b_a=$8
    __b_l[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY )) __b_l[List]=$8
    fv.views.listSetRange "${1}l" "${#__b_a[@]}"
    fv.views.insert "$1" "${1}l"
    fv.views.insert "$FV_DESKTOP" "$1"
}

declare -A TLA=()
class TTestList : TView
    public
        var Top
        var Focused
        override proc Draw
        override proc HandleEvent
end
TTestList.Draw() { tlpaint "$this" "${Top:-0}" "${Focused:-0}"; }
TTestList.HandleEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbDown ]; then
            local o=${Focused:-0} n
            n=$(( (o + 1) % SizeY ))
            Focused=$n
            fv.views.drawPart "$this" tlpaint "$o" "$(( o + 1 ))" "${Top:-0}" "$n"
            fv.views.drawPart "$this" tlpaint "$n" "$(( n + 1 ))" "${Top:-0}" "$n"
            fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbPgDn ]; then
            Top=$(( ${Top:-0} + SizeY ))
            fv.views.drawView "$this"
            fv.views.clearEvent "$this"
        fi
    elif [ "$FV_EV_WHAT" = evMouseDown ]; then
        inherited HandleEvent "$@"
    fi
}
build TTestList
# tlpaint V TOP FOCUSED -- rows FV_CLIP_Y1..Y2-1 in one writeLines call (a single
# row, kbDown's drawPart, with writeLine as a list's FocusItem repaint) (element
# y = row y; one fv.video write per list); where the kcl has no writeLines
# (before D21 stage E) the old stand-in, one writeLine (writeBuf) per row
tlpaint() {
    local -n __b_d=${1}_data
    local y s a n=${FV_DRAW_PAL:5:1} f=${FV_DRAW_PAL:6:1} w=${__b_d[SizeX]:-0}
    local -a tt=() aa=()
    [[ -n $n ]] || n=${FV_DRAW_PAL:0:1}
    [[ -n $f ]] || f=$n
    if [[ -z ${TLA[$n$w]-} ]]; then printf -v a '%*s' "$w" ''; TLA[$n$w]=${a// /$n}; fi
    if [[ -z ${TLA[$f$w]-} ]]; then printf -v a '%*s' "$w" ''; TLA[$f$w]=${a// /$f}; fi
    if (( FV_CLIP_Y2 - FV_CLIP_Y1 == 1 )); then
        # (one row, e.g. kbDown's drawPart: writeLine, as a list's FocusItem
        # repaint does; writeLines pays ~50 us more for a single row)
        y=$FV_CLIP_Y1
        printf -v s '%-*s' "$w" " item $(( $2 + y ))"
        if (( y == $3 )); then a=${TLA[$f$w]}; else a=${TLA[$n$w]}; fi
        fv.views.writeLine 0 "$y" 1 "${s:0:w}" "$a"
        return
    fi
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        printf -v s '%-*s' "$w" " item $(( $2 + y ))"
        tt[y]=${s:0:w}
        if (( y == $3 )); then aa[y]=${TLA[$f$w]}; else aa[y]=${TLA[$n$w]}; fi
    done
    fv.views.writeLines 0 0 tt aa
}
if ! declare -F fv.views.writeLines >/dev/null; then
tlpaint() {
    local -n __b_d=${1}_data
    local y s a n=${FV_DRAW_PAL:5:1} f=${FV_DRAW_PAL:6:1} w=${__b_d[SizeX]:-0}
    [[ -n $n ]] || n=${FV_DRAW_PAL:0:1}
    [[ -n $f ]] || f=$n
    if [[ -z ${TLA[$n$w]-} ]]; then printf -v a '%*s' "$w" ''; TLA[$n$w]=${a// /$n}; fi
    if [[ -z ${TLA[$f$w]-} ]]; then printf -v a '%*s' "$w" ''; TLA[$f$w]=${a// /$f}; fi
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        printf -v s '%-*s' "$w" " item $(( $2 + y ))"
        if (( y == $3 )); then a=${TLA[$f$w]}; else a=${TLA[$n$w]}; fi
        fv.views.writeLine 0 "$y" 1 "${s:0:w}" "$a"
    done
}
fi
# tlpaintk V TOP FOCUSED -- tlpaint with non-ASCII names (TLKIND cyr / cjk: the
# pgdn-cyr / pgdn-cjk actions, which put it in tlpaint's place): row I is
# `Отчёт_квартал_I.txt   SIZE` or 4 CJK characters + `_I.txt   SIZE`, padded
# with blanks to the row's W cells (a CJK character takes 2; padded by
# characters, not by printf, which pads by bytes in some bashes)
TLKIND=cyr
TLCJ='报告文件数据项目系统管理用户设置网络服务图像音乐视频文档表格演示代码测试结果版本历史记录备份恢复安全权限日志配置'
printf -v TLB '%*s' 1100 ''
# (fv.video's UTF-8 locale, found at its load; '' = none on this host: the two
# actions are left out with a note)
TLLOC=${__FV_VS_LOC:-}
tlpaintk() {
    local -n __b_d=${1}_data
    local y a n=${FV_DRAW_PAL:5:1} f=${FV_DRAW_PAL:6:1} w=${__b_d[SizeX]:-0}
    local -a tt=() aa=()
    [[ -n $n ]] || n=${FV_DRAW_PAL:0:1}
    [[ -n $f ]] || f=$n
    if [[ -z ${TLA[$n$w]-} ]]; then printf -v a '%*s' "$w" ''; TLA[$n$w]=${a// /$n}; fi
    if [[ -z ${TLA[$f$w]-} ]]; then printf -v a '%*s' "$w" ''; TLA[$f$w]=${a// /$f}; fi
    tlrowsk "$2" "$3"
    # (a refused row would time the refusal: the check pass reports it)
    if (( FV_CLIP_Y2 - FV_CLIP_Y1 == 1 )) || ! declare -F fv.views.writeLines >/dev/null; then
        for y in "${!tt[@]}"; do fv.views.writeLine 0 "$y" 1 "${tt[y]}" "${aa[y]}" || FAIL+=" [tlpaintk: writeLine rc $?]"; done
        return
    fi
    fv.views.writeLines 0 0 tt aa || FAIL+=" [tlpaintk: writeLines rc $?]"
}
# tlrowsk TOP FOCUSED -- tlpaintk's rows (its tt, aa, w, n, f), built in a
# UTF-8 locale whatever the caller's (characters, not bytes; critic 3a-1 M2:
# a C locale built broken rows that writeLines refused); in ASCII mode a CJK
# character is one cell, as fv.video counts it there
tlrowsk() {
    local LC_ALL=$TLLOC
    # (a separate local: in one, ${#TLCJ} is taken before the locale switch)
    local s i c k l=${#TLCJ}
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        i=$(( $1 + y ))
        if [[ $TLKIND == cjk ]]; then
            c=${TLCJ:i % l:1}${TLCJ:i * 7 % l:1}${TLCJ:i * 13 % l:1}${TLCJ:i * 29 % l:1}
            s=" ${c}_$i.txt   $(( i * 37 % 100000 ))" k=$(( w - 4 ))
            if (( ${FV_VIDEO_ASCII:-0} )); then k=$w; fi
        else
            s=" Отчёт_квартал_$i.txt   $(( i * 37 % 100000 ))" k=$w
        fi
        if (( ${#s} < k )); then s+=${TLB:0:k-${#s}}; else s=${s:0:k}; fi
        tt[y]=$s
        if (( y == $2 )); then aa[y]=${TLA[$f$w]}; else aa[y]=${TLA[$n$w]}; fi
    done
}
TLP0=$(declare -f tlpaint)
# tlkind ascii|cyr|cjk -- the stand-in's names from now on
tlkind() {
    if [[ $1 == ascii ]]; then eval "$TLP0"; return; fi
    TLKIND=$1
    tlpaint() { tlpaintk "$@"; }
}

# win NAME AX AY BX BY TITLE NUM [LEAFCLASS] -- a TWindow with a selectable
# leaf (default TTestList) over its interior, following it on a resize
win() {
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    "${8:-TTestList}.new" "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 ))
    local -n __b_l=${1}l_data
    __b_l[Options]=$(( __b_l[Options] | FV_OF_SELECTABLE ))
    __b_l[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    fv.views.insert "$1" "${1}l"
    fv.views.insert "$FV_DESKTOP" "$1"
}
# scene side|overlap|p2 -- the application at W x H (not drawn yet)
scene() {
    FV_SCREEN_W=$W FV_SCREEN_H=$H
    local cls=TMyApp
    if [ "$1" = list ]; then cls=TListApp; fi
    if [ "$1" = dialog ]; then cls=TDlgApp; fi
    "$cls.new" app || exit 2
    local hw=$(( W / 2 )) wh=$(( H - 1 ))
    case $1 in
        side|dialog) win w1 0 0 "$hw" "$wh" 'Files' 1; win w2 "$hw" 0 "$W" "$wh" 'Panel two' 2 ;;
        overlap) win w1 0 0 "$hw" "$wh" 'Files' 1; win w2 $(( W / 4 )) 0 $(( W / 4 + hw )) "$wh" 'Panel two' 2 ;;
        p2)      win w1 2 1 40 20 'Files' 1 TView; win w2 30 5 70 22 'Panel two' 2 TView ;;
        # (P3 3b) the stand-in window, then the list window in front of it
        list)    win w2 "$hw" 0 "$W" "$wh" 'Panel two' 2; lwin w1 0 0 "$hw" "$wh" 'Files' 1 LA ;;
        lists)   lwin w1 0 0 "$hw" "$wh" 'Files' 1 LA; lwin w2 "$hw" 0 "$W" "$wh" 'Panel two' 2 LA ;;
    esac
}

# ---- the counters (kcl/fv.views/tests/fvw_testlib.sh's shims) ---------------
CALLS=0 WRITES=0
DISPATCHERS=(kk._exec kk._call kk._parent kk._constructor_exec)
WRITERS=(fv.video.writeStr fv.video.writeBuf fv.video.writeCStr fv.video.writeChar fv.video.fillRect fv.video.shadeRect fv.video.fillColumns fv.video._shadef fv.video._wstr fv.video._fcf fv.video._wbf fv.video._wrows fv.video._wrowsu)
wrap() {
    local c=$1 f src
    shift
    for f; do
        declare -F "$f" >/dev/null || continue
        declare -F "__bw_$f" >/dev/null && continue
        src=$(declare -f "$f")
        eval "__bw_${src}"
        eval "$f() { $c=\$(( $c + 1 )); __bw_$f \"\$@\"; }"
    done
}
unwrap() {
    local f src
    for f; do
        declare -F "__bw_$f" >/dev/null || continue
        src=$(declare -f "__bw_$f")
        eval "${src#__bw_}"
        unset -f "__bw_$f"
    done
}

# ---- the runs ------------------------------------------------------------------
# run BYTES -- one app.Run over BYTES + Alt-X; T = its microseconds
run() {
    printf '%s\033x' "$1" > "$KF"
    exec {KFD}<"$KF"
    FV_KEY_FD=$KFD
    fv.keyboard.flush
    local t0 t1
    t0=$EPOCHREALTIME
    app.Run
    t1=$EPOCHREALTIME
    exec {KFD}<&-
    T=$(( ${t1/[.,]/} - ${t0/[.,]/} ))
}
# unshow -- the application as before its first paint, on a fresh buffer
# (fv.app private state: see the header)
unshow() {
    fv.views._virt app InitScreen
    __FV_AP_SHOWN=0
    app_data[State]=$(( app_data[State] & ~FV_SF_EXPOSED ))
}
# cold -- fv.video's per-process caches emptied (fvcases.sh's cold)
cold() {
    if declare -p __FV_VS_CC >/dev/null 2>&1; then __FV_VS_CC=(); fi
    if declare -p __FV_VS_N16 >/dev/null 2>&1; then __FV_VS_N16=(); fi
    if declare -p __FV_VS_CPAL >/dev/null 2>&1; then __FV_VS_CPAL='' __FV_VS_CSG16='' __FV_VS_CSG256=''; fi
}
# keys UNIT1 UNIT2 COUNT -> KEYS = COUNT units, UNIT1 and UNIT2 alternately
keys() {
    local i
    KEYS=''
    for (( i = 0; i < $3; i++ )); do
        if (( i % 2 )); then KEYS+=$2; else KEYS+=$1; fi
    done
}
# sgr X Y -> REPLY = a left press + release at the cell X Y (0-based)
sgr() { REPLY=$'\e[<0;'"$(( $1 + 1 ));$(( $2 + 1 ))M"$'\e[<0;'"$(( $1 + 1 ));$(( $2 + 1 ))m"; }

FAIL=''
# checked TEXT CONDITION... -- the check pass: CONDITION false -> FAIL
checked() {
    local t=$1
    shift
    "$@" || FAIL+=" [$t]"
    (( ! __FV_VW_EOF )) || FAIL+=" [$t: the Run ended at the end of input: a key was not read as meant]"
}
# count LABEL PREFIX UNIT1 UNIT2 SUFFIX CHECK... -- the untimed pass of one
# action: the counts of PREFIX + UNIT1 + SUFFIX minus PREFIX + SUFFIX, then
# CHECK
count() {
    local label=$1 p=$2 u=$3 s=$5 c0 w0
    shift 5
    wrap CALLS "${DISPATCHERS[@]}"; wrap WRITES "${WRITERS[@]}"
    CALLS=0 WRITES=0; run "$p$s"; c0=$CALLS w0=$WRITES
    CALLS=0 WRITES=0; run "$p$u$s"
    unwrap "${DISPATCHERS[@]}" "${WRITERS[@]}"
    echo "# calls $label $(( CALLS - c0 ))"
    echo "# writes $label $(( WRITES - w0 ))"
    checked "$label" "$@"
}
# timed LABEL PREFIX UNIT1 UNIT2 SUFFIX -- the measurement (see the header)
timed() {
    local label=$1 p=$2 s=$5 b t i d=0
    keys "$3" "$4" "$N"
    # (the base: the least of 3 Runs without the units)
    for (( i = 0; i < 3; i++ )); do run "$p$s"; if (( i == 0 || T < b )); then b=$T; fi; done
    run "$p$KEYS$s"; t=$T
    d=$(( (t - b) * 10 / N ))
    (( d > 0 )) || d=0
    printf '%s %d.%d\n' "$label" $(( d / 10 )) $(( d % 10 ))
}
# paints LABEL -- W.paint and W.paint+init (N Runs each, minus the base Run)
paints() {
    local label=$1 i b=0 d t0 t1
    for (( i = 0; i < 3; i++ )); do run ''; if (( i == 0 || T < b )); then b=$T; fi; done
    d=0
    for (( i = 0; i < N; i++ )); do unshow; run ''; d=$(( d + T - b )); done
    d=$(( d * 10 / N ))
    printf '%s.paint %d.%d\n' "$label" $(( d / 10 )) $(( d % 10 ))
    d=0
    for (( i = 0; i < N; i++ )); do
        unshow; cold
        t0=$EPOCHREALTIME; fv.views._virt app InitScreen; t1=$EPOCHREALTIME
        __FV_AP_SHOWN=0 app_data[State]=$(( app_data[State] & ~FV_SF_EXPOSED ))
        run ''
        d=$(( d + ${t1/[.,]/} - ${t0/[.,]/} + T - b ))
    done
    d=$(( d * 10 / N ))
    printf '%s.paint+init %d.%d\n' "$label" $(( d / 10 )) $(( d % 10 ))
}
# paintcount LABEL -- the counts of a first paint
paintcount() {
    local c0 w0
    wrap CALLS "${DISPATCHERS[@]}"; wrap WRITES "${WRITERS[@]}"
    CALLS=0 WRITES=0; run ''; c0=$CALLS w0=$WRITES
    unshow
    CALLS=0 WRITES=0; run ''
    unwrap "${DISPATCHERS[@]}" "${WRITERS[@]}"
    echo "# calls $1.paint $(( CALLS - c0 ))"
    echo "# writes $1.paint $(( WRITES - w0 ))"
    checked "$1.paint" test "$__FV_AP_SHOWN" = 1
}

# the effects the check pass looks for
cur() { [ "${app__fvdesktop_data[Current]}" = "$1" ]; }
focused() { [ "${w2l_data[Focused]}" = "$1" ]; }
top() { [ "${w2l_data[Top]}" = "$1" ]; }
cur2() { ! [ "${w2_data[Current]}" = "$1" ]; }
bounds() { fv.views.getBounds "$1"; [ "$RESULT" = "$2" ]; }
yes() { :; }
# (P3 3b) lst F T: w1l's Focused / TopItem = FRESH_T + F / + T; lend: End reached
lst() { [ "${w1l_data[Focused]}" = "$(( FRESH_T + $1 ))" ] && [ "${w1l_data[TopItem]}" = "$(( FRESH_T + $2 ))" ]; }
lend() { [ "${w1l_data[Focused]}" = "$(( ${w1l_data[Range]} - 1 ))" ]; }
# lkind ascii|cyr|cjk: w1l's names from now on (the list redrawn)
lkind() {
    case $1 in ascii) w1l_data[List]=LA ;; cyr) w1l_data[List]=LC ;; cjk) w1l_data[List]=LJ ;; esac
    fv.views.drawView w1l
}
# listacts LABEL KIND -- the counts, then the times, of one kind's actions
listacts() {
    local l=$1 k=$2 r=$(( H - 3 ))
    count "$l.list.down.$k" "$K_F12" "$K_DOWN" '' '' lst 1 0
    count "$l.list.down-edge.$k" "$K_F11" "$K_DOWN" '' '' lst "$r" 1
    count "$l.list.pgdn.$k" "$K_F11" "$K_PGDN" '' '' lst $(( 2 * r - 1 )) "$r"
    count "$l.list.wheel.$k" "$K_F12" "$LWHEEL" '' '' lst 0 1
    count "$l.list.click.$k" "$K_F12" "$LC1" '' '' lst 3 0
    count "$l.list.end-home.$k" '' "$K_END" '' '' lend
    if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
    timed "$l.list.down.$k" "$K_F12" "$K_DOWN" "$K_DOWN" ''
    timed "$l.list.down-edge.$k" "$K_F11" "$K_DOWN" "$K_DOWN" ''
    timed "$l.list.pgdn.$k" "$K_F11" "$K_PGDN" "$K_PGDN" ''
    timed "$l.list.wheel.$k" "$K_F12" "$LWHEEL" "$LWHEEL" ''
    timed "$l.list.click.$k" "$K_F12" "$LC1" "$LC2" ''
    timed "$l.list.end-home.$k" '' "$K_END" "$K_HOME" ''
}

K_DOWN=$'\e[B' K_PGDN=$'\e[6~' K_F6=$'\e[17~' K_TAB=$'\t' K_CTRLL=$'\x0c'
K_RESIZE=$'\e[15;5~' K_RIGHT=$'\e[C' K_LEFT=$'\e[D' K_SRIGHT=$'\e[1;2C' K_SLEFT=$'\e[1;2D' K_ENTER=$'\r'
K_F12=$'\e[24~' K_F11=$'\e[23~' K_END=$'\e[F' K_HOME=$'\e[H'

exec 3>&2 2>"$ERRF"
case $CASE in
    views-80|views-200)
        L=${W}x$H
        scene side
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys: the initial cmCommandSetChanged)
        paintcount "$L"
        count "$L.redraw" '' "$K_CTRLL" '' '' yes
        count "$L.down" '' "$K_DOWN" '' '' focused 1
        count "$L.pgdn" '' "$K_PGDN" '' '' top $(( H - 3 ))
        count "$L.tab" '' "$K_F6" '' '' cur w1
        run "$K_F6"
        TTestList.new w2b 1 $(( H - 3 )) $(( W / 2 - 1 )) $(( H - 2 ))
        w2b_data[Options]=$(( w2b_data[Options] | FV_OF_SELECTABLE ))
        fv.views.insert w2 w2b
        c0=${w2_data[Current]}
        count "$L.tab-in" "" "$K_TAB" "" "" cur2 "$c0"
        hw=$(( W / 2 )) y=$(( H / 2 ))
        sgr 5 "$y"; c1=$REPLY; sgr $(( hw + 5 )) "$y"; c2=$REPLY
        count "$L.click" '' "$c1" '' '' cur w1
        run "$c2"
        count "$L.move" "$K_RESIZE" "$K_RIGHT" '' "$K_ENTER" bounds w2 "$(( hw + 1 )) 0 $(( W + 1 )) $(( H - 1 ))"
        run "$K_RESIZE$K_LEFT$K_ENTER"
        count "$L.grow" "$K_RESIZE" "$K_SRIGHT" '' "$K_ENTER" bounds w2 "$hw 0 $(( W + 1 )) $(( H - 1 ))"
        run "$K_RESIZE$K_SLEFT$K_ENTER"
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        fv.views.delete w2 w2b; w2b.delete
        paints "$L"
        timed "$L.redraw" '' "$K_CTRLL" "$K_CTRLL" ''
        timed "$L.down" '' "$K_DOWN" "$K_DOWN" ''
        timed "$L.pgdn" '' "$K_PGDN" "$K_PGDN" ''
        timed "$L.tab" '' "$K_F6" "$K_F6" ''
        TTestList.new w2b 1 $(( H - 3 )) $(( W / 2 - 1 )) $(( H - 2 ))
        w2b_data[Options]=$(( w2b_data[Options] | FV_OF_SELECTABLE ))
        fv.views.insert w2 w2b
        timed "$L.tab-in" '' "$K_TAB" "$K_TAB" ''
        fv.views.delete w2 w2b; w2b.delete
        timed "$L.click" '' "$c1" "$c2" ''
        timed "$L.move" "$K_RESIZE" "$K_RIGHT" "$K_LEFT" "$K_ENTER"
        timed "$L.grow" "$K_RESIZE" "$K_SRIGHT" "$K_SLEFT" "$K_ENTER"
        # (the fresh non-ASCII pages, last, counts and times: every other
        # action ran exactly as before these two existed; the stand-in's names
        # change for these two only, in the scene of W.pgdn: the second window
        # current, no w2b; its rows go on past every row shown before)
        if [[ -n $TLLOC ]]; then
            run "$c2"; app.Idle
            tlkind cyr
            count "$L.pgdn-cyr" '' "$K_PGDN" '' '' top $(( ${w2l_data[Top]:-0} + H - 3 ))
            tlkind cjk
            count "$L.pgdn-cjk" '' "$K_PGDN" '' '' top $(( ${w2l_data[Top]:-0} + H - 3 ))
            tlkind ascii
            if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
            tlkind cyr
            timed "$L.pgdn-cyr" '' "$K_PGDN" "$K_PGDN" ''
            tlkind cjk
            timed "$L.pgdn-cjk" '' "$K_PGDN" "$K_PGDN" ''
            tlkind ascii
            if [[ -n $FAIL ]]; then echo "fvviewcases.sh: $CASE: the timed pgdn-cyr / pgdn-cjk failed:$FAIL" >&3; exit 3; fi
        else
            echo "# note: no UTF-8 locale on this host: $L.pgdn-cyr and $L.pgdn-cjk not measured"
        fi
        ;;
    views-overlap-80)
        L=overlap.${W}x$H
        scene overlap
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys: the initial cmCommandSetChanged)
        count "$L.tab" '' "$K_F6" '' '' cur w1
        run "$K_F6"
        y=$(( H / 2 ))
        sgr 5 "$y"; c1=$REPLY; sgr $(( W * 3 / 4 - 5 )) "$y"; c2=$REPLY
        count "$L.click" '' "$c1" '' '' cur w1
        run "$c2"
        q=$(( W / 4 ))
        count "$L.move" "$K_RESIZE" "$K_RIGHT" '' "$K_ENTER" bounds w2 "$(( q + 1 )) 0 $(( q + W / 2 + 1 )) $(( H - 1 ))"
        run "$K_RESIZE$K_LEFT$K_ENTER"
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        timed "$L.tab" '' "$K_F6" "$K_F6" ''
        timed "$L.click" '' "$c1" "$c2" ''
        timed "$L.move" "$K_RESIZE" "$K_RIGHT" "$K_LEFT" "$K_ENTER"
        ;;
    views-p2-80)
        L=p2.${W}x$H
        scene p2
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys: the initial cmCommandSetChanged)
        paintcount "$L"
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        paints "$L"
        ;;
    views-list-80|views-list-200)
        L=${W}x$H
        listdata
        scene list
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys)
        # (the list's rows 3 and 8 are screen rows 4 and 9; the wheel report
        # over the list's middle)
        sgr 5 4; LC1=$REPLY; sgr 5 9; LC2=$REPLY
        LWHEEL=$'\e[<65;6;'"$(( H / 2 + 1 ))M"
        listacts "$L" ascii
        # (every other item marked: Marks read inline, design §5)
        MKS=(); for (( i = 0; i < 60000; i += 2 )); do MKS[i]=1; done
        w1l_data[Marks]=MKS
        count "$L.list.pgdn-marks" "$K_F11" "$K_PGDN" '' '' lst $(( 2 * (H - 3) - 1 )) $(( H - 3 ))
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        timed "$L.list.pgdn-marks" "$K_F11" "$K_PGDN" "$K_PGDN" ''
        w1l_data[Marks]=''
        if [[ -n $TLLOC ]]; then
            lkind cyr; listacts "$L" cyr
            lkind cjk; listacts "$L" cjk
            lkind ascii
        else
            echo "# note: no UTF-8 locale on this host: the cyr and cjk list actions and standin.pgdn-cjk not measured"
        fi
        # (the stand-in beside the list, in this process: F6 makes w2 current)
        run "$K_F6"; app.Idle
        count "$L.standin.down" '' "$K_DOWN" '' '' cur w2
        count "$L.standin.pgdn" '' "$K_PGDN" '' '' cur w2
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        timed "$L.standin.down" '' "$K_DOWN" "$K_DOWN" ''
        timed "$L.standin.pgdn" '' "$K_PGDN" "$K_PGDN" ''
        # (kcl P3 3v: the stand-in's PgDn while the list beside it shows CJK
        # names -- its rows share the screen rows with wide cells)
        if [[ -n $TLLOC ]]; then
            lkind cjk
            count "$L.standin.pgdn-cjk" '' "$K_PGDN" '' '' cur w2
            if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
            timed "$L.standin.pgdn-cjk" '' "$K_PGDN" "$K_PGDN" ''
            lkind ascii
        fi
        ;;
    views-dialog-80)
        L=dlg.${W}x$H
        scene dialog
        mkdlg dlg d TDialog
        mkdlg pdlg p TPaintDlg
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys)
        K_F2=$'\e[12~' K_F3=$'\e[13~' K_F4=$'\e[14~' K_CF4=$'\e[1;5S' K_F9=$'\e[20~'
        # (the checks: the dialog closed again and out of the desktop; Tab moved
        # the focus from opts; a key nobody takes left the focus and the check
        # boxes as they were; the 8-control dialog and its controls gone)
        closed() { [[ -z ${dlg_data[Owner]-} && -z ${pdlg_data[Owner]-} ]]; }
        moved() { ! [ "${dlg_data[Current]}" = d_opts ] && closed; }
        stay() { [ "${dlg_data[Current]}" = d_opts ] && [ "${d_opts_data[Value]}" = 0 ] && closed; }
        gone() { ! fv.views.isView dlg8 && ! fv.views.isView e_ok && closed; }
        count "$L.open-close" '' "$K_F2$K_CF4" '' '' closed
        fv.views.select d_opts
        count "$L.tab" "$K_F2" "$K_TAB" '' "$K_CF4" moved
        fv.views.select d_opts
        count "$L.key" "$K_F2" x '' "$K_CF4" stay
        count "$L.fkey" "$K_F2" "$K_F9" '' "$K_CF4" stay
        count "$L.paint" "$K_F3" "$K_F3" '' "$K_CF4" closed
        count "$L.build-run-destroy" '' "$K_F4$K_CF4" '' '' gone
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        timed "$L.open-close" '' "$K_F2$K_CF4" "$K_F2$K_CF4" ''
        timed "$L.tab" "$K_F2" "$K_TAB" "$K_TAB" "$K_CF4"
        fv.views.select d_opts
        timed "$L.key" "$K_F2" x x "$K_CF4"
        timed "$L.fkey" "$K_F2" "$K_F9" "$K_F9" "$K_CF4"
        timed "$L.paint" "$K_F3" "$K_F3" "$K_F3" "$K_CF4"
        timed "$L.build-run-destroy" '' "$K_F4$K_CF4" "$K_F4$K_CF4" ''
        # (kcl P3 3d) typing into the dialog's first input line (made the
        # dialog's Current: its text is selected as the dialog opens, FV's
        # SelectAll on focus, so each Run's first key replaces it); the
        # scrolled cases start each Run on a 70-character line, End first
        if ! declare -F TInputLine.new >/dev/null; then
            echo "# note: no TInputLine in this kcl (before P3 3d): the dlg typing actions not measured"
        else
            K_END=$'\e[F' K_BS=$'\x7f' K_SLEFT=$'\e[1;2D'
            printf -v LONG70 '%70s' ''
            LONG70=${LONG70// /w}
            typed() { fv.dialogs.getText d_in1; [[ -n $RESULT && $RESULT != w* ]] && [ "${dlg_data[Current]}" = d_in1 ] && closed; }
            long() { fv.dialogs.getText d_in1; (( ${#RESULT} >= 70 )) && closed; }
            fv.views.select d_in1
            count "$L.type" "$K_F2" a '' "$K_CF4" typed
            count "$L.type-back" "${K_F2}a" "$K_BS" '' "$K_CF4" closed
            fv.dialogs.setText d_in1 "$LONG70"
            count "$L.type-scrolled" "$K_F2$K_END" a '' "$K_CF4" long
            fv.dialogs.setText d_in1 "$LONG70"
            count "$L.shift-left" "$K_F2$K_END" "$K_SLEFT" '' "$K_CF4" long
            if [[ -n $TLLOC ]]; then
                count "$L.type-cyr" "$K_F2" 'ж' '' "$K_CF4" typed
                count "$L.type-cjk" "$K_F2" '中' '' "$K_CF4" typed
            fi
            if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
            timed "$L.type" "$K_F2" a b "$K_CF4"
            timed "$L.type-back" "$K_F2" a "$K_BS" "$K_CF4"
            fv.dialogs.setText d_in1 "$LONG70"
            timed "$L.type-scrolled" "$K_F2$K_END" a b "$K_CF4"
            fv.dialogs.setText d_in1 "$LONG70"
            timed "$L.shift-left" "$K_F2$K_END" "$K_SLEFT" "$K_SLEFT" "$K_CF4"
            if [[ -n $TLLOC ]]; then
                timed "$L.type-cyr" "$K_F2" 'ж' 'ы' "$K_CF4"
                timed "$L.type-cjk" "$K_F2" '中' '文' "$K_CF4"
            else
                echo "# note: no UTF-8 locale on this host: dlg.type-cyr / type-cjk not measured"
            fi
        fi
        # (kcl P3 3h) the history window: Down on the history dialog's line,
        # Esc (CSI u: see the header); the check: the window gone (no view of
        # it left), the line's text and the list as they were, the dialog closed
        if ! declare -F THistory.new >/dev/null; then
            echo "# note: no THistory in this kcl (before P3 3h): dlg.history-open-close not measured"
        else
            K_F7=$'\e[18~' K_ESCU=$'\e[27u'
            TDialog.new hdlg 10 4 70 18 'History'
            TInputLine.new h_in 3 2 40 3 255
            THistory.new h_hi 40 2 43 3 h_in 1
            TButton.new h_ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
            for v in h_in h_hi h_ok; do fv.views.insert hdlg "$v"; done
            fv.views.select h_in
            for (( i = 1; i <= 10; i++ )); do fv.histlist.historyAdd 1 "search text $i"; done
            fv.dialogs.setText h_in 'search text 10'
            hclosed() {
                fv.dialogs.getText h_in
                [ "$RESULT" = 'search text 10' ] && ! fv.views.isView h_hi__fvhw1 && [[ -z ${hdlg_data[Owner]-} ]] \
                    && fv.histlist.historyCount 1 && [ "$RESULT" = 10 ]
            }
            count "$L.history-open-close" "$K_F7" "$K_DOWN$K_ESCU" '' "$K_CF4" hclosed
            if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
            timed "$L.history-open-close" "$K_F7" "$K_DOWN$K_ESCU" "$K_DOWN$K_ESCU" "$K_CF4"
        fi
        # (kcl P3 3e) the message box end to end: F8 = a real
        # fv.msgbox.messageBox (Error, OK; built, run, closed by Ctrl+F4,
        # destroyed), F11 = the design's stand-in (M3: the same dialog, text
        # and OK built by hand, execView, destroyed); the check: the answer
        # cmCancel, no box left, the test dialogs closed
        if ! declare -F fv.msgbox.messageBox >/dev/null; then
            echo "# note: no fv.msgbox in this kcl (before P3 3e): dlg.msgbox.e2e / msgbox.standin not measured"
        else
            K_F8=$'\e[19~'
            MBR=''
            mbgone() {
                [ "$MBR" = cmCancel ] && ! fv.views.isView "${FV_DESKTOP}__fvmsgbox" && ! fv.views.isView sbox && closed
            }
            count "$L.msgbox.standin" '' "$K_F11$K_CF4" '' '' mbgone
            count "$L.msgbox.e2e" '' "$K_F8$K_CF4" '' '' mbgone
            if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
            timed "$L.msgbox.standin" '' "$K_F11$K_CF4" "$K_F11$K_CF4" ''
            timed "$L.msgbox.e2e" '' "$K_F8$K_CF4" "$K_F8$K_CF4" ''
        fi
        ;;
    views-paint|views-paint-80)
        L=paint.${W}x$H
        listdata ascii
        scene lists
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys)
        paintcount "$L"
        checked "$L.paint: one bar shown" test "$(( w1__fvsb1_data[State] & FV_SF_VISIBLE )):$(( w2__fvsb1_data[State] & FV_SF_VISIBLE ))" = "0:$FV_SF_VISIBLE"
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        paints "$L"
        ;;
    views-resize)
        scene side
        run ''; app.Idle   # (the first paint; the Idle a terminal gives between keys: the initial cmCommandSetChanged)
        SIZE='24 80'
        fv.video.querySize() { RESULT=$SIZE; }
        # resize W H -> T = one Run over the resize + Alt-X
        resize() { SIZE="$2 $1"; FV_VIDEO_RESIZED=1; run ''; }
        wrap CALLS "${DISPATCHERS[@]}"; wrap WRITES "${WRITERS[@]}"
        CALLS=0 WRITES=0; run ''; c0=$CALLS w0=$WRITES
        CALLS=0 WRITES=0; resize 200 50; c1=$(( CALLS - c0 )) w1=$(( WRITES - w0 ))
        checked resize bounds app '0 0 200 50'
        CALLS=0 WRITES=0; resize 80 24; c2=$(( CALLS - c0 )) w2=$(( WRITES - w0 ))
        checked resize bounds app '0 0 80 24'
        unwrap "${DISPATCHERS[@]}" "${WRITERS[@]}"
        if [[ -n $FAIL ]] || [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: the check failed:$FAIL $(head -c 600 "$ERRF")" >&3; exit 3; fi
        echo "# calls resize.80x24-200x50 $c1"; echo "# writes resize.80x24-200x50 $w1"
        echo "# calls resize.200x50-80x24 $c2"; echo "# writes resize.200x50-80x24 $w2"
        b=0
        for (( i = 0; i < 3; i++ )); do run ''; if (( i == 0 || T < b )); then b=$T; fi; done
        up=0 dn=0
        for (( i = 0; i < N; i++ )); do
            resize 200 50; up=$(( up + T - b ))
            resize 80 24; dn=$(( dn + T - b ))
        done
        up=$(( up * 10 / N )) dn=$(( dn * 10 / N ))
        printf 'resize.80x24-200x50 %d.%d\n' $(( up / 10 )) $(( up % 10 ))
        printf 'resize.200x50-80x24 %d.%d\n' $(( dn / 10 )) $(( dn % 10 ))
        ;;
esac
if [[ -s $ERRF ]]; then echo "fvviewcases.sh: $CASE: error output during the timing: $(head -c 600 "$ERRF")" >&3; exit 3; fi
exit 0
