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
# TView with TView's default EventMask: Draw = one writeBuf per visible row;
# kbDown = two drawParts, the old and the new focused row; kbPgDn = a new
# page and drawView), the status line (FV's StdStatusKeys). The overlap scene
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
# CASE:
#   views-80, views-200  paint, paint+init, redraw, down, pgdn, tab, tab-in,
#                        click, move, grow (80x24 / 200x50)
#   views-overlap-80     overlap.80x24.tab, .click, .move
#   views-resize         resize.80x24-200x50, resize.200x50-80x24
#   views-p2-80          p2.80x24.paint, p2.80x24.paint+init
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
    views-80|views-overlap-80|views-p2-80) W=80 H=24 ;;
    views-200) W=200 H=50 ;;
    views-resize) W=80 H=24 ;;
    *) echo "fvviewcases.sh: unknown case '$CASE'" >&2; exit 2 ;;
esac

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
# tlpaint V TOP FOCUSED -- rows FV_CLIP_Y1..Y2-1, one writeLine (writeBuf) each
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
    TMyApp.new app || exit 2
    local hw=$(( W / 2 )) wh=$(( H - 1 ))
    case $1 in
        side)    win w1 0 0 "$hw" "$wh" 'Files' 1; win w2 "$hw" 0 "$W" "$wh" 'Panel two' 2 ;;
        overlap) win w1 0 0 "$hw" "$wh" 'Files' 1; win w2 $(( W / 4 )) 0 $(( W / 4 + hw )) "$wh" 'Panel two' 2 ;;
        p2)      win w1 2 1 40 20 'Files' 1 TView; win w2 30 5 70 22 'Panel two' 2 TView ;;
    esac
}

# ---- the counters (kcl/fv.views/tests/fvw_testlib.sh's shims) ---------------
CALLS=0 WRITES=0
DISPATCHERS=(kk._exec kk._call kk._parent kk._constructor_exec)
WRITERS=(fv.video.writeStr fv.video.writeBuf fv.video.writeCStr fv.video.writeChar fv.video.fillRect fv.video.shadeRect fv.video.fillColumns fv.video._shadef fv.video._wstr fv.video._fcf fv.video._wbf)
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

K_DOWN=$'\e[B' K_PGDN=$'\e[6~' K_F6=$'\e[17~' K_TAB=$'\t' K_CTRLL=$'\x0c'
K_RESIZE=$'\e[15;5~' K_RIGHT=$'\e[C' K_LEFT=$'\e[D' K_SRIGHT=$'\e[1;2C' K_SLEFT=$'\e[1;2D' K_ENTER=$'\r'

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
