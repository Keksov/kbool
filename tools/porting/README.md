# tools/porting

## mdlinks.sh

A checker of relative links and heading anchors in the tracked `*.md` files of
the five repos (the root and `kcl kklass kkore ktests`). It only reports; it
never edits. Plain bash, no kbool, `LC_ALL=C`, no fork per file; the whole tree
takes a few seconds. Works under Git-bash 5.2 and MSYS2 5.3 with identical
output. It is the gate for moves of documentation.

```bash
bash tools/porting/mdlinks.sh [--root DIR] [--list] [PATH...]
```

- `--root DIR` — the tree root (default: two levels above the script). A
  repo `kcl kklass kkore ktests` is included when `DIR/NAME/.git` exists.
- `--list` — print every resolved link as `FILE:LINE: ok: TARGET` instead of
  the broken ones (same order, same summary and rc).
- `PATH` — root-relative `.md` files or directories (a directory means every
  tracked `.md` under it). Default: every tracked `.md` of the five repos.
  Target files are still looked up in the whole tree.
- Source files are `git ls-files` of each repo, kept when the name ends in
  `.md` and the file exists. Positional paths that do not exist, an unknown
  option or a `--root` that is not a directory print the usage and exit 2.

**Output.** One line per broken link on stdout:

```
FILE:LINE: broken: TARGET (no such file)
FILE:LINE: broken: TARGET (no such anchor)
```

`FILE` is root-relative (`kcl/...` for the submodules), `TARGET` the link
target as written (without `<>` and without the `"title"`). Order: repo order
`. kcl kklass kkore ktests`, then `git ls-files` order, then line. The summary
goes to stderr: `mdlinks: N file(s), M link(s), K broken`, where M counts
the links resolved against the tree (a path and its anchor are one link);
empty targets, absolute paths (`/a/b`) and anything with a scheme (`https:`,
`mailto:`, …) are skipped and not counted. A setext heading underline
(`===` / `---` under paragraph text) is not understood; each one found is
reported on stderr as `mdlinks: note: setext heading underline not handled at
FILE:LINE`.

**rc.** 0 — no broken link; 1 — at least one; 2 — usage error.

**What is checked.**

- A path target (relative to the directory of the file, `.`/`..` folded)
  exists when it is a tracked file, a directory that holds a tracked file, a
  submodule directory, or a file on disk that git does not list yet — the
  last only if its basename matches exactly (case-sensitively) an entry of its
  parent directory. A path above the root does not exist. A directory target
  needs no README.
- `#frag` alone checks the file itself; `file.md#frag` checks the target's
  headings; any other target accepts `#L12` or `#L12-L30` and rejects other
  fragments, except `.html`, `.htm`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`,
  `.pdf`, `.ico` (path only, fragment ignored). An empty fragment is accepted.
- Not parsed: reference definitions, HTML anchors and
  comments, percent-encoding (a fragment is compared byte for byte; an image
  link is checked like a link), multi-line
  code spans (code spans are tracked per line).
- Skipped for links and headings: fenced blocks (` ``` ` or `~~~`, up to 3
  spaces of indent, closed by the same character, at least as long, followed by
  nothing) and inline code spans; a link whose `[` is inside a code span is not
  a link, a code span inside the link text does not hide it.

**Slug rules** (GitHub-like, locale-independent). Headings are lines of 1–6
`#` after at most 3 spaces and at least one space, outside fences; the text
loses trailing spaces and a closing `#` run. ASCII: letters lower-cased,
digits `_` `-` kept, space becomes `-`, every other ASCII byte dropped (so
`*` and the backtick disappear and their content stays). A Cyrillic letter
(UTF-8 lead byte `D0`/`D1`) is kept and lower-cased; every other multi-byte
character (`—`, `·`, `§`, `→`, `⚠`, Greek, CJK, `µ`, `²`, …) is dropped. No
`--` collapsing and no trimming of `-`: `a — b` is `a--b`, `⚠ Two FPC quirks`
is `-two-fpc-quirks`. Equal slugs in one file: the first is bare, then `-1`,
`-2`, … The link fragment is compared byte for byte, no lower-casing.

**Test.**

```bash
TMPDIR=<scratch dir> bash tools/porting/tests/mdlinks/run.sh      # prints PASS n/n
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe tools/porting/tests/mdlinks/run.sh
```

The test builds a fixture git repo with a nested `kcl` repo in a temp dir and
does not touch the real tree.
