#!/usr/bin/env bash
# tools/bench/fvdlgcases.sh ROOT CASE [N] -- one bin/fvdlg process bench case
# (kcl/docs/dev/fv/P4_DESIGN.md §6.2; kklass/docs/dev/IMAGE_PLAN.md §11 and
# stage I5: bin/fvdlg through `kk.image --background`), run by
# tools/bench/bench.sh (suite `fvdlg`). A SKELETON that P4 stage 4e extends:
# today every row is launch -> exit of a spawned `bash ROOT/bin/fvdlg
# --fv-headless --fv-keys K --fv-size 80x24 --fv-out /dev/null WIDGET…`
# (bash's start and exit included) — an upper bound of launch -> first frame
# (the dialog's first frame comes before the key that ends it); 4e adds the
# first-frame mark itself. Prints `LABEL MICROSECONDS` lines (one decimal:
# the mean of the measurement's starts) and `# TEXT` notes.
#
# Every image lives in a temp folder (KBOOL_IMAGE_DIR): under $IMGBENCH_TMP
# when bench.sh set it (one folder per side), else one of its own (mktemp -d,
# removed at exit). The user's image cache is never read or written; every
# background writer is waited for (its marker NAME.bg gone, at most 150 s;
# a writer still there then is stopped and named in a note).
#
# CASE:
#   dlg-proc   dlg1.proc.WIDGET.image  a hit (the image warmed first: a miss,
#                                      its writer waited for, checked valid)
#              dlg1.proc.WIDGET        the same with KBOOL_IMAGE=off
#                                      (interleaved) — the plain load
#              WIDGET: msgbox (Enter), menu (Down Enter), inputbox (xy Enter);
#              a note when the image was written again during the timing
#   dlg-miss   fvdlg.miss              the first call (an empty image folder):
#                                      launch -> exit with the background
#                                      writer started — must be about the
#                                      plain load (dlg1.proc.msgbox), not the
#                                      writer's seconds
#              fvdlg.miss.write        launch -> the writer's end (its marker
#                                      gone): when the image is there
#              (one start each per measurement; N is not used)
# N (default 5) = starts per measurement.
set -u
ROOT=${1:?usage: fvdlgcases.sh ROOT CASE [N]}
CASE=${2:?usage: fvdlgcases.sh ROOT CASE [N]}
N=${3:-5}
[[ $N == [1-9]* && $N != *[!0-9]* ]] || { echo "fvdlgcases.sh: N must be a positive count" >&2; exit 2; }
[[ -f $ROOT/kbool.sh && -f $ROOT/bin/fvdlg && -f $ROOT/kcl/fv.dlg/fv.dlg.sh ]] \
    || { echo "fvdlgcases.sh: no kbool.sh, bin/fvdlg or kcl/fv.dlg in '$ROOT'" >&2; exit 2; }
[[ -f $ROOT/kkore/kimgbg.sh ]] || { echo "fvdlgcases.sh: this kbool has no kk.image --background (kkore/kimgbg.sh)" >&2; exit 2; }
case $CASE in dlg-proc|dlg-miss) ;; *) echo "fvdlgcases.sh: unknown case '$CASE'" >&2; exit 2 ;; esac
unset -v KBOOL_IMAGE KBOOL_IMAGE_DIR KBOOL_IMAGE_CHECK KBOOL_IMAGE_CHAIN VERBOSE_KKLASS FVDLG_NOTTY

side=${ROOT//[!A-Za-z0-9]/_}
(( ${#side} <= 60 )) || side=${side: -60}
if [[ -n ${IMGBENCH_TMP-} && -d ${IMGBENCH_TMP-} ]]; then
    W=$IMGBENCH_TMP/fvdlg.$side
    mkdir -p "$W" || exit 2
else
    W=$(mktemp -d "${TMPDIR:-/tmp}/kbfvdlg.XXXXXX") || exit 2
    trap 'rm -rf -- "$W"' EXIT
fi
D=$W/img
printf '\r' > "$W/enter.keys"
printf '\033[B\r' > "$W/down.keys"
printf 'xy\r' > "$W/xy.keys"
printf '%s\n' 'source "$1/kbool.sh" || exit 2' 'kk.image --path fv.dlg' > "$W/probe.sh"
echo "# dlg1.proc / fvdlg.miss rows: launch -> exit of a spawned bin/fvdlg (headless, 80x24): an upper bound of launch -> first frame"

# widget NAME -> ARGS (the fvdlg arguments after the headless flags)
widget() {
    case $1 in
        msgbox)   ARGS=(--fv-keys "$W/enter.keys" --title T --msgbox 'Hello, world' 0 0) ;;
        menu)     ARGS=(--fv-keys "$W/down.keys" --menu Pick 0 0 0 a Apple b Banana c Cherry) ;;
        inputbox) ARGS=(--fv-keys "$W/xy.keys" --inputbox Name 0 0 ab) ;;
    esac
}
# run DIR OFF WIDGET -> US: one spawned fvdlg, launch -> exit (us); rc 1 when
# its status is not 0
run() {
    local t0 t1 rc
    widget "$3"
    t0=$EPOCHREALTIME
    KBOOL_IMAGE_DIR=$1 KBOOL_IMAGE=$2 "$BASH" "$ROOT/bin/fvdlg" --fv-headless --fv-size 80x24 --fv-out /dev/null "${ARGS[@]}" \
        </dev/null >/dev/null 2>&1
    rc=$?
    t1=$EPOCHREALTIME
    US=$(( 10#${t1//[.,]/} - 10#${t0//[.,]/} ))
    return "$rc"
}
# bgwait DIR [S] -> rc 0 when no writer's marker is left in DIR (polled every
# 0.1 s, at most S s, default 150); else the writer is stopped (TERM, then
# KILL, to its process group and pid) and rc 1
bgwait() {
    local n=$(( ${2:-150} * 10 )) f t o p g q any
    while (( n-- > 0 )); do
        any=0
        for f in "$1"/*.bg; do [[ -e $f ]] && any=1; done
        (( any )) || return 0
        sleep 0.1
    done
    for f in "$1"/*.bg; do
        [[ -e $f ]] || continue
        { IFS=' ' read -r t o p g q < "$f"; } 2>/dev/null || continue
        [[ -n $p && $p != *[!0-9]* ]] || continue
        [[ -n $q && $q != *[!0-9]* && $q != 0 ]] && kill -TERM -- "-$q" 2>/dev/null
        kill -TERM "$p" 2>/dev/null
        sleep 1
        [[ -n $q && $q != *[!0-9]* && $q != 0 ]] && kill -KILL -- "-$q" 2>/dev/null
        kill -KILL "$p" 2>/dev/null
    done
    return 1
}
valid() { KBOOL_IMAGE_DIR=$1 "$BASH" "$W/probe.sh" "$ROOT" >"$W/probe.out" 2>/dev/null; }
# nonce DIR -> NONCE (the image's plain line, field 7 after #P)
nonce() {
    local - f l1 l2 IFS=$'\x1f'
    local -a a=()
    set -f
    NONCE=""
    for f in "$1"/fv.dlg-*.img; do [[ -f $f ]] || continue
        { IFS= read -r l1; IFS= read -r l2; } < "$f" || return 1
        a=($l2)
        NONCE=${a[8]-}
    done
}
mean() { printf '%s %d.%d\n' "$1" $(( $2 / $3 )) $(( $2 * 10 / $3 % 10 )); }

case $CASE in
dlg-proc)
    ok=0
    for (( i = 0; i < 3; i++ )); do
        if valid "$D"; then ok=1; break; fi
        run "$D" "" msgbox || :
        bgwait "$D" || echo "# dlg-proc: a background writer still ran after 150 s (stopped)"
    done
    (( ok )) || valid "$D" && ok=1
    (( ok )) || echo "# dlg1.proc.*.image: no valid image after three first calls"
    nonce "$D"; n0=$NONCE
    declare -A S=()
    for (( i = 0; i < N; i++ )); do
        for w in msgbox menu inputbox; do
            if (( ok )); then
                run "$D" "" "$w" || { echo "# dlg1.proc.$w.image: fvdlg failed"; exit 3; }
                S[$w.image]=$(( ${S[$w.image]:-0} + US ))
            fi
            run "$D" off "$w" || { echo "# dlg1.proc.$w: fvdlg failed"; exit 3; }
            S[$w]=$(( ${S[$w]:-0} + US ))
        done
    done
    for w in msgbox menu inputbox; do
        (( ok )) && mean "dlg1.proc.$w.image" "${S[$w.image]}" "$N"
        mean "dlg1.proc.$w" "${S[$w]}" "$N"
    done
    nonce "$D"
    if (( ok )) && [[ $NONCE != "$n0" ]]; then echo "# dlg1.proc.*.image: the image was written again during the timing (not every start was a hit)"; fi
    bgwait "$D" 30 || echo "# dlg-proc: a background writer ran after the timing (stopped)" ;;
dlg-miss)
    M=$W/miss
    rm -rf -- "$M"
    t0=$EPOCHREALTIME
    run "$M" "" msgbox || { echo "# fvdlg.miss: fvdlg failed"; bgwait "$M" 150; exit 3; }
    mean fvdlg.miss "$US" 1
    if bgwait "$M"; then
        t1=$EPOCHREALTIME
        mean fvdlg.miss.write $(( 10#${t1//[.,]/} - 10#${t0//[.,]/} )) 1
        valid "$M" || echo "# fvdlg.miss: no valid image after the background writer ($(< "$W/probe.out"))"
    else
        echo "# fvdlg.miss: the background writer still ran after 150 s (stopped)"
    fi
    rm -rf -- "$M" ;;
esac
exit 0
