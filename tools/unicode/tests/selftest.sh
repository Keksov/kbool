#!/usr/bin/env bash
# selftest.sh -- checks tools/unicode/gen_width.sh and width.awk offline.
#
#     bash tools/unicode/tests/selftest.sh
#     SELFTEST_AWKS="gawk mawk" bash tools/unicode/tests/selftest.sh
#     UNICODE_UCD=/path/to/16.0.0 bash tools/unicode/tests/selftest.sh
#
# Per awk (SELFTEST_AWKS, default: every one of gawk mawk nawk original-awk
# "busybox awk" awk found here):
#   * the fixtures (tests/fixtures/, small hand-made inputs) give exactly
#     tests/expected_block.txt, and a second run is byte-identical;
#   * the classes of the fixtures' code points, read back from the block,
#     are the ones written down below (independent of the golden file);
#   * with UNICODE_UCD (a folder with the five real input files): the
#     committed kcl/fv.unicode/fv.unicode.sh regenerated into a copy is
#     byte-identical to it (else SKIP).
# Once (default awk): --urls, --unit splicing, the error paths (incl. inputs
# whose header names another version than --version).
# After a fixture change: regenerate expected_block.txt with
#   bash tools/unicode/gen_width.sh --ucd tools/unicode/tests/fixtures \
#     --version 1.2.3 --stdout > tools/unicode/tests/expected_block.txt
# and check the new classes against the list below.
# Exit 0 = all PASS (or SKIP), 1 = a FAIL.

SELF=${BASH_SOURCE[0]}
if [[ $SELF == */* ]]; then HERE=${SELF%/*}; else HERE=.; fi
HERE=$(cd "$HERE" && pwd) || exit 1
GEN=$HERE/../gen_width.sh
FIX=$HERE/fixtures
GOLD=$HERE/expected_block.txt
ROOT=$(cd "$HERE/../../.." && pwd) || exit 1
export LC_ALL=C.UTF-8

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM HUP
PASS=0 FAIL=0 SKIP=0
pass() { PASS=$(( PASS + 1 )); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); printf 'FAIL: %s%s\n' "$1" "${2:+  -- $2}"; }
skip() { SKIP=$(( SKIP + 1 )); printf 'SKIP: %s\n' "$1"; }
# sedi EXPR FILE — FILE edited in place by sed EXPR (no `sed -i`: BSD and macOS
# sed take the next word as a backup suffix)
sedi() { sed "$1" "$2" > "$2.new" && mv -f "$2.new" "$2"; }

# the fixtures' code points (hex) and their classes
WANT='0041:n 00A9:x 00AA:n 00AD:n 0300:z 0488:z 0600:n 1100:w 115F:w 1160:z 11A7:z 11A8:z
11FF:z 1200:n 200B:z 200D:z 200F:z 2010:n 20E3:z 231A:y 231B:y 231C:n 2500:n 2764:x
3000:w 302A:z 3164:z 3248:w 324F:w 3250:n 3400:n 4E00:w 9FFF:w AC00:w AC1B:w D7A3:w
D7A4:n FE00:z FE0F:z FF20:n FF21:w FF3A:w FF3B:n 1F1E6:r 1F1E7:n 1F1FF:r 1F3FA:n
1F3FB:m 1F3FF:m 1F600:y 1F64F:y 1F650:n 1FC00:x 1FFFD:x 1FFFE:n 20000:w 2A6DF:w
2A6E0:n E0000:z E0001:z E0100:z E01EF:z E0FFF:z E1000:n 10FFFF:n 0:n'

# cls CP(hex) -> CLS: the class from the loaded block (own decoder, not the unit's)
cls() {
    local c=$((16#$1)) s o='' k n p
    CLS=${__FV_UC_P[c >> 14]:(c >> 8) % 64:1}
    if [[ $CLS == '*' ]]; then
        s=${__FV_UC_M[c >> 8]}
        while [[ -n $s ]]; do
            k=${s:0:1} s=${s:1}
            n=${s%%[![:digit:]]*} s=${s:${#n}}
            printf -v p '%*s' "$n" ''
            o+=${p// /$k}
        done
        (( ${#o} == 256 )) || { CLS="?len${#o}"; return; }
        CLS=${o:c % 256:1}
    fi
}
# loadblock FILE -> __FV_UC_P, __FV_UC_M (the block sourced)
loadblock() { unset __FV_UC_P __FV_UC_M; source "$1"; }

awks=()
if [[ -n ${SELFTEST_AWKS:-} ]]; then
    read -r -a awks <<<"$SELFTEST_AWKS"
else
    for a in gawk mawk nawk original-awk awk; do command -v "$a" >/dev/null 2>&1 && awks+=("$a"); done
    if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
        printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$TMP/bbawk"; chmod +x "$TMP/bbawk"; awks+=("$TMP/bbawk")
    fi
fi
(( ${#awks[@]} )) || { echo "selftest: no awk found" >&2; exit 1; }

for a in "${awks[@]}"; do
    an=${a##*/}
    [[ $an == bbawk ]] && an='busybox awk'
    if ! command -v "$a" >/dev/null 2>&1; then skip "[$an] not installed"; continue; fi
    out1=$TMP/b1 out2=$TMP/b2
    if bash "$GEN" --awk "$a" --ucd "$FIX" --version 1.2.3 --stdout > "$out1" 2> "$TMP/e1"; then
        if cmp -s "$out1" "$GOLD"; then pass "[$an] fixtures -> expected_block.txt"
        else fail "[$an] fixtures -> expected_block.txt" "$(diff "$GOLD" "$out1" | head -5 | tr '\n' ' ')"; fi
    else
        fail "[$an] fixtures generate" "$(tr '\n' ' ' < "$TMP/e1")"
        continue
    fi
    if grep -q "note: '@missing 3400..4DBF; W' not applied" "$TMP/e1"; then pass "[$an] a W @missing line is reported, not applied"
    else fail "[$an] the @missing note" "$(tr '\n' ' ' < "$TMP/e1")"; fi
    bash "$GEN" --awk "$a" --ucd "$FIX" --version 1.2.3 --stdout > "$out2" 2>/dev/null
    if cmp -s "$out1" "$out2"; then pass "[$an] a second run is byte-identical"; else fail "[$an] a second run differs"; fi

    loadblock "$out1"
    bad=''
    for e in $WANT; do
        cls "${e%%:*}"
        [[ $CLS == "${e#*:}" ]] || bad+=" U+${e%%:*}=$CLS(want ${e#*:})"
    done
    if [[ -z $bad ]]; then pass "[$an] the classes of $(wc -w <<<"$WANT") fixture code points"; else fail "[$an] classes" "$bad"; fi
    # invariants: 68 strings of 64 letters; '*' <-> an M entry of 256 letters
    bad='' all=''
    (( ${#__FV_UC_P[@]} == 68 )) || bad+=" ${#__FV_UC_P[@]} strings"
    for (( i = 0; i < 68; i++ )); do
        [[ ${#__FV_UC_P[i]} == 64 && ${__FV_UC_P[i]} != *[!znwxymr*]* ]] || bad+=" P[$i]"
        all+=${__FV_UC_P[i]-}
    done
    nstar=${all//[!*]/} nstar=${#nstar}
    (( nstar == ${#__FV_UC_M[@]} )) || bad+=" $nstar '*' pages, ${#__FV_UC_M[@]} M entries"
    for i in "${!__FV_UC_M[@]}"; do
        [[ ${all:i:1} == '*' ]] || bad+=" M[$i] for a page that is not '*'"
        cls "$(printf '%X' $(( i * 256 )))"
        [[ $CLS == \?len* ]] && bad+=" M[$i] $CLS"
    done
    if [[ -z $bad ]]; then pass "[$an] page table invariants"; else fail "[$an] invariants" "$bad"; fi

    if [[ -n ${UNICODE_UCD:-} ]]; then
        cp "$ROOT/kcl/fv.unicode/fv.unicode.sh" "$TMP/unit.sh"
        if bash "$GEN" --awk "$a" --ucd "$UNICODE_UCD" --unit "$TMP/unit.sh" > "$TMP/o" 2>&1 \
            && cmp -s "$TMP/unit.sh" "$ROOT/kcl/fv.unicode/fv.unicode.sh"; then
            pass "[$an] the real inputs regenerate kcl/fv.unicode/fv.unicode.sh byte for byte"
        else
            fail "[$an] the real inputs regenerate the committed unit" "$(tr '\n' ' ' < "$TMP/o"; cmp "$TMP/unit.sh" "$ROOT/kcl/fv.unicode/fv.unicode.sh")"
        fi
    else
        skip "[$an] real inputs (set UNICODE_UCD to a folder with the five 16.0.0 files)"
    fi
done

# --- the generator itself (default awk) ----------------------------------------------
want='https://www.unicode.org/Public/16.0.0/ucd/EastAsianWidth.txt
https://www.unicode.org/Public/16.0.0/ucd/UnicodeData.txt
https://www.unicode.org/Public/16.0.0/ucd/DerivedCoreProperties.txt
https://www.unicode.org/Public/16.0.0/ucd/HangulSyllableType.txt
https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-data.txt'
got=$(bash "$GEN" --urls)
if [[ $got == "$want" ]]; then pass "--urls (16.0.0)"; else fail "--urls" "$got"; fi

printf '#!/bin/bash\n# head\n# BEGIN GENERATED old\nold=1\n# END GENERATED\ntail=1\n' > "$TMP/u.sh"
bash "$GEN" --ucd "$FIX" --version 1.2.3 --unit "$TMP/u.sh" > "$TMP/o" 2>/dev/null; rc=$?
{ printf '#!/bin/bash\n# head\n'; cat "$GOLD"; printf 'tail=1\n'; } > "$TMP/uw.sh"
if [[ $rc == 0 ]] && cmp -s "$TMP/u.sh" "$TMP/uw.sh" && grep -q regenerated "$TMP/o"; then pass "--unit replaces the block only"
else fail "--unit replaces the block only" "rc=$rc $(cat "$TMP/o")"; fi
bash "$GEN" --ucd "$FIX" --version 1.2.3 --unit "$TMP/u.sh" > "$TMP/o" 2>/dev/null; rc=$?
if [[ $rc == 0 ]] && grep -q unchanged "$TMP/o" && cmp -s "$TMP/u.sh" "$TMP/uw.sh"; then pass "--unit again: unchanged"
else fail "--unit again" "rc=$rc $(cat "$TMP/o")"; fi

# expect RC WORDS TITLE ARGS... — the generator's rc, and stderr holding WORDS
expect() {
    local want=$1 words=$2 title=$3 rc
    shift 3
    bash "$GEN" "$@" > "$TMP/o" 2> "$TMP/e"; rc=$?
    if [[ $rc == "$want" && $(<"$TMP/e") == *"$words"* ]]; then pass "$title: rc $want"; else fail "$title" "rc=$rc stderr=$(tr '\n' ' ' < "$TMP/e")"; fi
}
V=(--version 1.2.3)
expect 2 "unknown argument" "an unknown argument" --frob
expect 2 "is not N.N.N" "a bad --version" --version 16 --urls
expect 2 "no input" "no input" --stdout
expect 2 "name different folders" "--fetch and --ucd naming different folders" --fetch "$TMP/a" --ucd "$TMP/b"
mkdir -p "$TMP/part"; cp "$FIX"/*.txt "$TMP/part/"; rm "$TMP/part/HangulSyllableType.txt"
expect 1 "missing input" "a missing input file" --ucd "$TMP/part" "${V[@]}" --stdout
cp "$FIX"/*.txt "$TMP/part/"; printf '12G4;W\n' >> "$TMP/part/EastAsianWidth.txt"
expect 1 "bad code point range" "a malformed code point" --ucd "$TMP/part" "${V[@]}" --stdout
cp "$FIX"/*.txt "$TMP/part/"; printf '# emoji-data.txt\n# Version: 1.2\n# only comments\n' > "$TMP/part/emoji-data.txt"
expect 1 "none of the lines" "an input without data lines" --ucd "$TMP/part" "${V[@]}" --stdout
expect 1 "not EastAsianWidth-1.2.4.txt" "inputs of another version than --version (first line)" --ucd "$FIX" --version 1.2.4 --stdout
cp "$FIX"/*.txt "$TMP/part/"; sedi '1s/.*/# HangulSyllableType.txt/' "$TMP/part/HangulSyllableType.txt"
expect 1 "names 'no version'" "a first line without the version" --ucd "$TMP/part" "${V[@]}" --stdout
cp "$FIX"/*.txt "$TMP/part/"; sedi 's/^# Version: 1.2$/# Version: 1.3/' "$TMP/part/emoji-data.txt"
expect 1 "says version '1.3', not 1.2" "emoji-data.txt of another version" --ucd "$TMP/part" "${V[@]}" --stdout
cp "$FIX"/*.txt "$TMP/part/"; sedi '/^# Version:/d' "$TMP/part/emoji-data.txt"
expect 1 "says version 'none'" "emoji-data.txt without a version line" --ucd "$TMP/part" "${V[@]}" --stdout
printf 'x=1\n' > "$TMP/nm.sh"
expect 1 "needs exactly one" "a unit without the markers" --ucd "$FIX" "${V[@]}" --unit "$TMP/nm.sh"
printf '# END GENERATED\n# BEGIN GENERATED\n' > "$TMP/rev.sh"
expect 1 "comes before" "END before BEGIN" --ucd "$FIX" "${V[@]}" --unit "$TMP/rev.sh"
expect 1 "not found" "a missing awk" --ucd "$FIX" "${V[@]}" --awk no-such-awk-here --stdout

printf '\nselftest: %d PASS, %d FAIL, %d SKIP (awks: %s)\n' "$PASS" "$FAIL" "$SKIP" "${awks[*]##*/}"
(( FAIL == 0 ))
