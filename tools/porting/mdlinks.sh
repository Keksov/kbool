#!/usr/bin/env bash
# mdlinks.sh - checker of relative links and heading anchors in the tracked
# *.md files of the kbool tree (the root repo and kcl kklass kkore ktests).
# It only reports; it never edits anything. Plain bash, no kbool, no per-file
# fork. See tools/porting/README.md (section "mdlinks.sh").
#
#   mdlinks.sh [--root DIR] [--list] [PATH...]
#
# rc 0: no broken link; 1: at least one broken link; 2: usage error.

set -u
shopt -s extglob
export LC_ALL=C

SEP=$'\x01'

usage() {
    cat <<'EOF'
usage: mdlinks.sh [--root DIR] [--list] [PATH...]
  --root DIR  tree root (default: two levels above this script)
  --list      print every resolved link as "FILE:LINE: ok: TARGET" instead of
              the broken ones
  PATH        root-relative .md file or directory (default: every tracked .md)
output: FILE:LINE: broken: TARGET (no such file|no such anchor); summary on
stderr; rc 0 = clean, 1 = broken links, 2 = usage error
EOF
}
die_usage() {
    [[ -z ${1-} ]] || printf 'mdlinks: %s\n' "$1" >&2
    usage >&2
    exit 2
}

# ---- arguments --------------------------------------------------------------
ROOT='' LIST=0
ARGS=()
while (($#)); do
    case $1 in
        --root) (($# >= 2)) || die_usage "--root needs a directory"; ROOT=$2; shift 2 ;;
        --list) LIST=1; shift ;;
        -h | --help) usage; exit 0 ;;
        --) shift; ARGS+=("$@"); break ;;
        -*) die_usage "unknown option: $1" ;;
        *) ARGS+=("$1"); shift ;;
    esac
done
if [[ -z $ROOT ]]; then
    d=${BASH_SOURCE[0]}
    if [[ $d == */* ]]; then d=${d%/*}; else d=.; fi
    ROOT=$d/../..
fi
[[ -d $ROOT ]] || die_usage "--root is not a directory: $ROOT"
ROOT=$(cd "$ROOT" && pwd) || die_usage "bad root: $ROOT"

# ---- tables -----------------------------------------------------------------
declare -A TRACKED=() DIRS=() SCANNED=() LINKS=() HAS=() SEEN=() CYR=() INSRC=()
FILES=() SRC=() NOTES=()
LK='' SLUG='' NORM='' ESC=0 RES=3 NSPAN=0
SPS=() SPE=()

RE_FENCE='^[ ]{0,3}(`{3,}|~{3,})(.*)$'
RE_HEAD='^[ ]{0,3}#{1,6}[[:space:]]+(.*)$'
RE_SETEXT='^[ ]{0,3}(={3,}|-{3,})[[:space:]]*$'
RE_NOTTEXT='^[[:space:]]*($|[|>#*+<-]|[0-9]+[.)][[:space:]])'
RE_ANGLE='^[[:space:]]*<([^<>]*)>([[:space:]]+"[^"]*")?[[:space:]]*\)'
RE_PLAIN='^[[:space:]]*([^()[:space:]]*)([[:space:]]+"[^"]*")?[[:space:]]*\)'
RE_TITLED='^([^[:space:]]+)[[:space:]]+"[^"]*"$'
RE_SCHEME='^[a-z]+:'
RE_LINE='^L[0-9]+(-L[0-9]+)?$'
RE_CLOSE='^(.*[[:space:]])#+$'

# Cyrillic upper -> lower (UTF-8 pairs); everything else Cyrillic stays as is.
build_cyr() {
    local b h h2 k v
    for ((b = 0x80; b <= 0xaf; b++)); do
        printf -v h '%02x' "$b"
        if ((b <= 0x8f)); then printf -v h2 '%02x' $((b + 0x10)); v="\\xd1\\x$h2"
        elif ((b <= 0x9f)); then printf -v h2 '%02x' $((b + 0x20)); v="\\xd0\\x$h2"
        else printf -v h2 '%02x' $((b - 0x20)); v="\\xd1\\x$h2"; fi
        printf -v k "\\xd0\\x$h"
        printf -v v "$v"
        CYR[$k]=$v
    done
}
build_cyr

# ---- the file universe -------------------------------------------------------
load_repo() {   # PREFIX(with trailing / or empty) DIR
    local pre=$1 p full dd
    while IFS= read -r -d '' p; do
        full=$pre$p
        TRACKED[$full]=1
        dd=$full
        while [[ $dd == */* ]]; do
            dd=${dd%/*}
            [[ -z ${DIRS[$dd]-} ]] || break
            DIRS[$dd]=1
        done
        if [[ $p == *.md && -f $ROOT/$full ]]; then FILES+=("$full"); fi
    done < <(git -C "$2" ls-files -z 2>/dev/null)
}
load_repo '' "$ROOT"
for n in kcl kklass kkore ktests; do
    if [[ -e $ROOT/$n/.git ]]; then
        DIRS[$n]=1
        load_repo "$n/" "$ROOT/$n"
    fi
done

# select the source files
select_files() {
    local a p f k i
    local -a keys=() extra=()
    if ((${#ARGS[@]} == 0)); then SRC=("${FILES[@]}"); return; fi
    for a in "${ARGS[@]}"; do
        p=$a
        while [[ $p == ./* ]]; do p=${p#./}; done
        p=${p%/}
        [[ -e $ROOT/$p ]] || die_usage "no such path: $a"
        [[ $p != . && -n $p ]] || { SRC=("${FILES[@]}"); return; }
        keys+=("$p")
    done
    for f in "${FILES[@]}"; do
        INSRC[$f]=1
        for k in "${keys[@]}"; do
            if [[ $f == "$k" || $f == "$k"/* ]]; then SRC+=("$f"); break; fi
        done
    done
    for k in "${keys[@]}"; do   # an existing .md that git does not list (not yet added)
        if [[ $k == *.md && -f $ROOT/$k && -z ${INSRC[$k]-} ]]; then SRC+=("$k"); INSRC[$k]=1; fi
    done
}
select_files

# ---- slugs --------------------------------------------------------------------
slugify() {   # TEXT -> SLUG (global; never $(...))
    local t=$1 i c c2 out='' len
    if [[ -z ${t//[ -~]/} ]]; then   # printable ASCII only
        t=${t,,}
        t=${t// /-}
        SLUG=${t//[^a-z0-9_-]/}
        return
    fi
    # (no ${t,,} here: some C locales lower-case bytes >= 0x80, e.g. 0xD0 -> 0xF0)
    len=${#t}
    for ((i = 0; i < len; i++)); do
        c=${t:i:1}
        case $c in
            [a-z0-9_-]) out+=$c ;;
            [A-Z]) out+=${c,,} ;;
            ' ') out+=- ;;
            $'\xd0' | $'\xd1') c2=${t:i+1:1}; out+=${CYR["$c$c2"]-$c$c2}; i=$((i + 1)) ;;
        esac
    done
    SLUG=$out
}

add_slug() {   # FILE SLUG
    local k=$1$SEP$2 n
    if [[ -z ${HAS["$k"]-} ]]; then HAS["$k"]=1; SEEN["$k"]=0; return; fi
    n=${SEEN["$k"]}
    while :; do
        n=$((n + 1))
        [[ -n ${HAS["$k-$n"]-} ]] || break
    done
    SEEN["$k"]=$n
    HAS["$k-$n"]=1
}

# ---- links in one line --------------------------------------------------------
compute_spans() {   # LINE -> SPS[] SPE[] NSPAN (code spans, byte offsets, end exclusive)
    local rest=$1 off=0 pre run n=0 i j
    local -a rs=() rl=()
    NSPAN=0 SPS=() SPE=()
    while [[ $rest == *'`'* ]]; do
        pre=${rest%%\`*}
        rest=${rest:${#pre}}
        run=0
        while [[ $rest == '`'* ]]; do rest=${rest#\`}; run=$((run + 1)); done
        rs[n]=$((off + ${#pre})); rl[n]=$run; n=$((n + 1))
        off=$((off + ${#pre} + run))
    done
    for ((i = 0; i < n; i++)); do
        for ((j = i + 1; j < n; j++)); do
            if ((rl[j] == rl[i])); then
                SPS[NSPAN]=${rs[i]}; SPE[NSPAN]=$((rs[j] + rl[j])); NSPAN=$((NSPAN + 1))
                i=$j
                break
            fi
        done
    done
}
in_span() {   # POS
    local k
    for ((k = 0; k < NSPAN; k++)); do
        (($1 >= SPS[k] && $1 < SPE[k])) && return 0
    done
    return 1
}

extract_links() {   # uses $line and $n of scan_file; appends "LINE SEP TARGET" to LK
    local s=$line pos=0 rest before p i c depth open after t consumed inner
    NSPAN=0
    [[ $s != *'`'* ]] || compute_spans "$s"
    while :; do
        rest=${s:pos}
        [[ $rest == *']('* ]] || break
        before=${rest%%']('*}
        p=$((pos + ${#before}))
        pos=$((p + 2))
        if ((NSPAN)); then in_span "$p" && continue; fi
        depth=0 open=-1
        for ((i = p - 1; i >= 0; i--)); do
            c=${s:i:1}
            [[ $c == '[' || $c == ']' ]] || continue
            if ((NSPAN)); then in_span "$i" && continue; fi
            if [[ $c == ']' ]]; then depth=$((depth + 1))
            elif ((depth == 0)); then open=$i; break
            else depth=$((depth - 1)); fi
        done
        ((open >= 0)) || continue
        after=${s:pos}
        if [[ $after =~ $RE_ANGLE ]]; then
            t=${BASH_REMATCH[1]}; consumed=${#BASH_REMATCH[0]}
        elif [[ $after =~ $RE_PLAIN ]]; then
            t=${BASH_REMATCH[1]}; consumed=${#BASH_REMATCH[0]}
        else   # balanced parentheses, e.g. a URL with (v=vs.85)
            depth=1 consumed=-1
            for ((i = 0; i < ${#after}; i++)); do
                c=${after:i:1}
                if [[ $c == '(' ]]; then depth=$((depth + 1))
                elif [[ $c == ')' ]]; then
                    depth=$((depth - 1))
                    if ((depth == 0)); then consumed=$((i + 1)); break; fi
                fi
            done
            ((consumed >= 0)) || continue
            inner=${after:0:consumed-1}
            inner=${inner#"${inner%%[![:space:]]*}"}
            inner=${inner%"${inner##*[![:space:]]}"}
            if [[ $inner =~ $RE_TITLED ]]; then t=${BASH_REMATCH[1]}
            elif [[ $inner == *[[:space:]]* ]]; then continue
            else t=$inner; fi
        fi
        pos=$((pos + consumed))
        LK+=$n$SEP$t$'\n'
    done
}

# ---- one file: slugs and links, scanned once -----------------------------------
scan_file() {   # PATH (root-relative)
    local f=$1 line n=0 fch='' flen=0 run rest prev='' text
    SCANNED[$f]=1
    LK=''
    if [[ ! -f $ROOT/$f ]]; then LINKS[$f]=''; return; fi
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        if [[ $line == [\ \`~]* && $line =~ $RE_FENCE ]]; then
            run=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
            if [[ -n $fch ]]; then
                if [[ ${run:0:1} == "$fch" && ${#run} -ge $flen && $rest != *[![:space:]]* ]]; then fch=''; fi
                prev=''
                continue
            elif [[ ${run:0:1} == '~' || $rest != *'`'* ]]; then
                fch=${run:0:1} flen=${#run} prev=''
                continue
            fi
        fi
        [[ -z $fch ]] || continue
        if [[ $line == [\ \#]* && $line =~ $RE_HEAD ]]; then
            text=${BASH_REMATCH[1]}
            text=${text%"${text##*[![:space:]]}"}
            if [[ $text =~ $RE_CLOSE ]]; then
                text=${BASH_REMATCH[1]}
                text=${text%"${text##*[![:space:]]}"}
            elif [[ $text == +('#') ]]; then text=''; fi
            text=${text#"${text%%[![:space:]]*}"}
            slugify "$text"
            [[ -z $SLUG ]] || add_slug "$f" "$SLUG"
            prev=''
        else
            if [[ $line == [=\ -]* && $line =~ $RE_SETEXT && -n $prev && ! $prev =~ $RE_NOTTEXT ]]; then
                NOTES+=("$f:$n")
            fi
            prev=$line
        fi
        if [[ $line == *']('* ]]; then extract_links; fi
    done < "$ROOT/$f"
    LINKS[$f]=$LK
}

# ---- resolving one link -----------------------------------------------------------
normalize() {   # PATH -> NORM (no leading/trailing /, . and .. folded), ESC=1 above the root
    local IFS=/ part
    local -a st=() parts
    ESC=0
    set -f
    parts=($1)
    set +f
    for part in "${parts[@]}"; do
        case $part in
            .) ;;
            ..) if ((${#st[@]})); then unset 'st[${#st[@]}-1]'; else ESC=1; fi ;;
            *) st+=("$part") ;;
        esac
    done
    NORM="${st[*]}"
}

disk_ok() {   # NORM ISDIR - exists on disk with its basename in a glob of the parent (exact case)
    local p=$1 parent base f
    [[ -e $ROOT/$p ]] || return 1
    if (($2)); then [[ -d $ROOT/$p ]] || return 1; fi
    if [[ $p == */* ]]; then parent=$ROOT/${p%/*} base=${p##*/}; else parent=$ROOT base=$p; fi
    for f in "$parent"/* "$parent"/.*; do
        [[ ${f##*/} == "$base" ]] && return 0
    done
    return 1
}

anchor_ok() {   # NORM FRAG
    local f=$1 frag=$2
    [[ -n $frag ]] || return 0
    if [[ $f == *.md ]]; then
        [[ -n ${SCANNED[$f]-} ]] || scan_file "$f"
        [[ -n ${HAS["$f$SEP$frag"]-} ]]
        return
    fi
    case ${f##*.} in
        html | htm | png | jpg | jpeg | gif | svg | pdf | ico) return 0 ;;
    esac
    [[ $frag =~ $RE_LINE ]]
}

resolve() {   # FILE TARGET -> RES: 0 ok, 1 no such file, 2 no such anchor, 3 skipped
    local file=$1 t=$2 path frag='' dir='' isdir=0 exists=0
    RES=3
    [[ -n $t ]] || return 0
    if [[ $t =~ $RE_SCHEME || $t == /* ]]; then return 0; fi
    if [[ $t == *'#'* ]]; then path=${t%%'#'*} frag=${t#*'#'}; else path=$t; fi
    if [[ -z $path ]]; then
        NORM=$file
    else
        [[ $path != */ ]] || isdir=1
        [[ $file != */* ]] || dir=${file%/*}/
        normalize "$dir$path"
        if ((ESC)); then RES=1; return 0; fi
        if [[ -z $NORM ]]; then exists=1
        elif ((isdir)); then [[ -z ${DIRS["$NORM"]-} ]] || exists=1
        elif [[ -n ${TRACKED["$NORM"]-} || -n ${DIRS["$NORM"]-} ]]; then exists=1
        fi
        if ((!exists)) && disk_ok "$NORM" "$isdir"; then exists=1; fi
        if ((!exists)); then RES=1; return 0; fi
    fi
    if [[ $t == *'#'* ]] && ! anchor_ok "$NORM" "$frag"; then RES=2; return 0; fi
    RES=0
}

# ---- main ---------------------------------------------------------------------------
NFILES=0 NLINKS=0 NBROKEN=0
for f in "${SRC[@]}"; do
    NFILES=$((NFILES + 1))
    [[ -n ${SCANNED[$f]-} ]] || scan_file "$f"
    links=${LINKS[$f]-}
    [[ -n $links ]] || continue
    while IFS=$SEP read -r ln tg; do
        resolve "$f" "$tg"
        case $RES in
            3) ;;
            0) NLINKS=$((NLINKS + 1))
               if ((LIST)); then printf '%s:%s: ok: %s\n' "$f" "$ln" "$tg"; fi ;;
            *) NLINKS=$((NLINKS + 1)); NBROKEN=$((NBROKEN + 1))
               if ((!LIST)); then
                   if ((RES == 1)); then why='no such file'; else why='no such anchor'; fi
                   printf '%s:%s: broken: %s (%s)\n' "$f" "$ln" "$tg" "$why"
               fi ;;
        esac
    done <<<"$links"
done

for x in "${NOTES[@]}"; do
    printf 'mdlinks: note: setext heading underline not handled at %s\n' "$x" >&2
done
printf 'mdlinks: %d file(s), %d link(s), %d broken\n' "$NFILES" "$NLINKS" "$NBROKEN" >&2
((NBROKEN == 0)) || exit 1
exit 0
