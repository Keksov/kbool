#!/usr/bin/env bash
# selftest.sh -- checks tools/kbdlayout/gen.sh and layouts.awk offline.
#
#     bash tools/kbdlayout/tests/selftest.sh
#     SELFTEST_AWKS="gawk mawk" bash tools/kbdlayout/tests/selftest.sh
#     KBDLAYOUT_SRC=/path/to/archives bash tools/kbdlayout/tests/selftest.sh
#
# Per awk (SELFTEST_AWKS, default: every one of gawk mawk nawk original-awk
# "busybox awk" awk found here):
#   * the fixtures (tests/fixtures/: a small hand-made symbols tree and
#     keysymdef.h) give exactly tests/expected_out.txt, and a second run is
#     byte-identical;
#   * what the fixtures must give, read back from the output by sourcing it
#     (independent of the golden file): the merge rules, the aliases, the
#     keysym forms, the first-key rule and the small-letter rule (Greek Sigma), the
#     split into script letters (__FV_KL_D) and the rest (__FV_KL_S), the files
#     without a table (__FV_KL_NOTAB, __FV_KL_VX), what is left out;
#   * with KBDLAYOUT_SRC (a folder holding xkeyboard-config-2.48.tar.xz and
#     xorgproto-2025.1.tar.xz): the committed kcl/fv.keyboard/fv.keyboard.layouts.sh
#     regenerated into a copy is byte-identical to it (else SKIP).
# Once (default awk): --urls, --out (a second run says unchanged), the error
# paths (no us, a default layout missing, bad options, a missing archive, an
# archive that is not the pinned one).
# After a fixture change: regenerate expected_out.txt with
#   bash tools/kbdlayout/gen.sh --tree tools/kbdlayout/tests/fixtures --version 0.1 \
#     --proto-version 0.1 --dset 'ru gr' --stdout > tools/kbdlayout/tests/expected_out.txt
# and check the new entries against the list below.
# Exit 0 = all PASS (or SKIP), 1 = a FAIL.

SELF=${BASH_SOURCE[0]}
if [[ $SELF == */* ]]; then HERE=${SELF%/*}; else HERE=.; fi
HERE=$(cd "$HERE" && pwd) || exit 1
GEN=$HERE/../gen.sh
FIX=$HERE/fixtures
GOLD=$HERE/expected_out.txt
ROOT=$(cd "$HERE/../../.." && pwd) || exit 1
export LC_ALL=C

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM HUP
PASS=0 FAIL=0 SKIP=0
pass() { PASS=$(( PASS + 1 )); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); printf 'FAIL: %s%s\n' "$1" "${2:+  -- $2}"; }
skip() { SKIP=$(( SKIP + 1 )); printf 'SKIP: %s\n' "$1"; }
FIXARGS=(--tree "$FIX" --version 0.1 --proto-version 0.1 --dset 'ru gr')

# the entries the fixtures must give: LAYOUT CHAR KEY ('-' = absent); a default
# layout's entry is looked up in __FV_KL_D and __FV_KL_S together (check() also checks
# which of the two holds what). Greek capital sigma takes the key of its small letter (S)
# though it is also at W (level 2 of final sigma's key), as the generator's rule says
WANT='ru ё ` | ru Ё ` | ru й q | ru ц w | ru а f | ru А f | ru ж ; | ru ч x | ru б , | ru ю . | ru № 3 | ru я -
| gr ς w | gr Σ s | gr σ s | gr φ f | gr Φ f | gr θ t | gr τ - | gr æ -
| ru(phonetic) я q | ru(phonetic) ф f | ru(phonetic) а i | ru(phonetic) э \ | ru(phonetic) й -
| ru(aug) й - | ru(aug) а i | ru(aug) ф - | ru(aug) ц w | ru(aug) е e
| us(rus) я q | us(rus) ф f
| ru(broken) * - | us(intl) * - | ru(common) * - | ru(notalayout) * - | gr(simple) * - | gr(extra) * -'

# check FILE TITLE — the fixture entries read back from FILE (sourced)
check() {
    local f=$1 t=$2 bad='' item lay ch key got
    unset __FV_KL_D __FV_KL_S __FV_KL_V __FV_KL_ORDER __FV_KL_VERSION __FV_KL_NOTAB __FV_KL_VX
    local __FV_KL_ALL=1
    # shellcheck disable=SC1090  # the generated file
    source "$f" || { fail "$t: the output sources" "rc $?"; return; }
    [[ $__FV_KL_ORDER == 'ru gr' && $__FV_KL_VERSION == 0.1 ]] || bad+=" order/version [$__FV_KL_ORDER] [$__FV_KL_VERSION]"
    # the script letters in D, the rest (No sign) in S; the files without a table, the variants among them
    [[ ${__FV_KL_D[ru]} != *'№'* && ${__FV_KL_S[ru]-} == '[№]=3' && -z ${__FV_KL_S[gr]+x} ]] || bad+=" D/S split [${__FV_KL_S[ru]-}]"
    [[ $__FV_KL_NOTAB == ' us ' && $__FV_KL_VX == ' us(rus) ' ]] || bad+=" NOTAB [$__FV_KL_NOTAB] VX [$__FV_KL_VX]"
    while IFS= read -r -d '|' item || [[ -n $item ]]; do
        item=${item//$'\n'/}
        read -r lay ch key <<< "$item"
        [[ -n $lay ]] || continue
        local -A T=()
        if [[ $ch == '*' ]]; then
            if [[ -n ${__FV_KL_D[$lay]+x}${__FV_KL_V[$lay]+x} ]]; then bad+=" $lay:present"; fi
            continue
        fi
        if [[ -n ${__FV_KL_D[$lay]+x} ]]; then eval "T=(${__FV_KL_D[$lay]} ${__FV_KL_S[$lay]-})"
        elif [[ -n ${__FV_KL_V[$lay]+x} ]]; then eval "T=(${__FV_KL_V[$lay]})"
        else bad+=" $lay:missing"; continue; fi
        got=${T[$ch]-}
        if [[ $key == - ]]; then [[ -z $got ]] || bad+=" $lay:$ch=[$got],want-none"
        elif [[ $got != "$key" ]]; then bad+=" $lay:$ch=[$got],want[$key]"; fi
        unset T
    done <<< "$WANT"
    if [[ -z $bad ]]; then pass "$t: the fixture entries"; else fail "$t: the fixture entries" "$bad"; fi
}

awks=()
if [[ -n ${SELFTEST_AWKS:-} ]]; then
    read -r -a awks <<<"$SELFTEST_AWKS"
else
    for a in gawk mawk nawk original-awk awk; do command -v "$a" >/dev/null 2>&1 && awks+=("$a"); done
    if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
        printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$TMP/bbawk"; chmod +x "$TMP/bbawk"; awks+=("$TMP/bbawk")
    fi
fi
(( ${#awks[@]} )) || { fail "an awk to run" "none found"; exit 1; }

for a in "${awks[@]}"; do
    n=${a##*/}
    if bash "$GEN" "${FIXARGS[@]}" --awk "$a" --stdout > "$TMP/o1" 2> "$TMP/e1"; then
        if cmp -s "$TMP/o1" "$GOLD"; then pass "$n: the fixtures give expected_out.txt"
        else fail "$n: the fixtures give expected_out.txt" "$(diff "$GOLD" "$TMP/o1" | head -5 | tr '\n' ' ')"; fi
        bash "$GEN" "${FIXARGS[@]}" --awk "$a" --stdout > "$TMP/o2" 2>/dev/null
        if cmp -s "$TMP/o1" "$TMP/o2"; then pass "$n: a second run is byte-identical"; else fail "$n: a second run is byte-identical"; fi
        if grep -q 'left out ru(broken) (include nosuchfile(x) not found)' "$TMP/e1"; then pass "$n: the left-out section is reported"
        else fail "$n: the left-out section is reported" "$(tr '\n' ' ' < "$TMP/e1")"; fi
        check "$TMP/o1" "$n"
    else
        fail "$n: gen.sh on the fixtures" "$(tr '\n' ' ' < "$TMP/e1")"
    fi
done

# --- once, with the default awk ------------------------------------------------------
if out=$(bash "$GEN" --urls) && [[ $out == $'https://www.x.org/releases/individual/data/xkeyboard-config/xkeyboard-config-2.48.tar.xz\nhttps://www.x.org/releases/individual/proto/xorgproto-2025.1.tar.xz' ]]; then
    pass "--urls: the two pinned archives"
else
    fail "--urls: the two pinned archives" "$out"
fi

if bash "$GEN" "${FIXARGS[@]}" --out "$TMP/out.sh" 2> "$TMP/e" && cmp -s "$TMP/out.sh" "$GOLD" \
   && bash "$GEN" "${FIXARGS[@]}" --out "$TMP/out.sh" 2> "$TMP/e2" && grep -q 'unchanged' "$TMP/e2"; then
    pass "--out writes the file; a second run says unchanged"
else
    fail "--out writes the file; a second run says unchanged" "$(tr '\n' ' ' < "$TMP/e") $(tr '\n' ' ' < "$TMP/e2" 2>/dev/null)"
fi

# expect_rc RC TITLE ARGS... — gen.sh ARGS exits RC with a message on stderr
expect_rc() {
    local want=$1 t=$2 rc=0
    shift 2
    bash "$GEN" "$@" > /dev/null 2> "$TMP/err" || rc=$?
    if [[ $rc == "$want" && -s $TMP/err ]]; then pass "$t: rc $want"; else fail "$t: rc $want" "rc=$rc [$(tr '\n' ' ' < "$TMP/err")]"; fi
}
mkdir -p "$TMP/nous/xkeyboard-config-0.1/symbols" "$TMP/nous/xorgproto-0.1/include/X11"
cp "$FIX/xkeyboard-config-0.1/symbols/ru" "$TMP/nous/xkeyboard-config-0.1/symbols/"
cp "$FIX/xorgproto-0.1/include/X11/keysymdef.h" "$TMP/nous/xorgproto-0.1/include/X11/"
expect_rc 1 "a tree without symbols/us" --tree "$TMP/nous" --version 0.1 --proto-version 0.1 --stdout
expect_rc 1 "a default layout that is not there" "${FIXARGS[@]:0:6}" --dset 'ru xx' --stdout
expect_rc 2 "no input" --stdout
expect_rc 2 "a bad --version" --version 2 --tree "$FIX" --stdout
expect_rc 2 "a bad --dset" "${FIXARGS[@]:0:6}" --dset 'ru;rm' --stdout
expect_rc 2 "--src and --tree together" --src "$TMP" --tree "$FIX" --stdout
expect_rc 2 "an unknown option" --nosuch
expect_rc 1 "--src without the archives" --src "$TMP/empty-$$" --stdout
mkdir -p "$TMP/fake"
printf 'not the archive\n' > "$TMP/fake/xkeyboard-config-2.48.tar.xz"
printf 'not the archive\n' > "$TMP/fake/xorgproto-2025.1.tar.xz"
if command -v xz >/dev/null 2>&1; then
    expect_rc 1 "an archive that is not the pinned one (sha256)" --src "$TMP/fake" --stdout
    if grep -q 'is not the pinned' "$TMP/err"; then pass "the sha256 refusal names the pin"; else fail "the sha256 refusal names the pin" "$(tr '\n' ' ' < "$TMP/err")"; fi
else
    skip "an archive that is not the pinned one (no xz here)"
fi

# --- the committed file, regenerated from the real archives -----------------------------
if [[ -n ${KBDLAYOUT_SRC:-} ]]; then
    if bash "$GEN" --src "$KBDLAYOUT_SRC" --stdout > "$TMP/real" 2> "$TMP/rerr" \
       && cmp -s "$TMP/real" "$ROOT/kcl/fv.keyboard/fv.keyboard.layouts.sh"; then
        pass "the committed fv.keyboard.layouts.sh regenerates byte for byte from KBDLAYOUT_SRC"
    else
        fail "the committed fv.keyboard.layouts.sh regenerates byte for byte from KBDLAYOUT_SRC" "$(tail -2 "$TMP/rerr" | tr '\n' ' ')"
    fi
else
    skip "the committed fv.keyboard.layouts.sh regenerated (set KBDLAYOUT_SRC to the folder of the two archives)"
fi

printf '%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
