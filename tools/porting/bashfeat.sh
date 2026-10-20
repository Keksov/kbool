#!/usr/bin/env bash
# Bash-feature map: greps the tracked shell files of the kbool tree for
# version-dependent bash features listed in bashfeatures.tsv and prints one
# TSV row per hit. File set, unit and class rules are the same as scan.sh.
#
#   bashfeat.sh [--summary] [ROOT]
#
# ROOT defaults to the folder two levels above this script. Files scanned:
# `git ls-files` of ROOT and of kcl kklass kkore ktests, kept when the name
# ends in .sh or the first line starts with "#!". Comment-only lines are
# skipped. Plain bash + grep + awk + sort; no kbool.
#
# bashfeatures.tsv columns: id<TAB>min<TAB>feature<TAB>regex (ERE).
# Output: feature<TAB>min<TAB>file<TAB>line<TAB>unit<TAB>class<TAB>text
# --summary: one line per feature with hit counts per class.
# Static matching finds only where a feature is written, not how it behaves.

set -u
export LC_ALL=C
summary=0
root=''
for a in "$@"; do
    case "$a" in
        --summary) summary=1 ;;
        *) root=$a ;;
    esac
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -n "$root" ] || root=$here/../..
root=$(cd "$root" && pwd) || { echo "bashfeat.sh: bad root" >&2; exit 2; }
patterns=$here/bashfeatures.tsv
[ -f "$patterns" ] || { echo "bashfeat.sh: no $patterns" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/bashfeat.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

# ---- file list (NUL separated, paths relative to the kbool root) ----------
list=$work/files.0
: > "$list"
for repo in . kcl kklass kkore ktests; do
    [ -d "$root/$repo" ] || continue
    prefix=''
    [ "$repo" = . ] || prefix=$repo/
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        p=$prefix$f
        [ -f "$root/$p" ] || continue
        case "$p" in
            *.sh) ;;
            *)
                first=''
                IFS= read -r -n 2 first < "$root/$p" || true
                [ "$first" = '#!' ] || continue
                ;;
        esac
        printf '%s\0' "$p" >> "$list"
    done < <(git -C "$root/$repo" ls-files)
done

# ---- post-processor: grep -n output -> TSV rows for one feature -----------
post='
function classify(p, unit,   c) {
    if (index(p, "/tests/")) return "test"
    if (index(p, "/bench") || p ~ /(^|\/)bench[^\/]*\.sh$/) return "bench"
    if (index(p, "/docs/") || index(p, "/examples/")) return "docs"
    if (index(p, "ktests/tools/")) return "harness"
    if (unit ~ /^kcl\/(tsed|tawk|tfind|tgrep|thead|ttail|tpipe|tutil)$/) return "wrapper"
    return "core"
}
function unitof(p,   a, n) {
    n = split(p, a, "/")
    if (a[1] == "kcl") return (n > 2) ? "kcl/" a[2] : "kcl"
    if (a[1] == "kkore" || a[1] == "kklass" || a[1] == "ktests") return a[1]
    return "kbool"
}
{
    i = index($0, ":"); file = substr($0, 1, i - 1); rest = substr($0, i + 1)
    j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)
    sub(/\r$/, "", text)
    if (text ~ /^[ \t]*#/) next
    gsub(/\t/, " ", text)
    sub(/^ +/, "", text); sub(/ +$/, "", text)
    text = substr(text, 1, 160)
    u = unitof(file)
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, min, file, line, u, classify(file, u), text
}'

emit() {
    local id min name regex
    while IFS=$'\t' read -r id min name regex; do
        [ "$id" = id ] && continue
        [ -n "$id" ] || continue
        ( cd "$root" && xargs -0 grep -anHE -e "$regex" -- < "$list" 2>/dev/null ) |
            awk -v id="$id" -v min="$min" "$post" |
            sort -t $'\t' -k3,3 -k4,4n
    done < "$patterns"
}

if [ "$summary" -eq 0 ]; then
    printf 'feature\tmin\tfile\tline\tunit\tclass\ttext\n'
    emit
    exit 0
fi

emit > "$work/hits.tsv"
awk -F'\t' -v pat="$patterns" '
BEGIN {
    n = split("core wrapper harness test bench docs", cls, " ")
    while ((getline l < pat) > 0) {
        split(l, f, "\t")
        if (f[1] == "id" || f[1] == "") continue
        ids[++m] = f[1]; mins[f[1]] = f[2]; names[f[1]] = f[3]
    }
}
{ cnt[$1 SUBSEP $6]++ }
END {
    for (k = 1; k <= m; k++) {
        id = ids[k]
        s = id " " mins[id] " " names[id] "  "
        for (c = 1; c <= n; c++) s = s (c > 1 ? " " : "") cls[c] "=" (cnt[id SUBSEP cls[c]] + 0)
        print s
    }
}' "$work/hits.tsv"
