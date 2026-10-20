#!/usr/bin/env bash
# Portability scanner: greps the tracked shell files of the kbool tree for
# constructs listed in patterns.tsv and prints one TSV row per hit.
#
#   scan.sh [--summary] [ROOT]
#
# ROOT defaults to the folder two levels above this script. Files scanned:
# `git ls-files` of ROOT and of kcl kklass kkore ktests, kept when the name
# ends in .sh or the first line starts with "#!". Comment-only lines are
# skipped (except for P01). Plain bash + grep + awk + sort; no kbool.
#
# Output: pattern<TAB>file<TAB>line<TAB>unit<TAB>class<TAB>text
# --summary: one line per pattern with hit counts per class.

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
root=$(cd "$root" && pwd) || { echo "scan.sh: bad root" >&2; exit 2; }
patterns=$here/patterns.tsv
[ -f "$patterns" ] || { echo "scan.sh: no $patterns" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/scan.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

# ---- file list (NUL separated, paths relative to the kbool root) ----------
. "$here/lib.sh"
list=$work/files.0
porting_filelist "$root" "$list"

# ---- post-processor: grep -n output -> TSV rows for one pattern -----------
post=$PORTING_AWK_FUNCS'
{
    i = index($0, ":"); file = substr($0, 1, i - 1); rest = substr($0, i + 1)
    j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)
    sub(/\r$/, "", text)
    if (id != "P01" && text ~ /^[ \t]*#/) next
    gsub(/\t/, " ", text)
    sub(/^ +/, "", text); sub(/ +$/, "", text)
    text = substr(text, 1, 160)
    u = unitof(file)
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, file, line, u, classify(file, u), text
}'

emit() {
    local id name regex note
    while IFS=$'\t' read -r id name regex note; do
        [ "$id" = id ] && continue
        [ -n "$id" ] || continue
        ( cd "$root" && xargs -0 grep -anHE -e "$regex" -- < "$list" 2>/dev/null ) |
            awk -v id="$id" "$post" |
            sort -t $'\t' -k2,2 -k3,3n
    done < "$patterns"
}

if [ "$summary" -eq 0 ]; then
    printf 'pattern\tfile\tline\tunit\tclass\ttext\n'
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
        ids[++m] = f[1]; names[f[1]] = f[2]
    }
}
{ cnt[$1 SUBSEP $5]++ }
END {
    for (k = 1; k <= m; k++) {
        id = ids[k]
        s = id " " names[id] "  "
        for (c = 1; c <= n; c++) s = s (c > 1 ? " " : "") cls[c] "=" (cnt[id SUBSEP cls[c]] + 0)
        print s
    }
}' "$work/hits.tsv"
