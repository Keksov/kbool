#!/usr/bin/env bash
# Tests of tools/porting/mdlinks.sh. The fixture tree (a git repo plus a nested
# kcl repo) is built in a temp dir; nothing of the real tree is read.
# Prints `PASS n/n` (rc 0) or the failures (rc 1).
# Run with either bash:  TMPDIR=$SCRATCH bash tools/porting/tests/mdlinks/run.sh

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
M=$HERE/../../mdlinks.sh

W=$(mktemp -d "${TMPDIR:-/tmp}/mdlinks.XXXXXX") || exit 1
cleanup() { rm -rf "$W"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

N=0 NFAIL=0
FAILS=()
t_eq() {   # NAME EXPECTED ACTUAL
    N=$((N + 1))
    if [[ $2 == "$3" ]]; then return 0; fi
    NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: expected [$2] got [$3]")
}
t_has() {  # NAME TEXT LINE   (the exact line is present)
    N=$((N + 1))
    if [[ $'\n'$2$'\n' == *$'\n'"$3"$'\n'* ]]; then return 0; fi
    NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: missing line [$3] in:" "$2")
}
t_no() {   # NAME TEXT LINE   (the exact line is absent)
    N=$((N + 1))
    if [[ $'\n'$2$'\n' != *$'\n'"$3"$'\n'* ]]; then return 0; fi
    NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: unexpected line [$3] in:" "$2")
}
t_nosub() {  # NAME TEXT SUBSTRING   (absent)
    N=$((N + 1))
    if [[ $2 != *"$3"* ]]; then return 0; fi
    NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: unexpected [$3] in:" "$2")
}

# run_m ARGS...: OUT = stdout, ERR = stderr, RC; the fixture root is $T
run_m() {
    OUT=$("$BASH" "$M" --root "$T" "$@" 2>"$W/err"); RC=$?
    ERR=$(<"$W/err")
}
# ln FILE MARKER: the line number of the first line of $T/FILE containing MARKER
ln() { local n; n=$(grep -n -F -- "$2" "$T/$1" | head -1); echo "${n%%:*}"; }
b() { printf '%s:%s: broken: %s (%s)' "$1" "$(ln "$1" "$2")" "$3" "$4"; }   # FILE MARKER TARGET REASON
k() { printf '%s:%s: ok: %s' "$1" "$(ln "$1" "$2")" "$3"; }               # FILE MARKER TARGET

G=(git -c user.name=t -c user.email=t@example.invalid)
T=$W/fx
mkdir -p "$T/docs" "$T/dir1"

# ---------------------------------------------------------------- fixture: root repo
cat >"$T/a.md" <<'EOF'
# Top Heading

[c01](docs/b.md) good link
[c02](docs/nope.md) missing file
[c03](dir1/) directory with slash
[c04](dir1) directory without slash
[c05](nodir/) missing directory
[c06](#top-heading) same-file anchor
[c07](#missing-one) missing same-file anchor
[c08](docs/b.md#second-part) file anchor
[c08b](docs/b.md#nope) missing file anchor
[c11](code.sh#L311) line anchor on a script
[c11b](code.sh#L3-L9) line range on a script
[c12](code.sh#foo) other anchor on a script
[c13](docs/B.md) wrong case in the basename
[c14](late.md) untracked but on disk
[c15](kcl) submodule dir
[c16](kcl/) submodule dir with slash
[c17](./docs/../docs/b.md) normalised
[c18](docs/b.md "a title") with title
[c19](<docs/b.md>) angle brackets
[c20](docs/b.md#second-part "t") anchor and title
[c21](#Top-Heading) frag is compared byte-exact
EOF
cat >"$T/docs/b.md" <<'EOF'
# B

## Second part

[c09](../kcl/x.md) into the submodule
[c09b](../kcl/nothere.md) missing in the submodule
[esc](../../x.md) above the root
EOF
cat >"$T/code.sh" <<'EOF'
#!/bin/bash
echo hi
EOF
printf 'x\n' >"$T/dir1/x.txt"
cat >"$T/f.md" <<'EOF'
# Fences

```
[f01](missing_in_fence.md)
[bcdflps](,[bcdflps])*
operator[](int Index)
```

Inline `[f02](missing_in_code.md)` code, then [f02b](missing_after_code.md) a link.
Tilde fence:

~~~
[f05](missing_in_tilde.md)
```
[f06](still_in_tilde.md)
~~~

````
[f07](in_long_fence.md)
```
[f08](still_in_long.md)
````

1. an item

   ```bash
   [f03](missing_in_list_fence.md)
   ```
2. next [f04](missing_after_fence.md)

[`a[0]` index](docs/b.md) text with a code span with brackets
[`x[1]` gone](docs/gone.md) the span inside the text does not hide it
| [t01](docs/b.md) | [t02](docs/gone2.md) |
[e1]() empty
[e2](/a/b) absolute
[e3](https://example.com/a(v=vs.85).aspx) url with parentheses
[e4](mailto:x@example.invalid) mail
EOF
cat >"$T/s.md" <<'EOF'
[s1](docs/b.md) counted
[e1]() empty
[e2](/a/b) absolute
[e3](https://example.com/a(v=vs.85).aspx) parentheses in a url
[e4](http://example.invalid/x) http
EOF
cat >"$T/h.md" <<'EOF'
# Heading with `code` and *star*
## the `-0` derivation
## Same
## Same
## Same
## Как пользоваться
## Иван Ёж
## ⚠ Two FPC quirks
## 3.1 C1 — `$this.func` prints under `$( )`
## 004_Argv.sh — typed
## a — b
## 4. The template
## snake_case_name _and_ more
## Closed heading ##
### _
```
## not a heading in a fence
```

[h01](#heading-with-code-and-star)
[h02](#the--0-derivation)
[h03](#same)
[h04](#same-1)
[h05](#same-2)
[h06](#как-пользоваться)
[h07](#иван-ёж)
[h08](#-two-fpc-quirks)
[h09](#31-c1--thisfunc-prints-under--)
[h10](#004_argvsh--typed)
[h11](#a--b)
[h12](#4-the-template)
[h13](#snake_case_name-_and_-more)
[h14](#closed-heading)
[h15](#_)
EOF
cat >"$T/hbad.md" <<'EOF'
# Heading with `code` and *star*
## a — b
## Same
## Same
## Как пользоваться
```
## Fenced heading
```

[b01](#a-b)
[b02](#same-2)
[b03](#Как-пользоваться)
[b04](#как-Пользоваться)
[b05](#not-a-heading)
[b06](#fenced-heading)
EOF
cat >"$T/cy.md" <<'EOF'
# Кириллица

[cy](#кириллица)
EOF
"${G[@]}" init -q "$T"
"${G[@]}" -C "$T" add -A
printf '# Late\n' >"$T/late.md"   # on disk, never added

# ---------------------------------------------------------------- fixture: nested kcl repo
# (created after the root's add -A, so the root does not record it as an embedded repo)
mkdir -p "$T/kcl/n"
printf '# Root\n' >"$T/root.md"
"${G[@]}" -C "$T" add root.md
cat >"$T/kcl/x.md" <<'EOF'
# X

[c10](../root.md) back to the root repo
[c10b](../docs/b.md#second-part) back, with an anchor
[c10c](../../nothing.md) above the root
[c10d](n/y.md) down
EOF
cat >"$T/kcl/n/y.md" <<'EOF'
# Y
[y1](../x.md#x) up
[y2](../../root.md) up two
EOF
"${G[@]}" init -q "$T/kcl"
"${G[@]}" -C "$T/kcl" add -A

# ---------------------------------------------------------------- the full fixture run
run_m
FULL=$OUT FULLERR=$ERR FULLRC=$RC
run_m --list
LIST=$OUT LISTERR=$ERR LISTRC=$RC

# a.md
t_has c01-good      "$LIST" "$(k a.md '[c01]' docs/b.md)"
t_no  c01-notbroken "$FULL" "$(b a.md '[c01]' docs/b.md 'no such file')"
t_has c02-nofile    "$FULL" "$(b a.md '[c02]' docs/nope.md 'no such file')"
t_has c03-dirslash  "$LIST" "$(k a.md '[c03]' dir1/)"
t_has c04-dir       "$LIST" "$(k a.md '[c04]' dir1)"
t_has c05-nodir     "$FULL" "$(b a.md '[c05]' nodir/ 'no such file')"
t_has c06-anchor    "$LIST" "$(k a.md '[c06]' '#top-heading')"
t_has c07-noanchor  "$FULL" "$(b a.md '[c07]' '#missing-one' 'no such anchor')"
t_has c08-fileanch  "$LIST" "$(k a.md '[c08](' 'docs/b.md#second-part')"
t_has c08b-noanch   "$FULL" "$(b a.md '[c08b]' 'docs/b.md#nope' 'no such anchor')"
t_has c11-L311      "$LIST" "$(k a.md '[c11](' 'code.sh#L311')"
t_has c11b-Lrange   "$LIST" "$(k a.md '[c11b]' 'code.sh#L3-L9')"
t_has c12-foo       "$FULL" "$(b a.md '[c12]' 'code.sh#foo' 'no such anchor')"
t_has c13-case      "$FULL" "$(b a.md '[c13]' docs/B.md 'no such file')"
t_has c14-disk      "$LIST" "$(k a.md '[c14]' late.md)"
t_has c15-subdir    "$LIST" "$(k a.md '[c15]' kcl)"
t_has c16-subdir/   "$LIST" "$(k a.md '[c16]' kcl/)"
t_has c17-norm      "$LIST" "$(k a.md '[c17]' ./docs/../docs/b.md)"
t_has c18-title     "$LIST" "$(k a.md '[c18]' docs/b.md)"
t_has c19-angle     "$LIST" "$(k a.md '[c19]' docs/b.md)"
t_has c20-anch+tit  "$LIST" "$(k a.md '[c20]' docs/b.md#second-part)"
t_has c21-bytewise  "$FULL" "$(b a.md '[c21]' '#Top-Heading' 'no such anchor')"

# cross-repo prefix logic
t_has c09-intosub   "$LIST" "$(k docs/b.md '[c09](' ../kcl/x.md)"
t_has c09b-intosub  "$FULL" "$(b docs/b.md '[c09b]' ../kcl/nothere.md 'no such file')"
t_has esc-above     "$FULL" "$(b docs/b.md '[esc]' ../../x.md 'no such file')"
t_has c10-fromsub   "$LIST" "$(k kcl/x.md '[c10](' ../root.md)"
t_has c10b-fromsub  "$LIST" "$(k kcl/x.md '[c10b]' ../docs/b.md#second-part)"
t_has c10c-above    "$FULL" "$(b kcl/x.md '[c10c]' ../../nothing.md 'no such file')"
t_has c10d-down     "$LIST" "$(k kcl/x.md '[c10d]' n/y.md)"
t_has y1-up         "$LIST" "$(k kcl/n/y.md '[y1]' ../x.md#x)"
t_has y2-up2        "$LIST" "$(k kcl/n/y.md '[y2]' ../../root.md)"

# fences, code spans, parse corners (f.md)
for tgt in missing_in_fence.md missing_in_code.md missing_in_tilde.md still_in_tilde.md \
           in_long_fence.md still_in_long.md missing_in_list_fence.md; do
    t_nosub "f-skip-$tgt" "$FULL" "broken: $tgt "
done
t_nosub f-lookalike1 "$FULL$LIST" ',[bcdflps])*'
t_nosub f-lookalike2 "$FULL$LIST" 'int Index'
t_has f02b-after-code   "$FULL" "$(b f.md '[f02b]' missing_after_code.md 'no such file')"
t_has f04-after-fence   "$FULL" "$(b f.md '[f04]' missing_after_fence.md 'no such file')"
t_has span-in-text-ok   "$LIST" "$(k f.md '[`a[0]`' docs/b.md)"
t_has span-in-text-bad  "$FULL" "$(b f.md '[`x[1]`' docs/gone.md 'no such file')"
t_has row-1             "$LIST" "$(k f.md '[t01]' docs/b.md)"
t_has row-2             "$FULL" "$(b f.md '[t02]' docs/gone2.md 'no such file')"
t_nosub skipped-empty    "$LIST"$'\n' $'ok: \n'
t_nosub skipped-absolute "$LIST$FULL" '/a/b'
t_nosub skipped-https    "$LIST$FULL" 'vs.85'
t_nosub skipped-mailto   "$LIST$FULL" 'mailto'

# slugs (h.md, hbad.md, cy.md)
run_m h.md
t_eq h-clean-out "" "$OUT"
t_eq h-clean-rc 0 "$RC"
t_eq h-clean-sum 'mdlinks: 1 file(s), 15 link(s), 0 broken' "$ERR"
run_m hbad.md
t_has b01-collapse "$OUT" "$(b hbad.md '[b01]' '#a-b' 'no such anchor')"
t_has b02-dup      "$OUT" "$(b hbad.md '[b02]' '#same-2' 'no such anchor')"
t_has b03-upper    "$OUT" "$(b hbad.md '[b03]' '#Как-пользоваться' 'no such anchor')"
t_has b04-mixed    "$OUT" "$(b hbad.md '[b04]' '#как-Пользоваться' 'no such anchor')"
t_has b05-none     "$OUT" "$(b hbad.md '[b05]' '#not-a-heading' 'no such anchor')"
t_has b06-fenced   "$OUT" "$(b hbad.md '[b06]' '#fenced-heading' 'no such anchor')"
t_eq  hbad-sum 'mdlinks: 1 file(s), 6 link(s), 6 broken' "$ERR"
t_eq  cy-first-bytes '23 20 d0 9a' "$(head -c 4 "$T/cy.md" | od -An -tx1 | tr -s ' ' | sed 's/^ //')"
run_m cy.md
t_eq  cy-rc 0 "$RC"
t_eq  cy-sum 'mdlinks: 1 file(s), 1 link(s), 0 broken' "$ERR"

# counts and summary (s.md): M counts only resolved links
run_m s.md
t_eq s-out "" "$OUT"
t_eq s-sum 'mdlinks: 1 file(s), 1 link(s), 0 broken' "$ERR"

# --list and the rc/summary contract
t_eq    full-rc 1 "$FULLRC"
t_eq    list-rc 1 "$LISTRC"
t_eq    list-summary "$FULLERR" "$LISTERR"
t_no    list-no-broken "$LIST" "$(b a.md '[c02]' docs/nope.md 'no such file')"
t_nosub list-has-no-broken-word "$LIST" ': broken:'
t_nosub full-has-no-ok-word "$FULL" ': ok:'
t_eq    full-files 'mdlinks: 10 file(s)' "${FULLERR%%, *}"

# order: repo order (root repo first, then kcl), git ls-files order, then line
files=$(printf '%s\n' "$FULL" | cut -d: -f1 | uniq | tr '\n' ' ')
t_eq order-files 'a.md docs/b.md f.md hbad.md kcl/x.md ' "$files"
lines=$(printf '%s\n' "$FULL" | grep '^a.md:' | cut -d: -f2 | tr '\n' ' ')
sorted=$(printf '%s\n' "$FULL" | grep '^a.md:' | cut -d: -f2 | sort -n | tr '\n' ' ')
t_eq order-lines "$sorted" "$lines"

# positional arguments
run_m docs
t_eq    pos-dir-sum 'mdlinks: 1 file(s), 3 link(s), 2 broken' "$ERR"
t_has   pos-dir-line "$OUT" "$(b docs/b.md '[c09b]' ../kcl/nothere.md 'no such file')"
t_nosub pos-dir-only "$OUT" 'a.md:'
run_m kcl
t_eq    pos-kcl-sum 'mdlinks: 2 file(s), 6 link(s), 1 broken' "$ERR"
run_m ./docs/b.md
t_eq    pos-file-sum 'mdlinks: 1 file(s), 3 link(s), 2 broken' "$ERR"

# a clean root: rc 0, the summary, --list
mkdir -p "$W/clean"
printf '# One\n\n[a](two.md#two)\n[b](#one)\n' >"$W/clean/one.md"
printf '# Two\n\n[a](one.md)\n' >"$W/clean/two.md"
"${G[@]}" init -q "$W/clean" && "${G[@]}" -C "$W/clean" add -A
OUT=$("$BASH" "$M" --root "$W/clean" 2>"$W/err"); RC=$?; ERR=$(<"$W/err")
t_eq clean-rc 0 "$RC"
t_eq clean-out "" "$OUT"
t_eq clean-sum 'mdlinks: 2 file(s), 3 link(s), 0 broken' "$ERR"
OUT2=$("$BASH" "$M" --root "$W/clean" --list 2>/dev/null)
t_eq clean-list $'one.md:3: ok: two.md#two\none.md:4: ok: #one\ntwo.md:3: ok: one.md' "$OUT2"

# usage errors: rc 2, nothing on stdout
run_m --bogus
t_eq usage-opt-rc 2 "$RC"
t_eq usage-opt-out "" "$OUT"
run_m nosuch.md
t_eq usage-path-rc 2 "$RC"
t_eq usage-path-out "" "$OUT"
OUT=$("$BASH" "$M" --root "$W/nonexistent" 2>"$W/err"); RC=$?
t_eq usage-root-rc 2 "$RC"
t_eq usage-root-out "" "$OUT"
OUT=$("$BASH" "$M" --root 2>"$W/err"); RC=$?
t_eq usage-noarg-rc 2 "$RC"

# idempotence
run_m; A1=$OUT$'\n'$ERR
run_m; A2=$OUT$'\n'$ERR
t_eq idempotent "$A1" "$A2"

if ((NFAIL)); then
    printf '%s\n' "${FAILS[@]}"
    printf 'FAIL %d/%d\n' "$NFAIL" "$N"
    exit 1
fi
printf 'PASS %d/%d\n' "$N" "$N"
