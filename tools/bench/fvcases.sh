#!/usr/bin/env bash
# tools/bench/fvcases.sh ROOT CASE [N] -- one fv bench case (the kcl/fv.video
# screen buffer), run in this (fresh) process by tools/bench/bench.sh. ROOT is a
# kbool tree; its kcl/fv.video/fv.video.sh is sourced. Prints one line per
# measurement, `LABEL MICROSECONDS` (one decimal: the mean of one action), and
# `# TEXT` notes. Frames go to /dev/null (FV_VIDEO_OUT_FD); the terminal is never
# touched (no initVideo).
#
# The scene: a two-panel file manager. Each panel is a frame (box drawing, a
# title written with writeCStr) around a list of 400 names (one writeBuf per
# row: name, size and, at 200 columns, a date, ~5 colour runs; every sixth name
# Cyrillic), one selected row (the active panel's); a status line (writeCStr).
# The actions (fv.video calls only, rows formatted beforehand):
#   W.paint    the first paint, cold: initScreen + the whole scene +
#              updateScreen; initScreen empties the text caches, and the
#              caches it keeps (the class cache, the 16-colour map) are emptied
#              before each run, outside the timed window (`cold` below)
#   W.down     the selection one row down: 2 writeBuf + updateScreen (partial)
#   W.scroll   the selection on the last row, the list moves one name: every
#              row of the panel written again + updateScreen (one new name each)
#   W.tab      the selection to the other panel: 2 writeBuf + updateScreen
#   resize.A-B resizeScreen to the other size + the whole scene + updateScreen
#              (80x24 <-> 200x50; both sizes painted once before; resizeScreen
#              keeps the palette and the text cache)
# CASE (W = 80x24 or 200x50):
#   fv-80, fv-200            W.paint, W.down, W.scroll, W.tab
#   fv-wide-80, fv-wide-200  every other name CJK / Hangul / emoji (2 cells per
#                            character): wide.W.paint, .down, .scroll
#   fv-resize                resize.80x24-200x50, resize.200x50-80x24
# N (default 10) = actions per measurement. Before the timing a subshell runs
# the scene and every action once with error output on: any fv.video error stops
# the case (rc 3). A fv.video without wide characters (before kcl P1b) prints a
# note and no numbers for the wide cases. Any caller locale works: widths come
# from fv.video.strWidth. ASCII mode (FV_ASCII=1 in the environment, or no
# UTF-8 locale) is measured with a note (non-ASCII text in its ASCII form).
set -u
ROOT=${1:?usage: fvcases.sh ROOT CASE [N]}
CASE=${2:?usage: fvcases.sh ROOT CASE [N]}
N=${3:-10}
UNIT=$ROOT/kcl/fv.video/fv.video.sh

[[ -f $UNIT ]] || { echo "fvcases.sh: no $UNIT" >&2; exit 2; }
FV_COLORS=256
# a caller locale that does not exist (LANG=xx_YY.UTF-8 not installed): bash
# keeps whatever locale was active when a later restore of LC_ALL to it fails,
# so fv.video's own LC_ALL switches would leave the shell in a locale that
# changes from call to call (fv.video then measures its text in the wrong one).
# Such a caller is measured with LANG=C instead, with a note.
loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ -n $loc ]] && [[ -n $( { LC_ALL=$loc; } 2>&1 ) ]]; then
    echo "# the caller's locale '$loc' does not exist: measured with LANG=C"
    { unset LC_ALL LC_CTYPE; export LANG=C; } 2>/dev/null
fi
source "$ROOT/kbool.sh" || exit 2
source "$UNIT" || exit 2
declare -F fv.video.updateScreen >/dev/null || { echo "fvcases.sh: this fv.video has no screen buffer (before kcl P1a)" >&2; exit 2; }
exec {OUTFD}>/dev/null
FV_VIDEO_OUT_FD=$OUTFD

WIDE=0 SIZES=()
case $CASE in
    fv-80)       SIZES=("80 24") ;;
    fv-200)      SIZES=("200 50") ;;
    fv-wide-80)  SIZES=("80 24") WIDE=1 ;;
    fv-wide-200) SIZES=("200 50") WIDE=1 ;;
    fv-resize)   SIZES=("80 24" "200 50") ;;
    *) echo "fvcases.sh: unknown case '$CASE'" >&2; exit 2 ;;
esac

# the mode is decided at initScreen: ASCII mode (FV_ASCII=1, or no UTF-8
# locale) is measured too, with a note; a fv.video in UTF-8 mode that gives a
# CJK character one cell has no wide characters (before kcl P1b)
FV_SCREEN_W=80 FV_SCREEN_H=24 fv.video.initScreen
if (( ${FV_VIDEO_ASCII:-0} )); then
    echo "# ASCII mode (FV_ASCII=1 or no UTF-8 locale): non-ASCII text measured as its ASCII form"
elif (( WIDE )); then
    fv.video.strWidth '漢'
    if [[ $RESULT != 2 ]]; then
        echo "# no wide characters in this fv.video (before kcl P1b): no wide numbers"
        exit 0
    fi
fi

# rep CHAR COUNT -> REP
rep() { printf -v REP '%*s' "$2" ''; REP=${REP// /$1}; }

# the names: NAME[i] and its display cells CELLS[i], as fv.video stores it
# (fv.video.strWidth: in fv.video's own locale and mode, whatever the caller's)
L=400
CJK=(資料報告 中文测试 한국어문서 テスト結果)
NAME=() CELLS=() DIR=()
for (( i = 0; i < L; i++ )); do
    if (( WIDE && i % 4 == 1 )); then
        NAME[i]="${CJK[i / 4 % 4]}_$i.txt"
    elif (( WIDE && i % 4 == 3 )); then
        NAME[i]="📁🎉 photos $i.png"
    else
        case $(( i % 6 )) in
            0) NAME[i]="report_$i.txt" ;;
            1) NAME[i]="photo-$i.jpg" ;;
            2) NAME[i]="Документ_$i.odt" ;;
            3) NAME[i]="src_$i" ;;
            4) NAME[i]="archive.$i.tar.gz" ;;
            *) NAME[i]="Readme $i.md" ;;
        esac
    fi
    fv.video.strWidth "${NAME[i]}"; CELLS[i]=$RESULT
    DIR[i]=$(( i % 5 == 3 ))
done

# per size s (0, 1): the panel width, visible rows, frame strings, status line,
# the selected row's symbols; per name the row text RT[s*L+i] and symbols RN[s*L+i]
SW=() SH=() SPW=() SVIS=() SFTOP=() SFBOT=() SSTAT=() SSEL=() RT=() RN=()
for (( s = 0; s < ${#SIZES[@]}; s++ )); do
    read -r w h <<< "${SIZES[s]}"
    pw=$(( w / 2 )) in=$(( w / 2 - 2 ))
    dw=0; (( pw >= 60 )) && dw=15
    nw=$(( in - 11 - dw ))
    SW[s]=$w SH[s]=$h SPW[s]=$pw SVIS[s]=$(( h - 3 ))
    rep '═' $(( pw - 2 )); SFTOP[s]="╔$REP╗" SFBOT[s]="╚$REP╝"
    printf -v SSTAT[s] '%-*s' "$w" ' ~F1~ Help ~F3~ View ~F5~ Copy ~F6~ Move ~F10~ Quit'
    rep G "$in"; SSEL[s]=$REP
    for (( i = 0; i < L; i++ )); do
        printf -v sz '%8d' $(( (i * 7919) % 99999999 ))
        if (( DIR[i] )); then sz='   <DIR>'; fi
        printf -v pad '%*s' $(( nw - CELLS[i] )) ''
        t=" ${NAME[i]}$pad $sz"
        if (( DIR[i] )); then rep E $(( 1 + nw + 1 )); else rep B $(( 1 + nw + 1 )); fi
        a=$REP
        rep A 8; a+=$REP
        if (( dw )); then
            printf -v d ' %02d.%02d.26 %02d:%02d' $(( i % 28 + 1 )) $(( i % 12 + 1 )) $(( i % 24 )) $(( i % 60 ))
            t+=$d; rep 8 15; a+=$REP
        fi
        RT[s*L+i]="$t " RN[s*L+i]="${a}B"
    done
done
TITLE=(' ~Л~евая ' ' ~П~равая ')

# set_size S: the current size (also FV_SCREEN_W / FV_SCREEN_H)
set_size() {
    S=$1 W=${SW[$1]} H=${SH[$1]} PW=${SPW[$1]} VIS=${SVIS[$1]} BASE=$(( $1 * L ))
    FV_SCREEN_W=$W FV_SCREEN_H=$H
}
TOP=(0 200) SEL=(0 0) ACT=0

# row P R: row R of panel P written (selected or not)
row() {
    local i=$(( BASE + (TOP[$1] + $2) % L ))
    if (( $1 == ACT && $2 == SEL[$1] )); then fv.video.writeBuf $(( $1 * PW + 1 )) $(( $2 + 1 )) "${RT[i]}" "${SSEL[S]}"
    else fv.video.writeBuf $(( $1 * PW + 1 )) $(( $2 + 1 )) "${RT[i]}" "${RN[i]}"; fi
}
rows() { local r; for (( r = 0; r < VIS; r++ )); do row "$1" "$r"; done; }
scene() {   # the whole scene into the buffer
    local p x r
    fv.video.fillRect 0 0 "$W" $(( H - 1 )) 8
    for p in 0 1; do
        x=$(( p * PW ))
        fv.video.writeStr "$x" 0 "${SFTOP[S]}" 9
        fv.video.writeCStr $(( x + 3 )) 0 "${TITLE[p]}" 9 C
        for (( r = 1; r <= VIS; r++ )); do
            fv.video.writeStr "$x" "$r" '║' 9
            fv.video.writeStr $(( x + PW - 1 )) "$r" '║' 9
        done
        rows "$p"
        fv.video.writeStr "$x" $(( H - 2 )) "${SFBOT[S]}" 9
    done
    fv.video.writeCStr 0 $(( H - 1 )) "${SSTAT[S]}" P Q
}
paint()  { fv.video.initScreen; scene; fv.video.updateScreen; }
down()   { local r=${SEL[ACT]}; SEL[ACT]=$(( (r + 1) % VIS )); row "$ACT" "$r"; row "$ACT" "${SEL[ACT]}"; fv.video.updateScreen; }
scroll() { SEL[ACT]=$(( VIS - 1 )); TOP[ACT]=$(( TOP[ACT] + 1 )); rows "$ACT"; fv.video.updateScreen; }
tab()    { local o=$ACT; ACT=$(( 1 - ACT )); row "$o" "${SEL[o]}"; row "$ACT" "${SEL[ACT]}"; fv.video.updateScreen; }
resize() { set_size "$1"; fv.video.resizeScreen; scene; fv.video.updateScreen; }

# timed LABEL COUNT CMD... : the mean microseconds of one CMD over COUNT runs
timed() {
    local label=$1 n=$2 i t0 t1 d
    shift 2
    t0=$EPOCHREALTIME
    for (( i = 0; i < n; i++ )); do "$@"; done
    t1=$EPOCHREALTIME
    d=$(( (${t1/[.,]/} - ${t0/[.,]/}) * 10 / n ))
    printf '%s %d.%d\n' "$label" $(( d / 10 )) $(( d % 10 ))
}

# cold: empty the caches initScreen keeps -- fv.video PRIVATE state, reached
# into on purpose so that every timed paint is a first paint of the process:
# the per-character class cache of the width walk (__FV_VS_CC) and the
# 256 -> 16 colour map (__FV_VS_N16). Names a fv.video does not have are skipped.
cold() {
    if declare -p __FV_VS_CC >/dev/null 2>&1; then __FV_VS_CC=(); fi
    if declare -p __FV_VS_N16 >/dev/null 2>&1; then __FV_VS_N16=(); fi
}
# timed_cold LABEL COUNT CMD... : timed, with cold before each run (outside
# the timed window)
timed_cold() {
    local label=$1 n=$2 i t0 t1 d=0
    shift 2
    for (( i = 0; i < n; i++ )); do
        cold
        t0=$EPOCHREALTIME; "$@"; t1=$EPOCHREALTIME
        d=$(( d + ${t1/[.,]/} - ${t0/[.,]/} ))
    done
    d=$(( d * 10 / n ))
    printf '%s %d.%d\n' "$label" $(( d / 10 )) $(( d % 10 ))
}

# the check: the scene and every action once, in a subshell (its caches go
# with it), fv.video errors printed
check() {
    local VERBOSE_KKLASS=debug
    set_size 0
    paint || return
    down && scroll && tab || return
    if (( ${#SIZES[@]} > 1 )); then resize 1 && resize 0 || return; fi
}
out=$(check 2>&1); rc=$?
if (( rc )) || [[ $out == *Error:* ]]; then
    echo "fvcases.sh: $CASE: the check failed (rc $rc): ${out//$'\n'/ | }" >&2
    exit 3
fi
[[ -n $out ]] && printf '%s\n' "$out"

set_size 0
sz=${W}x$H
if [[ $CASE == fv-resize ]]; then
    paint; resize 1; resize 0
    up=0 dn=0
    for (( i = 0; i < N; i++ )); do
        t0=$EPOCHREALTIME; resize 1; t1=$EPOCHREALTIME
        up=$(( up + ${t1/[.,]/} - ${t0/[.,]/} ))
        t0=$EPOCHREALTIME; resize 0; t1=$EPOCHREALTIME
        dn=$(( dn + ${t1/[.,]/} - ${t0/[.,]/} ))
    done
    up=$(( up * 10 / N )) dn=$(( dn * 10 / N ))
    printf 'resize.%s-%s %d.%d\n' "$sz" "${SW[1]}x${SH[1]}" $(( up / 10 )) $(( up % 10 ))
    printf 'resize.%s-%s %d.%d\n' "${SW[1]}x${SH[1]}" "$sz" $(( dn / 10 )) $(( dn % 10 ))
    exit 0
fi
p=$sz
(( WIDE )) && p=wide.$sz
timed_cold "$p.paint" "$N" paint
timed "$p.down" "$N" down
timed "$p.scroll" "$N" scroll
(( WIDE )) || timed "$p.tab" "$N" tab
exit 0
