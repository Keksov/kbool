#!/usr/bin/env bash
# termcheck.sh -- asks you to press keys and use the mouse in a terminal and
# writes a log of what the terminal really sent. Read tools/termcheck/README.md.
#
#     bash tools/termcheck/termcheck.sh [--only GROUPS] [--timeout SECONDS]
#                                       [--out DIR] [--with-dangerous]
#     bash tools/termcheck/termcheck.sh --help
#
# Test mode (tools/termcheck/tests/selftest.sh):  --feed FILE reads the keys
# from FILE instead of a terminal: one line per item, printf %b escapes, an
# empty line = nothing pressed. No terminal is opened or drawn on. The hidden
# variable TERMCHECK_SCREEN_W sets the screen width in that mode (default 80).
#
# Sync mode (tools/termcheck/autodrive.ps1, README "Automatic run (Windows)"):
# TERMCHECK_SYNC=FILE appends one line per state to FILE:
#     ready <group> <item-id> [target X Y [X2 Y2]] [screen W H]
#     done <item-id> <result> [cell X Y [cell2 X Y]] [screen W H] [skipped]
#     finish-wait
#     end <complete|incomplete|error> <exit status>
# TERMCHECK_NONCE=WORD sets the window title to termcheck-WORD (OSC 2).
# TERMCHECK_SKIP=ID[:REASON],... (sync mode only) logs these items as NONE with
# note=skipped-by-driver[:REASON] without waiting. --list-items prints the item table.

TERMCHECK_VERSION=1

if ! (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
    echo "termcheck: bash 5.1 or newer is needed (this is $BASH_VERSION)" >&2
    exit 2
fi

TC_SELF=${BASH_SOURCE[0]}
if [[ $TC_SELF == */* ]]; then TC_DIR=${TC_SELF%/*}; else TC_DIR=.; fi
TC_ROOT=$(cd "$TC_DIR/../.." && pwd) || exit 2

TC_GROUPS=(arrows nav fkeys special chars keypad mouse resize)

tc_usage() {
    cat <<'EOF'
termcheck.sh -- terminal key and mouse check; writes a log file to send back.

Usage: bash tools/termcheck/termcheck.sh [options]

  --only GROUPS      run only these groups (comma list). Groups:
                     arrows nav fkeys special chars keypad mouse resize
  --timeout SECONDS  how long to wait for each item (default 10; decimals
                     allowed, at most 6 digits after the point)
  --out DIR          write the log into DIR (default: the current directory)
  --with-dangerous   also ask for Alt+F4 (it closes most terminal windows)
  --feed FILE        test mode: take the keys from FILE, no terminal is used
  --list-items       print the items (group, id, kind, expected) and exit;
                     includes the wide-screen mouse item
  -h, --help         this text

The screen must be at least 80 columns by 24 rows. Press Ctrl+C at the end (or
at any time) to finish: the terminal is put back and the log path is printed.
The log file is named fv_termcheck_<date>_<terminal>.log.
EOF
}

# ---- arguments ---------------------------------------------------------------
TC_ONLY=''
TC_TIMEOUT_TXT=10
TC_OUT=.
TC_DANGER=0
TC_FEEDFILE=''
TC_LIST=0
while (( $# )); do
    case $1 in
        -h|--help) tc_usage; exit 0 ;;
        --list-items) TC_LIST=1; shift ;;
        --only) [[ $# -ge 2 ]] || { echo "termcheck: --only needs a value" >&2; exit 2; }
            TC_ONLY=$2; shift 2 ;;
        --timeout) [[ $# -ge 2 ]] || { echo "termcheck: --timeout needs a value" >&2; exit 2; }
            TC_TIMEOUT_TXT=$2; shift 2 ;;
        --out) [[ $# -ge 2 ]] || { echo "termcheck: --out needs a directory" >&2; exit 2; }
            TC_OUT=$2; shift 2 ;;
        --feed) [[ $# -ge 2 ]] || { echo "termcheck: --feed needs a file" >&2; exit 2; }
            TC_FEEDFILE=$2; shift 2 ;;
        --with-dangerous) TC_DANGER=1; shift ;;
        *) echo "termcheck: unknown option '$1' (try --help)" >&2; exit 2 ;;
    esac
done

# TC_PARSE_US SECONDS: TC_US = microseconds; rc 1 when not a positive number
tc_parse_us() {
    local i f
    [[ $1 =~ ^([0-9]+)(\.([0-9]{1,6}))?$ ]] || return 1
    i=${BASH_REMATCH[1]}
    f=${BASH_REMATCH[3]}000000
    f=${f:0:6}
    TC_US=$(( 10#$i * 1000000 + 10#$f ))
    (( TC_US > 0 ))
}
if ! tc_parse_us "$TC_TIMEOUT_TXT"; then
    echo "termcheck: --timeout '$TC_TIMEOUT_TXT' is not a positive number of seconds (at most 6 decimals)" >&2
    exit 2
fi
TC_TIMEOUT_US=$TC_US

declare -A TC_SEL=()
if [[ -n $TC_ONLY ]]; then
    IFS=',' read -ra tc_w <<< "$TC_ONLY"
    for tc_g in "${tc_w[@]}"; do
        tc_ok=0
        for tc_k in "${TC_GROUPS[@]}"; do [[ $tc_g == "$tc_k" ]] && tc_ok=1; done
        if (( ! tc_ok )); then
            echo "termcheck: unknown group '$tc_g' (groups: ${TC_GROUPS[*]})" >&2
            exit 2
        fi
        TC_SEL[$tc_g]=1
    done
else
    for tc_g in "${TC_GROUPS[@]}"; do TC_SEL[$tc_g]=1; done
fi

# ---- the item list -------------------------------------------------------------
IT_GROUP=() IT_ID=() IT_HUMAN=() IT_EXP=() IT_KIND=() IT_HINT=()
IT_MK=() IT_B=() IT_M=() IT_X=() IT_Y=() IT_X2=() IT_Y2=()
TC_N=0

# tc_add GROUP ID HUMAN EXPECTED [HINT] -- a key item
tc_add() {
    [[ -n ${TC_SEL[$1]:-} ]] || return 0
    IT_GROUP[TC_N]=$1 IT_ID[TC_N]=$2 IT_HUMAN[TC_N]=$3 IT_EXP[TC_N]=$4 IT_HINT[TC_N]=${5-}
    IT_KIND[TC_N]=key
    (( TC_N++ ))
}

# tc_add_mouse ID HUMAN MK B M X Y [X2 Y2] -- a mouse item
tc_add_mouse() {
    [[ -n ${TC_SEL[mouse]:-} ]] || return 0
    IT_GROUP[TC_N]=mouse IT_ID[TC_N]=$1 IT_HUMAN[TC_N]=$2 IT_KIND[TC_N]=mouse
    IT_MK[TC_N]=$3 IT_B[TC_N]=$4 IT_M[TC_N]=$5 IT_X[TC_N]=$6 IT_Y[TC_N]=$7
    IT_X2[TC_N]=${8-} IT_Y2[TC_N]=${9-} IT_HINT[TC_N]=''
    case $3 in
        click|wheel|dbl|tri) IT_EXP[TC_N]="b=$4,m=$5,x=$6,y=$7" ;;
        drag) IT_EXP[TC_N]="b=$4,m=$5,down@$6,$7,up@$8,$9" ;;
    esac
    (( TC_N++ ))
}

tc_build_items() {
    local mod mname base human n key zhe
    local -a mods=('' Shift Ctrl Alt)
    # arrows
    for base in Up Down Left Right; do
        for mod in "${mods[@]}"; do
            human=${mod:+$mod+}$base
            tc_add arrows "$human" "$human" "kb$mod$base"
        done
    done
    # navigation keys
    for key in Home:Home End:End PgUp:'Page Up' PgDn:'Page Down' Ins:Insert Del:Delete; do
        base=${key%%:*} n=${key#*:}
        for mod in "${mods[@]}"; do
            human=${mod:+$mod+}$n
            if [[ $base == Ins && $mod == Shift ]]; then
                tc_add nav "Shift+Ins" "$human" "kb${mod}Ins" "(this may paste the clipboard into the terminal; that is fine)"
            else
                tc_add nav "${mod:+$mod+}$base" "$human" "kb$mod$base"
            fi
        done
    done
    # function keys
    for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
        for mod in "${mods[@]}"; do
            mname=${mod:+$mod+}F$n
            if [[ $mod == Alt && $n == 4 && $TC_DANGER == 0 ]]; then continue; fi
            case $mname in
                F11|Alt+F11) tc_add fkeys "$mname" "$mname" "kb${mod}F$n" "(the terminal may go full screen; just wait for the countdown)" ;;
                Alt+F4) tc_add fkeys "$mname" "$mname" "kb${mod}F$n" "(this closes most terminal windows!)" ;;
                Alt+F2) tc_add fkeys "$mname" "$mname" "kb${mod}F$n" "(the terminal may open a window; ignore it)" ;;
                *) tc_add fkeys "$mname" "$mname" "kb${mod}F$n" ;;
            esac
        done
    done
    # special keys
    tc_add special Tab "Tab" kbTab
    tc_add special Shift+Tab "Shift+Tab" kbShiftTab
    tc_add special Enter "Enter" kbEnter
    tc_add special Esc "Esc" kbEsc
    tc_add special Backspace "Backspace" kbBack
    tc_add special Ctrl+Backspace "Ctrl+Backspace" none "(finding T-1: a key is expected to arrive as plain Backspace; what comes is recorded)"
    tc_add special Alt+Backspace "Alt+Backspace" kbAltBack
    tc_add special Ctrl+Space "Ctrl+Space" kbCtrlSpace "(arrives as the byte 0)"
    # characters and Ctrl letters
    tc_add chars Alt+X "Alt+X  (lower-case x)" "kbAltX:x"
    tc_add chars Alt+Shift+X "Alt+Shift+X  (capital X)" "kbAltX:X" "(Alt+Shift may switch the keyboard layout; that is fine)"
    tc_add chars Ctrl+A "Ctrl+A" kbCtrlA
    tc_add chars Ctrl+Z "Ctrl+Z" kbCtrlZ
    tc_add chars 'Ctrl+\' 'Ctrl+\' kbCtrlBackslash
    zhe=$'\xd0\xb6'
    tc_add chars zhe "the letter $zhe  (Cyrillic zhe)" "kbChar:$zhe" "(switch to the Russian keyboard layout first: Win+Space)"
    tc_add chars Space "the Space bar" "kbChar: "
    # keypad
    tc_add keypad Keypad5-NumLockOff "keypad 5 with NumLock OFF" "kbCenter|kbChar:5" "(no keypad? just wait)"
    tc_add keypad Keypad5-NumLockOn "keypad 5 with NumLock ON" "kbChar:5" "(turn NumLock on first; no keypad? just wait)"
    tc_add keypad KeypadEnter "keypad Enter" kbEnter "(no keypad? just wait)"
    # mouse: tc_add_mouse ID HUMAN MK B M X Y [X2 Y2]  (cells are 0-based)
    tc_add_mouse Click-Left "LEFT-click the highlighted X" click 1 0 12 6
    tc_add_mouse Click-Right "RIGHT-click the highlighted X" click 2 0 40 8
    tc_add_mouse Click-Middle "MIDDLE-click (wheel button) the highlighted X" click 4 0 60 10
    tc_add_mouse Wheel-Up "Turn the mouse WHEEL UP (away from you) over the X" wheel 1 0 20 12
    tc_add_mouse Wheel-Down "Turn the mouse WHEEL DOWN (toward you) over the X" wheel 2 0 50 14
    tc_add_mouse Drag "DRAG: press the left button on A, move, release on B" drag 1 0 10 16 60 18
    tc_add_mouse Double-Click "DOUBLE-click the highlighted X" dbl 1 0 30 6
    tc_add_mouse Triple-Click "TRIPLE-click the highlighted X" tri 1 0 45 9
    tc_add_mouse Ctrl+Click "Hold Ctrl and LEFT-click the highlighted X" click 1 4 15 11
    tc_add_mouse Shift+Click "Hold Shift and LEFT-click the highlighted X (terminals often keep it)" click 1 1 55 13
    if (( FV_SCREEN_W >= 230 )); then
        tc_add_mouse Click-Far-Right "LEFT-click the X at the far right (column 227)" click 1 0 226 10
    fi
    # resize
    if [[ -n ${TC_SEL[resize]:-} ]]; then
        IT_GROUP[TC_N]=resize IT_ID[TC_N]=Resize IT_HUMAN[TC_N]="Resize the window now (drag a corner)" \
            IT_EXP[TC_N]=cmResizeApp IT_KIND[TC_N]=resize IT_HINT[TC_N]="(stay at 80x24 or larger)"
        (( TC_N++ ))
    fi
}

# ---- --list-items: the item table for tools/termcheck/autodrive.ps1 -----------------
# one line per item: group TAB id TAB kind TAB expected (kind: key, mouse:MK, resize);
# the screen is taken as 240 wide so the far-right mouse item is listed too
if (( TC_LIST )); then
    FV_SCREEN_W=240
    tc_build_items
    for (( tc_i = 0; tc_i < TC_N; tc_i++ )); do
        tc_k=${IT_KIND[tc_i]}
        if [[ $tc_k == mouse ]]; then tc_k=mouse:${IT_MK[tc_i]}; fi
        printf '%s\t%s\t%s\t%s\n' "${IT_GROUP[tc_i]}" "${IT_ID[tc_i]}" "$tc_k" "${IT_EXP[tc_i]}"
    done
    exit 0
fi

# ---- sync mode (TERMCHECK_SYNC) ----------------------------------------------------
TC_SYNC=${TERMCHECK_SYNC:-}
TC_NONCE=${TERMCHECK_NONCE:-}
TC_NONCE=${TC_NONCE//[^A-Za-z0-9_-]/}
TC_CELL='' TC_CELL2='' TC_RSZ=''
declare -A TC_SKIP=()
if [[ -n $TC_SYNC ]]; then
    if ! { : >> "$TC_SYNC"; } 2>/dev/null; then
        echo "termcheck: cannot write the sync file '$TC_SYNC'" >&2
        exit 2
    fi
    IFS=',' read -ra tc_w <<< "${TERMCHECK_SKIP:-}"
    for tc_g in "${tc_w[@]}"; do
        [[ -n $tc_g ]] || continue
        # ID or ID:REASON (a word); the reason goes into the note
        if [[ $tc_g == *:* ]]; then
            tc_k=${tc_g#*:}
            tc_k=${tc_k//[^A-Za-z0-9_-]/}
            TC_SKIP[${tc_g%%:*}]=${tc_k:--}
        else
            TC_SKIP[$tc_g]=-
        fi
    done
fi

# tc_sync LINE: one line to the sync file (opened and closed per line = flushed)
tc_sync() { if [[ -n $TC_SYNC ]]; then printf '%s\n' "$1" >> "$TC_SYNC"; fi; }

# TERMCHECK_TRACE=FILE: one line per loop turn of drain / settle / wait / finish:
#     <epoch.us> <phase> <event>[:<key>] r=<FV_VIDEO_RESIZED> <group/item>
TC_TRACE=${TERMCHECK_TRACE:-}
if [[ -n $TC_TRACE ]] && ! { : >> "$TC_TRACE"; } 2>/dev/null; then
    echo "termcheck: cannot write the trace file '$TC_TRACE'" >&2
    exit 2
fi
tc_trace() {
    if [[ -n $TC_TRACE ]]; then
        printf '%s %s %s%s r=%s %s\n' "$EPOCHREALTIME" "$1" "${FV_EV_WHAT:--}" "${FV_EV_KEY:+:$FV_EV_KEY}" \
            "${FV_VIDEO_RESIZED:-0}" "${TC_CUR:--}" >> "$TC_TRACE"
    fi
}

# TERMCHECK_LABEL=WORD: the log file is named after it instead of the terminal guess
TC_LABEL=${TERMCHECK_LABEL:-}
TC_LABEL=${TC_LABEL//[^A-Za-z0-9._-]/_}

# tc_sync_ready INDEX: the item waits for input from now on
tc_sync_ready() {
    local i=$1 l="ready ${IT_GROUP[$1]} ${IT_ID[$1]}"
    [[ -n $TC_SYNC ]] || return 0
    case ${IT_KIND[i]} in
        mouse)
            l+=" target ${IT_X[i]} ${IT_Y[i]}"
            if [[ -n ${IT_X2[i]} ]]; then l+=" ${IT_X2[i]} ${IT_Y2[i]}"; fi
            l+=" screen $FV_SCREEN_W $FV_SCREEN_H"
            ;;
        resize) l+=" screen $FV_SCREEN_W $FV_SCREEN_H" ;;
    esac
    tc_sync "$l"
}

# tc_sync_done INDEX: the item is judged (RES) and logged
tc_sync_done() {
    local i=$1 l="done ${IT_ID[$1]} $RES"
    [[ -n $TC_SYNC ]] || return 0
    case ${IT_KIND[i]} in
        mouse)
            if [[ -n $TC_CELL ]]; then l+=" cell $TC_CELL"; fi
            if [[ -n $TC_CELL2 ]]; then l+=" cell2 $TC_CELL2"; fi
            ;;
        resize) if [[ -n $TC_RSZ ]]; then l+=" screen $TC_RSZ"; fi ;;
    esac
    tc_sync "$l"
}

TC_FEED=0
if [[ -n $TC_FEEDFILE ]]; then
    TC_FEED=1
    if [[ ! -r $TC_FEEDFILE ]]; then
        echo "termcheck: cannot read the feed file '$TC_FEEDFILE'" >&2
        exit 2
    fi
fi
if [[ ! -d $TC_OUT || ! -w $TC_OUT ]]; then
    echo "termcheck: the output folder '$TC_OUT' is not a writable directory" >&2
    exit 2
fi
TC_OUT=$(cd "$TC_OUT" && pwd) || exit 2

# ---- state -------------------------------------------------------------------
TC_LOG=''
TC_CUR=''           # group/item being run
TC_FINISH=0         # 1 once the finish prompt was reached
TC_DONE=0           # 1 once the summary was written
TC_EOF=0
TC_POLL=0.05
TC_EXTRA_US=200000
TC_LAST='-'
TC_FEEDFD=''
declare -A TC_CNT=()
declare -A TC_GN=()

tc_log() { if [[ -n $TC_LOG ]]; then printf '%s\n' "$1" >> "$TC_LOG"; fi; }

tc_now() { TC_NOW=${EPOCHREALTIME/[.,]/}; }

# TC_Q VALUE: TC_QV = printf %q of VALUE, byte-wise (C locale)
tc_q() {
    local LC_ALL=C
    printf -v TC_QV '%q' "$1"
}

# ---- finishing: summary and the traps --------------------------------------
tc_summary_text() {
    local g r line total=0 n
    for g in "${TC_GROUPS[@]}"; do
        [[ -n ${TC_GN[$g]:-} ]] || continue
        line="summary  $g"
        for r in OK DIFF NONE INFO; do
            n=${TC_CNT[$g/$r]:-0}
            line+="  $r=$n"
        done
        printf '%s\n' "$line"
    done
    for r in OK DIFF NONE INFO; do
        n=0
        for g in "${TC_GROUPS[@]}"; do (( n += ${TC_CNT[$g/$r]:-0} )); done
        total+="  $r=$n"
    done
    printf 'summary  total%s\n' "${total#0}"
}

tc_finalize() {
    local line one wlog
    if (( TC_DONE )); then return 0; fi
    TC_DONE=1
    if [[ -z $TC_LOG ]]; then return 0; fi
    if [[ -n $TC_CUR && $TC_FINISH == 0 ]]; then
        tc_log "incomplete at $TC_CUR"
    else
        tc_log "run complete"
    fi
    while IFS= read -r line; do tc_log "$line"; done < <(tc_summary_text)
    one=$(tc_summary_text | tail -n 1)
    printf 'termcheck: %s\n' "${one#summary  total  }"
    printf 'termcheck: log written to %s\n' "$TC_LOG"
    if command -v cygpath >/dev/null 2>&1; then
        wlog=$(cygpath -w "$TC_LOG" 2>/dev/null)
        if [[ -n $wlog ]]; then printf 'termcheck: (Windows path: %s)\n' "$wlog"; fi
    fi
    if (( ! TC_FEED )); then
        printf 'termcheck: please send that file. If the terminal looks broken, type: reset\n'
    fi
}

tc_on_exit() {
    local rc=$? st=complete
    tc_finalize
    if [[ -n $TC_SYNC ]]; then
        if [[ -z $TC_LOG ]]; then st=error
        elif [[ -n $TC_CUR && $TC_FINISH == 0 ]]; then st=incomplete; fi
        tc_sync "end $st $rc"
    fi
}

tc_on_sig() {
    case $1 in
        int)  tc_log "ctrl-c: interrupt received, terminal restored by fv.video"; exit 130 ;;
        hup)  tc_log "hup: hangup received, terminal restored by fv.video"; exit 129 ;;
        term) tc_log "term: terminate received, terminal restored by fv.video"; exit 143 ;;
    esac
}

# the script's own traps first; fv.video chains them (README fv.video, "Exit paths")
trap 'tc_on_exit' EXIT
trap 'tc_on_sig int' INT
trap 'tc_on_sig hup' HUP
trap 'tc_on_sig term' TERM

# ---- the header data, collected BEFORE the terminal is touched ----------------

tc_hdr_stty=''
if (( ! TC_FEED )) && [[ -r /dev/tty ]]; then
    tc_hdr_stty=$({ stty -a < /dev/tty; } 2>/dev/null) || tc_hdr_stty=''
fi
tc_git() {
    local h
    h=$(git -C "$1" rev-parse --short HEAD 2>/dev/null) || h=''
    printf '%s' "${h:-unknown}"
}
TC_GIT_KBOOL=$(tc_git "$TC_ROOT")
TC_GIT_KCL=$(tc_git "$TC_ROOT/kcl")
TC_UNAME=$(uname -a 2>/dev/null) || TC_UNAME=unknown
TC_PROCVER=''
if [[ -r /proc/version ]]; then IFS= read -r TC_PROCVER < /proc/version || true; fi
printf -v TC_DATE '%(%Y-%m-%d %H:%M:%S %z)T' -1
printf -v TC_STAMP '%(%Y%m%d-%H%M%S)T' -1

# the terminal guess for the file name (amendment A8)
if [[ -n ${WT_SESSION-} ]]; then tc_g1=WT
elif [[ -n ${TERM_PROGRAM-} ]]; then tc_g1=$TERM_PROGRAM
else tc_g1=${TERM:-unknown}; fi
tc_g2=${MSYSTEM:-${OSTYPE:-unknown}}
TC_GUESS=${tc_g1}-${tc_g2}
TC_GUESS=${TC_GUESS//[^A-Za-z0-9._-]/_}
if [[ -n $TC_LABEL ]]; then TC_GUESS=$TC_LABEL; fi

# ---- load the units ------------------------------------------------------------
# shellcheck source=/dev/null
source "$TC_ROOT/kbool.sh" || { echo "termcheck: cannot load $TC_ROOT/kbool.sh" >&2; exit 2; }
kk.uses fv.drivers || { echo "termcheck: cannot load the fv.drivers unit" >&2; exit 2; }

# ---- the terminal ------------------------------------------------------------
if (( TC_FEED )); then
    exec {TC_NULLFD}< /dev/null
    exec {TC_FEEDFD}< "$TC_FEEDFILE"
    FV_KEY_FD=$TC_NULLFD
    FV_SCREEN_W=${TERMCHECK_SCREEN_W:-80}
    FV_SCREEN_H=24
else
    if ! fv.video.initVideo; then
        echo "termcheck: no terminal (run this from a terminal window, not from a pipe or a service)" >&2
        exit 2
    fi
    fv.drivers.initEvents
    if (( FV_SCREEN_W < 80 || FV_SCREEN_H < 24 )); then
        tc_sw=$FV_SCREEN_W tc_sh=$FV_SCREEN_H
        fv.video.doneVideo
        echo "termcheck: the window is ${tc_sw}x${tc_sh}; enlarge the window to at least 80x24 and run it again" >&2
        exit 2
    fi
fi

tc_put() { if (( ! TC_FEED )); then printf '%s' "$1" >&"$FV_TTY_FD"; fi; }

# sync mode: the window title names the run, so the driver finds this window
if [[ -n $TC_SYNC && -n $TC_NONCE ]]; then tc_put $'\e]2;termcheck-'"$TC_NONCE"$'\a'; fi

# ---- drawing -------------------------------------------------------------------
TC_S=''
# tc_at ROW COL TEXT: append "move there, write TEXT" to TC_S
tc_at() { TC_S+=$'\e['"$1;$2H$3"; }

tc_title() { # INDEX
    TC_S=$'\e[0m\e[2J\e[H'
    tc_at 1 2 "termcheck  item $(( $1 + 1 ))/$TC_N   [${IT_GROUP[$1]}]"
    tc_at 22 2 "last: $TC_LAST"
    tc_at 23 2 "Ctrl+C = stop and put the terminal back"
}

tc_draw_key() {
    tc_title "$1"
    tc_at 8 4 "Press:   ${IT_HUMAN[$1]}"
    tc_at 10 4 "(expected: ${IT_EXP[$1]})"
    if [[ -n ${IT_HINT[$1]} ]]; then tc_at 12 4 "${IT_HINT[$1]}"; fi
    tc_put "$TC_S"
}

# tc_mark X Y LABEL: [L] with the label cell in reverse video
tc_mark() {
    tc_at "$(( $2 + 1 ))" "$1" "["
    tc_at "$(( $2 + 1 ))" "$(( $1 + 1 ))" $'\e[7m'"$3"$'\e[0m'
    tc_at "$(( $2 + 1 ))" "$(( $1 + 2 ))" "]"
}

tc_draw_mouse() {
    local i=$1
    tc_title "$i"
    tc_at 3 3 "${IT_HUMAN[$i]}"
    if [[ ${IT_MK[$i]} == drag ]]; then
        tc_mark "${IT_X[$i]}" "${IT_Y[$i]}" A
        tc_mark "${IT_X2[$i]}" "${IT_Y2[$i]}" B
    else
        tc_mark "${IT_X[$i]}" "${IT_Y[$i]}" X
    fi
    tc_put "$TC_S"
}

tc_draw_resize() {
    tc_title "$1"
    tc_at 8 4 "${IT_HUMAN[$1]}"
    tc_at 10 4 "(now ${FV_SCREEN_W}x${FV_SCREEN_H})"
    tc_at 12 4 "${IT_HINT[$1]}"
    tc_put "$TC_S"
}

# tc_countdown SECONDS-LEFT
tc_countdown() {
    tc_put $'\e[21;4H\e[2K'"time left: $1 s   (nothing happens = skipped)"
}

# ---- waiting for input ------------------------------------------------------
# Resizes are coalesced while draining and settling: fv.drivers.getEvent runs
# fv.video.updateSize (a `stty size` fork, ~13 ms) for every resize event, so
# the flag is taken off before each call and the size is read once at the end.

# tc_drain: drop what is already pending (STALE counts the events); at most ~0.3 s
tc_drain() {
    local n=0 rsz=0 end
    if (( TC_FEED )); then return 0; fi
    tc_now
    end=$(( TC_NOW + 300000 ))
    while :; do
        if (( FV_VIDEO_RESIZED )); then rsz=1; FV_VIDEO_RESIZED=0; fi
        fv.drivers.getEvent 0 || break
        tc_trace drain
        [[ $FV_EV_WHAT == evNothing ]] && break
        (( n++ ))
        tc_now
        if (( TC_NOW >= end )); then tc_trace drain-time-limit; break; fi
    done
    if (( rsz || FV_VIDEO_RESIZED )); then fv.video.updateSize; tc_trace drain-resize; fi
    (( STALE += n ))
}

# tc_settle: show the result for ~0.4 s; events arriving meanwhile are stale
tc_settle() {
    local end rsz=0
    if (( TC_FEED )); then return 0; fi
    tc_now
    end=$(( TC_NOW + 400000 ))
    while :; do
        tc_now
        (( TC_NOW >= end )) && break
        if (( FV_VIDEO_RESIZED )); then rsz=1; FV_VIDEO_RESIZED=0; fi
        fv.drivers.getEvent 0.05 || break
        tc_trace settle
        [[ $FV_EV_WHAT != evNothing ]] && (( STALE++ ))
    done
    if (( rsz || FV_VIDEO_RESIZED )); then fv.video.updateSize; tc_trace settle-resize; fi
}

# ---- recording ------------------------------------------------------------------
RES='' GOT='' CHARV='' RAW='' EXTRA='' NOTE='' NOISE='' STALE=0
NOISE_N=0

tc_noise() { # WHAT
    (( NOISE_N++ ))
    if (( NOISE_N <= 8 )); then NOISE+="${NOISE:+,}$1"; fi
}

tc_record() { # INDEX
    local i=$1 g=${IT_GROUP[$1]} cq tl
    tc_q "$CHARV"; cq=$TC_QV
    tl=''
    if (( STALE > 0 )); then tl+=$'\t'"stale=$STALE"; fi
    if [[ -n $NOISE ]]; then
        tl+=$'\t'"noise=$NOISE"
        if (( NOISE_N > 8 )); then tl+="(+$(( NOISE_N - 8 )) more)"; fi
    fi
    if [[ -n $NOTE ]]; then tl+=$'\t'"note=$NOTE"; fi
    tc_log "$g"$'\t'"${IT_ID[$i]}"$'\t'"${IT_EXP[$i]}"$'\t'"${GOT:--}"$'\t'"$RES"$'\t'"char=$cq"$'\t'"raw=${RAW:--}"$'\t'"extra=${EXTRA:--}$tl"
    TC_CNT[$g/$RES]=$(( ${TC_CNT[$g/$RES]:-0} + 1 ))
    TC_GN[$g]=1
    TC_LAST="$RES  ${IT_ID[$i]}${GOT:+ -> $GOT}"
}

# ---- one key item -----------------------------------------------------------------
# tc_key_match EXPECTED-SPEC NAME CHAR: rc 0 when NAME/CHAR is one of the alternatives
tc_key_match() {
    local alt a name chr
    IFS='|' read -ra alt <<< "$1"
    for a in "${alt[@]}"; do
        name=${a%%:*}
        if [[ $a == *:* ]]; then
            chr=${a#*:}
            if [[ $2 == "$name" && $3 == "$chr" ]]; then
                if [[ $a != "${alt[0]}" ]]; then NOTE='accepted-alternative'; fi
                return 0
            fi
        elif [[ $2 == "$name" ]]; then
            if [[ $a != "${alt[0]}" ]]; then NOTE='accepted-alternative'; fi
            return 0
        fi
    done
    return 1
}

# tc_raw_of_key: TC_RAW = the raw bytes of the last key as %q (NUL -> "NUL len=1")
tc_raw_of_key() {
    if [[ -z $FV_KEY_SEQ && ${FV_KEY_LEN:-0} == 1 ]]; then
        TC_RAW='NUL len=1'
    else
        tc_q "$FV_KEY_SEQ"; TC_RAW=$TC_QV
        if [[ -z $FV_KEY_SEQ ]]; then TC_RAW="''"; fi
    fi
}

tc_run_key() {
    local i=$1 rc left last_left=-1 end n=0 nbytes=0 first=0 rawq
    tc_now
    local deadline=$(( TC_NOW + TC_TIMEOUT_US ))
    GOT='' CHARV='' RAW='' EXTRA=''
    while :; do
        tc_now
        (( TC_NOW >= deadline )) && break
        left=$(( (deadline - TC_NOW + 999999) / 1000000 ))
        if (( left != last_left )); then last_left=$left; tc_countdown "$left"; fi
        fv.drivers.getEvent "$TC_POLL"; rc=$?; tc_trace wait
        if (( rc == 1 )); then TC_EOF=1; break; fi
        if (( rc == 2 )); then NOTE='getEvent-rc2'; break; fi
        case $FV_EV_WHAT in
            evKeyDown) first=1; break ;;
            evNothing) : ;;
            evCommand) tc_noise resize ;;
            evMouse*) tc_noise mouse ;;
        esac
    done
    if (( first )); then
        GOT=$FV_EV_KEY CHARV=$FV_EV_CHAR
        tc_raw_of_key; RAW=$TC_RAW
        # more keys within 0.2 s are recorded as extra (at most 8 events / 32 bytes)
        tc_now
        end=$(( TC_NOW + TC_EXTRA_US ))
        while :; do
            tc_now
            (( TC_NOW >= end )) && break
            fv.drivers.getEvent "$TC_POLL"; rc=$?; tc_trace wait
            (( rc == 1 )) && { TC_EOF=1; break; }
            (( rc == 2 )) && break
            case $FV_EV_WHAT in
                evKeyDown)
                    (( n++ ))
                    nbytes=$(( nbytes + ${FV_KEY_LEN:-0} ))
                    if (( n <= 8 && nbytes <= 32 )); then
                        tc_raw_of_key; rawq=$TC_RAW
                        EXTRA+="${EXTRA:+ }$FV_EV_KEY=${rawq// /_}"
                    fi
                    ;;
                evNothing) : ;;
                evCommand) tc_noise resize ;;
                evMouse*) tc_noise mouse ;;
            esac
        done
        if (( n > 0 )); then
            if [[ -z $EXTRA ]]; then EXTRA="(+$n)"; fi
            if (( n > 8 || nbytes > 32 )); then EXTRA+=" (total $n events, $nbytes bytes)"; fi
        fi
    fi
    # judge
    local exp=${IT_EXP[$i]}
    if (( ! first )); then
        RES=NONE
    elif [[ $exp == none ]]; then
        RES=INFO
    elif tc_key_match "$exp" "$GOT" "$CHARV"; then
        RES=OK
    else
        RES=DIFF
    fi
}

# ---- one mouse item -----------------------------------------------------------------
tc_mouse_fields() { # TAG: TC_MF = "TAG(b=,x=,y=,m=)" of the current mouse event
    printf -v TC_MF '%s(b=%s,x=%s,y=%s,m=%s)' "$1" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_MODS"
}

tc_run_mouse() {
    local i=$1 mk=${IT_MK[$1]} wb=${IT_B[$1]} wm=${IT_M[$1]}
    local wx=${IT_X[$1]} wy=${IT_Y[$1]} wx2=${IT_X2[$1]} wy2=${IT_Y2[$1]}
    local rc left last_left=-1 downs=0 ups=0 moves=0 done_=0 target=0 ext
    local d_b='' d_x='' d_y='' d_m='' u_x='' u_y='' w_dir='' w_x='' w_y='' w_m='' dflag=0 tflag=0
    local g_down='' g_up='' g_wheel='' r_down='' r_up='' r_wheel='' gap='' t_prev=0 t_this
    local deadline
    tc_now
    deadline=$(( TC_NOW + TC_TIMEOUT_US ))
    GOT='' CHARV='' RAW='' EXTRA=''
    while (( ! done_ )); do
        tc_now
        (( TC_NOW >= deadline )) && break
        left=$(( (deadline - TC_NOW + 999999) / 1000000 ))
        if (( left != last_left )); then last_left=$left; tc_countdown "$left"; fi
        fv.drivers.getEvent "$TC_POLL"; rc=$?; tc_trace wait
        if (( rc == 1 )); then TC_EOF=1; break; fi
        if (( rc == 2 )); then NOTE='getEvent-rc2'; break; fi
        case $FV_EV_WHAT in
            evMouseDown)
                t_this=$TC_NOW
                (( downs++ ))
                tc_q "$FV_KEY_SEQ"
                if (( downs == 1 )); then
                    d_b=$FV_EV_MOUSE_BUTTONS d_x=$FV_EV_MOUSE_X d_y=$FV_EV_MOUSE_Y d_m=$FV_EV_MOUSE_MODS
                    tc_mouse_fields down; g_down=$TC_MF; r_down=$TC_QV
                    ext=$(( TC_NOW + 5000000 ))
                    if (( deadline < ext )); then deadline=$ext; fi
                elif [[ $mk == dbl || $mk == tri ]]; then
                    if (( t_prev > 0 )); then gap="$(( (t_this - t_prev) / 1000 ))ms"; fi
                    if [[ $mk == dbl && $FV_EV_MOUSE_DOUBLE == 1 && $dflag == 0 ]] ||
                       [[ $mk == tri && $FV_EV_MOUSE_TRIPLE == 1 && $tflag == 0 ]]; then
                        if [[ $mk == dbl ]]; then dflag=1; else tflag=1; fi
                        d_b=$FV_EV_MOUSE_BUTTONS d_x=$FV_EV_MOUSE_X d_y=$FV_EV_MOUSE_Y d_m=$FV_EV_MOUSE_MODS
                        tc_mouse_fields down; g_down=$TC_MF; r_down=$TC_QV
                        if [[ $mk == dbl ]]; then g_down+="+double"; else g_down+="+triple"; fi
                        ext=$(( TC_NOW + 500000 ))
                        if (( deadline > ext )); then deadline=$ext; fi
                    elif [[ $mk == tri && $FV_EV_MOUSE_DOUBLE == 1 ]]; then
                        : # the second click of a triple: a double, as it should be
                    else
                        tc_noise "extra-down(${FV_EV_MOUSE_X},${FV_EV_MOUSE_Y},dbl=${FV_EV_MOUSE_DOUBLE},tri=${FV_EV_MOUSE_TRIPLE})"
                    fi
                else
                    tc_noise "down2"
                fi
                t_prev=$t_this
                ;;
            evMouseUp)
                if (( downs > 0 && ups == 0 )); then
                    (( ups++ ))
                    u_x=$FV_EV_MOUSE_X u_y=$FV_EV_MOUSE_Y
                    tc_mouse_fields up; g_up=$TC_MF; tc_q "$FV_KEY_SEQ"; r_up=$TC_QV
                    if [[ $mk == click || $mk == drag ]]; then done_=1; fi
                    if [[ $mk == dbl && $dflag == 1 ]] || [[ $mk == tri && $tflag == 1 ]]; then done_=1; fi
                else
                    tc_noise up
                fi
                ;;
            evMouseMove)
                if (( downs > 0 && ups == 0 )); then (( moves++ )); else tc_noise move; fi
                ;;
            evMouseWheel)
                if [[ $mk == wheel && -z $g_wheel ]]; then
                    w_dir=$FV_EV_WHEEL w_x=$FV_EV_MOUSE_X w_y=$FV_EV_MOUSE_Y w_m=$FV_EV_MOUSE_MODS
                    g_wheel="wheel(w=$w_dir,x=$w_x,y=$w_y,m=$w_m)"; tc_q "$FV_KEY_SEQ"; r_wheel=$TC_QV
                    ext=$(( TC_NOW + TC_EXTRA_US ))
                    if (( deadline > ext )); then deadline=$ext; fi
                elif [[ $mk == wheel ]]; then
                    (( target++ ))
                else
                    tc_noise wheel
                fi
                ;;
            evKeyDown) tc_noise "key:$FV_EV_KEY" ;;
            evCommand) tc_noise resize ;;
            evNothing) : ;;
        esac
    done
    if (( target > 0 )); then EXTRA="(+$target wheel events)"; fi
    # the cells really received, for the sync file (the driver calibrates on them)
    TC_CELL='' TC_CELL2=''
    if [[ $mk == wheel ]]; then
        if [[ -n $g_wheel ]]; then TC_CELL="$w_x $w_y"; fi
    elif (( downs > 0 )); then
        TC_CELL="$d_x $d_y"
        if [[ $mk == drag && -n $g_up ]]; then TC_CELL2="$u_x $u_y"; fi
    fi
    # judge
    RES=NONE
    case $mk in
        wheel)
            if [[ -n $g_wheel ]]; then
                GOT=$g_wheel RAW=$r_wheel
                if [[ $w_dir == "$wb" && $w_x == "$wx" && $w_y == "$wy" ]]; then RES=OK
                else RES=DIFF; NOTE="off(dx=$(( w_x - wx )),dy=$(( w_y - wy )))"; fi
            fi
            ;;
        *)
            if (( downs > 0 )); then
                GOT=$g_down RAW="down=$r_down"
                if [[ -n $g_up ]]; then GOT+=" $g_up"; RAW+=" up=$r_up"; fi
                if [[ $mk == drag ]]; then GOT+=" moves=$moves"; fi
                [[ -n $gap ]] && NOTE="gap=$gap"
                local ok=1
                [[ $d_x == "$wx" && $d_y == "$wy" ]] || { ok=0; NOTE+="${NOTE:+ }off(dx=$(( d_x - wx )),dy=$(( d_y - wy )))"; }
                [[ $d_b == "$wb" ]] || ok=0
                [[ $d_m == "$wm" ]] || ok=0
                case $mk in
                    click) [[ -n $g_up ]] || { ok=0; NOTE+="${NOTE:+ }no-release"; } ;;
                    dbl) (( dflag )) || { ok=0; NOTE+="${NOTE:+ }no-double-flag(downs=$downs)"; } ;;
                    tri) (( tflag )) || { ok=0; NOTE+="${NOTE:+ }no-triple-flag(downs=$downs)"; } ;;
                    drag)
                        [[ -n $g_up ]] || { ok=0; NOTE+="${NOTE:+ }no-release"; }
                        if [[ -n $g_up ]]; then
                            [[ $u_x == "$wx2" && $u_y == "$wy2" ]] || { ok=0; NOTE+="${NOTE:+ }end-off(dx=$(( u_x - wx2 )),dy=$(( u_y - wy2 )))"; }
                            (( moves > 0 )) || { ok=0; NOTE+="${NOTE:+ }no-moves"; }
                        fi
                        ;;
                esac
                if (( ok )); then RES=OK; else RES=DIFF; fi
            fi
            ;;
    esac
}

# ---- the resize item -----------------------------------------------------------------
tc_run_resize() {
    local i=$1 rc left last_left=-1 n=0 ow=$FV_SCREEN_W oh=$FV_SCREEN_H quiet nw='' nh=''
    local deadline cap
    tc_now
    deadline=$(( TC_NOW + TC_TIMEOUT_US ))
    cap=$(( TC_NOW + TC_TIMEOUT_US + 5000000 ))    # a resize storm cannot hold the item longer
    GOT='' CHARV='' RAW='' EXTRA=''
    while :; do
        tc_now
        (( TC_NOW >= deadline )) && break
        left=$(( (deadline - TC_NOW + 999999) / 1000000 ))
        if (( left != last_left )); then last_left=$left; tc_countdown "$left"; fi
        fv.drivers.getEvent "$TC_POLL"; rc=$?; tc_trace wait
        if (( rc == 1 )); then TC_EOF=1; break; fi
        if (( rc == 2 )); then break; fi
        case $FV_EV_WHAT in
            evCommand)
                if [[ $FV_EV_COMMAND == cmResizeApp ]]; then
                    (( n++ )); nw=$FV_EV_ID nh=$FV_EV_INFO
                    # a drag sends many sizes: wait until 0.6 s pass without a new one
                    tc_now; quiet=$(( TC_NOW + 600000 ))
                    deadline=$(( quiet < cap ? quiet : cap ))
                fi
                ;;
            evKeyDown) tc_noise "key:$FV_EV_KEY" ;;
            evMouse*) tc_noise mouse ;;
        esac
    done
    TC_RSZ=''
    if (( n > 0 )); then
        TC_RSZ="$nw $nh"
        GOT="cmResizeApp ${ow}x${oh}->${nw}x${nh}"
        EXTRA="(events: $n)"
        if [[ $nw == "$ow" && $nh == "$oh" ]]; then RES=DIFF; NOTE='same-size'; else RES=OK; fi
    else
        RES=NONE
    fi
}

# ---- the log header ---------------------------------------------------------------------
tc_header() {
    local line
    tc_log "# fv_termcheck log"
    tc_log "# termcheck version: $TERMCHECK_VERSION"
    tc_log "# date: $TC_DATE"
    tc_log "# commits: kbool=$TC_GIT_KBOOL kcl=$TC_GIT_KCL"
    tc_log "# TERM=${TERM-<unset>} COLORTERM=${COLORTERM-<unset>}"
    tc_log "# TERM_PROGRAM=${TERM_PROGRAM-<unset>} TERM_PROGRAM_VERSION=${TERM_PROGRAM_VERSION-<unset>}"
    tc_log "# WT_SESSION: $([[ -n ${WT_SESSION-} ]] && echo set || echo 'not set')"
    tc_log "# MSYSTEM=${MSYSTEM-<unset>} OSTYPE=${OSTYPE-<unset>} WSL_DISTRO_NAME=${WSL_DISTRO_NAME-<unset>}"
    if [[ -n $TC_LABEL ]]; then tc_log "# label: $TC_LABEL (TERMCHECK_LABEL)"; fi
    tc_log "# ssh: $([[ -n ${SSH_CONNECTION-} ]] && echo yes || echo no)"
    tc_log "# uname: $TC_UNAME"
    tc_log "# /proc/version: ${TC_PROCVER:-<none>}"
    tc_log "# bash: $BASH_VERSION"
    tc_log "# locale: LANG=${LANG-<unset>} LC_ALL=${LC_ALL-<unset>} LC_CTYPE=${LC_CTYPE-<unset>}"
    tc_log "# FV_ESC_TIMEOUT: ${FV_ESC_TIMEOUT:-<unset, default 0.02>}"
    tc_log "# screen: ${FV_SCREEN_W}x${FV_SCREEN_H}"
    tc_log "# item timeout: $TC_TIMEOUT_TXT s   groups: ${TC_ONLY:-all}   dangerous: $TC_DANGER   items: $TC_N"
    if (( TC_FEED )); then tc_log "# mode: feed ($TC_FEEDFILE), no terminal"; fi
    if [[ -n $tc_hdr_stty ]]; then
        while IFS= read -r line; do tc_log "# stty: $line"; done <<< "$tc_hdr_stty"
    else
        tc_log "# stty: <not available>"
    fi
    tc_log "# columns: group  item  expected  got  result  char=  raw=  extra=  [stale= noise= note=]   (TAB separated)"
}

# ---- main ------------------------------------------------------------------------------------
tc_build_items
if (( TC_N == 0 )); then
    echo "termcheck: no items selected" >&2
    if (( ! TC_FEED )); then fv.video.doneVideo; fi
    exit 2
fi

tc_name=fv_termcheck_${TC_STAMP}_${TC_GUESS}
TC_LOG=$TC_OUT/$tc_name.log
tc_n=1
while [[ -e $TC_LOG ]]; do
    (( tc_n++ ))
    TC_LOG=$TC_OUT/${tc_name}-$tc_n.log
done
: > "$TC_LOG" || { TC_LOG=''; echo "termcheck: cannot write the log" >&2; (( TC_FEED )) || fv.video.doneVideo; exit 2; }
tc_header

# tc_feed_next INDEX: feed mode, queue the next line of the feed file as the input
tc_feed_next() {
    STALE=0 TC_EOF=0
    tc_line=''
    if [[ -n $TC_FEEDFD ]]; then IFS= read -r -u "$TC_FEEDFD" tc_line || tc_line=''; fi
    printf -v tc_bytes '%b' "$tc_line"
    fv.keyboard.flush
    fv.drivers.doneEvents
    fv.drivers.clearEvent
    if [[ -n $tc_bytes ]]; then fv.keyboard.feed "$tc_bytes"; fi
    tc_log "# prompt $(( $1 + 1 ))/$TC_N [${IT_GROUP[$1]}] ${IT_HUMAN[$1]}"
}

for (( tc_i = 0; tc_i < TC_N; tc_i++ )); do
    TC_CUR=${IT_GROUP[tc_i]}/${IT_ID[tc_i]}
    RES='' GOT='' CHARV='' RAW='' EXTRA='' NOTE='' NOISE='' NOISE_N=0
    # input of this item: the feed line is queued (feed mode)
    if (( TC_FEED )); then tc_feed_next "$tc_i"; fi
    # sync mode: an item the driver asked to skip is logged without waiting
    if [[ -n ${TC_SKIP[${IT_ID[tc_i]}]:-} ]]; then
        tc_k=${TC_SKIP[${IT_ID[tc_i]}]}
        RES=NONE NOTE=skipped-by-driver TC_CELL='' TC_CELL2='' TC_RSZ=''
        if [[ $tc_k == - ]]; then tc_k=''; fi
        if [[ -n $tc_k ]]; then NOTE+=":$tc_k"; fi
        tc_record "$tc_i"
        tc_sync "done ${IT_ID[tc_i]} NONE skipped${tc_k:+ $tc_k}"
        STALE=0
        continue
    fi
    tc_attempt=1 tc_first=''
    while :; do
        # draw the prompt, drop pending input (STALE), then announce "ready" and wait
        case ${IT_KIND[tc_i]} in
            key) tc_draw_key "$tc_i" ;;
            mouse) tc_draw_mouse "$tc_i" ;;
            resize) tc_draw_resize "$tc_i" ;;
        esac
        tc_drain
        tc_sync_ready "$tc_i"
        case ${IT_KIND[tc_i]} in
            key) tc_run_key "$tc_i" ;;
            mouse) tc_run_mouse "$tc_i" ;;
            resize) tc_run_resize "$tc_i" ;;
        esac
        # sync mode: a mouse item that landed on the wrong cell is asked once more,
        # so the driver can calibrate; only the second attempt is logged
        if [[ -n $TC_SYNC && ${IT_KIND[tc_i]} == mouse && $tc_attempt == 1 && $RES == DIFF && $NOTE == *'off('* ]] && (( ! TC_EOF )); then
            tc_first="cell $TC_CELL${TC_CELL2:+ cell2 $TC_CELL2}"
            tc_sync "retry ${IT_ID[tc_i]} DIFF $tc_first"
            tc_attempt=2
            tc_settle
            RES='' GOT='' CHARV='' RAW='' EXTRA='' NOTE='' NOISE='' NOISE_N=0 STALE=0
            if (( TC_FEED )); then tc_feed_next "$tc_i"; fi
            continue
        fi
        break
    done
    if [[ -n $tc_first ]]; then NOTE+="${NOTE:+ }retried(first:${tc_first// /_})"; fi
    tc_record "$tc_i"
    tc_sync_done "$tc_i"
    STALE=0
    if (( TC_EOF && ! TC_FEED )); then
        tc_log "eof: terminal input ended"
        exit 1
    fi
    tc_put $'\e[22;1H\e[2K'"last: $TC_LAST"
    tc_settle
done

# ---- the finish prompt --------------------------------------------------------------------------
TC_CUR='finish'
TC_FINISH=1
if (( TC_FEED )); then
    tc_log "# finish: feed ends here"
    exit 0
fi
TC_S=$'\e[0m\e[2J\e[H'
tc_at 1 2 "termcheck  all items done"
tc_at 8 4 "Press Ctrl+C to finish."
tc_at 10 4 "(the log file is written already; Ctrl+C puts the terminal back and prints its name)"
tc_at 22 2 "last: $TC_LAST"
tc_put "$TC_S"
tc_drain
tc_sync finish-wait
tc_now
tc_end=$(( TC_NOW + 120000000 ))
tc_why=timeout
while :; do
    tc_now
    (( TC_NOW >= tc_end )) && break
    if ! fv.drivers.getEvent 0.2; then tc_why=eof; break; fi
    tc_trace finish
    if [[ $FV_EV_WHAT == evKeyDown ]]; then
        tc_put $'\e[12;4H\e[2K'"(that was ${FV_EV_KEY}; press Ctrl+C to finish)"
    fi
done
tc_log "finish: $tc_why"
fv.video.doneVideo
exit 0
