#!/usr/bin/env bash
# tools/bench/prepare.sh DEST SPEC... -- build the bench sides for bench.sh.
# Run from the kbool root of a checkout with submodules (git needed).
#
# SPEC = NAME=PIN[,PIN...]      PIN = [SUB@]REF[+PATCH]
#   SUB    the submodule the pin applies to: `kklass` (the default: a bare REF
#          pins kklass, as before) or `kcl` (for the fv suite)
#   REF    `pointer` (the submodule as checked out in this tree) or any ref of
#          its origin (Keksov/kklass, Keksov/kcl: branch, tag, sha): a commit
#          already present is used as is, anything else is fetched. A short
#          sha works only where the commit is present; CI's submodules are
#          shallow: there give a branch, a tag or a full 40-character sha
#   PATCH  optional: a file under tools/bench/variants/, applied to the side's
#          SUB with `patch -p1` (a bisection variant)
#   e.g.   old=main  cur=pointer  fvold=kcl@da4c745  both=v0.1.1,kcl@perf+x.patch
# A submodule no pin names stays as checked out. Each side is a copy of the
# kbool tree without .git at DEST/NAME, with DEST/NAME/.bench_rev naming what
# it holds: line 1 its kklass ("<sha> <subject> [+PATCH]", as before), line 2
# "kcl <sha> <subject> [+PATCH]".
# Prints `NAME=DEST/NAME` per side (the arguments for bench.sh).
set -eu

die() { echo "prepare.sh: $*" >&2; exit 2; }
DEST=${1:?usage: prepare.sh DEST NAME=[SUB@]REF[+PATCH][,...]...}
shift
[[ -f kbool.sh && -d kklass && -d kcl ]] || die "run from the kbool root"
mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd)

# pin SIDE SUB REF PATCH -> REV: the side's SUB at REF, patched
pin() {
    local side=$1 sub=$2 ref=$3 patch=$4 depth p
    if [[ $ref == pointer ]]; then
        REV=$(git -C "$sub" log -1 --format='%h %s')
    elif [[ $ref != */* ]] && git -C "$sub" rev-parse -q --verify "$ref^{commit}" >/dev/null; then
        # a commit already present (a short sha, a local branch or tag): no fetch
        # (a short sha is no remote ref; `origin/x` and remote names still fetch below)
        rm -rf "${side:?}/$sub"
        mkdir -p "$side/$sub"
        git -C "$sub" archive "$ref" | (cd "$side/$sub" && tar -xf -)
        REV=$(git -C "$sub" log -1 --format='%h %s' "$ref")
    else
        # --depth only in a shallow clone (CI): in a full one it would make it shallow
        depth=()
        [[ $(git -C "$sub" rev-parse --is-shallow-repository) == true ]] && depth=(--depth=1)
        git -C "$sub" fetch -q "${depth[@]}" origin "$ref" || die "cannot fetch $sub ref '$ref'"
        rm -rf "${side:?}/$sub"
        mkdir -p "$side/$sub"
        git -C "$sub" archive FETCH_HEAD | (cd "$side/$sub" && tar -xf -)
        REV=$(git -C "$sub" log -1 --format='%h %s' FETCH_HEAD)
    fi
    if [[ -n $patch ]]; then
        p=$PWD/tools/bench/variants/$patch
        [[ -f $p ]] || die "no variant $p"
        (cd "$side/$sub" && patch -s -p1 < "$p") || die "variant $patch does not apply to $sub of $(basename "$side")"
        REV+=" +$patch"
    fi
}

for spec in "$@"; do
    [[ $spec == ?*=?* ]] || die "bad spec '$spec' (NAME=[SUB@]REF[+PATCH][,...])"
    name=${spec%%=*}
    declare -A want=()
    pinlist=${spec#*=}
    # read -a drops a trailing empty field: an empty pin anywhere is refused here
    [[ $pinlist == ,* || $pinlist == *, || $pinlist == *,,* ]] && die "bad spec '$spec': an empty pin"
    IFS=, read -r -a pins <<< "$pinlist"
    for p in "${pins[@]}"; do
        sub=kklass
        case $p in
            kklass@*|kcl@*) sub=${p%%@*} p=${p#*@} ;;
        esac
        [[ -n $p && $p != +* ]] || die "bad spec '$spec': an empty $sub ref"
        [[ -z ${want[$sub]-} ]] || die "bad spec '$spec': $sub pinned twice"
        want[$sub]=$p
    done
    side=$DEST/$name
    rm -rf "$side"
    mkdir -p "$side"
    tar --exclude=.git -cf - . | (cd "$side" && tar -xf -)
    revs=()
    for sub in kklass kcl; do
        ref=${want[$sub]:-pointer} patch=""
        if [[ $ref == *+* ]]; then patch=${ref#*+}; ref=${ref%%+*}; fi
        pin "$side" "$sub" "$ref" "$patch"
        revs+=("$REV")
    done
    unset want
    printf '%s\nkcl %s\n' "${revs[0]}" "${revs[1]}" > "$side/.bench_rev"
    printf '%s=%s\n' "$name" "$side"
done
