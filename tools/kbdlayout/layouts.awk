# layouts.awk -- xkeyboard-config symbols -> the layout tables of kcl/fv.keyboard.
# POSIX awk (no gawk extensions: no length(array), no strtonum, no {n}
# intervals); run with LC_ALL=C (bytes: printf "%c" makes one byte).
#
#   awk -f layouts.awk -v dset="ru gr ..." KEYSYMDEF.H SYMBOLS-FILE...
#
# Each SYMBOLS-FILE is one file of xkeyboard-config's symbols/ folder, named by
# its path; the file name after the last "/" given as -v base=DIR-PREFIX is
# stripped, so "DIR/ru" is the file "ru" and "DIR/sun_vndr/gr" "sun_vndr/gr".
# Reads every xkb_symbols section, resolves include / augment / override /
# replace (xkbcomp's merge per level; `any` and NoSymbol keep a level), and
# for every layout section (flags with alphanumeric_keys, not hidden) takes
# the main block's non-ASCII characters of levels 1 and 2 -> the US key at
# that position. Output (the data part of fv.keyboard.layouts.sh):
#
#   __FV_KL_D[NAME]=$'TEXT'   each layout of the default set (dset, in order):
#                             its script letters
#   __FV_KL_S[NAME]=$'TEXT'   the same layout's other characters (issym:
#                             symbols, Latin letters), when it has any
#   __FV_KL_NOTAB=' FILE ...' the symbols files whose own layout has no
#                             table (Latin layouts: "us", "de"; files that are
#                             no layout: "level3"), C order
#   __FV_KL_VX=' NAME ...'    the variants with a table in those files
#                             ("us(rus)"); fv.keyboard skips the other names of
#                             those files quietly, without loading the variants
#   if [[ ${__FV_KL_ALL-} != 1 ]]; then return 0; fi
#   declare -gA __FV_KL_V=()
#   __FV_KL_V['NAME']=$'TEXT' every other layout of a script typed key for
#                             key (>= 10 of the 26 letter keys non-Latin at
#                             level 1), sorted by name (C order)
#
# NAME is the file for its default section ("ru") and FILE(SECTION) for the
# others ("bg(phonetic)"); TEXT is "[CHAR]=BASE ..." where BASE is the US key
# (a letter or digit as is, anything else after a backslash), ready for a bash
# associative compound assignment. Level 1 before level 2, keys in the order
# TLDE AE01-AE12 AD01-AD12 AC01-AC11 AB01-AB10 BKSL; a character met twice in
# one layout keeps its first key, except a level-2 capital whose small letter
# is at level 1 of some key (entries()). On stderr: the conflicts inside the default
# set per script (a character at different keys, "-> the winner"), a summary
# of the variants, the sections left out (an include target missing), and a
# count line.

BEGIN {
    nk = split("TLDE AE01 AE02 AE03 AE04 AE05 AE06 AE07 AE08 AE09 AE10 AE11 AE12 " \
        "AD01 AD02 AD03 AD04 AD05 AD06 AD07 AD08 AD09 AD10 AD11 AD12 " \
        "AC01 AC02 AC03 AC04 AC05 AC06 AC07 AC08 AC09 AC10 AC11 " \
        "AB01 AB02 AB03 AB04 AB05 AB06 AB07 AB08 AB09 AB10 BKSL", KEYS, " ")
    us = "`1234567890-=qwertyuiop[]asdfghjkl;'zxcvbnm,./\\"
    for (i = 1; i <= nk; i++) { MK[KEYS[i]] = i; USB[KEYS[i]] = substr(us, i, 1) }
    # keycodes/aliases "qwerty" and evdev's (the only aliases the symbols use)
    na = split("LatQ AD01 LatW AD02 LatE AD03 LatR AD04 LatT AD05 LatY AD06 LatU AD07 " \
        "LatI AD08 LatO AD09 LatP AD10 LatA AC01 LatS AC02 LatD AC03 LatF AC04 LatG AC05 " \
        "LatH AC06 LatJ AC07 LatK AC08 LatL AC09 LatZ AB01 LatX AB02 LatC AB03 LatV AB04 " \
        "LatB AB05 LatN AB06 LatM AB07 AC12 BKSL HZTG TLDE", t, " ")
    for (i = 1; i < na; i += 2) ALIAS[t[i]] = t[i + 1]
    for (i = 32; i < 127; i++) ORD[sprintf("%c", i)] = i
    HEX = "0123456789abcdef"
    nd = split(dset, DS, " ")
    for (i = 1; i <= nd; i++) INDSET[DS[i]] = i
    nt = 0; cur = ""; nsec = 0
}

# ---- keysymdef.h: XK_name -> code point (from the "U+XXXX" comment) --------
FILENAME ~ /keysymdef\.h$/ {
    if ($1 == "#define" && $2 ~ /^XK_/ && match($0, /U\+[0-9A-Fa-f]+/)) {
        n = substr($2, 4); v = hexval(substr($0, RSTART + 2, RLENGTH - 2))
        # the Unicode name after U+XXXX: capital letter -> its small letter's name (L2)
        un = substr($0, RSTART + RLENGTH); sub(/^[ \t]+/, "", un); sub(/[ \t]*[*].*$/, "", un)
        if (un != "" && !(un in UN)) UN[un] = v
        if (un ~ /CAPITAL LETTER/ && !(v in CAPN)) { sn = un; sub(/CAPITAL LETTER/, "SMALL LETTER", sn); CAPN[v] = sn }
        if (!(n in KS)) KS[n] = v
        if ($3 ~ /^0x[0-9A-Fa-f]+$/) { kv = hexval(substr($3, 3)); if (!(kv in KSV)) KSV[kv] = v }
        nks++
    }
    next
}

# ---- a symbols file: tokens, parsed when the next file starts or at END ------
FNR == 1 { if (cur != "") parsefile(cur); cur = FILENAME; if (base != "" && index(cur, base) == 1) cur = substr(cur, length(base) + 1); nt = 0 }
{ tokline(uncomment($0)) }

END {
    if (cur != "") parsefile(cur)
    if (!nks) { print "layouts.awk: no keysyms read (keysymdef.h first)" > "/dev/stderr"; exit 1 }
    if (!("us" in DFLT)) { print "layouts.awk: no symbols/us among the inputs" > "/dev/stderr"; exit 1 }
    # the US layout must give the US keys this table assumes (a parser check)
    resolve("us(" DFLT["us"] ")")
    for (i = 1; i <= nk; i++) {
        k = KEYS[i]; c = kschar(R["us(" DFLT["us"] ")", k, 1])
        if (c != ORD[USB[k]]) { printf "layouts.awk: us(%s) key %s is not '%s'\n", DFLT["us"], k, USB[k] > "/dev/stderr"; exit 1 }
    }
    nl = 0
    for (s = 1; s <= nsec; s++) {
        sid = SEC[s]
        f = SFILE[sid]
        if (f !~ /\// && !(f in TOPF)) { TOPF[f] = 1; TF[++ntf] = f }
        if (SFL[sid] !~ / alphanumeric_keys/ || SFL[sid] ~ / hidden/) continue
        resolve(sid)
        if (f ~ /\//) continue                        # vendor folders: no layout of their own here
        nm = (DFLT[f] == SNAME[sid]) ? f : f "(" SNAME[sid] ")"
        if (BAD[sid]) { printf "layouts.awk: left out %s (include %s not found)\n", nm, BAD[sid] > "/dev/stderr"; nout++; continue }
        text = entries(sid, nm)
        # a variant only for a script typed key for key: at least 10 of the 26
        # letter keys give a non-Latin character at level 1 (the Latin layouts'
        # accented letters stay out: their typists' Alt+letter is already Latin)
        if (text == "" || (!(nm in INDSET) && NL[nm] < 10)) { nlat++; continue }
        TEXT[nm] = text; NM[++nl] = nm
    }
    # sort the names (insertion sort; C byte order)
    for (i = 2; i <= nl; i++) { x = NM[i]; for (j = i - 1; j >= 1 && NM[j] > x; j--) NM[j + 1] = NM[j]; NM[j + 1] = x }
    for (i = 2; i <= ntf; i++) { x = TF[i]; for (j = i - 1; j >= 1 && TF[j] > x; j--) TF[j + 1] = TF[j]; TF[j + 1] = x }
    for (i = 1; i <= nd; i++) {
        if (!(DS[i] in TEXT)) { printf "layouts.awk: default layout %s not found\n", DS[i] > "/dev/stderr"; exit 1 }
        printf "__FV_KL_D[%s]=$'%s'\n", DS[i], bq(LETT[DS[i]]); ndn += NE[DS[i]] - NS2[DS[i]]
    }
    for (i = 1; i <= nd; i++) if (SYMT[DS[i]] != "") { printf "__FV_KL_S[%s]=$'%s'\n", DS[i], bq(SYMT[DS[i]]); nsn += NS2[DS[i]] }
    # the symbols files whose own layout has no table (the Latin layouts: us,
    # de, fr, ...; the files that are no layout: level3, ...) and the variants
    # with a table among their sections (us(rus)): fv.keyboard skips the
    # others of those files quietly, without loading the variants
    o = ""
    for (i = 1; i <= ntf; i++) if (!(TF[i] in TEXT)) { o = o " " TF[i]; NOTAB[TF[i]] = 1; nnt++ }
    printf "__FV_KL_NOTAB='%s '\n", o
    o = ""
    for (i = 1; i <= nl; i++) { x = NM[i]; sub(/[(].*$/, "", x); if (x in NOTAB) { o = o " " NM[i]; nvx++ } }
    printf "__FV_KL_VX='%s '\n", o
    print "# the variants: sourced again with __FV_KL_ALL=1 only for a layout FV_KBD_LAYOUT names"
    print "if [[ ${__FV_KL_ALL-} != 1 ]]; then return 0; fi"
    print "declare -gA __FV_KL_V=()"
    for (i = 1; i <= nl; i++) if (!(NM[i] in INDSET)) { printf "__FV_KL_V['%s']=$'%s'\n", NM[i], bq(TEXT[NM[i]]); nvn += NE[NM[i]]; nv++ }
    conflicts()
    printf "layouts.awk: %d sections, %d default layouts (%d letter entries, %d other), %d variant layouts (%d entries, %d in files without a table), %d Latin layouts, %d files without a table, %d left out\n", \
        nsec, nd, ndn, nsn, nv, nvn, nvx, nlat, nnt, nout > "/dev/stderr"
}

# ---- helpers ----------------------------------------------------------------
# S quoted for bash's $'...' (only \ and ' are special there; no gsub: its
# replacement escapes differ between awks)
function bq(s,   i, c, o) {
    o = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"
        else if (c == "'") o = o "\\'"
        else o = o c
    }
    return o
}

function hexval(s,   i, v) {
    s = tolower(s); v = 0
    for (i = 1; i <= length(s); i++) v = v * 16 + index(HEX, substr(s, i, 1)) - 1
    return v
}

# a line without its comment (// or # outside a string)
function uncomment(s,   i, c, q, o) {
    if (index(s, "\"") == 0) {
        i = index(s, "//"); if (i) s = substr(s, 1, i - 1)
        i = index(s, "#"); if (i) s = substr(s, 1, i - 1)
        return s
    }
    q = 0; o = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\"") q = !q
        else if (!q && (c == "#" || (c == "/" && substr(s, i + 1, 1) == "/"))) break
        o = o c
    }
    return o
}

function addtok(t) { TOK[++nt] = t }

function tokline(s,   c, m) {
    while (s != "") {
        if (match(s, /^[ \t\r\f]+/)) { s = substr(s, RLENGTH + 1); continue }
        c = substr(s, 1, 1)
        if (c == "\"") {
            m = index(substr(s, 2), "\"")
            if (!m) { addtok("\"" substr(s, 2)); return }
            addtok("\"" substr(s, 2, m - 1)); s = substr(s, m + 2); continue
        }
        if (c == "<") { m = index(s, ">"); if (m) { addtok(substr(s, 1, m)); s = substr(s, m + 1); continue } }
        if (index("{}[](),;=!+|", c)) { addtok(c); s = substr(s, 2); continue }
        if (match(s, /^[A-Za-z0-9_.-]+/)) { addtok(substr(s, 1, RLENGTH)); s = substr(s, RLENGTH + 1); continue }
        addtok(c); s = substr(s, 2)
    }
}

# the tokens of file F -> sections and statements
function parsefile(f,   i, fl, nm, sid, t, mode, sp, kc, d, j, m, kb, l1, l2, expl) {
    i = 1; fl = ""
    while (i <= nt) {
        t = TOK[i]
        if (t != "xkb_symbols") {
            if (t == ";" || t == "}") fl = ""
            else if (t ~ /^[a-z_]+$/) fl = fl " " t
            i++; continue
        }
        nm = TOK[i + 1]
        if (substr(nm, 1, 1) != "\"") { i++; continue }
        nm = substr(nm, 2); i += 2
        if (TOK[i] != "{") { fl = ""; continue }
        i++
        sid = f "(" nm ")"
        if (!(sid in SFL)) { SEC[++nsec] = sid; NS[sid] = 0 }
        SFL[sid] = fl " "; SFILE[sid] = f; SNAME[sid] = nm
        if (fl ~ / default/ && !(f in DEXPL)) { DFLT[f] = nm; DEXPL[f] = 1 }
        else if (!(f in DFLT)) DFLT[f] = nm
        fl = ""
        while (i <= nt && TOK[i] != "}") {
            t = TOK[i]; mode = "o"
            if (t == "override" || t == "augment" || t == "replace") { mode = substr(t, 1, 1); i++; t = TOK[i] }
            if (t == "include" || (substr(t, 1, 1) == "\"" && TOK[i - 1] ~ /^(override|augment|replace)$/)) {
                if (t == "include") i++
                sp = TOK[i]
                if (substr(sp, 1, 1) == "\"") { m = ++NS[sid]; STY[sid, m] = "i"; SMO[sid, m] = mode; SAR[sid, m] = substr(sp, 2) }
                i++; if (TOK[i] == ";") i++
                continue
            }
            if (t == "key" && TOK[i + 2] == "{") {
                kc = TOK[i + 1]; i += 3; d = 0; m = 0
                split("", kb)
                while (i <= nt) {
                    if (TOK[i] == "{") d++
                    else if (TOK[i] == "}") { if (!d) break; d-- }
                    kb[++m] = TOK[i]; i++
                }
                i++; if (TOK[i] == ";") i++
                kc = substr(kc, 2, length(kc) - 2)
                if (kc in ALIAS) kc = ALIAS[kc]
                if (!(kc in MK)) continue
                l1 = ""; l2 = ""; expl = 0
                for (j = 1; j <= m; j++) {
                    if (kb[j] == "symbols" && kb[j + 1] == "[") {
                        if (kb[j + 2] ~ /^(Group)?1$/ && kb[j + 4] == "=" && kb[j + 5] == "[") { j += 5; expl = 1; break }
                        continue
                    }
                    if (kb[j] == "[" && (j == 1 || kb[j - 1] == "," || kb[j - 1] == "{")) break
                }
                if (j > m) continue
                # the list from kb[j] = "[": level 1, level 2
                j++
                if (kb[j] != "," && kb[j] != "]") { l1 = kb[j]; j++ }
                if (kb[j] == ",") { j++; if (kb[j] != "," && kb[j] != "]") l2 = kb[j] }
                m = ++NS[sid]; STY[sid, m] = "k"; SMO[sid, m] = mode; SAR[sid, m] = kc
                SL1[sid, m] = (l1 == "NoSymbol" || l1 == "any" || l1 == "{") ? "" : l1
                SL2[sid, m] = (l2 == "NoSymbol" || l2 == "any" || l2 == "{") ? "" : l2
                continue
            }
            # any other statement: up to its ';' (braces counted)
            d = 0
            while (i <= nt) {
                if (TOK[i] == "{") d++
                else if (TOK[i] == "}") { if (!d) break; d-- }
                else if (TOK[i] == ";" && !d) { i++; break }
                i++
            }
        }
        i++; if (TOK[i] == ";") i++
    }
}

# set level L of key K of SID to V by MODE (o override, a augment, r replace)
function mset(sid, k, l, v, mode) {
    if (mode == "a") { if (R[sid, k, l] == "") R[sid, k, l] = v; return }
    if (v == "" && mode != "r") return
    R[sid, k, l] = v
}

# resolve SID's keys into R[SID, KEY, LEVEL] (memoised; a cycle stops at its start)
function resolve(sid,   i, m, sp, n, parts, seps, p, q, f2, s2, sb, md, k, x, c) {
    if (sid in DONE) return
    DONE[sid] = 1
    for (i = 1; i <= NS[sid]; i++) {
        if (STY[sid, i] == "k") {
            md = SMO[sid, i]; k = SAR[sid, i]
            mset(sid, k, 1, SL1[sid, i], md); mset(sid, k, 2, SL2[sid, i], md)
            continue
        }
        # include "a(b)+c|d": parts joined by + (the statement's mode) or | (augment)
        sp = SAR[sid, i]; n = 0; x = "+"
        while (sp != "") {
            if (match(sp, /[+|]/)) { p = substr(sp, 1, RSTART - 1); c = substr(sp, RSTART, 1); sp = substr(sp, RSTART + 1) }
            else { p = sp; c = ""; sp = "" }
            if (p != "") { parts[++n] = p; seps[n] = x }
            x = c
        }
        for (q = 1; q <= n; q++) {
            p = parts[q]
            if (p ~ /:[0-9]+$/) { if (p !~ /:1$/) continue; sub(/:1$/, "", p) }
            if (match(p, /\(.*\)$/)) { f2 = substr(p, 1, RSTART - 1); s2 = substr(p, RSTART + 1, RLENGTH - 2) }
            else { f2 = p; s2 = (p in DFLT) ? DFLT[p] : "" }
            sb = f2 "(" s2 ")"
            if (!(sb in SFL)) { if (!BAD[sid]) BAD[sid] = p; continue }
            resolve(sb)
            if (BAD[sb] && !BAD[sid]) BAD[sid] = BAD[sb]
            md = (seps[q] == "|") ? "a" : SMO[sid, i]
            for (m = 1; m <= nk; m++) {
                k = KEYS[m]
                if (md == "r") { R[sid, k, 1] = R[sb, k, 1]; R[sid, k, 2] = R[sb, k, 2] }
                else { mset(sid, k, 1, R[sb, k, 1], md); mset(sid, k, 2, R[sb, k, 2], md) }
            }
        }
    }
}

# keysym name -> code point, -1 when it is no character
function kschar(n,   v) {
    if (n == "") return -1
    if (length(n) == 1 && (n in ORD)) return ORD[n]
    if (n in KS) return KS[n]
    if (n ~ /^U[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?$/) return hexval(substr(n, 2))
    if (n ~ /^0x[0-9A-Fa-f]+$/) {
        v = hexval(substr(n, 3))
        if (v >= 16777216) return v - 16777216
        if ((v >= 32 && v <= 126) || (v >= 160 && v <= 255)) return v
        if (v in KSV) return KSV[v]
    }
    return -1
}

# code point -> UTF-8 bytes
function utf8(c) {
    if (c < 128) return sprintf("%c", c)
    if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
    if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
    return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64)
}

# a character of a table: >= U+00A0 (no C1 control), no surrogate, <= U+10FFFF
function okchar(c) { return c >= 160 && c <= 1114111 && !(c >= 55296 && c <= 57343) }

function scriptof(c) {
    if (c >= 1024 && c <= 1327) return "Cyrillic"
    if ((c >= 880 && c <= 1023) || (c >= 7936 && c <= 8191)) return "Greek"
    if (c >= 1424 && c <= 1535) return "Hebrew"
    if (c >= 1328 && c <= 1423) return "Armenian"
    if ((c >= 1536 && c <= 1791) || (c >= 1872 && c <= 1919) || (c >= 2208 && c <= 2303) || (c >= 64336 && c <= 65279)) return "Arabic"
    if ((c >= 4256 && c <= 4351) || (c >= 7312 && c <= 7359)) return "Georgian"
    if (c >= 3584 && c <= 3711) return "Thai"
    if ((c >= 160 && c <= 591) || (c >= 7680 && c <= 7935)) return "Latin"
    return "other"
}

# a character that is no script letter (L3): below U+0370 (ASCII, Latin-1,
# the Latin blocks, IPA, spacing modifiers, combining marks), General
# Punctuation, Currency Symbols, Letterlike Symbols, the mathematical blocks
# (Mathematical Operators, Misc. Mathematical Symbols A / B, Supplemental
# Mathematical Operators, Mathematical Alphanumeric Symbols)
function issym(c) {
    return c < 880 || (c >= 8192 && c <= 8303) || (c >= 8352 && c <= 8399) || (c >= 8448 && c <= 8527) \
        || (c >= 8704 && c <= 8959) || (c >= 10176 && c <= 10223) || (c >= 10624 && c <= 11007) \
        || (c >= 119808 && c <= 120831)
}

# the TEXT of SID (layout name NM); NE[NM] = its entries; CH[NM, char] = its
# key; LETT[NM] / SYMT[NM] the same entries split: script letters / the rest
# (issym). A character met twice keeps its first key, except a level-2
# character whose small letter (keysymdef.h's names: CAPITAL -> SMALL) is a
# level-1 character of this layout: it takes that key (Greek Sigma: S, where
# sigma is, not W, where final sigma is)
function entries(sid, nm,   l, i, k, c, ch, b, o, e, lch) {
    o = ""; NE[nm] = 0; NL[nm] = 0; LETT[nm] = ""; SYMT[nm] = ""
    for (l = 1; l <= 2; l++) for (i = 1; i <= nk; i++) {
        k = KEYS[i]; c = kschar(R[sid, k, l])
        if (!okchar(c)) continue
        if (l == 1 && USB[k] ~ /^[a-z]$/ && scriptof(c) != "Latin") NL[nm]++
        ch = utf8(c)
        if ((nm, ch) in CH) continue
        b = USB[k]
        if (l == 2 && (c in CAPN) && (CAPN[c] in UN)) { lch = utf8(UN[CAPN[c]]); if ((nm, lch) in L1K) b = L1K[nm, lch] }
        if (l == 1) L1K[nm, ch] = b
        CH[nm, ch] = b; CP[ch] = c
        if (b !~ /^[a-z0-9]$/) b = "\\" b
        e = "[" ch "]=" b
        o = o (o == "" ? "" : " ") e; NE[nm]++
        if (issym(c)) { SYMT[nm] = SYMT[nm] (SYMT[nm] == "" ? "" : " ") e; NS2[nm]++ }
        else LETT[nm] = LETT[nm] (LETT[nm] == "" ? "" : " ") e
        if (!(ch in SEEN)) { SEEN[ch] = 1; ALLCH[++nall] = ch }
    }
    return o
}

# the conflicts of the default set's script letters (per script, in code
# point order; the issym characters are in no default table) and how many
# variant entries disagree with the default set's winner
function conflicts(   i, j, ch, w, wb, line, n, sc, x, o, cnt, vd) {
    # code point order of every character seen
    for (i = 2; i <= nall; i++) { x = ALLCH[i]; for (j = i - 1; j >= 1 && CP[ALLCH[j]] > CP[x]; j--) ALLCH[j + 1] = ALLCH[j]; ALLCH[j + 1] = x }
    for (i = 1; i <= nall; i++) {
        ch = ALLCH[i]; w = ""; wb = ""; n = 0; line = ""
        if (issym(CP[ch])) continue               # not in the default tables (L3)
        split("", o)
        for (j = 1; j <= nd; j++) {
            if (!((DS[j], ch) in CH)) continue
            x = CH[DS[j], ch]
            if (w == "") { w = DS[j]; wb = x }
            if (!(x in o)) { o[x] = DS[j]; n++ } else o[x] = o[x] "," DS[j]
        }
        if (n > 1) {
            sc = scriptof(CP[ch]); line = ""
            for (x in o) line = line " " x "=" o[x]
            printf "conflict %s U+%04X %s:%s -> %s (%s)\n", sc, CP[ch], ch, sortwords(line), wb, w > "/dev/stderr"
            cnt[sc]++
        }
        if (w != "") for (j = 1; j <= nl; j++) if (!(NM[j] in INDSET) && ((NM[j], ch) in CH) && CH[NM[j], ch] != wb) vd[scriptof(CP[ch])]++
    }
    for (sc in cnt) printf "conflicts %s: %d characters inside the default set\n", sc, cnt[sc] > "/dev/stderr"
    for (sc in vd) printf "variants %s: %d variant entries put a default-table character at another key\n", sc, vd[sc] > "/dev/stderr"
}

# the words of S in C order, joined by one space
function sortwords(s,   n, a, i, j, x, o) {
    n = split(s, a, " ")
    for (i = 2; i <= n; i++) { x = a[i]; for (j = i - 1; j >= 1 && a[j] > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
    o = ""
    for (i = 1; i <= n; i++) o = o " " a[i]
    return o
}
