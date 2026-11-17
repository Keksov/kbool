#!/usr/bin/env bash
# gen_width.sh -- regenerate the character class table of kcl/fv.unicode from the
# Unicode Character Database. Plain bash + one POSIX awk program (width.awk).
#
#     bash tools/unicode/gen_width.sh --fetch DIR           # download into DIR, then generate
#     bash tools/unicode/gen_width.sh --ucd DIR             # the five files are already in DIR
#     bash tools/unicode/gen_width.sh --ucd DIR --stdout    # print the block, change nothing
#     bash tools/unicode/gen_width.sh --urls                # print the input URLs
#
# Options:
#   --version V    Unicode version (default 16.0.0, the one glibc 2.41 uses)
#   --ucd DIR      folder holding EastAsianWidth.txt, UnicodeData.txt,
#                  DerivedCoreProperties.txt, HangulSyllableType.txt, emoji-data.txt
#   --fetch DIR    download those five files of version V into DIR first (curl or
#                  wget); DIR is created; never point it into the repository
#   --unit FILE    the file whose block between the lines `# BEGIN GENERATED` and
#                  `# END GENERATED` is replaced (default kcl/fv.unicode/fv.unicode.sh)
#   --stdout       print the block (markers included) instead of writing FILE
#   --awk AWK      the awk to run (default: $AWK, else awk)
#   --urls         print the five URLs of version V and exit
#
# Each input must carry version V in its header (UnicodeData.txt has no stamp).
# The block records the version, the URLs and the sha256 of every input, and no
# date: the same inputs always give a byte-identical file. The inputs are not
# committed. rc 0 = done; 1 = a failure (message on stderr); 2 = a bad call.
set -u

HERE=${BASH_SOURCE[0]%/*}
[[ $HERE == "${BASH_SOURCE[0]}" ]] && HERE=.
HERE=$(cd "$HERE" && pwd) || exit 1
ROOT=$(cd "$HERE/../.." && pwd) || exit 1

VER=16.0.0 UCD='' FETCH='' UNIT=$ROOT/kcl/fv.unicode/fv.unicode.sh OUT=unit AWKP=${AWK:-awk}
FILES=(EastAsianWidth.txt UnicodeData.txt DerivedCoreProperties.txt HangulSyllableType.txt emoji-data.txt)

usage() { sed -n '2,/^set -u/{/^set -u/d;s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"; }
bad() { printf 'gen_width.sh: %s\n' "$1" >&2; exit 2; }
fail() { printf 'gen_width.sh: %s\n' "$1" >&2; exit 1; }

while (( $# )); do
    case $1 in
        --version) (( $# >= 2 )) || bad "--version needs a value"; VER=$2; shift 2 ;;
        --ucd) (( $# >= 2 )) || bad "--ucd needs a folder"; UCD=$2; shift 2 ;;
        --fetch) (( $# >= 2 )) || bad "--fetch needs a folder"; FETCH=$2; shift 2 ;;
        --unit) (( $# >= 2 )) || bad "--unit needs a file"; UNIT=$2; shift 2 ;;
        --awk) (( $# >= 2 )) || bad "--awk needs a program"; AWKP=$2; shift 2 ;;
        --stdout) OUT=stdout; shift ;;
        --urls) OUT=urls; shift ;;
        -h|--help) usage; exit 0 ;;
        *) bad "unknown argument '$1' (see --help)" ;;
    esac
done
[[ $VER =~ ^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2}$ ]] || bad "--version '$VER' is not N.N.N"

# url FILE -> URL (emoji-data.txt lives in ucd/emoji/)
url() {
    if [[ $1 == emoji-data.txt ]]; then URL=https://www.unicode.org/Public/$VER/ucd/emoji/$1
    else URL=https://www.unicode.org/Public/$VER/ucd/$1; fi
}

if [[ $OUT == urls ]]; then
    for f in "${FILES[@]}"; do url "$f"; printf '%s\n' "$URL"; done
    exit 0
fi

if [[ -n $FETCH ]]; then
    [[ -n $UCD && $UCD != "$FETCH" ]] && bad "--fetch and --ucd name different folders"
    mkdir -p "$FETCH" || fail "cannot create $FETCH"
    for f in "${FILES[@]}"; do
        url "$f"
        rc=0
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --proto '=https' --proto-redir '=https' --max-time 120 -o "$FETCH/$f.part" "$URL" || rc=$?
        elif command -v wget >/dev/null 2>&1; then
            wget -q --https-only -T 120 -O "$FETCH/$f.part" "$URL" || rc=$?
        else
            fail "neither curl nor wget found"
        fi
        if (( rc )); then rm -f "$FETCH/$f.part"; fail "download failed (rc $rc): $URL"; fi
        mv -f "$FETCH/$f.part" "$FETCH/$f" || { rm -f "$FETCH/$f.part"; fail "cannot write $FETCH/$f"; }
    done
    UCD=$FETCH
fi
[[ -n $UCD ]] || bad "no input: give --ucd DIR or --fetch DIR (see --help)"
for f in "${FILES[@]}"; do
    [[ -f $UCD/$f && -r $UCD/$f ]] || fail "missing input $UCD/$f"
done
if ! command -v "$AWKP" >/dev/null 2>&1; then fail "awk '$AWKP' not found"; fi

# Every input must be of version VER: the first line of EastAsianWidth.txt,
# DerivedCoreProperties.txt and HangulSyllableType.txt is "# NAME-VER.txt";
# emoji-data.txt has a "Version: M.m" line (16.0: "Used with Emoji Version
# 16.0 ...") among its first 20 lines, compared with VER's M.m. UnicodeData.txt
# carries no version stamp at all (pure data lines): it is not checked.
want=${VER%.*}
for f in "${FILES[@]}"; do
    [[ $f == UnicodeData.txt ]] && continue
    got=$(LC_ALL=C "$AWKP" -v f="$f" '
        f != "emoji-data.txt" { if ($0 ~ /^# [A-Za-z]+-[0-9]+\.[0-9]+\.[0-9]+\.txt[ \t\r]*$/) print $2; exit }
        NR > 20 { exit }
        /^#.*[Vv]ersion:? [0-9]+\.[0-9]+/ { s = $0; sub(/^.*[Vv]ersion:? /, "", s); sub(/[^0-9.].*$/, "", s); print s; exit }' "$UCD/$f")
    if [[ $f == emoji-data.txt ]]; then
        [[ $got == "$want" ]] || fail "$UCD/$f: its header says version '${got:-none}', not $want (--version $VER)"
    else
        [[ $got == "${f%.txt}-$VER.txt" ]] || fail "$UCD/$f: its first line names '${got:-no version}', not ${f%.txt}-$VER.txt (--version $VER)"
    fi
done

# sha FILE -> SHA (sha256sum, else shasum -a 256, else openssl)
sha() {
    local line
    if command -v sha256sum >/dev/null 2>&1; then line=$(sha256sum < "$1")
    elif command -v shasum >/dev/null 2>&1; then line=$(shasum -a 256 < "$1")
    elif command -v openssl >/dev/null 2>&1; then line=$(openssl dgst -sha256 < "$1"); line=${line##*= }
    else fail "no sha256 tool (sha256sum, shasum, openssl)"; fi
    SHA=${line%% *}
    [[ $SHA =~ ^[0-9a-f]{64}$ ]] || fail "bad sha256 of $1"
}

TMP=$(mktemp -d 2>/dev/null) || fail "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

{
    printf '# BEGIN GENERATED by tools/unicode/gen_width.sh -- do not edit by hand (tools/unicode/README.md)\n'
    printf '# Unicode %s; widths by the glibc 2.41 rules (tools/unicode/width.awk); inputs and sha256:\n' "$VER"
    for f in "${FILES[@]}"; do
        url "$f"; sha "$UCD/$f"
        printf '#   %s %s\n' "$SHA" "$URL"
    done
    printf 'declare -g __FV_UC_VERSION=%s\n' "$VER"
} > "$TMP/head" || fail "cannot write the block"

args=()
for f in "${FILES[@]}"; do args+=("$UCD/$f"); done
LC_ALL=C "$AWKP" -f "$HERE/width.awk" "${args[@]}" > "$TMP/data" 2> "$TMP/err" || {
    cat "$TMP/err" >&2
    fail "width.awk failed"
}
grep -v '^width\.awk: [0-9]* pages, [0-9]* mixed$' "$TMP/err" >&2
{ cat "$TMP/head" "$TMP/data"; printf '# END GENERATED\n'; } > "$TMP/block" || fail "cannot write the block"

if [[ $OUT == stdout ]]; then
    cat "$TMP/block"
    exit 0
fi

[[ -f $UNIT ]] || fail "no unit file $UNIT"
# exactly one BEGIN line followed by exactly one END line
nb=$(grep -c '^# BEGIN GENERATED' "$UNIT")
ne=$(grep -c '^# END GENERATED' "$UNIT")
[[ $nb == 1 && $ne == 1 ]] || fail "$UNIT: needs exactly one '# BEGIN GENERATED' and one '# END GENERATED' line (found $nb / $ne)"
LC_ALL=C "$AWKP" -v blk="$TMP/block" '
    /^# BEGIN GENERATED/ { while ((getline l < blk) > 0) print l; skip = 1; next }
    /^# END GENERATED/ { if (!skip) exit 3; skip = 0; next }
    !skip { print }
    END { if (skip) exit 3 }' "$UNIT" > "$TMP/unit" || fail "$UNIT: the END line comes before the BEGIN line"
if cmp -s "$TMP/unit" "$UNIT"; then
    printf 'gen_width.sh: %s unchanged (Unicode %s)\n' "$UNIT" "$VER"
    exit 0
fi
cat "$TMP/unit" > "$UNIT" || fail "cannot write $UNIT"
printf 'gen_width.sh: %s regenerated (Unicode %s)\n' "$UNIT" "$VER"
