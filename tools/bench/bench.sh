#!/usr/bin/env bash
# tools/bench/bench.sh -- kklass call-path benchmarks, one or more kbool trees
# side by side (A/B), every measurement in a fresh process (cases.sh).
#
#   bash tools/bench/bench.sh [--rounds R] [--n N] [--out FILE] [--title T] \
#        NAME=ROOT [NAME=ROOT...] -- SUITE...
#
# NAME=ROOT  a side: a label and a kbool tree (its kbool.sh is sourced; a
#            `.bench_rev` file in ROOT, written by prepare.sh, names its kklass).
# SUITE      call  -- the call cases of cases.sh: per case and side the median
#                     of R rounds (min-max), and every side's ratio to the first
#            drift -- the drift cases: per case and side the median over R rounds
#                     of the s.Short time before and after the stressor batches,
#                     and their ratio (1.00 = no drift)
# Rounds interleave the sides (A B A B ...), so machine noise hits all sides alike.
# Output: a Markdown report on stdout and in FILE. Plain bash, no tools but uname.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROUNDS=5 N=2000 OUT="" TITLE="kklass bench"
CALL_CASES=(plain call1 call14 long inherited nested prop newdel)
DRIFT_CASES=(drift-short drift-helper drift-nest drift-up drift-newdel)

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
    for x in "$@"; do v+=("${x/./}"); done
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
say "## $TITLE"
say ""
say '```'
say "bash     $BASH_VERSION ($BASH)"
say "system   $(uname -srm 2>/dev/null)"
[[ -n $cpu ]] && say "cpu      $cpu"
say "rounds   $ROUNDS, N=$N calls per measurement"
for (( k = 0; k < ${#NAMES[@]}; k++ )); do
    rev="?"
    [[ -r ${ROOTS[k]}/.bench_rev ]] && { IFS= read -r rev < "${ROOTS[k]}/.bench_rev" || true; }
    say "side ${NAMES[k]}   kklass $rev"
done
say '```'

declare -A VAL=()   # [case|side|label] = "v1 v2 ..."

run_case() {  # SIDE-INDEX CASE
    local k=$1 c=$2 line out rc
    out=$("$BASH" "$HERE/cases.sh" "${ROOTS[k]}" "$c" "$N" 2>&1)
    rc=$?
    if (( rc != 0 )); then
        say "!! side ${NAMES[k]} case $c: rc $rc: ${out//$'\n'/ | }"
        return 1
    fi
    while IFS= read -r line; do
        [[ $line == *' '[0-9]*.[0-9] ]] || continue
        VAL["$c|$k|${line% *}"]+="${line##* } "
    done <<< "$out"
}

for suite in "${SUITES[@]}"; do
    case $suite in
        call)  cases=("${CALL_CASES[@]}") ;;
        drift) cases=("${DRIFT_CASES[@]}") ;;
        *) die "unknown suite '$suite'" ;;
    esac
    for (( r = 1; r <= ROUNDS; r++ )); do
        for c in "${cases[@]}"; do
            for (( k = 0; k < ${#NAMES[@]}; k++ )); do run_case "$k" "$c"; done
        done
    done

    say ""
    if [[ $suite == call ]]; then
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
