#!/usr/bin/env bash
# candidate list: lexical matches, false positives expected; indirect = the command named in an assignment, a ${X:-default} or a lookup (type -P/command -v/hash/which)
#
# External-tool table: which external binaries each unit calls, split into
# unit code and unit tests.
#
#   tools.sh [ROOT]
#
# ROOT defaults to the folder two levels above this script. File set, `unit`
# and `class` rules are those of scan.sh (see lib.sh); class is collapsed to
#   code = core, wrapper, harness      test = test, bench, docs
#
# via=direct: a candidate command word at a command position: after line
# start, `;`, `|`, `&`, `(`, `$(`, a backquote, `then`, `do`, `else`, `if`,
# `elif`, `while`, `until`, `!`, `{` (so also after `&&` and `||`), optionally
# behind `exec`/`command` and `VAR=value ` assignments.
# via=indirect: a candidate word that is
#   (i)   the whole right-hand side of an assignment: NAME=cmd, NAME="cmd",
#         NAME='cmd' (also behind local/declare/readonly/export and inside
#         `local a=x b=cmd` lists);
#   (ii)  the default/alternative of a parameter expansion: ${X:-cmd}
#         ${X-cmd} ${X:=cmd} ${X=cmd};
#   (iii) an argument of `type -P|-p|-t`, `command -v|-V`, `hash`, `which`.
# Comment-only lines are skipped. Purely lexical: quoting and heredoc bodies
# are not understood. `hits` counts occurrences, not lines; a line can yield
# both kinds, each kind is counted on its own.
#
# Output (stdout, TSV, sorted in the C locale by unit, class, command, via):
#   unit<TAB>class<TAB>command<TAB>via<TAB>builtin<TAB>hits<TAB>files
# files = up to 5 paths, `;`-separated, then `;+N` when N more files exist.

set -u
export LC_ALL=C

root=${1:-}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -n "$root" ] || root=$here/../..
root=$(cd "$root" && pwd) || { echo "tools.sh: bad root" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/tools.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

. "$here/lib.sh"
list=$work/files.0
porting_filelist "$root" "$list"

cmds='awk gawk sed grep egrep find xargs head tail cat tac sort uniq cut tr wc
paste join comm fold column split stat date touch mktemp mkdir rmdir rm mv cp ln
readlink realpath basename dirname chmod chown ls du df env timeout sleep nc ncat
ps pgrep pkill kill od xxd hexdump base64 md5sum sha1sum sha256sum cksum openssl
iconv diff cmp patch tar gzip xz curl wget git python python3 perl node ruby
tput stty uname hostname whoami id getconf flock setsid nohup stdbuf seq shuf
printf echo test true false yes tee'
builtins='printf echo test true false'

# ---- pass 1: per (file, command, via) occurrence counts ---------------------
{
    printf '%s\n' "$PORTING_AWK_FUNCS"
    cat <<'AWKEOF'
function inc(w, via) { cnt[cur SUBSEP w SUBSEP via]++ }
function unq(w) { gsub(/^["'(]+|["')]+$/, "", w); return w }
# lookup command segment: type/command/hash/which and their arguments
function lookup(s,   n, a, i, w, opts, words, nw) {
    n = split(s, a, /[ \t]+/)
    opts = ""; nw = 0
    for (i = 2; i <= n; i++) {
        if (a[i] ~ /^-/) { opts = opts substr(a[i], 2); continue }
        words[++nw] = unq(a[i])
    }
    if (a[1] == "type" && opts !~ /[Ppt]/) return
    if (a[1] == "command" && opts !~ /[vV]/) return
    for (i = 1; i <= nw; i++) if (words[i] in want) inc(words[i], "indirect")
}
BEGIN {
    n = split(cmds, c, /[ \n]+/)
    for (i = 1; i <= n; i++) if (c[i] != "") want[c[i]] = 1
    n = split(builtins, c, / /)
    for (i = 1; i <= n; i++) isb[c[i]] = 1
    kwre = "(^|[ \t])(then|do|else)([ \t]|$)"
}
FNR == 1 { cur = FILENAME }
{
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*#/) next

    # --- indirect (i): NAME=cmd, NAME="cmd", NAME='cmd'
    s = line
    while (match(s, /(^|[ \t;|&(])[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=("[A-Za-z0-9_.+-]+"|'[A-Za-z0-9_.+-]+'|[A-Za-z0-9_.+-]+)([ \t;|&)]|$)/)) {
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH - 1)
        sub(/^[^=]*=/, "", m)
        sub(/[ \t;|&)]$/, "", m)
        m = unq(m)
        if (m in want) inc(m, "indirect")
    }
    # --- indirect (ii): ${X:-cmd} ${X-cmd} ${X:=cmd} ${X=cmd}
    s = line
    while (match(s, /\$\{[A-Za-z_][A-Za-z0-9_]*(:-|:=|-|=)[^}]*\}/)) {
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        sub(/^\$\{[A-Za-z_][A-Za-z0-9_]*(:-|:=|-|=)/, "", m)
        sub(/\}$/, "", m)
        m = unq(m)
        if (m in want) inc(m, "indirect")
    }

    # --- direct, and indirect (iii), per command segment
    # function definitions `name()` are not calls
    gsub(/[A-Za-z_][A-Za-z0-9_.:-]*[ \t]*\([ \t]*\)/, " ", line)
    gsub(/\$\(|[;|&(`]/, "&\001", line)
    gsub(kwre, "&\001", line)
    m = split(line, seg, "\001")
    for (k = 1; k <= m; k++) {
        s = seg[k]
        sub(/^[ \t]+/, "", s)
        for (;;) {
            if (s ~ /^(then|do|else|if|elif|while|until|!|\{)[ \t]+/) {
                sub(/^(then|do|else|if|elif|while|until|!|\{)[ \t]+/, "", s); continue }
            if (s ~ /^command[ \t]+-[vV]([ \t]|$)/) break
            if (s ~ /^(exec|command)[ \t]+/) { sub(/^(exec|command)[ \t]+/, "", s); continue }
            if (s ~ /^[A-Za-z_][A-Za-z0-9_]*=([^ \t"']|"[^"]*"|'[^']*')*[ \t]+/) {
                sub(/^[A-Za-z_][A-Za-z0-9_]*=([^ \t"']|"[^"]*"|'[^']*')*[ \t]+/, "", s); continue }
            break
        }
        if (!match(s, /^[A-Za-z0-9_.+-]+/)) continue
        w = substr(s, 1, RLENGTH)
        nx = substr(s, RLENGTH + 1, 1)
        if (!(nx == "" || nx ~ /[ \t)<>]/)) continue
        if (w == "type" || w == "command" || w == "hash" || w == "which") { lookup(s); continue }
        if (!(w in want)) continue
        inc(w, "direct")
    }
}
END {
    for (k in cnt) {
        split(k, p, SUBSEP)
        u = unitof(p[1])
        cl = classify(p[1], u)
        cl = (cl == "core" || cl == "wrapper" || cl == "harness") ? "code" : "test"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\n", u, cl, p[2], p[3], (p[2] in isb) ? "yes" : "no", p[1], cnt[k]
    }
}
AWKEOF
} > "$work/pass1.awk"

( cd "$root" && xargs -0 awk -v cmds="$cmds" -v builtins="$builtins" \
      -f "$work/pass1.awk" -- < "$work/files.0" ) | sort -t $'\t' -k1,1 -k2,2 -k3,3 -k4,4 -k6,6 > "$work/pass1.tsv"

# ---- pass 2: aggregate per (unit, class, command, via) -----------------------
printf 'unit\tclass\tcommand\tvia\tbuiltin\thits\tfiles\n'
awk -F'\t' '
function flush() {
    if (key == "") return
    out = ""
    for (i = 1; i <= nf && i <= 5; i++) out = out (i > 1 ? ";" : "") fl[i]
    if (nf > 5) out = out ";+" (nf - 5)
    printf "%s\t%s\t%s\t%s\t%s\t%d\t%s\n", u, c, w, v, b, hits, out
}
{
    k = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
    if (k != key) { flush(); key = k; u = $1; c = $2; w = $3; v = $4; b = $5; hits = 0; nf = 0 }
    hits += $7; fl[++nf] = $6
}
END { flush() }' "$work/pass1.tsv"
