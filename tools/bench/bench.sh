#!/usr/bin/env bash
# tools/bench/bench.sh -- kklass call-path and kcl fv screen benchmarks, one or
# more kbool trees side by side (A/B), every measurement in a fresh process
# (cases.sh, fvcases.sh, fvviewcases.sh).
#
#   bash tools/bench/bench.sh [--rounds R] [--n N] [--out FILE] [--title T] \
#        NAME=ROOT [NAME=ROOT...] -- SUITE...
#
# NAME=ROOT  a side: a label and a kbool tree (its kbool.sh is sourced; a
#            `.bench_rev` file in ROOT, written by prepare.sh, names its kklass
#            and its kcl).
# SUITE      call  -- the call cases of cases.sh: per case and side the median
#                     of R rounds (min-max), and every side's ratio to the first
#            drift -- the drift cases: per case and side the median over R rounds
#                     of the s.Short time before and after the stressor batches,
#                     and their ratio (1.00 = no drift)
#            fv    -- the screen actions of fvcases.sh (kcl/fv.video): per action
#                     and side the median of R rounds in ms (min-max), and every
#                     side's ratio to the first
#            fvviews -- the application actions of fvviewcases.sh (kcl fv.views,
#                     fv.menus, fv.app: every action inside app.Run, keys from a
#                     file), reported as fv; its `# calls` / `# writes` notes
#                     follow the table
# --n N      calls (call, drift) or actions (fv, fvviews) per measurement;
#            default 2000 for call and drift, 10 for fv and fvviews.
# Rounds interleave the sides (A B A B ...), so machine noise hits all sides alike.
# Output: a Markdown report on stdout and in FILE. Plain bash, no tools but uname.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROUNDS=5 N="" OUT="" TITLE=""
CALL_CASES=(plain call1 call14 long inherited nested prop newdel)
DRIFT_CASES=(drift-short drift-helper drift-nest drift-up drift-newdel)
FV_CASES=(fv-80 fv-200 fv-resize fv-wide-80 fv-wide-200)
FVV_CASES=(views-80 views-200 views-overlap-80 views-resize views-p2-80 views-list-80 views-list-200 views-paint-80 views-paint)

die() { echo "bench.sh: $*" >&2; exit 2; }

while (( $# )); do
    case $1 in
        --rounds) ROUNDS=${2:?}; shift 2 ;;
        --n)      N=${2:?}; shift 2 ;;
        --out)    OUT=${2:?}; shift 2 ;;
        --title)  TITLE=${2:?}; shift 2 ;;
        --)       shift; break ;;
        *=*)      break ;;
        *)        die "unknown option '$1'" ;;
    esac
done
NAMES=() ROOTS=()
while (( $# )) && [[ $1 != -- ]]; do
    [[ $1 == ?*=?* ]] || die "a side is NAME=ROOT, got '$1'"
    r=${1#*=}
    # a Windows path (D:/a/...) for a Cygwin/MSYS bash
    if [[ $r == [A-Za-z]:[/\\]* ]] && command -v cygpath >/dev/null 2>&1; then r=$(cygpath -u "$r"); fi
    [[ -f $r/kbool.sh ]] || die "no kbool.sh in '$r'"
    NAMES+=("${1%%=*}") ROOTS+=("$r")
    shift
done
[[ ${1-} == -- ]] && shift
SUITES=("$@")
(( ${#NAMES[@]} )) || die "no side given"
(( ${#SUITES[@]} )) || SUITES=(call drift)

REPORT=""
say() { REPORT+="$*"$'\n'; printf '%s\n' "$*"; }

# median VALUES... -> RESULT (decimal strings with one decimal; pure bash)
median() {
    local -a v=() s=()
    local x i j t
    for x in "$@"; do v+=("$(( 10#${x/./} ))"); done
    s=("${v[@]}")
    for (( i = 1; i < ${#s[@]}; i++ )); do
        t=${s[i]}
        for (( j = i - 1; j >= 0 && s[j] > t; j-- )); do s[j+1]=${s[j]}; done
        s[j+1]=$t
    done
    MIN=${s[0]} MAX=${s[${#s[@]}-1]} RESULT=${s[${#s[@]}/2]}
}
dec() { printf -v RESULT '%d.%d' $(( $1 / 10 )) $(( $1 % 10 )); }
ratio() { # A B (tenths) -> RESULT = B/A with two decimals
    local a=$1 b=$2 r
    (( a > 0 )) || { RESULT="-"; return; }
    r=$(( (b * 1000 / a + 5) / 10 ))
    printf -v RESULT '%d.%02d' $(( r / 100 )) $(( r % 100 ))
}

cpu=""
if [[ -r /proc/cpuinfo ]]; then
    while IFS= read -r line; do
        [[ $line == "model name"* ]] && { cpu=${line#*: }; break; }
    done < /proc/cpuinfo
fi
has_kk=0 has_fv=0
for suite in "${SUITES[@]}"; do
    case $suite in
        call|drift) has_kk=1 ;;
        fv|fvviews) has_fv=1 ;;
        *) die "unknown suite '$suite'" ;;
    esac
done
if [[ -z $TITLE ]]; then
    TITLE="kklass bench"
    (( has_fv )) && TITLE="fv bench"
    (( has_fv && has_kk )) && TITLE="kklass + fv bench"
fi
say "## $TITLE"
say ""
say '```'
say "bash     $BASH_VERSION ($BASH)"
say "system   $(uname -srm 2>/dev/null)"
[[ -n $cpu ]] && say "cpu      $cpu"
(( has_kk )) && say "rounds   $ROUNDS, N=${N:-2000} calls per measurement"
if (( has_fv && has_kk )); then say "fv       N=${N:-10} actions per measurement"
elif (( has_fv )); then say "rounds   $ROUNDS, N=${N:-10} actions per measurement"; fi
for (( k = 0; k < ${#NAMES[@]}; k++ )); do
    revs=()
    [[ -r ${ROOTS[k]}/.bench_rev ]] && { mapfile -t revs < "${ROOTS[k]}/.bench_rev" || true; }
    # line 1: kklass; the lines after it name the other pinned submodules ("kcl ...")
    say "side ${NAMES[k]}   kklass ${revs[0]:-?}"
    for line in "${revs[@]:1}"; do say "side ${NAMES[k]}   $line"; done
done
say '```'

declare -A VAL=()   # [case|side|label] = "v1 v2 ..."
declare -A NOTE=()  # [side: text] = 1: the `# text` lines of fvcases.sh / fvviewcases.sh
NOTEL=()            # the same in the order first seen (per suite)
LABELS=()           # "case|label" in the order first seen (the fv table's rows)
declare -A SEEN=()

run_case() {  # SIDE-INDEX CASE SCRIPT N
    local k=$1 c=$2 line out rc
    out=$("$BASH" "$HERE/$3" "${ROOTS[k]}" "$c" "$4" 2>&1)
    rc=$?
    if (( rc != 0 )); then
        say "!! side ${NAMES[k]} case $c: rc $rc: ${out//$'\n'/ | }"
        return 1
    fi
    while IFS= read -r line; do
        if [[ $line == '# '* ]]; then
            if [[ -z ${NOTE["${NAMES[k]}: ${line#\# }"]-} ]]; then NOTE["${NAMES[k]}: ${line#\# }"]=1; NOTEL+=("${NAMES[k]}: ${line#\# }"); fi
            continue
        fi
        [[ $line == *' '[0-9]*.[0-9] ]] || continue
        VAL["$c|$k|${line% *}"]+="${line##* } "
        if [[ -z ${SEEN["$c|${line% *}"]-} ]]; then SEEN["$c|${line% *}"]=1; LABELS+=("$c|${line% *}"); fi
    done <<< "$out"
}
# ms TENTHS-OF-US -> RESULT = milliseconds with two decimals
ms() { printf -v RESULT '%d.%02d' $(( $1 / 10000 )) $(( $1 / 100 % 100 )); }

for suite in "${SUITES[@]}"; do
    case $suite in
        call)  cases=("${CALL_CASES[@]}") script=cases.sh n=${N:-2000} ;;
        drift) cases=("${DRIFT_CASES[@]}") script=cases.sh n=${N:-2000} ;;
        fv)    cases=("${FV_CASES[@]}") script=fvcases.sh n=${N:-10} ;;
        fvviews) cases=("${FVV_CASES[@]}") script=fvviewcases.sh n=${N:-10} ;;
    esac
    NOTE=() NOTEL=()
    for (( r = 1; r <= ROUNDS; r++ )); do
        for c in "${cases[@]}"; do
            for (( k = 0; k < ${#NAMES[@]}; k++ )); do run_case "$k" "$c" "$script" "$n"; done
        done
    done

    say ""
    if [[ $suite == fv || $suite == fvviews ]]; then
        say "### $suite: ms per action, median of $ROUNDS (min-max)"
        say ""
        hdr="| action |" sep="|---|"
        for (( k = 0; k < ${#NAMES[@]}; k++ )); do hdr+=" ${NAMES[k]} |"; sep+="---|"; done
        for (( k = 1; k < ${#NAMES[@]}; k++ )); do hdr+=" ${NAMES[k]}/${NAMES[0]} |"; sep+="---|"; done
        say "$hdr"; say "$sep"
        for key in "${LABELS[@]}"; do
            c=${key%%|*}
            [[ " ${cases[*]} " == *" $c "* ]] || continue
            row="| ${key#*|} |"; meds=()
            for (( k = 0; k < ${#NAMES[@]}; k++ )); do
                # shellcheck disable=SC2086
                set -- ${VAL[$c|$k|${key#*|}]-}
                if (( $# )); then
                    median "$@"; meds[k]=$RESULT
                    ms "$RESULT"; m=$RESULT; ms "$MIN"; lo=$RESULT; ms "$MAX"; hi=$RESULT
                    row+=" $m ($lo-$hi) |"
                else row+=" - |"; meds[k]=0
                fi
            done
            for (( k = 1; k < ${#NAMES[@]}; k++ )); do
                if (( meds[k] )); then ratio "${meds[0]}" "${meds[k]}"; else RESULT="-"; fi
                row+=" $RESULT |"
            done
            say "$row"
        done
        if (( ${#NOTEL[@]} )); then
            say ""
            for key in "${NOTEL[@]}"; do say "- side $key"; done
        fi
    elif [[ $suite == call ]]; then
        say "### call: microseconds per call, median of $ROUNDS (min-max)"
        say ""
        hdr="| case |" sep="|---|"
        for (( k = 0; k < ${#NAMES[@]}; k++ )); do hdr+=" ${NAMES[k]} |"; sep+="---|"; done
        for (( k = 1; k < ${#NAMES[@]}; k++ )); do hdr+=" ${NAMES[k]}/${NAMES[0]} |"; sep+="---|"; done
        say "$hdr"; say "$sep"
        for c in "${cases[@]}"; do
            row="| $c |"; meds=()
            for (( k = 0; k < ${#NAMES[@]}; k++ )); do
                # shellcheck disable=SC2086
                set -- ${VAL[$c|$k|$c]-}
                if (( $# )); then
                    median "$@"; meds[k]=$RESULT
                    dec "$RESULT"; m=$RESULT; dec "$MIN"; lo=$RESULT; dec "$MAX"; hi=$RESULT
                    row+=" $m ($lo-$hi) |"
                else row+=" - |"; meds[k]=0
                fi
            done
            for (( k = 1; k < ${#NAMES[@]}; k++ )); do ratio "${meds[0]}" "${meds[k]}"; row+=" $RESULT |"; done
            say "$row"
        done
    else
        say "### drift: s.Short in microseconds before / after 6x$N stressor calls, median of $ROUNDS"
        say ""
        say "| case | side | before | stressor first -> last | after | after/before |"
        say "|---|---|---|---|---|---|"
        for c in "${cases[@]}"; do
            for (( k = 0; k < ${#NAMES[@]}; k++ )); do
                # shellcheck disable=SC2086
                set -- ${VAL[$c|$k|before2]-}
                (( $# )) || { say "| $c | ${NAMES[k]} | - | - | - | - |"; continue; }
                median "$@"; b=$RESULT
                # shellcheck disable=SC2086
                set -- ${VAL[$c|$k|after2]-}; median "$@"; a=$RESULT
                # shellcheck disable=SC2086
                set -- ${VAL[$c|$k|stress1]-}; median "$@"; s1=$RESULT
                # shellcheck disable=SC2086
                set -- ${VAL[$c|$k|stress6]-}; median "$@"; s6=$RESULT
                ratio "$b" "$a"; q=$RESULT
                dec "$b"; b=$RESULT; dec "$a"; a=$RESULT; dec "$s1"; s1=$RESULT; dec "$s6"; s6=$RESULT
                say "| $c | ${NAMES[k]} | $b | $s1 -> $s6 | $a | $q |"
            done
        done
    fi
done

[[ -n $OUT ]] && printf '%s' "$REPORT" > "$OUT"
exit 0
