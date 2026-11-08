#!/usr/bin/env bash
# tools/bench/prepare.sh DEST SPEC... -- build the bench sides for bench.sh.
# Run from the kbool root of a checkout with submodules (git needed).
#
# SPEC = NAME=REF[+PATCH]
#   REF    `pointer` (kklass at kbool's submodule pointer, i.e. as checked out)
#          or any ref of Keksov/kklass (branch, tag, sha): fetched from origin
#   PATCH  optional: a file under tools/bench/variants/, applied to the side's
#          kklass with `patch -p1` (a bisection variant)
# Each side is a copy of the kbool tree without .git at DEST/NAME, with
# DEST/NAME/.bench_rev naming its kklass ("<sha> <subject> [+PATCH]").
# Prints `NAME=DEST/NAME` per side (the arguments for bench.sh).
set -eu

die() { echo "prepare.sh: $*" >&2; exit 2; }
DEST=${1:?usage: prepare.sh DEST NAME=REF[+PATCH]...}
shift
[[ -f kbool.sh && -d kklass ]] || die "run from the kbool root"
mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd)

for spec in "$@"; do
    [[ $spec == ?*=?* ]] || die "bad spec '$spec' (NAME=REF[+PATCH])"
    name=${spec%%=*} ref=${spec#*=} patch=""
    if [[ $ref == *+* ]]; then patch=${ref#*+}; ref=${ref%%+*}; fi
    side=$DEST/$name
    rm -rf "$side"
    mkdir -p "$side"
    tar --exclude=.git -cf - . | (cd "$side" && tar -xf -)
    if [[ $ref == pointer ]]; then
        rev=$(git -C kklass log -1 --format='%h %s')
    elif [[ $ref != */* ]] && git -C kklass rev-parse -q --verify "$ref^{commit}" >/dev/null; then
        # a commit already present (a short sha, a local branch or tag): no fetch
        # (a short sha is no remote ref; `origin/x` and remote names still fetch below)
        rm -rf "$side/kklass"
        mkdir -p "$side/kklass"
        git -C kklass archive "$ref" | (cd "$side/kklass" && tar -xf -)
        rev=$(git -C kklass log -1 --format='%h %s' "$ref")
    else
        # --depth only in a shallow clone (CI): in a full one it would make it shallow
        depth=()
        [[ $(git -C kklass rev-parse --is-shallow-repository) == true ]] && depth=(--depth=1)
        git -C kklass fetch -q "${depth[@]}" origin "$ref" || die "cannot fetch kklass ref '$ref'"
        rm -rf "$side/kklass"
        mkdir -p "$side/kklass"
        git -C kklass archive FETCH_HEAD | (cd "$side/kklass" && tar -xf -)
        rev=$(git -C kklass log -1 --format='%h %s' FETCH_HEAD)
    fi
    if [[ -n $patch ]]; then
        p=$PWD/tools/bench/variants/$patch
        [[ -f $p ]] || die "no variant $p"
        (cd "$side/kklass" && patch -s -p1 < "$p") || die "variant $patch does not apply to $name"
        rev+=" +$patch"
    fi
    printf '%s\n' "$rev" > "$side/.bench_rev"
    printf '%s=%s\n' "$name" "$side"
done
