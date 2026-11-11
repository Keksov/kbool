# tools/unicode — the generator of the fv.unicode character table

`gen_width.sh` reads the Unicode Character Database and rewrites the generated
block of [`kcl/fv.unicode/fv.unicode.sh`](../../kcl/fv.unicode/README.md): one
class letter per code point (width 0 / 1 / 2 and the cluster role), by the
**glibc 2.41 width rules**, for **Unicode 16.0.0** (the version glibc 2.41 —
Debian 13 — uses). Plain bash plus one POSIX awk program (`width.awk`: no
`strtonum`, hex parsed by hand), so gawk, mawk, BSD awk and busybox awk all run
it. The inputs are **not** committed; the block records their URLs and sha256.

## Regenerate

```bash
# download the five files into a scratch folder (never into the repository), then generate
bash tools/unicode/gen_width.sh --fetch /tmp/ucd-16.0.0

# or, with the files already there
bash tools/unicode/gen_width.sh --ucd /tmp/ucd-16.0.0

# look first: print the block, change nothing
bash tools/unicode/gen_width.sh --ucd /tmp/ucd-16.0.0 --stdout | less
```

It prints `… regenerated` or `… unchanged`. **The same inputs always give a
byte-identical file** (no date in the block; `tests/selftest.sh` checks it, and
with `UNICODE_UCD` set it regenerates a copy of the committed unit and compares
it byte for byte). After regenerating, run `bash kcl/fv.unicode/tests/tests.sh`
and, in the lab VM, its `004_Glibc` (charWidth against glibc's `wcwidth()`).

| option | meaning |
|---|---|
| `--version V` | Unicode version, default `16.0.0` |
| `--ucd DIR` | the folder holding the five inputs |
| `--fetch DIR` | download them first (curl, else wget; HTTPS only) into DIR (created) |
| `--unit FILE` | the file whose block is replaced (default `kcl/fv.unicode/fv.unicode.sh`): exactly one `# BEGIN GENERATED` line and one `# END GENERATED` line after it |
| `--stdout` | print the block (markers included) instead |
| `--awk AWK` | the awk to run (default `$AWK`, else `awk`) |
| `--urls` | print the five URLs of the version and exit |

rc 0 done; 1 a failure (a missing or malformed input — a bad code point, a
data file without the lines it must have, **an input of another version than
`--version`** —, a failed download, no awk, no sha256 tool, a unit without the
markers); 2 a bad call. Messages go to stderr.

## Inputs (16.0.0)

| file | used for |
|---|---|
| `https://www.unicode.org/Public/16.0.0/ucd/EastAsianWidth.txt` | W and F → 2 (explicit lines only) |
| `https://www.unicode.org/Public/16.0.0/ucd/UnicodeData.txt` | Mn, Me → 0; the regional indicators (by name) |
| `https://www.unicode.org/Public/16.0.0/ucd/DerivedCoreProperties.txt` | Default_Ignorable_Code_Point → 0 |
| `https://www.unicode.org/Public/16.0.0/ucd/HangulSyllableType.txt` | V and T jamo → 0 |
| `https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-data.txt` | Extended_Pictographic, Emoji_Modifier (the cluster classes) |

The files are untrusted data: only awk reads them, every field is checked, and
nothing in them is ever executed. `--fetch` downloads over HTTPS only (curl
`--proto '=https' --proto-redir '=https'`, wget `--https-only`) into
`FILE.part` and renames it when complete; a failed download leaves no `.part`.

**Version check.** Each input must be of the version given: the first line of
`EastAsianWidth.txt`, `DerivedCoreProperties.txt` and `HangulSyllableType.txt`
must read `# NAME-V.txt` (`# EastAsianWidth-16.0.0.txt`), and `emoji-data.txt`
must have a version line for V's major.minor among its first 20 lines (16.0:
`# Used with Emoji Version 16.0 …`, 17.0: `# Version: 17.0`); otherwise rc 1.
`UnicodeData.txt` carries no version stamp at all (it holds data lines only),
so it cannot be checked — fetch all five together.

## The rules

Widths, first match wins (glibc's charmap header; the full table with
examples is in the [fv.unicode README](../../kcl/fv.unicode/README.md)):
U+00AD 1; U+115F 2; U+3248..324F 2; Hangul V/T 0; Mn, Me 0;
Default_Ignorable_Code_Point 0; East_Asian_Width W/F 2; else 1. An `@missing`
line that says W or F is reported on stderr and not applied, like the header's
prose defaults (glibc takes explicit lines only). So an unassigned code point
is 1, except the reserved ranges `EastAsianWidth.txt` lists explicitly as W
(Cn lines in the CJK blocks and planes 2 and 3: 2) and the unassigned
default-ignorables (U+2065, U+FFF0..FFF8, U+E0000..E0FFF: 0); glibc's
`wcwidth()` is −1 for all of them.

Classes: `z` width 0; `m` Emoji_Modifier; `r` regional indicator; `x` / `y`
Extended_Pictographic of width 1 / 2; `n` / `w` everything else of width 1 / 2.
All lower case and distinct in any case, on purpose: a caller's `nocasematch`
must never make one class letter match another.

The block: `__FV_UC_VERSION`; `__FV_UC_P`, 68 strings of 64 letters (a page of
256 code points per letter, `*` for a mixed page); `__FV_UC_M[page]`, the
letters of each mixed page run-length coded (`n169x1n86`). The layout and its
costs: [fv.unicode README, The table](../../kcl/fv.unicode/README.md#the-table).

## A new Unicode version

1. `bash tools/unicode/gen_width.sh --fetch /tmp/ucd-V --version V`.
2. `kcl/fv.unicode/fv.unicode.sh`'s comment and README name the version; the
   spot checks in `kcl/fv.unicode/tests/001_Table.sh` expect `16.0.0`.
3. `004_Glibc` compares only against a glibc whose width data has the same
   version (it SKIPs otherwise), so check which glibc has it first.

## Tests

`bash tools/unicode/tests/selftest.sh` (also run by `kcl/fv.unicode/tests/003`):
for every awk it finds (`SELFTEST_AWKS="gawk mawk"` to choose), the hand-made
inputs in `tests/fixtures/` give exactly `tests/expected_block.txt`, a second
run is byte-identical, the classes of 66 fixture code points read back from the
block are the ones written down in the script, and the page table is sound;
then `--urls`, `--unit` splicing (only the block changes; a second run says
`unchanged`) and the error paths (incl. inputs of another version). With `UNICODE_UCD=DIR` (the five real files)
the committed unit is regenerated into a copy and compared byte for byte. After
a fixture change, regenerate the golden file (the command is in the script's
header) and check the new classes against the list in the script.
