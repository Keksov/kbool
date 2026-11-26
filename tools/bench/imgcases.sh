#!/usr/bin/env bash
# tools/bench/imgcases.sh ROOT CASE [N] -- one kk.image bench case (kkore's
# load image, kklass/docs/dev/IMAGE_PLAN.md §11), run in this process by
# tools/bench/bench.sh. ROOT is a kbool tree (its kbool.sh and kcl/fv.dlg are
# used). Prints `LABEL MICROSECONDS` lines (one decimal: the mean of the
# measurement's starts) and `# TEXT` notes, like the other case files.
#
# Every image lives in a temp folder (KBOOL_IMAGE_DIR): under $IMGBENCH_TMP
# when bench.sh set it (one folder per side, shared by the cases of a run,
# removed by bench.sh), else a folder of its own (mktemp -d, removed at exit).
# The user's image cache is never read or written. KBOOL_IMAGE,
# KBOOL_IMAGE_CHECK, KBOOL_IMAGE_CHAIN and VERBOSE_KKLASS of the caller are
# dropped; the caller's locale is kept (and named in a note: the hit path's
# text work costs more under a UTF-8 locale).
#
# A "start" is a fresh process: `bash SCRIPT ROOT` where SCRIPT (in the temp
# folder) sources ROOT/kbool.sh, runs the load and prints $EPOCHREALTIME;
# launch -> return = that mark minus $EPOCHREALTIME taken before the spawn
# (bash's own start included, its exit not). Before timing, the image is
# warmed (up to three starts) and checked valid with `kk.image --path`;
# after the timing, a hit row checks that the image was not written again
# (its nonce, the plain header line's field 7).
#
# CASE:
#   img-hit    image.hit.fvdlg   `source kbool.sh; kk.image fv.dlg`, a hit
#              image.load.fvdlg  the same with KBOOL_IMAGE=off (interleaved)
#              image.hit.fvdlg.dates  (Linux / macOS / BSD only) the hit with
#                                KBOOL_IMAGE_CHECK=dates beside the default stat
#              image.bash, image.kbool  references: a bare bash start; a start
#                                that only sources kbool.sh
#   img-chain  image.hit.chain   `kk.uses tstringlist; kk.image fv.dlg`, a hit
#              image.load.chain  the same with KBOOL_IMAGE=off
#              image.load.tstringlist  `kk.uses tstringlist` alone
#   img-check  image.check       in a fresh process, after `source kbool.sh`:
#                                `kk.image --path fv.dlg` — the hit path's checks
#                                (kimghit.sh parsed, prep, key, header, edges,
#                                staleness, clash and base checks) without the
#                                source of the image and the hooks
#              image.check.warm  the same call repeated in one process (the
#                                mean of calls 2..N+1: the caches warm)
#              image.check.chain the first call after `kk.uses tstringlist`
#              image.check.dates (Linux / macOS / BSD only) image.check with
#                                KBOOL_IMAGE_CHECK=dates
#   img-miss   image.miss.fvdlg  a first start (an empty image folder): the
#                                normal load, then the writer; plus the writer's
#                                profile as image.miss.fvdlg.PART rows (the
#                                kimage.sh seam __KK_IMG_PROF; a kbool without
#                                it gives the total only)
#              image.miss.chain  the same on top of `kk.uses tstringlist`
#              (one start each per measurement; N is not used)
#   img-alt    image.alt.first   two scripts in two folders alternate, 10 starts
#              image.alt.start   (the second folder holds a copy of fv.dlg.sh, so
#                                its request resolves to another file: another
#                                image): .first = the mean of starts 1-2 (the
#                                misses), .start = of starts 3-10; a note counts
#                                the images written in starts 3-10 (must be 0)
#              (N is not used)
#   img-forks  notes only: the forks of one hit per check mode (dates, stat,
#              hash), counted from an xtrace (PS4 with $BASHPID: a line with
#              another pid is a fork; a command word of the main shell that is
#              a file on PATH is listed too), as kkore/tests/023 does
# N (default 5) = starts per measurement.
set -u
ROOT=${1:?usage: imgcases.sh ROOT CASE [N]}
CASE=${2:?usage: imgcases.sh ROOT CASE [N]}
N=${3:-5}
[[ $N == [1-9]* && $N != *[!0-9]* ]] || { echo "imgcases.sh: N must be a positive count" >&2; exit 2; }
[[ -f $ROOT/kbool.sh && -f $ROOT/kcl/fv.dlg/fv.dlg.sh && -f $ROOT/kcl/tstringlist/tstringlist.sh ]] \
    || { echo "imgcases.sh: no kbool.sh, kcl/fv.dlg or kcl/tstringlist in '$ROOT'" >&2; exit 2; }
[[ -f $ROOT/kkore/kimghit.sh ]] || { echo "imgcases.sh: this kbool has no kk.image (kkore/kimghit.sh)" >&2; exit 2; }
case $CASE in img-hit|img-chain|img-check|img-miss|img-alt|img-forks) ;; *) echo "imgcases.sh: unknown case '$CASE'" >&2; exit 2 ;; esac
unset -v KBOOL_IMAGE KBOOL_IMAGE_DIR KBOOL_IMAGE_CHECK KBOOL_IMAGE_CHAIN VERBOSE_KKLASS __KK_IMG_PROF

# the temp folder: the side's under IMGBENCH_TMP, else our own
side=${ROOT//[!A-Za-z0-9]/_}
(( ${#side} <= 60 )) || side=${side: -60}
if [[ -n ${IMGBENCH_TMP-} && -d ${IMGBENCH_TMP-} ]]; then
    W=$IMGBENCH_TMP/$side
    mkdir -p "$W" || exit 2
else
    W=$(mktemp -d "${TMPDIR:-/tmp}/kbimg.XXXXXX") || exit 2
    trap 'rm -rf -- "$W"' EXIT
fi
D=$W/img                                  # the shared image folder (made by kk.image)
POSIX=1
case $OSTYPE in msys*|cygwin*) POSIX=0 ;; esac
echo "# caller locale: LC_ALL=${LC_ALL-} LC_CTYPE=${LC_CTYPE-} LANG=${LANG-}"

# the start scripts ($1 = ROOT; they live in $W, the caller folder of every request)
mk() { [[ -f $W/$1 ]] || printf '%s\n' "$2" > "$W/$1"; }
mk empty.sh 'printf "%s\n" "$EPOCHREALTIME"'
mk src.sh 'source "$1/kbool.sh" || exit 2
printf "%s\n" "$EPOCHREALTIME"'
mk hit.sh 'source "$1/kbool.sh" || exit 2
kk.image fv.dlg || exit 3
printf "%s\n" "$EPOCHREALTIME"'
mk chain.sh 'source "$1/kbool.sh" || exit 2
kk.uses tstringlist || exit 2
kk.image fv.dlg || exit 3
printf "%s\n" "$EPOCHREALTIME"'
mk tsl.sh 'source "$1/kbool.sh" || exit 2
kk.uses tstringlist || exit 2
printf "%s\n" "$EPOCHREALTIME"'
# the miss: $2 chain or -, $3 the writer profile file (kimage.sh seam)
mk miss.sh 'source "$1/kbool.sh" || exit 2
if [[ $2 == chain ]]; then kk.uses tstringlist || exit 2; fi
__KK_IMG_PROF=$3
kk.image fv.dlg || exit 3
printf "%s\n" "$EPOCHREALTIME"'
# validity: prints the image path; rc 0 = a valid image (the next start is a
# hit); the reason on stderr (kk._image_dbg redefined: VERBOSE_KKLASS is keyed)
mk probe.sh 'source "$1/kbool.sh" || exit 2
if [[ $2 == chain ]]; then kk.uses tstringlist || exit 2; fi
kk._image_dbg() { printf "%s\n" "$*" >&2; }
kk.image --path fv.dlg'
# the checks alone: $2 chain or -, $3 calls; prints the first call and the sum of the others (us)
mk check.sh 'source "$1/kbool.sh" || exit 2
if [[ $2 == chain ]]; then kk.uses tstringlist || exit 2; fi
f=0 s=0
for (( i = 0; i < $3; i++ )); do
    t0=$EPOCHREALTIME
    kk.image --path fv.dlg > /dev/null || exit 3
    t1=$EPOCHREALTIME
    u=$(( 10#${t1//[.,]/} - 10#${t0//[.,]/} ))
    if (( i == 0 )); then f=$u; else s=$(( s + u )); fi
done
printf "%s %s\n" "$f" "$s"'
# the traced hit: $2 the trace file
mk forks.sh 'source "$1/kbool.sh" || exit 2
exec 8> "$2"
BASH_XTRACEFD=8
PS4='"'"'+${BASHPID}|'"'"'
printf "MAIN=%s\n" "$BASHPID" >&8
set -x
kk.image fv.dlg 2> /dev/null
set +x
printf "pid=%s\n" "${__KK_UNIT_PID[fv.dlg]-image}"'

US=0
# run SCRIPT DIR OFF CHECK [ARG...] -> US: one start, launch -> its mark (us); rc 1 on a failure
run() {
    local t0 out
    t0=$EPOCHREALTIME
    out=$(KBOOL_IMAGE_DIR=$2 KBOOL_IMAGE=$3 KBOOL_IMAGE_CHECK=$4 "$BASH" "$W/$1" "$ROOT" "${@:5}" 2> /dev/null) || return 1
    out=${out##*$'\n'}
    [[ $out == [0-9]*[.,][0-9]* ]] || return 1
    US=$(( 10#${out//[.,]/} - 10#${t0//[.,]/} ))
}
# valid DIR CHECK KIND -> IMG (the path), WHY; rc 0 = a valid image
IMG="" WHY=""
valid() {
    local e
    e=$(KBOOL_IMAGE_DIR=$1 KBOOL_IMAGE_CHECK=$2 "$BASH" "$W/probe.sh" "$ROOT" "$3" 2>&1 >"$W/probe.out")
    local rc=$?
    IMG=$(< "$W/probe.out")
    WHY=${e##*$'\n'}
    return $rc
}
# warm SCRIPT DIR CHECK KIND -> rc 0 when the image is valid after at most three starts
warm() {
    local i
    for (( i = 0; i < 3; i++ )); do
        valid "$2" "$3" "$4" && return 0
        run "$1" "$2" "" "$3" || :
    done
    valid "$2" "$3" "$4"
}
# nonce FILE -> NONCE: the plain header line's field 7 (a rewrite changes it)
NONCE=""
nonce() {
    local l1 l2 IFS=$'\x1f'
    local -a a=()
    NONCE=""
    [[ -f $1 ]] || return 1
    { IFS= read -r l1; IFS= read -r l2; } < "$1" || return 1
    a=($l2)
    NONCE=${a[8]-}
}
# mean LABEL SUM COUNT
mean() { printf '%s %d.%d\n' "$1" $(( $2 / $3 )) $(( $2 * 10 / $3 % 10 )); }

case $CASE in
img-hit)
    modes=("")
    (( POSIX )) && modes+=(dates)
    ok=()
    for m in "${modes[@]}"; do
        if warm hit.sh "$D" "$m" -; then ok+=(1); else ok+=(0); echo "# image.hit.fvdlg${m:+.$m}: no valid image after three starts ($WHY)"; fi
    done
    nonce "$IMG"; n0=$NONCE
    declare -A S=()
    for (( i = 0; i < N; i++ )); do
        for (( k = 0; k < ${#modes[@]}; k++ )); do
            (( ok[k] )) || continue
            run hit.sh "$D" "" "${modes[k]}" || { echo "# image.hit.fvdlg${modes[k]:+.${modes[k]}}: a start failed"; exit 3; }
            S[hit${modes[k]}]=$(( ${S[hit${modes[k]}]:-0} + US ))
        done
        run hit.sh "$D" off "" || { echo "# image.load.fvdlg: a start failed"; exit 3; }
        S[load]=$(( ${S[load]:-0} + US ))
        run src.sh "$D" "" "" && S[kbool]=$(( ${S[kbool]:-0} + US ))
        run empty.sh "$D" "" "" && S[bash]=$(( ${S[bash]:-0} + US ))
    done
    (( ok[0] )) && mean image.hit.fvdlg "${S[hit]}" "$N"
    mean image.load.fvdlg "${S[load]}" "$N"
    (( ${#modes[@]} > 1 && ok[1] )) && mean image.hit.fvdlg.dates "${S[hitdates]}" "$N"
    mean image.kbool "${S[kbool]:-0}" "$N"
    mean image.bash "${S[bash]:-0}" "$N"
    if (( ok[0] )); then
        valid "$D" "" -
        nonce "$IMG"
        [[ $NONCE == "$n0" ]] || echo "# image.hit.fvdlg: the image was written again during the timing (not every start was a hit)"
    fi ;;
img-chain)
    if ! warm chain.sh "$D" "" chain; then echo "# image.hit.chain: no valid image after three starts ($WHY)"; okc=0; else okc=1; fi
    nonce "$IMG"; n0=$NONCE
    sh=0 sl=0 st=0
    for (( i = 0; i < N; i++ )); do
        if (( okc )); then run chain.sh "$D" "" "" || { echo "# image.hit.chain: a start failed"; exit 3; }; sh=$(( sh + US )); fi
        run chain.sh "$D" off "" || { echo "# image.load.chain: a start failed"; exit 3; }; sl=$(( sl + US ))
        run tsl.sh "$D" "" "" || { echo "# image.load.tstringlist: a start failed"; exit 3; }; st=$(( st + US ))
    done
    (( okc )) && mean image.hit.chain "$sh" "$N"
    mean image.load.chain "$sl" "$N"
    mean image.load.tstringlist "$st" "$N"
    if (( okc )); then
        valid "$D" "" chain
        nonce "$IMG"
        [[ $NONCE == "$n0" ]] || echo "# image.hit.chain: the image was written again during the timing (not every start was a hit)"
    fi ;;
img-check)
    rows=("image.check||-" "image.check.chain||chain")
    (( POSIX )) && rows+=("image.check.dates|dates|-")
    for r in "${rows[@]}"; do
        IFS='|' read -r lab m k <<< "$r"
        sc=hit.sh; [[ $k == chain ]] && sc=chain.sh
        if ! warm "$sc" "$D" "$m" "$k"; then echo "# $lab: no valid image after three starts ($WHY)"; continue; fi
        s=0
        for (( i = 0; i < N; i++ )); do
            out=$(KBOOL_IMAGE_DIR=$D KBOOL_IMAGE_CHECK=$m "$BASH" "$W/check.sh" "$ROOT" "$k" 1 2>/dev/null) || { echo "# $lab: the check said 'not valid'"; exit 3; }
            s=$(( s + ${out%% *} ))
        done
        mean "$lab" "$s" "$N"
        if [[ $lab == image.check ]]; then
            out=$(KBOOL_IMAGE_DIR=$D "$BASH" "$W/check.sh" "$ROOT" - $(( N + 1 )) 2>/dev/null) || { echo "# image.check.warm: the check said 'not valid'"; exit 3; }
            mean image.check.warm "${out#* }" "$N"
        fi
    done ;;
img-miss)
    for k in - chain; do
        lab=image.miss.fvdlg; [[ $k == chain ]] && lab=image.miss.chain
        M=$W/miss.$k
        rm -rf -- "$M" "$W/prof.txt"
        if ! run miss.sh "$M" "" "" "$k" "$W/prof.txt"; then echo "# $lab: the start failed"; exit 3; fi
        tot=$US
        what="" prof=""
        if [[ -f $W/prof.txt ]]; then { IFS= read -r what; IFS= read -r prof; } < "$W/prof.txt"; fi
        if [[ -z $what ]]; then
            # (a kbool without the seam: the image file tells)
            what="no image written"
            for f in "$M"/*.img; do [[ -f $f ]] && what=wrote; done
        fi
        if [[ $what != wrote ]]; then echo "# $lab: ${what}"; fi
        mean "$lab" "$tot" 1
        # the writer's profile: "before 31, load 792, ..., fresh process 1645
        # (P 180 sim 780 scan 589) (a start 113 ms) (dump 465, compare 77),
        # ..., rename 75; total 3843": LABEL NUMBER pairs, a parenthesised
        # group's labels after the label before it (fresh-process.P)
        prof=${prof#profile }
        prof=${prof//[,;]/ }
        read -r -a parts <<< "$prof"
        pl="" outer="" inner=0
        for p in "${parts[@]}"; do
            close=0
            [[ $p == '('* ]] && { inner=1; p=${p#(}; }
            [[ $p == *')' ]] && { close=1; p=${p%)}; }
            if [[ -n $p && $p != *[!0-9]* ]]; then
                pl=${pl# }; pl=${pl// /-}
                if (( inner )); then pl=$outer.$pl; else outer=$pl; fi
                [[ -n $pl ]] && mean "$lab.$pl" $(( 10#$p * 1000 )) 1
                pl=""
            elif [[ -n $p && $p != ms ]]; then
                pl+=" $p"
            fi
            (( close )) && inner=0
        done
        rm -rf -- "$M" "$W/prof.txt"
    done ;;
img-alt)
    A=$W/alta B=$W/altb M=$W/alt
    mkdir -p "$A" "$B"
    for x in a b; do
        [[ -f $W/alt$x/$x.sh ]] || printf '%s\n' 'source "$1/kbool.sh" || exit 2' 'kk.image fv.dlg || exit 3' 'printf "%s\n" "$EPOCHREALTIME"' > "$W/alt$x/$x.sh"
    done
    # (the original's mtime kept — a copy made "now" would be a racy stamp;
    # touch -r, not `cp -p`, which fails on Cygwin's ACL-less temp folders)
    if [[ ! -f $B/fv.dlg.sh ]]; then
        cp "$ROOT/kcl/fv.dlg/fv.dlg.sh" "$B/fv.dlg.sh" && touch -r "$ROOT/kcl/fv.dlg/fv.dlg.sh" "$B/fv.dlg.sh" || exit 2
    fi
    rm -rf -- "$M"
    declare -A NB=()
    s1=0 s3=0 w=0
    for (( i = 1; i <= 10; i++ )); do
        if (( i % 2 )); then sc=alta/a.sh; else sc=altb/b.sh; fi
        run "$sc" "$M" "" "" || { echo "# image.alt: start $i failed"; exit 3; }
        if (( i <= 2 )); then s1=$(( s1 + US )); else s3=$(( s3 + US )); fi
        for f in "$M"/*.img; do
            [[ -f $f ]] || continue
            nonce "$f"
            if [[ ${NB[$f]-} != "$NONCE" ]]; then
                (( i > 2 )) && w=$(( w + 1 ))
                NB[$f]=$NONCE
            fi
        done
    done
    mean image.alt.first "$s1" 2
    mean image.alt.start "$s3" 8
    echo "# image.alt: ${#NB[@]} images; written in starts 3-10: $w"
    rm -rf -- "$M" ;;
img-forks)
    for m in dates stat hash; do
        if ! warm hit.sh "$D" "$m" -; then echo "# image.forks.$m: no valid image after three starts ($WHY)"; continue; fi
        T=$W/fk.trace
        out=$(KBOOL_IMAGE_DIR=$D KBOOL_IMAGE_CHECK=$m "$BASH" "$W/forks.sh" "$ROOT" "$T" 2>/dev/null)
        forks=0 main="" cmds="" ext=""
        unset -v words; declare -A words=()
        while IFS= read -r line; do
            case $line in MAIN=*) main=${line#MAIN=}; continue ;; +*) ;; *) continue ;; esac
            p=${line%%|*}; p=${p##*+}
            [[ -n $p && $p != *[!0-9]* ]] || continue
            c=${line#*|}
            if [[ $p == "$main" ]]; then
                [[ $c == "command "* ]] && c=${c#command }
                c=${c%% *}
                [[ -z $c || $c == *[=\[\(\$\'\"]* ]] || words[$c]=1
                continue
            fi
            # (a prefix assignment — LC_ALL=C of stat / cksum — is traced on its own line)
            [[ $c == [A-Za-z_]*=* && $c != *" "* ]] && continue
            forks=$(( forks + 1 )); c=${c#command }; cmds+="${c%% *} "
        done < "$T"
        for c in "${!words[@]}"; do [[ $(type -t -- "$c" 2>/dev/null) != file ]] || ext+="$c "; done
        hit=hit; [[ $out == *pid=image* ]] || hit="NOT a hit"
        echo "# image.forks.$m: $forks fork(s)${cmds:+ (${cmds% })}${ext:+; external commands in the main shell: ${ext% }} — $hit"
        rm -f -- "$T"
    done ;;
esac
exit 0
