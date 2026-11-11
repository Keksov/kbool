# width.awk -- Unicode data -> the fv.unicode class table (the data part of the
# generated block). Called by gen_width.sh; POSIX awk only (gawk, mawk, BSD awk,
# busybox awk): no strtonum, no gensub, no arrays of arrays; hex is parsed by hand.
#
#   awk -f width.awk EastAsianWidth.txt UnicodeData.txt DerivedCoreProperties.txt \
#       HangulSyllableType.txt emoji-data.txt
#
# The files are told apart by their names, so the order does not matter.
#
# The width of a code point follows glibc 2.41 (its localedata/charmaps/UTF-8
# WIDTH rules), in this order:
#   U+00AD SOFT HYPHEN                         1
#   U+115F HANGUL CHOSEONG FILLER              2
#   U+3248..U+324F (circled numbers on black   2   East_Asian_Width A, but glibc
#     squares)                                     2.41's table has them 2
#   Hangul_Syllable_Type V or T                0
#   General_Category Mn or Me                  0
#   Default_Ignorable_Code_Point               0
#   East_Asian_Width W or F (explicit lines)   2
#   everything else                            1
# (EastAsianWidth's @missing defaults and the header's prose W defaults are NOT
# applied, as in glibc. So an unassigned code point is 1, except where a rule
# above names it explicitly: the reserved ranges EastAsianWidth.txt lists as W
# (Cn lines in the CJK blocks and planes 2 and 3) are 2, and the unassigned
# Default_Ignorable_Code_Points (U+2065, U+FFF0..FFF8, U+E0000..E0FFF) are 0.
# glibc's wcwidth() is -1 for all of them: it lists assigned characters only.)
#
# The class adds the cluster role (kcl/fv.unicode/README.md):
#   z  width 0 (extends the cell before it)
#   m  Emoji_Modifier (width 2; extends an Extended_Pictographic base)
#   r  a regional indicator (UnicodeData name REGIONAL INDICATOR SYMBOL LETTER *)
#   x  Extended_Pictographic, width 1        y  Extended_Pictographic, width 2
#   n  width 1                               w  width 2
# All lower case and no two alike in any case, on purpose: a caller's
# nocasematch must never make one letter match another.
#
# Output (stdout): bash lines for the generated block --
#   __FV_UC_P   68 strings of 64 letters: the letter of page p (256 code points)
#               is ${__FV_UC_P[p >> 6]:p % 64:1} -- the class all its code points
#               share, or '*' for a page whose code points differ. Short strings
#               in an array, not one long string: bash's substring of a long
#               string walks it character by character in a UTF-8 locale, and
#               68 elements load ~3x faster than one element per page.
#   __FV_UC_M   [page]=the 256 class letters of every '*' page, run-length
#               coded (letter + count: n169x1n86); fv.unicode expands a page on
#               its first lookup
# Diagnostics on stderr; exit 1 when an input is missing or malformed.

function hex(s,    i, n, c) {
    n = 0
    s = toupper(s)
    if (s == "" || length(s) > 6) return -1
    for (i = 1; i <= length(s); i++) {
        c = index("0123456789ABCDEF", substr(s, i, 1))
        if (c == 0) return -1
        n = n * 16 + c - 1
    }
    return n
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function die(msg) { printf "width.awk: %s\n", msg > "/dev/stderr"; bad = 1; exit 1 }
# "A..B" or "A" -> LO, HI
function range(s,    p) {
    s = trim(s)
    p = index(s, "..")
    if (p) { LO = hex(substr(s, 1, p - 1)); HI = hex(substr(s, p + 2)) } else { LO = hex(s); HI = LO }
    if (LO < 0 || HI < LO || HI > 1114111) die(FILENAME ":" FNR ": bad code point range '" s "'")
}
# a data line "RANGE ; VALUE # comment" -> LO, HI, VAL; 0 for a comment / blank line
function dataline(    s, f) {
    s = $0
    sub(/#.*/, "", s)
    if (trim(s) == "") return 0
    if (split(s, f, ";") < 2) die(FILENAME ":" FNR ": no ';'")
    range(f[1])
    VAL = trim(f[2])
    return 1
}

FNR == 1 {
    name = FILENAME
    sub(/.*\//, "", name)
    if (name == "EastAsianWidth.txt") kind = "eaw"
    else if (name == "UnicodeData.txt") kind = "ud"
    else if (name == "DerivedCoreProperties.txt") kind = "dcp"
    else if (name == "HangulSyllableType.txt") kind = "hst"
    else if (name == "emoji-data.txt") kind = "emoji"
    else die("unknown input " FILENAME)
    seen[kind] = 1
}
kind == "eaw" && /^#[ \t]*@missing:/ {
    s = $0
    sub(/^#[ \t]*@missing:[ \t]*/, "", s)
    split(s, f, ";")
    v = trim(f[2])
    if (v == "W" || v == "F") printf "width.awk: note: '@missing %s' not applied (glibc takes explicit lines only)\n", trim(s) > "/dev/stderr"
    next
}
kind == "eaw" {
    if (!dataline()) next
    if (VAL == "W" || VAL == "F") for (c = LO; c <= HI; c++) wide[c] = 1
    neaw++
    next
}
kind == "ud" {
    if ($0 == "") next
    if (split($0, f, ";") < 15) die(FILENAME ":" FNR ": not 15 fields")
    c = hex(f[1])
    if (c < 0) die(FILENAME ":" FNR ": bad code point")
    if (f[2] ~ /, First>$/) { first = c; next }
    a = c
    if (f[2] ~ /, Last>$/) a = first
    if (f[3] == "Mn" || f[3] == "Me") for (k = a; k <= c; k++) zero[k] = 1
    if (f[2] ~ /^REGIONAL INDICATOR SYMBOL LETTER /) ri[c] = 1
    nud++
    next
}
kind == "dcp" {
    if (!dataline()) next
    if (VAL == "Default_Ignorable_Code_Point") { for (c = LO; c <= HI; c++) zero[c] = 1; ndi++ }
    next
}
kind == "hst" {
    if (!dataline()) next
    if (VAL == "V" || VAL == "T") { for (c = LO; c <= HI; c++) zero[c] = 1; nvt++ }
    next
}
kind == "emoji" {
    if (!dataline()) next
    if (VAL == "Extended_Pictographic") { for (c = LO; c <= HI; c++) xp[c] = 1; nxp++ }
    else if (VAL == "Emoji_Modifier") { for (c = LO; c <= HI; c++) em[c] = 1; nem++ }
    next
}

function cls(c) {
    if (c == 173) return "n"
    if (c == 4447) return "w"
    if (c >= 12872 && c <= 12879) return "w"                   # U+3248..324F: see the header
    if (c in zero) return "z"
    if (c in em) return "m"
    if (c in ri) return "r"
    if (c in xp) return (c in wide) ? "y" : "x"
    return (c in wide) ? "w" : "n"
}

# the 256 letters of a page run-length coded: letter + count, e.g. n169x1n86
function rle(s,    o, c, d, n, i) {
    o = ""; c = substr(s, 1, 1); n = 0
    for (i = 1; i <= length(s); i++) {
        d = substr(s, i, 1)
        if (d == c) n++
        else { o = o c n; c = d; n = 1 }
    }
    return o c n
}

END {
    if (bad) exit 1
    if (!seen["eaw"] || !seen["ud"] || !seen["dcp"] || !seen["hst"] || !seen["emoji"]) die("an input file is missing")
    if (!neaw || !nud || !ndi || !nvt || !nxp || !nem) die("an input holds none of the lines it must have")
    pages = ""
    nm = 0
    for (p = 0; p < 4352; p++) {
        s = ""
        u = 1
        k0 = cls(p * 256)
        for (c = p * 256; c < p * 256 + 256; c++) {
            k = cls(c)
            s = s k
            if (k != k0) u = 0
        }
        if (u) pages = pages k0
        else { pages = pages "*"; nm++; mp[nm] = p; ms[nm] = s }
    }
    print "declare -ga __FV_UC_P=("
    for (i = 0; i < 68; i++) printf "    '%s'\n", substr(pages, i * 64 + 1, 64)
    print ")"
    print "declare -ga __FV_UC_M=("
    for (i = 1; i <= nm; i++) printf "    [%d]=%s\n", mp[i], rle(ms[i])
    print ")"
    printf "width.awk: %d pages, %d mixed\n", 4352, nm > "/dev/stderr"
}
