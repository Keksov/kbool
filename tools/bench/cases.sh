#!/usr/bin/env bash
# tools/bench/cases.sh ROOT CASE [N] -- one kklass benchmark case, run in this
# (fresh) process by tools/bench/bench.sh. ROOT is a kbool tree (its kbool.sh is
# sourced). Prints one line per measurement: `NAME MICROSECONDS` (one decimal).
#
# call cases (mean time of one call over N calls):
#   plain     a plain bash function (the floor)
#   call1     obj.Short, a class with 1 field
#   call14    obj.Short, a class with 14 fields
#   long      obj.Long, a 17-line body, 1 field
#   inherited obj.Up -> inherited Up
#   nested    obj.Nest -> $this.Short (two method calls)
#   prop      obj.A, a property read (prints; the loop's stdout is /dev/null)
#   newdel    Class.new x; x.delete
# drift cases (does a long process slow down?): N calls per batch;
#   2 batches of s.Short, 6 batches of the stressor, 2 batches of s.Short again.
#   drift-nest (c.Nest), drift-up (c.Up), drift-helper (a method calling a plain
#   function twice), drift-short (s.Short: the control), drift-newdel.
set -u
ROOT=${1:?usage: cases.sh ROOT CASE [N]}
CASE=${2:?usage: cases.sh ROOT CASE [N]}
N=${3:-2000}

source "$ROOT/kbool.sh" || exit 2
kk.uses kklass_pascal || exit 2

class TSmall
    public
        var  A
        proc Short
        proc Long
        proc Up
        proc Helper
end
TSmall.Short() { RESULT=1; }
TSmall.Long() {
    local i s=""
    if (( ${#A} > 1000 )); then
        for (( i = 0; i < 3; i++ )); do s+="x$i"; done
        case $s in x0*) s=${s//x/y} ;; *) s=${s^^} ;; esac
        printf -v s '%s-%s' "$s" "$A"
        [[ -n $s ]] && RESULT=$s
        for (( i = 0; i < 3; i++ )); do s+="x$i"; done
        case $s in x0*) s=${s//x/y} ;; *) s=${s^^} ;; esac
        printf -v s '%s-%s' "$s" "$A"
        [[ -n $s ]] && RESULT=$s
        for (( i = 0; i < 3; i++ )); do s+="x$i"; done
        case $s in x0*) s=${s//x/y} ;; *) s=${s^^} ;; esac
        printf -v s '%s-%s' "$s" "$A"
        [[ -n $s ]] && RESULT=$s
    fi
    RESULT=1
}
TSmall.Up() { RESULT=1; }
bench_helper() { RESULT=$1; }
TSmall.Helper() { bench_helper 1; bench_helper 2; }
build TSmall

class TBig
    public
        var  P01
        var  P02
        var  P03
        var  P04
        var  P05
        var  P06
        var  P07
        var  P08
        var  P09
        var  P10
        var  P11
        var  P12
        var  P13
        var  P14
        proc Short
end
TBig.Short() { RESULT=1; }
build TBig

class TChild : TSmall
    public
        override proc Up
        proc Nest
end
TChild.Up() { inherited Up; }
TChild.Nest() { $this.Short; }
build TChild

TSmall.new s
TBig.new b
TChild.new c
s.A = x

plain() { RESULT=1; }
newdel() { TSmall.new bench_x; bench_x.delete; }

# timed LABEL CMD... : mean microseconds of one CMD over N runs
timed() {
    local label=$1 i t0 t1 d
    shift
    t0=$EPOCHREALTIME
    if [[ -n ${QUIET-} ]]; then
        for (( i = 0; i < N; i++ )); do "$@"; done >/dev/null
    else
        for (( i = 0; i < N; i++ )); do "$@"; done
    fi
    t1=$EPOCHREALTIME
    d=$(( (${t1/[.,]/} - ${t0/[.,]/}) * 10 / N ))
    printf '%s %d.%d\n' "$label" $(( d / 10 )) $(( d % 10 ))
}

drift() {   # STRESSOR-CMD...
    local b
    for b in 1 2; do timed "before$b" s.Short; done
    for b in 1 2 3 4 5 6; do timed "stress$b" "$@"; done
    for b in 1 2; do timed "after$b" s.Short; done
}

case $CASE in
    plain)        timed plain plain ;;
    call1)        timed call1 s.Short ;;
    call14)       timed call14 b.Short ;;
    long)         timed long s.Long ;;
    inherited)    timed inherited c.Up ;;
    nested)       timed nested c.Nest ;;
    prop)         QUIET=1 timed prop s.A ;;
    newdel)       timed newdel newdel ;;
    drift-nest)   drift c.Nest ;;
    drift-up)     drift c.Up ;;
    drift-helper) drift s.Helper ;;
    drift-short)  drift s.Short ;;
    drift-newdel) drift newdel ;;
    *) echo "cases.sh: unknown case '$CASE'" >&2; exit 2 ;;
esac
