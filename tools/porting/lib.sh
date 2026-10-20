# Shared helpers for the tools/porting scripts. Source it, do not run it.
#
#   porting_filelist ROOT LISTFILE
#       Writes the NUL-separated list of shell files of the kbool tree
#       (paths relative to ROOT) to LISTFILE: `git ls-files` of ROOT and of
#       kcl kklass kkore ktests, kept when the name ends in .sh or the first
#       line starts with "#!".
#
#   PORTING_AWK_FUNCS
#       awk source defining classify(path, unit) -> core|wrapper|harness|
#       test|bench|docs and unitof(path) -> kbool|kkore|kklass|ktests|kcl/<unit>.

porting_filelist() {
    local root=$1 list=$2 repo prefix f p first
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
}

read -r -d '' PORTING_AWK_FUNCS <<'AWKEOF'
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
AWKEOF
