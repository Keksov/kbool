#!/usr/bin/env bash
# selftest.sh -- checks termcheck.sh without a person at the keyboard.
#
#     bash tools/termcheck/tests/selftest.sh
#
# Part 1 (--feed): crafted byte files; the item, compare and log logic.
# Part 2 (pty): termcheck.sh on a real pseudo-terminal under util-linux
# script(1), keys typed by a feeder; needs script(1) from the same runtime
# (MSYS2, Cygwin, Linux). Where there is none (Git-bash) the pty cases print
# SKIP, not FAIL. termcheck is never run against the terminal that started
# this script: the pty cases run inside script(1) only, and --feed cases open
# no terminal at all.
# Exit 0 = all PASS (or SKIP), 1 = a FAIL.

SELF=${BASH_SOURCE[0]}
if [[ $SELF == */* ]]; then HERE=${SELF%/*}; else HERE=.; fi
HERE=$(cd "$HERE" && pwd) || exit 1
TC=$HERE/../termcheck.sh
KBOOL_ROOT=$(cd "$HERE/../../.." && pwd) || exit 1

# scratch under TERMCHECK_SELFTEST_TMP, else a fresh mktemp folder
if [[ -n ${TERMCHECK_SELFTEST_TMP:-} ]]; then
    TMP=$TERMCHECK_SELFTEST_TMP
    mkdir -p "$TMP" || exit 1
else
    TMP=$(mktemp -d) || exit 1
fi
PASS=0 FAIL=0 SKIP=0
DETAIL=''

cleanup() {
    if [[ -z ${TERMCHECK_SELFTEST_TMP:-} && -n $TMP && -d $TMP ]]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

pass() { PASS=$(( PASS + 1 )); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); printf 'FAIL: %s%s\n' "$1" "${2:+  -- $2}"; }
skip() { SKIP=$(( SKIP + 1 )); printf 'SKIP: %s\n' "$1"; }

# predicates; ok TITLE PREDICATE ARGS... passes when the predicate is true
has() { [[ $1 == *"$2"* ]]; }
not() { ! "$@"; }
eq2() { [[ $1 == "$2" || $1 == "$3" ]]; }
eq() { [[ $1 == "$2" ]]; }
re() { [[ $1 =~ $2 ]]; }
ok() {
    local t=$1
    shift
    if "$@"; then pass "$t"; else fail "$t" "$DETAIL"; fi
    DETAIL=''
}

# ---- part 1: --feed ----------------------------------------------------------
CASE=0
# feed ARGS... -- LINES... : run termcheck --feed on the lines; OUT, RC, LOG (path), LOGTXT
feed() {
    local args=() lines=() d f
    while [[ $# -gt 0 && $1 != -- ]]; do args+=("$1"); shift; done
    shift
    lines=("$@")
    CASE=$(( CASE + 1 ))
    d=$TMP/feed$CASE
    mkdir -p "$d"
    if (( ${#lines[@]} )); then printf '%s\n' "${lines[@]}" > "$d/feed.txt"; else : > "$d/feed.txt"; fi
    OUT=$(cd "$d" && timeout -k 5 60 bash "$TC" --feed feed.txt --out "$d" "${args[@]}" 2>&1)
    RC=$?
    LOG=''
    for f in "$d"/fv_termcheck_*.log; do [[ -e $f ]] && LOG=$f; done
    LOGTXT=''
    if [[ -n $LOG ]]; then LOGTXT=$(<"$LOG"); fi
}

# row ITEM : ROW = the log line of the item (group<TAB>item<TAB>...); rc 1 = none
row() {
    local l
    ROW=''
    while IFS= read -r l; do
        case $l in
            *$'\t'"$1"$'\t'*) ROW=$l; return 0 ;;
        esac
    done <<< "$LOGTXT"
    return 1
}

# field N : FIELD = the Nth tab-separated column of ROW (1-based)
field() {
    local IFS=$'\t' a
    read -ra a <<< "$ROW"
    FIELD=${a[$1 - 1]-}
}

# rowfield ITEM N : row + field
rowfield() { row "$1"; field "$2"; }

# want ITEM RESULT GOT-SUBSTRING TITLE
want() {
    local bad=0
    if ! row "$1"; then fail "$4" "no log line for $1"; return; fi
    field 5; [[ $FIELD == "$2" ]] || bad=1
    field 4; [[ $FIELD == *"$3"* ]] || bad=1
    DETAIL="row: $ROW"
    ok "$4" eq "$bad" 0
}

printf '== part 1: --feed ==\n'

# help and argument errors
OUT=$(bash "$TC" --help 2>&1); RC=$?
ok "--help: rc 0" eq "$RC" 0
ok "--help: prints the usage" has "$OUT" 'Usage:'
OUT=$(bash "$TC" --bogus 2>&1); RC=$?
ok "unknown option: rc 2" eq "$RC" 2
OUT=$(bash "$TC" --only nonsense 2>&1); RC=$?
ok "unknown group: rc 2" eq "$RC" 2
ok "unknown group: the groups are named" has "$OUT" arrows
OUT=$(bash "$TC" --timeout abc 2>&1); RC=$?
ok "--timeout abc: rc 2" eq "$RC" 2
OUT=$(bash "$TC" --timeout 1.1234567 2>&1); RC=$?
ok "--timeout with 7 decimals: rc 2" eq "$RC" 2
OUT=$(bash "$TC" --timeout 0 2>&1); RC=$?
ok "--timeout 0: rc 2" eq "$RC" 2
OUT=$(bash "$TC" --out "$TMP/does-not-exist" --feed /dev/null 2>&1); RC=$?
ok "--out into a missing folder: rc 2" eq "$RC" 2
OUT=$(bash "$TC" --feed "$TMP/no-such-feed" 2>&1); RC=$?
ok "--feed with a missing file: rc 2" eq "$RC" 2

# no terminal: refuse, rc 2, nothing drawn, no log
d=$TMP/noterm
mkdir -p "$d"
OUT=$(cd "$d" && FV_TTY=/nonexistent timeout -k 5 30 bash "$TC" --only arrows 2>&1 < /dev/null); RC=$?
DETAIL="out=$OUT"
ok "no terminal (FV_TTY=/nonexistent): rc 2" eq "$RC" 2
ok "no terminal: the message says so" has "$OUT" 'no terminal'
ok "no terminal: no escape byte was printed" not has "$OUT" $'\e'
n=0; for f in "$d"/*; do [[ -e $f ]] && n=$(( n + 1 )); done
ok "no terminal: no log file was left" eq "$n" 0
if command -v setsid >/dev/null 2>&1; then
    OUT=$(cd "$d" && timeout -k 5 30 setsid bash "$TC" --only arrows 2>&1 < /dev/null); RC=$?
    DETAIL="out=$OUT"
    ok "no controlling terminal (setsid): rc 2" eq "$RC" 2
else
    skip "no controlling terminal (setsid): setsid is not installed here"
fi

# OK / DIFF / NONE / extra, arrows: Up, Shift+Up, Ctrl+Up, Alt+Up ...
feed --only arrows -- $'\\e[A' $'\\e[1;2B' '' $'\\e[1;3A\\e[1;3B'
DETAIL="$OUT"
ok "feed run: rc 0" eq "$RC" 0
want Up OK kbUp "arrows: plain Up is OK"
want Shift+Up DIFF kbShiftDown "arrows: Shift+Down instead of Shift+Up is DIFF and keeps the decoded name"
want Ctrl+Up NONE "-" "arrows: an empty line is NONE"
want Alt+Up OK kbAltUp "arrows: Alt+Up is OK"
rowfield Alt+Up 8
DETAIL=$FIELD
ok "arrows: a second key within the window is extra" has "$FIELD" 'kbAltDown'
rowfield Up 7
DETAIL=$FIELD
ok "raw bytes are logged byte-exact (printf %q)" eq "$FIELD" "raw=\$'\\E[A'"
want Down NONE "-" "arrows: lines missing at the end of the feed are NONE"
ok "log: 'run complete'" has "$LOGTXT" 'run complete'
ok "log: the arrows summary line" has "$LOGTXT" 'summary  arrows  OK=2  DIFF=1  NONE=13'
ok "stdout names the log path" has "$OUT" 'log written to'

# header fields
for h in '# termcheck version:' '# date:' '# commits: kbool=' ' kcl=' '# TERM=' '# TERM_PROGRAM=' '# WT_SESSION:' \
         '# MSYSTEM=' ' OSTYPE=' '# uname:' '# /proc/version:' '# bash: ' '# locale:' '# stty:' \
         '# FV_ESC_TIMEOUT:' '# screen: 80x24' '# columns:'; do
    ok "header has '$h'" has "$LOGTXT" "$h"
done

# special keys: Ctrl+Backspace is INFO and keeps what came
feed --only special -- $'\\t' $'\\e[Z' $'\\r' $'\\e' $'\\x7f' $'\\x08' $'\\e\\x7f' ''
want Tab OK kbTab "special: Tab"
want Shift+Tab OK kbShiftTab "special: Shift+Tab"
want Enter OK kbEnter "special: Enter"
want Esc OK kbEsc "special: a lone Esc is kbEsc"
want Backspace OK kbBack "special: DEL is Backspace"
want Ctrl+Backspace INFO kbBack "special: Ctrl+Backspace is INFO and logs what came (0x08 = kbBack)"
rowfield Ctrl+Backspace 7
DETAIL=$FIELD
ok "special: Ctrl+Backspace raw is logged" re "$FIELD" '\\(b|010)'
want Alt+Backspace OK kbAltBack "special: Alt+Backspace"
want Ctrl+Space NONE "-" "special: Ctrl+Space with nothing is NONE"

# chars and keypad
ZHE=$'\xd0\xb6'
feed --only chars,keypad -- $'\\ex' $'\\ex' $'\\x01' $'\\x1a' $'\\x1c' $'\\xd0\\xb6' ' ' $'\\e[E' $'5' $'\\r'
want Alt+X OK kbAltX "chars: Alt+x (char x)"
want Alt+Shift+X DIFF kbAltX "chars: Alt+Shift+X given a lower-case x is DIFF (the char column is compared)"
want Ctrl+A OK kbCtrlA "chars: Ctrl+A"
want Ctrl+Z OK kbCtrlZ "chars: Ctrl+Z"
want 'Ctrl+\' OK kbCtrlBackslash "chars: Ctrl+backslash"
want zhe OK kbChar "chars: the letter zhe is kbChar"
rowfield zhe 6
DETAIL=$FIELD
ok "chars: the char column holds zhe" eq2 "$FIELD" "char=$ZHE" "char=\$'\\320\\266'"
want Space OK kbChar "chars: Space is kbChar"
want Keypad5-NumLockOff OK kbCenter "keypad: 5 with NumLock off, ESC [ E"
want Keypad5-NumLockOn OK kbChar "keypad: 5 with NumLock on is a character"
want KeypadEnter OK kbEnter "keypad: Enter"
feed --only chars,keypad -- $'\\eX' '' '' '' '' '' '' '5'
want Alt+X DIFF kbAltX "chars: Alt+X given a capital X is DIFF"
want Alt+Shift+X NONE "-" "chars: nothing for Alt+Shift+X"
want Keypad5-NumLockOff OK kbChar "keypad: a plain 5 is accepted for NumLock off"
row Keypad5-NumLockOff
DETAIL=$ROW
ok "keypad: the accepted alternative is noted" has "$ROW" 'accepted-alternative'

# extra keys are capped
feed --only arrows -- $'\\e[Aabcdefghijklmnop'
rowfield Up 8
DETAIL=$FIELD
ok "extra: the total is counted" has "$FIELD" 'total 16 events'
n=0; for w in $FIELD; do n=$(( n + 1 )); done
ok "extra: 8 entries plus the total note" eq "$n" 13

# mouse
feed --only mouse -- \
    $'\\e[<0;13;7M\\e[<0;13;7m' \
    $'\\e[<2;41;9M\\e[<2;41;9m' \
    $'\\e[<1;62;10M\\e[<1;62;10m' \
    $'\\e[<64;21;13M' \
    $'\\e[<65;51;15M' \
    $'\\e[<0;11;17M\\e[<32;30;17M\\e[<32;40;18M\\e[<0;61;19m' \
    $'\\e[<0;31;7M\\e[<0;31;7m\\e[<0;31;7M\\e[<0;31;7m' \
    $'\\e[<0;46;10M\\e[<0;46;10m\\e[<0;46;10M\\e[<0;46;10m\\e[<0;46;10M\\e[<0;46;10m' \
    $'\\e[<16;16;12M\\e[<16;16;12m' \
    ''
DETAIL=$OUT
ok "mouse feed run: rc 0" eq "$RC" 0
want Click-Left OK "down(b=1,x=12,y=6,m=0) up(b=0,x=12,y=6,m=0)" "mouse: left click on the marker is OK"
want Click-Right OK "down(b=2,x=40,y=8" "mouse: right click is OK (mask 2)"
want Click-Middle DIFF "x=61,y=9" "mouse: a click one cell off is DIFF"
row Click-Middle
DETAIL=$ROW
ok "mouse: the offset is noted" has "$ROW" 'off(dx=1,dy=-1)'
want Wheel-Up OK "wheel(w=1,x=20,y=12" "mouse: wheel up"
want Wheel-Down OK "wheel(w=2,x=50,y=14" "mouse: wheel down"
want Drag OK "moves=2" "mouse: drag from A to B with 2 moves"
want Double-Click OK "+double" "mouse: double click"
want Triple-Click OK "+triple" "mouse: triple click"
want Ctrl+Click OK "m=4" "mouse: Ctrl+click carries the modifier"
want Shift+Click NONE "-" "mouse: Shift+click grabbed by the terminal is NONE"
ok "mouse: no far-right item at 80 columns" not row Click-Far-Right
row Click-Left
DETAIL=$ROW
ok "mouse: raw reports are logged" has "$ROW" "raw=down=\$'\\E[<0;13;7M' up="

# a wrong button or a missing release is a DIFF, a key during a mouse item is noise
feed --only mouse -- $'\\e[<2;13;7M\\e[<2;13;7m' $'a\\e[<2;41;9M'
want Click-Left DIFF "down(b=2" "mouse: right button for the left-click item is DIFF"
want Click-Right DIFF "down(b=2,x=40,y=8,m=0)" "mouse: a press without a release is DIFF"
row Click-Right
DETAIL=$ROW
ok "mouse: no-release is noted" has "$ROW" 'no-release'
ok "mouse: a key before the click is logged as noise" has "$ROW" 'noise=key:kbChar'

# the far-right item exists on a wide screen
TERMCHECK_SCREEN_W=240 feed --only mouse -- '' '' '' '' '' '' '' '' '' '' $'\\e[<0;227;11M\\e[<0;227;11m'
want Click-Far-Right OK "x=226,y=10" "mouse: the far-right click at 0-based column 226 (SGR range)"

# resize in feed mode is NONE
feed --only resize,keypad -- '' '' ''
want Resize NONE "-" "resize: no resize event in feed mode is NONE"
ok "resize+keypad: 4 items" has "$LOGTXT" 'items: 4'

# --only and --with-dangerous count the items
feed --only fkeys -- ''
ok "fkeys: 47 items (Alt+F4 left out)" has "$LOGTXT" 'items: 47'
ok "fkeys: no Alt+F4 line by default" not row Alt+F4
feed --only fkeys --with-dangerous -- ''
ok "fkeys with --with-dangerous: 48 items" has "$LOGTXT" 'items: 48'
want Alt+F4 NONE "-" "fkeys: Alt+F4 is asked with --with-dangerous"
feed --only arrows,nav --timeout 0.25 -- ''
DETAIL=$OUT
ok "arrows+nav with --timeout 0.25: rc 0" eq "$RC" 0
ok "arrows+nav: 40 items" has "$LOGTXT" 'items: 40'
feed -- ''
n=${LOGTXT#*items: }; n=${n%%$'\n'*}
DETAIL="items: $n"
ok "all groups: the item count is 100..140 ($n)" re "$n" '^(1[0-3][0-9]|140)$'

# file name: terminal guess, sanitized
d=$TMP/names
mkdir -p "$d"
printf '\n' > "$d/f.txt"
( cd "$d" && WT_SESSION=abc MSYSTEM='MING W/64' bash "$TC" --feed f.txt --only resize >/dev/null 2>&1 )
f=''; for x in "$d"/fv_termcheck_*_WT-*.log; do [[ -e $x ]] && f=${x##*/}; done
DETAIL=$f
ok "file name: WT-<MSYSTEM> sanitized" re "$f" '^fv_termcheck_[0-9]{8}-[0-9]{6}_WT-MING_W_64\.log$'
( cd "$d" && env -u WT_SESSION -u MSYSTEM TERM_PROGRAM='my term!' bash "$TC" --feed f.txt --only resize >/dev/null 2>&1 )
f=''; for x in "$d"/fv_termcheck_*_my_term_-*.log; do [[ -e $x ]] && f=${x##*/}; done
DETAIL=$f
ok "file name: TERM_PROGRAM-<OSTYPE> sanitized" re "$f" '^fv_termcheck_[0-9]{8}-[0-9]{6}_my_term_-[A-Za-z0-9._-]+\.log$'
( cd "$d" && env -u WT_SESSION -u MSYSTEM -u TERM_PROGRAM TERM=xterm-256color bash "$TC" --feed f.txt --only resize >/dev/null 2>&1 )
f=''; for x in "$d"/fv_termcheck_*_xterm-256color-*.log; do [[ -e $x ]] && f=${x##*/}; done
DETAIL=$f
ok "file name: TERM when nothing else is set" re "$f" '^fv_termcheck_[0-9]{8}-[0-9]{6}_xterm-256color-[A-Za-z0-9._-]+\.log$'

# the log has LF only
feed --only chars -- ''
n=$(tr -cd '\r' < "$LOG" | wc -c)
ok "log: no CR byte" eq "$((n + 0))" 0

# --list-items: the item table for the Windows driver (autodrive.ps1)
OUT=$(bash "$TC" --list-items 2>&1); RC=$?
ok "--list-items: rc 0" eq "$RC" 0
n=0; while IFS= read -r l; do [[ -n $l ]] && n=$(( n + 1 )); done <<< "$OUT"
DETAIL="lines: $n"
ok "--list-items: 117 items (the far-right mouse item included)" eq "$n" 117
ok "--list-items: a key line is group TAB id TAB kind TAB expected" has "$OUT" $'arrows\tShift+Up\tkey\tkbShiftUp'
ok "--list-items: a mouse line names the mouse kind" has "$OUT" $'mouse\tDrag\tmouse:drag\tb=1,m=0,down@10,16,up@60,18'
ok "--list-items: the far-right item is listed" has "$OUT" $'mouse\tClick-Far-Right\tmouse:click'
ok "--list-items: the resize line" has "$OUT" $'resize\tResize\tresize\tcmResizeApp'
ok "--list-items: no Alt+F4 by default" not has "$OUT" $'\tAlt+F4\t'
OUT=$(bash "$TC" --list-items --with-dangerous 2>&1)
ok "--list-items --with-dangerous: Alt+F4 is listed" has "$OUT" $'fkeys\tAlt+F4\tkey\tkbAltF4'
OUT=$(bash "$TC" --list-items --only keypad 2>&1)
n=0; while IFS= read -r l; do [[ -n $l ]] && n=$(( n + 1 )); done <<< "$OUT"
ok "--list-items --only keypad: 3 lines" eq "$n" 3

# sync mode (TERMCHECK_SYNC) in --feed mode: ready/done lines, cells, skip, end
SYNCF=$TMP/sync1.txt
: > "$SYNCF"
TERMCHECK_SYNC=$SYNCF TERMCHECK_NONCE=n1 TERMCHECK_SKIP='Click-Right,Wheel-Up' feed --only mouse,resize -- \
    $'\\e[<0;13;7M\\e[<0;13;7m' \
    '' \
    $'\\e[<1;62;10M\\e[<1;62;10m' \
    $'\\e[<1;61;11M\\e[<1;61;11m' \
    '' \
    $'\\e[<65;51;15M' \
    $'\\e[<0;11;17M\\e[<32;30;17M\\e[<0;61;19m'
SYNCTXT=$(<"$SYNCF")
DETAIL=$SYNCTXT
ok "sync: rc 0" eq "$RC" 0
ok "sync: ready line of a click names the target and the screen" has "$SYNCTXT" 'ready mouse Click-Left target 12 6 screen 80 24'
ok "sync: done line of a click names the received cell" has "$SYNCTXT" 'done Click-Left OK cell 12 6'
ok "sync: a cell one off asks a retry with the received cell" has "$SYNCTXT" 'retry Click-Middle DIFF cell 61 9'
ok "sync: the retry is announced with a second ready" has "$SYNCTXT" $'retry Click-Middle DIFF cell 61 9\nready mouse Click-Middle target 60 10 screen 80 24\ndone Click-Middle OK cell 60 10'
want Click-Middle OK "x=60,y=10" "sync: only the second attempt is logged"
row Click-Middle
DETAIL=$ROW
ok "sync: the log notes the first attempt" has "$ROW" 'retried(first:cell_61_9)'
ok "sync: the wheel cell is reported" has "$SYNCTXT" 'done Wheel-Down OK cell 50 14'
ok "sync: a drag has two target cells" has "$SYNCTXT" 'ready mouse Drag target 10 16 60 18 screen 80 24'
ok "sync: a drag reports both ends" has "$SYNCTXT" 'done Drag OK cell 10 16 cell2 60 18'
ok "sync: a skipped item has no ready line" not has "$SYNCTXT" 'ready mouse Click-Right'
ok "sync: a skipped item is done NONE skipped" has "$SYNCTXT" 'done Click-Right NONE skipped'
ok "sync: an item with no input is done NONE without a cell" has "$SYNCTXT" $'done Double-Click NONE\n'
ok "sync: the resize ready line has the screen" has "$SYNCTXT" 'ready resize Resize screen 80 24'
ok "sync: the last line is 'end complete 0'" re "$SYNCTXT" $'\nend complete 0$'
ok "sync: no finish-wait line in feed mode" not has "$SYNCTXT" 'finish-wait'
want Click-Right NONE "-" "sync: the skipped item is logged NONE"
row Click-Right
DETAIL=$ROW
ok "sync: the skipped item has note=skipped-by-driver" has "$ROW" 'note=skipped-by-driver'
n=0 bad=''
while IFS= read -r l; do
    case $l in
        ready*) n=$(( n + 1 )); w=${l#ready * }; w=${w%% *} ;;
        done*) x=${l#done }; x=${x%% *}
            if [[ $l != *' skipped' && $x != "$w" ]]; then bad+="$x "; fi ;;
    esac
done <<< "$SYNCTXT"
DETAIL="unpaired: $bad"
ok "sync: every done follows the ready of the same item" eq "$bad" ''
ok "sync: 10 ready lines (11 items, 2 skipped, 1 retried)" eq "$n" 10
n=$(tr -cd '\r' < "$SYNCF" | wc -c)
ok "sync: no CR byte in the sync file" eq "$((n + 0))" 0
# TERMCHECK_TRACE: one line per loop turn; TERMCHECK_LABEL names the log
TRACEF=$TMP/trace1.txt
: > "$TRACEF"
TERMCHECK_TRACE=$TRACEF TERMCHECK_LABEL='mintty git' feed --only keypad --timeout 0.3 -- $'\\e[E' '' ''
TRTXT=$(<"$TRACEF")
DETAIL="${TRTXT:0:300}"
ok "trace: wait lines with the time, the event, the resize flag and the item" re "$TRTXT" '(^|'$'\n'')[0-9]+[.,][0-9]+ wait evKeyDown:kbCenter r=0 keypad/Keypad5-NumLockOff'
ok "trace: the polls of an item with no input are traced too" has "$TRTXT" 'wait evNothing r=0 keypad/KeypadEnter'
n=$(tr -cd '\r' < "$TRACEF" | wc -c)
ok "trace: no CR byte" eq "$((n + 0))" 0
DETAIL=$LOG
ok "label: the log is named after TERMCHECK_LABEL (sanitized)" re "${LOG##*/}" '^fv_termcheck_[0-9]{8}-[0-9]{6}_mintty_git\.log$'
ok "label: the header names it" has "$LOGTXT" '# label: mintty_git (TERMCHECK_LABEL)'
TERMCHECK_TRACE=$TMP/no-such-dir/trace.txt feed --only resize -- ''
ok "trace: an unwritable trace file: rc 2" eq "$RC" 2
SYNCF=$TMP/sync4.txt
: > "$SYNCF"
TERMCHECK_SYNC=$SYNCF TERMCHECK_SKIP='Up:taken-hotkey,Down:,Left:a b!' feed --only arrows -- ''
SYNCTXT=$(<"$SYNCF")
DETAIL=$SYNCTXT
ok "sync: a skip with a reason: done ... skipped REASON" has "$SYNCTXT" $'done Up NONE skipped taken-hotkey\n'
row Up
ok "sync: the reason is in the note" has "$ROW" 'note=skipped-by-driver:taken-hotkey'
ok "sync: an empty reason still skips, with no reason" has "$SYNCTXT" $'done Down NONE skipped\n'
ok "sync: the reason is reduced to one word" has "$SYNCTXT" $'done Left NONE skipped ab\n'
SYNCF=$TMP/sync3.txt
: > "$SYNCF"
TERMCHECK_SYNC=$SYNCF feed --only mouse -- $'\\e[<0;14;7M\\e[<0;14;7m' $'\\e[<0;14;8M\\e[<0;14;8m'
SYNCTXT=$(<"$SYNCF")
DETAIL=$SYNCTXT
ok "sync: a second miss is final (done DIFF with the cell)" has "$SYNCTXT" $'retry Click-Left DIFF cell 13 6\nready mouse Click-Left target 12 6 screen 80 24\ndone Click-Left DIFF cell 13 7'
n=0; while IFS= read -r l; do [[ $l == retry* ]] && n=$(( n + 1 )); done <<< "$SYNCTXT"
ok "sync: one retry per item at most" eq "$n" 1
ok "sync: no retry for a NONE item" not has "$SYNCTXT" 'retry Click-Right'
feed --only mouse -- $'\\e[<0;14;7M\\e[<0;14;7m'
want Click-Left DIFF "x=13,y=6" "sync: no retry without TERMCHECK_SYNC (a person runs it)"
TERMCHECK_SYNC=$TMP/no-such-dir/sync.txt feed --only resize -- ''
ok "sync: an unwritable sync file: rc 2" eq "$RC" 2
ok "sync: the message names the sync file" has "$OUT" 'cannot write the sync file'
SYNCF=$TMP/sync2.txt
: > "$SYNCF"
TERMCHECK_SKIP='Up' feed --only arrows -- ''
row Up
ok "sync: TERMCHECK_SKIP without TERMCHECK_SYNC is ignored" not has "$ROW" 'skipped-by-driver'
d=$TMP/noterm2
mkdir -p "$d"
OUT=$(cd "$d" && TERMCHECK_SYNC=$SYNCF FV_TTY=/nonexistent timeout -k 5 30 bash "$TC" --only arrows 2>&1 < /dev/null); RC=$?
SYNCTXT=$(<"$SYNCF")
DETAIL="rc=$RC sync=$SYNCTXT"
ok "sync: no terminal writes 'end error 2'" eq "$SYNCTXT" 'end error 2'

# ---- part 2: a pty ---------------------------------------------------------------
printf '== part 2: pty (script(1)) ==\n'

KT_TIMEOUT=$(type -P timeout || type -P gtimeout || true)
kt_need_timeout() { [[ -n $KT_TIMEOUT ]]; }
source "$KBOOL_ROOT/kcl/fv.video/tests/fvv_pty.sh"
FVP_ROOT=$TMP/pty
mkdir -p "$FVP_ROOT"

# pty_feeder CASE ACT... : text:STR waits until the typescript holds STR (20 s),
# type:BYTES types printf-%b bytes, sleep:S waits, sig:SIG signals the child;
# at the end waits for the wrapper's done file (30 s)
pty_feeder() {
    local d=$FVP_ROOT/$1 a i ts
    shift
    for a; do
        case $a in
            text:*)
                for (( i = 0; i < 400; i++ )); do
                    ts=''
                    # script(1) buffers its typescript file until it exits; its stdout is live
                    if [[ -f $d/script.out ]]; then ts=$(LC_ALL=C tr -d '\0' < "$d/script.out"); fi
                    [[ $ts == *"${a#text:}"* ]] && break
                    sleep 0.05
                done
                (( i < 400 )) || return 1
                ;;
            type:*) printf '%b' "${a#type:}" ;;
            sleep:*) sleep "${a#sleep:}" ;;
            sig:*) kill -"${a#sig:}" "$(<"$d/pid")" ;;
        esac
    done
    fvp_wait "$d/done" 30
}

pty_run() {
    local name=$1 d=$FVP_ROOT/$1 p
    shift
    pty_feeder "$name" "$@" | SHELL=$BASH TERM=xterm-256color "$KT_TIMEOUT" -k 5 60 \
        "$FVP_SCRIPT" -qec "'$BASH' '$d/wrap.sh'" "$d/ts" > "$d/script.out" 2>&1
    for p in pid wpid; do
        if [[ -s $d/$p ]] && kill -0 "$(<"$d/$p")" 2>/dev/null; then
            kill -KILL "$(<"$d/$p")" 2>/dev/null
            printf 'killed %s\n' "$p" >> "$d/survivors"
        fi
    done
}

# pty_case NAME OPTIONS...  (the child runs termcheck.sh with OPTIONS in the case folder)
pty_case() {
    local name=$1
    shift
    fvp_case "$name" "exec '$BASH' '$TC' --out \"\$D\" $*"
}

# pty_check NAME TITLE WANT_RC : the common checks of one pty run; PTYTXT = its log
pty_check() {
    local name=$1 title=$2 wrc=$3 ts rest seq f
    local LC_ALL=C
    if fvp_restored "$name"; then pass "$title: stty equal before/after, the restore sequences in the typescript"
    else fail "$title: restore" "$REPLY"; fi
    fvp_file "$name" rc
    DETAIL="rc=$REPLY"
    ok "$title: status $wrc (written inside the pty)" eq "$REPLY" "$wrc"
    fvp_ts "$name"; ts=$REPLY
    seq=$'\e[0m\e[?7h\e[?25h\e[?1049l\e[?1006l\e[?1003l\e[?1002l\e[?1000l'
    if [[ $ts == *"$seq"* ]]; then
        rest=${ts#*"$seq"}
        DETAIL="after the restore: ${rest:0:120}"
        ok "$title: the summary text follows the restore sequences" has "$rest" 'termcheck: log written to'
    else
        fail "$title: the restore sequences are in the documented order" "not found"
    fi
    PTYLOG=''
    for f in "$FVP_ROOT/$name"/fv_termcheck_*.log; do [[ -e $f ]] && PTYLOG=$f; done
    PTYTXT=''
    if [[ -n $PTYLOG ]]; then PTYTXT=$(<"$PTYLOG"); fi
    ok "$title: a log file exists" not eq "${#PTYTXT}" 0
}

if ! fvp_detect; then
    skip "pty cases: $FVP_WHY"
else
    # keypad group: three keys, then Ctrl+C at the finish prompt
    pty_case keypad --only keypad --timeout 5
    pty_run keypad \
        'text:Press:   keypad 5 with NumLock OFF' 'type:\e[E' \
        'text:Press:   keypad 5 with NumLock ON' 'type:5' \
        'text:Press:   keypad Enter' 'type:\r' \
        'text:Press Ctrl+C to finish' 'sleep:0.3' 'type:\x03'
    pty_check keypad "pty keypad run" 130
    DETAIL=$PTYTXT
    ok "pty keypad: NumLock-off 5 is OK" has "$PTYTXT" $'\tKeypad5-NumLockOff\tkbCenter|kbChar:5\tkbCenter\tOK'
    ok "pty keypad: NumLock-on 5 is OK" has "$PTYTXT" $'\tKeypad5-NumLockOn\tkbChar:5\tkbChar\tOK'
    ok "pty keypad: keypad Enter is OK" has "$PTYTXT" $'\tKeypadEnter\tkbEnter\tkbEnter\tOK'
    ok "pty keypad: the ctrl-c line" has "$PTYTXT" 'ctrl-c: interrupt received, terminal restored by fv.video'
    ok "pty keypad: 'run complete' (Ctrl+C at the finish prompt)" has "$PTYTXT" 'run complete'
    ok "pty keypad: header has the stty dump" has "$PTYTXT" '# stty: '
    ok "pty keypad: header screen is 100x30 (set by the harness)" has "$PTYTXT" '# screen: 100x30'
    fvp_ts keypad
    ok "pty keypad: the prompts show the expected names" has "$REPLY" '(expected: kbCenter|kbChar:5)'

    # mouse: one click, then Ctrl+C at the second item -> incomplete
    pty_case mouse --only mouse --timeout 5
    pty_run mouse \
        'text:LEFT-click the highlighted X' 'type:\e[<0;13;7M\e[<0;13;7m' \
        'text:RIGHT-click the highlighted X' 'sleep:0.3' 'type:\x03'
    pty_check mouse "pty mouse run" 130
    DETAIL=$PTYTXT
    ok "pty mouse: the click is OK" has "$PTYTXT" $'\tClick-Left\tb=1,m=0,x=12,y=6\tdown(b=1,x=12,y=6,m=0) up(b=0,x=12,y=6,m=0)\tOK\t'
    ok "pty mouse: the run is marked incomplete" has "$PTYTXT" 'incomplete at mouse/Click-Right'
    ok "pty mouse: the ctrl-c line" has "$PTYTXT" 'ctrl-c: interrupt received'

    # SIGTERM and SIGHUP during an item: restored, a 'term:' / 'hup:' line, incomplete
    pty_case term --only arrows --timeout 20
    pty_run term 'text:Press:   Up' 'sleep:0.3' 'sig:TERM'
    pty_check term "pty SIGTERM run" 143
    DETAIL=$PTYTXT
    ok "pty SIGTERM: the term line" has "$PTYTXT" 'term: terminate received'
    ok "pty SIGTERM: incomplete at the item" has "$PTYTXT" 'incomplete at arrows/Up'
    pty_case hup --only arrows --timeout 20
    pty_run hup 'text:Press:   Up' 'sleep:0.3' 'sig:HUP'
    pty_check hup "pty SIGHUP run" 129
    DETAIL=$PTYTXT
    ok "pty SIGHUP: the hup line" has "$PTYTXT" 'hup: hangup received'
    ok "pty SIGHUP: incomplete at the item" has "$PTYTXT" 'incomplete at arrows/Up'
fi

printf '== %d PASS, %d FAIL, %d SKIP ==\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
