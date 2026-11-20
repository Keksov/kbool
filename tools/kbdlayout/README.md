# tools/kbdlayout — the generator of fv.keyboard's layout tables

`gen.sh` reads the keyboard layouts of **xkeyboard-config** (the layout data of
every Linux desktop) and writes
[`kcl/fv.keyboard/fv.keyboard.layouts.sh`](../../kcl/fv.keyboard/README.md#layout-independent-keys-p3-3l):
for each layout, every non-ASCII character of the main block → the US key at
that position (Russian `а` → `f`). fv.keyboard uses it to name Alt + a letter
typed in a non-Latin layout by its key (`ESC а` → `kbAltF`), so `~F~ile`,
`Alt+X Exit` and every hot key work with any layout (design P3 §14.5, D30).
Plain bash plus one POSIX awk program (`layouts.awk`: no gawk extensions), so
gawk, mawk, BSD awk and busybox awk all run it. The inputs are **not**
committed; the file records their URLs and sha256.

## Regenerate

```bash
# download the two archives into a scratch folder (never into the repository), then generate
bash tools/kbdlayout/gen.sh --fetch /tmp/kbdlayout-2.48

# or, with the archives already there
bash tools/kbdlayout/gen.sh --src /tmp/kbdlayout-2.48

# look first: print the file, change nothing
bash tools/kbdlayout/gen.sh --src /tmp/kbdlayout-2.48 --stdout | less
```

It prints `… regenerated` or `… unchanged` and, on stderr, the conflicts of
the default layouts and a summary. **The same inputs always give a
byte-identical file** (no date in it; `tests/selftest.sh` checks it, and with
`KBDLAYOUT_SRC` set it regenerates a copy of the committed file and compares it
byte for byte). After regenerating, run `bash kcl/fv.keyboard/tests/tests.sh`.

| option | meaning |
|---|---|
| `--version V` | xkeyboard-config version, default `2.48` |
| `--proto-version P` | xorgproto version (its `keysymdef.h` names the keysyms), default `2025.1` |
| `--src DIR` | the folder holding `xkeyboard-config-V.tar.xz` and `xorgproto-P.tar.xz` |
| `--fetch DIR` | download them first (curl, else wget; HTTPS only) into DIR (created) |
| `--tree DIR` | instead of archives: `DIR/xkeyboard-config-V/symbols/` and `DIR/xorgproto-P/include/X11/keysymdef.h` already unpacked (the selftest's fixtures; the file then records no sha256) |
| `--out FILE` | the file written (default `kcl/fv.keyboard/fv.keyboard.layouts.sh`) |
| `--stdout` | print it instead |
| `--dset LIST` | the default layouts in priority order (default: the reviewed list below) |
| `--awk AWK` | the awk to run (default `$AWK`, else `awk`) |
| `--urls` | print the two URLs and exit |

rc 0 done; 1 a failure (a missing input, an archive whose sha256 is not the
pinned one, no `symbols/us`, a default layout not found, no awk / xz / sha256
tool); 2 a bad call. Messages go to stderr.

## Inputs (pinned)

| archive | sha256 | used for |
|---|---|---|
| `https://www.x.org/releases/individual/data/xkeyboard-config/xkeyboard-config-2.48.tar.xz` (2026-06-21) | `b77041324f0109f77161ee43743fe04baa485866af8460d31e476ad3f7648fd5` | `symbols/*` (the layouts) |
| `https://www.x.org/releases/individual/proto/xorgproto-2025.1.tar.xz` (2025-12-19) | `56898c716c0578df8a2d828c9c3e5c528277705c0484381a81960fe1a67668e8` | `include/X11/keysymdef.h` (keysym name → code point, from its `U+XXXX` comments) |

The archives of these versions must have exactly these sha256 (`gen.sh` checks
them before unpacking anything); another version's sha256 is recorded, not
checked (a note on stderr). The sha256 are of the archives as downloaded on
2026-11-20 (x.org publishes `.sig` files, not checked here). Only the files
needed are unpacked, into a temporary folder; the data is only read by awk,
every field checked, nothing in it executed. Both are under MIT / X11-style
licences (the `COPYING` file of each release); the generated file names them.

## The rules (layouts.awk)

* **Sections.** Every `xkb_symbols` section of every file in `symbols/` (symbolic
  links skipped: `caps`, `esperanto`, `lv3` … are aliases; with `--src` every path
  the archive lists as a link is removed after unpacking, so a tar that copies
  links, as MSYS tar does, reads the same files as Linux; and
  its vendor folders, for includes). A *layout* is a section whose flags hold
  `alphanumeric_keys` and not `hidden`; its name is the file for the file's
  default section (`ru`: the one flagged `default`, else the first) and
  `FILE(SECTION)` for the others (`bg(phonetic)`).
* **Merging** as xkbcomp, per level: `include "a(b)+c|d"` in statement order
  (`+` parts in the statement's mode, `|` parts augment; `:N` group parts other
  than 1 skipped), `augment` / `override` / `replace` statements and key
  prefixes; a key's `NoSymbol` or `any` keeps the level, `VoidSymbol` empties
  it, `replace key` replaces both levels. A section whose include target does
  not exist is left out (reported).
* **Keys.** The main block: TLDE, AE01–AE12, AD01–AD12, AC01–AC11, AB01–AB10,
  BKSL, by name or by the aliases the symbols use (`<LatQ>`…`<LatM>`: the
  qwerty aliases of `keycodes/aliases`; `<AC12>` = BKSL, `<HZTG>` = TLDE);
  levels 1 and 2 of group 1 (a bare list, or `symbols[Group1]`); a key's
  `type=` and its other groups are ignored.
* **Keysyms → characters:** a one-character name; a `keysymdef.h` name (by its
  `U+` comment); `U0430`; `0x1000430`; a Latin-1 value. Dead keys and other
  keysyms without a code point give nothing. Only characters ≥ U+00A0 (no C1,
  no surrogate) enter a table.
* **Entries:** level 1 before level 2, keys in the order above; a character
  met twice in one layout keeps its first key, except a level-2 character
  whose small letter is a level-1 character of the layout: it takes that
  key (Greek `Σ` is level 2 of both W, where `ς` is, and S, where `σ` is: it
  is S; 2.48: the five `gr` layouts and `ru(diktor)`'s `Ь`). "Small letter"
  comes from `keysymdef.h`'s Unicode names (`… CAPITAL LETTER X` → `… SMALL
  LETTER X`), so the rule needs no case table. The US key of each position
  is fixed (the PC-101 keys the kitty protocol's base key also uses); `us`
  itself must produce them at level 1 (a parser check).
* **Script letters and the rest:** a default layout's entries are split —
  its script letters go to `__FV_KL_D` (the default tables), the other
  characters to `__FV_KL_S`: everything below U+0370 (Latin letters, `§`,
  `×`, `÷`) and in General Punctuation (`– “ „`, ZWJ / ZWNJ), Currency (`€`),
  Letterlike (`№`) and the mathematical blocks. Latin-layout typists type
  those too (`ESC §` from a German keyboard must stay `kbAltChar`), so
  fv.keyboard uses `__FV_KL_S` only for a layout `FV_KBD_LAYOUT` names. The
  variants keep all their characters (they are used only when named).
* **Which layouts get a table:** the default set (`--dset`, all of them) and
  every other layout of a script typed key for key — at least 10 of the 26
  letter keys give a non-Latin character at level 1. Latin layouts (de, fr,
  AZERTY, Dvorak, …) get none: their typists' Alt + letter is already a Latin
  letter (fv.keyboard matches the typed letter first), and their accented
  letters would only add size.
* **Files without a table:** `__FV_KL_NOTAB` lists every top-level symbols
  file whose own (default) layout has no table — the Latin layouts (`us`,
  `de`, `fr`, …) and the files that are no layout (`level3`, `ctrl`, …);
  `__FV_KL_VX` the variants with a table among their sections (`us(rus)`,
  `de(ru)`, …). fv.keyboard skips a name of such a file that is not in
  `__FV_KL_VX` without a word and without loading the variants
  (`FV_KBD_LAYOUT=us,ru`).

The output: a header (the versions, the URLs and sha256), then
`__FV_KL_D[NAME]=$'[CHAR]=KEY …'` for each default layout (its script
letters), `__FV_KL_S[NAME]=…` for those that have other characters,
`__FV_KL_NOTAB=' … '` and `__FV_KL_VX=' … '`, then
`if [[ ${__FV_KL_ALL-} != 1 ]]; then return 0; fi` and `__FV_KL_V['NAME']=…`
for the variants (sorted): fv.keyboard sources the file at its first need
and sources it again with `__FV_KL_ALL=1` only for a layout named in
`FV_KBD_LAYOUT` that has no default table. A key is written as is when it is
a letter or a digit, else after a backslash; the text is ready for a bash
associative compound assignment.

Size (2.48): 1 629 sections; 14 default layouts, 860 letter entries (the
default table) + 24 other entries (`__FV_KL_S`); 252 variant layouts, 15 902
entries; 92 files without a table, 50 variants with a table among them; the
file is 141 KB (the part before the variants, ~9.7 KB, is all a session reads
unless a variant is named). Load cost: fv.keyboard README, Cost.

## The default order and its conflicts

A character in several default layouts takes the key of the first (unless
`FV_KBD_LAYOUT` or the locale names another, fv.keyboard README). The order,
reviewed against the conflicts `gen.sh` prints (2.48):

`ru gr il ara ir ge am th ua bg by kz mk rs`

* one per script first — Cyrillic ЙЦУКЕН (ru), Greek (gr), Hebrew (il),
  Arabic (ara), Persian (ir), Georgian (ge), Armenian (am), Thai (th): the most
  used layout of each;
* then the locale layouts of the same scripts: ua bg by kz mk rs — their own
  letters (Ukrainian `і ї є ґ`, Belarusian `ў`, Kazakh `ә ғ қ …`, Macedonian /
  Serbian `ј љ њ ѓ ќ ђ ћ џ ѕ`) are found without naming them; where they
  disagree with ru, ru wins unless the locale or `FV_KBD_LAYOUT` says
  otherwise.

The conflicts inside the default tables (lower case; the capitals are the
same; "→" the winner; 88 lines on stderr: 64 Cyrillic, 24 Arabic):

| script | characters | at | → |
|---|---|---|---|
| Cyrillic | all 32 letters `а`–`я` of ЙЦУКЕН | bg (BDS) at other keys for every one but `з`; mk and rs (a Latin-like order: `а`=a, `б`=b, `в`=v, …) for the 24 they share with ru; ua, by, kz agree with ru where they have the letter | ru (ЙЦУКЕН) |
| Cyrillic | `і` | s (ua), b (by), 3 (kz) | s (ua) |
| Arabic | 24 signs and letters (`ء آ أ ؤ إ ئ ة د ذ ز ط ظ ـ ك` the harakat `ً ٌ ٍ َ ُ ِ ّ ْ`, `، ؛`) | ara and ir at different keys | ara (Persian: locale `fa_IR` or `FV_KBD_LAYOUT=ir`) |

The symbols that used to conflict (`×` `÷`: ara / ir; `“` `„`: ge / bg / mk;
`№`: ru ua by 3, bg 0, kz /) are in no default table any more
(`__FV_KL_S`, used for a layout `FV_KBD_LAYOUT` names), so they are not
listed.

Across all variants (the summary lines): 1 912 Cyrillic, 1 295 Arabic, 383
Armenian, 143 Thai, 85 Georgian, 51 Hebrew and 32 Greek variant entries put
a default-table letter at another key (the symbols are not counted) — the phonetic
and alternative layouts, reached through `FV_KBD_LAYOUT`
(`bg_phonetic`, `ru_phonetic`, `am_phonetic`, `il_phonetic`, `ara_azerty`, …).
The full list prints on every run (`gen.sh … 2>&1 >/dev/null | grep ^conflict`).

## A new xkeyboard-config version

1. `bash tools/kbdlayout/gen.sh --fetch /tmp/kbdlayout-V --version V` (the
   sha256 is recorded, not checked: compare it with what x.org publishes),
   read the conflict list, update the order if a script's default changed.
2. Pin it: `DEF_XKB` / `PIN_XKB` (and `DEF_PROTO` / `PIN_PROTO`) in `gen.sh`,
   this README's tables, `--urls` in the selftest.
3. `bash kcl/fv.keyboard/tests/tests.sh` (012 spot-checks the tables).

## Tests

`bash tools/kbdlayout/tests/selftest.sh` (also run by
`kcl/fv.keyboard/tests/013_Generator.sh`): for every awk it finds
(`SELFTEST_AWKS="gawk mawk"` to choose), the hand-made fixtures in
`tests/fixtures/` (a `us`, a `ru` and a `gr` symbols file and a small
`keysymdef.h`, exercising the merge rules, the aliases, the keysym forms,
`any` / `NoSymbol` / `replace key`, two groups, comments in and out of strings,
a missing include, hidden and non-layout sections, a Latin variant, a
non-Latin variant in a Latin layout's file, a capital on two keys) give
exactly `tests/expected_out.txt`, a second run is byte-identical, and the
entries read back by sourcing the output are the ones written down in the
script; then `--urls`, `--out` (a second run says `unchanged`) and the error
paths (incl. an archive that is not the pinned one). With
`KBDLAYOUT_SRC=DIR` (the two real archives) the committed file is regenerated
into a copy and compared byte for byte. After a fixture change, regenerate the
golden file (the command is in the script's header) and check the new entries
against the list in the script.
