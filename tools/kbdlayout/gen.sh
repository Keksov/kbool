#!/usr/bin/env bash
# gen.sh -- regenerate kcl/fv.keyboard/fv.keyboard.layouts.sh (the keyboard
# layout tables of fv.keyboard) from xkeyboard-config. Plain bash + one POSIX
# awk program (layouts.awk).
#
#     bash tools/kbdlayout/gen.sh --fetch DIR            # download into DIR, then generate
#     bash tools/kbdlayout/gen.sh --src DIR              # the two archives are already in DIR
#     bash tools/kbdlayout/gen.sh --src DIR --stdout     # print the file, change nothing
#     bash tools/kbdlayout/gen.sh --urls                 # print the input URLs
#
# Options:
#   --version V        xkeyboard-config version (default 2.48)
#   --proto-version P  xorgproto version, for keysymdef.h (default 2025.1)
#   --src DIR          folder holding xkeyboard-config-V.tar.xz and
#                      xorgproto-P.tar.xz
#   --fetch DIR        download those two archives into DIR first (curl or
#                      wget, HTTPS only); DIR is created; never point it into
#                      the repository
#   --tree DIR         instead of archives: DIR/xkeyboard-config-V/symbols/ and
#                      DIR/xorgproto-P/include/X11/keysymdef.h already unpacked
#                      (the selftest's fixtures; the header then records no sha256)
#   --out FILE         the file written (default kcl/fv.keyboard/fv.keyboard.layouts.sh)
#   --stdout           print the file instead of writing it
#   --dset LIST        the default layouts, in priority order (default: the
#                      reviewed list in tools/kbdlayout/README.md)
#   --awk AWK          the awk to run (default: $AWK, else awk)
#   --urls             print the two URLs and exit
#
# The archives of the default versions must have the sha256 written below
# (another version: its sha256 is recorded, not checked). The file records the
# versions, the URLs and the sha256, and no date: the same inputs always give a
# byte-identical file. The inputs are never committed. Conflicts (a character
# at different keys in the default layouts) and the summary go to stderr.
# rc 0 = done; 1 = a failure (message on stderr); 2 = a bad call.
set -u

HERE=${BASH_SOURCE[0]%/*}
[[ $HERE == "${BASH_SOURCE[0]}" ]] && HERE=.
HERE=$(cd "$HERE" && pwd) || exit 1
ROOT=$(cd "$HERE/../.." && pwd) || exit 1

DEF_XKB=2.48 DEF_PROTO=2025.1
PIN_XKB=b77041324f0109f77161ee43743fe04baa485866af8460d31e476ad3f7648fd5
PIN_PROTO=56898c716c0578df8a2d828c9c3e5c528277705c0484381a81960fe1a67668e8
DSET_DEF='ru gr il ara ir ge am th ua bg by kz mk rs'

VER=$DEF_XKB PVER=$DEF_PROTO SRC='' FETCH='' TREE='' OUTF=$ROOT/kcl/fv.keyboard/fv.keyboard.layouts.sh
OUT=file AWKP=${AWK:-awk} DSET=$DSET_DEF

usage() { sed -n '2,/^set -u/{/^set -u/d;s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"; }
bad() { printf 'gen.sh: %s\n' "$1" >&2; exit 2; }
fail() { printf 'gen.sh: %s\n' "$1" >&2; exit 1; }

while (( $# )); do
    case $1 in
        --version) (( $# >= 2 )) || bad "--version needs a value"; VER=$2; shift 2 ;;
        --proto-version) (( $# >= 2 )) || bad "--proto-version needs a value"; PVER=$2; shift 2 ;;
        --src) (( $# >= 2 )) || bad "--src needs a folder"; SRC=$2; shift 2 ;;
        --fetch) (( $# >= 2 )) || bad "--fetch needs a folder"; FETCH=$2; shift 2 ;;
        --tree) (( $# >= 2 )) || bad "--tree needs a folder"; TREE=$2; shift 2 ;;
        --out) (( $# >= 2 )) || bad "--out needs a file"; OUTF=$2; shift 2 ;;
        --dset) (( $# >= 2 )) || bad "--dset needs a list"; DSET=$2; shift 2 ;;
        --awk) (( $# >= 2 )) || bad "--awk needs a program"; AWKP=$2; shift 2 ;;
        --stdout) OUT=stdout; shift ;;
        --urls) OUT=urls; shift ;;
        -h|--help) usage; exit 0 ;;
        *) bad "unknown argument '$1' (see --help)" ;;
    esac
done
[[ $VER =~ ^[0-9]{1,2}\.[0-9]{1,3}$ ]] || bad "--version '$VER' is not N.N"
[[ $PVER =~ ^[0-9]{1,4}\.[0-9]{1,2}$ ]] || bad "--proto-version '$PVER' is not N.N"
[[ $DSET =~ ^[a-z0-9]+( [a-z0-9]+)*$ ]] || bad "--dset '$DSET' is not a list of layout names"

XKB=xkeyboard-config-$VER PROTO=xorgproto-$PVER
URL_XKB=https://www.x.org/releases/individual/data/xkeyboard-config/$XKB.tar.xz
URL_PROTO=https://www.x.org/releases/individual/proto/$PROTO.tar.xz

if [[ $OUT == urls ]]; then printf '%s\n%s\n' "$URL_XKB" "$URL_PROTO"; exit 0; fi

if [[ -n $FETCH ]]; then
    [[ -n $SRC && $SRC != "$FETCH" ]] && bad "--fetch and --src name different folders"
    [[ -n $TREE ]] && bad "--fetch and --tree exclude each other"
    mkdir -p "$FETCH" || fail "cannot create $FETCH"
    for u in "$URL_XKB" "$URL_PROTO"; do
        f=$FETCH/${u##*/} rc=0
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --proto '=https' --proto-redir '=https' --max-time 300 -o "$f.part" "$u" || rc=$?
        elif command -v wget >/dev/null 2>&1; then
            wget -q --https-only -T 300 -O "$f.part" "$u" || rc=$?
        else
            fail "neither curl nor wget found"
        fi
        if (( rc )); then rm -f "$f.part"; fail "download failed (rc $rc): $u"; fi
        mv -f "$f.part" "$f" || { rm -f "$f.part"; fail "cannot write $f"; }
    done
    SRC=$FETCH
fi
[[ -n $SRC && -n $TREE ]] && bad "--src and --tree exclude each other"
[[ -n $SRC || -n $TREE ]] || bad "no input: give --src DIR, --fetch DIR or --tree DIR (see --help)"
if ! command -v "$AWKP" >/dev/null 2>&1; then fail "awk '$AWKP' not found"; fi

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

if [[ -n $SRC ]]; then
    # the archives: checked against the pins (default versions), then only the
    # files needed are unpacked into the temporary folder (never into SRC)
    for f in "$SRC/$XKB.tar.xz" "$SRC/$PROTO.tar.xz"; do [[ -f $f && -r $f ]] || fail "missing input $f"; done
    command -v xz >/dev/null 2>&1 || fail "no xz (needed to unpack the .tar.xz archives)"
    sha "$SRC/$XKB.tar.xz"; SHA_XKB=$SHA
    sha "$SRC/$PROTO.tar.xz"; SHA_PROTO=$SHA
    if [[ $VER == "$DEF_XKB" && $SHA_XKB != "$PIN_XKB" ]]; then fail "$SRC/$XKB.tar.xz: sha256 $SHA_XKB is not the pinned $PIN_XKB"; fi
    if [[ $PVER == "$DEF_PROTO" && $SHA_PROTO != "$PIN_PROTO" ]]; then fail "$SRC/$PROTO.tar.xz: sha256 $SHA_PROTO is not the pinned $PIN_PROTO"; fi
    [[ $VER == "$DEF_XKB" ]] || printf 'gen.sh: note: %s is not the pinned version; its sha256 is recorded, not checked\n' "$XKB" >&2
    [[ $PVER == "$DEF_PROTO" ]] || printf 'gen.sh: note: %s is not the pinned version; its sha256 is recorded, not checked\n' "$PROTO" >&2
    mkdir -p "$TMP/in" || fail "cannot create $TMP/in"
    # (symbolic links in symbols/ -- caps, esperanto, grp, japan, korean, lv2,
    # lv3, lv5 -- unpack as links, as copies or not at all depending on the
    # tar (MSYS tar copies a link whose target came first and fails on the
    # rest): tar's status is not trusted, and every path the archive lists as
    # a link is removed, so each platform reads the same files -- those the
    # loop below keeps on Linux, where links are skipped)
    xz -dc "$SRC/$XKB.tar.xz" | tar -xf - -C "$TMP/in" "$XKB/symbols" 2>/dev/null
    while IFS= read -r l; do
        [[ $l == "$XKB/symbols/"* && $l != *..* ]] && rm -f "$TMP/in/$l"
    done < <(xz -dc "$SRC/$XKB.tar.xz" | tar -tvf - "$XKB/symbols" 2>/dev/null \
                 | sed -n 's/^l.* \('"${XKB//./\\.}"'\/symbols\/[^ ]*\) -> .*$/\1/p')
    xz -dc "$SRC/$PROTO.tar.xz" | tar -xf - -C "$TMP/in" "$PROTO/include/X11/keysymdef.h" 2>/dev/null
    TREE=$TMP/in
    HEAD_XKB="$SHA_XKB $URL_XKB" HEAD_PROTO="$SHA_PROTO $URL_PROTO"
else
    HEAD_XKB="(unpacked tree, no sha256) $XKB" HEAD_PROTO="(unpacked tree, no sha256) $PROTO"
fi
SYM=$TREE/$XKB/symbols KSD=$TREE/$PROTO/include/X11/keysymdef.h
[[ -d $SYM && -f $SYM/us ]] || fail "no $XKB/symbols/us in the input"
[[ -f $KSD ]] || fail "no $PROTO/include/X11/keysymdef.h in the input"

# the symbols files in C order (the vendor folders' files after the top ones)
files=()
shopt -s nullglob
export LC_ALL=C
for f in "$SYM"/*; do [[ -f $f && ! -L $f ]] && files+=("$f"); done
for f in "$SYM"/*/*; do [[ -f $f && ! -L $f ]] && files+=("$f"); done

{
    printf '# kcl/fv.keyboard/fv.keyboard.layouts.sh -- GENERATED by tools/kbdlayout/gen.sh: do not edit\n'
    printf '# by hand (tools/kbdlayout/README.md). Data, not a unit: fv.keyboard sources it at the first\n'
    printf '# legacy Alt + non-ASCII key (or the first fv.keyboard.layoutBase); the variants after the\n'
    printf '# `return 0` line only for a layout FV_KBD_LAYOUT names that has no default table\n'
    printf '# (__FV_KL_ALL=1).\n'
    printf '# Layout data: xkeyboard-config %s (symbols/); keysym names: xorgproto %s\n' "$VER" "$PVER"
    printf '# (include/X11/keysymdef.h); both MIT/X11-style licences (COPYING of each release).\n'
    printf '# Inputs and sha256:\n#   %s\n#   %s\n' "$HEAD_XKB" "$HEAD_PROTO"
    printf '# A layout: [CHARACTER]=US-KEY for each non-ASCII character of the main block (TLDE,\n'
    printf '# AE01-AE12, AD01-AD12, AC01-AC11, AB01-AB10, BKSL), levels 1 and 2. A default layout:\n'
    printf '# its script letters in __FV_KL_D (the default tables), its other characters (symbols,\n'
    printf '# Latin letters) in __FV_KL_S, used only when FV_KBD_LAYOUT names it. __FV_KL_NOTAB: the\n'
    printf '# symbols files whose own layout has no table (Latin layouts, files that are no layout);\n'
    printf '# __FV_KL_VX: the variants with a table among their sections.\n'
    printf "declare -g __FV_KL_VERSION='%s'\n" "$VER"
    printf "declare -g __FV_KL_ORDER='%s'\n" "$DSET"
    printf 'declare -gA __FV_KL_D=() __FV_KL_S=()\n'
} > "$TMP/head" || fail "cannot write the header"

LC_ALL=C "$AWKP" -f "$HERE/layouts.awk" -v base="$SYM/" -v dset="$DSET" "$KSD" "${files[@]}" \
    > "$TMP/data" 2> "$TMP/err" || { cat "$TMP/err" >&2; fail "layouts.awk failed"; }
cat "$TMP/err" >&2
cat "$TMP/head" "$TMP/data" > "$TMP/out" || fail "cannot write the file"

if [[ $OUT == stdout ]]; then cat "$TMP/out"; exit 0; fi
if [[ -f $OUTF ]] && cmp -s "$TMP/out" "$OUTF"; then
    printf 'gen.sh: %s unchanged (xkeyboard-config %s)\n' "$OUTF" "$VER" >&2
    exit 0
fi
cat "$TMP/out" > "$OUTF" || fail "cannot write $OUTF"
printf 'gen.sh: %s regenerated (xkeyboard-config %s)\n' "$OUTF" "$VER" >&2
