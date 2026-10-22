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

## numbers.sh

Writes `docs/dev/launch/numbers.json`: the project figures the README and the
announcement quote (test totals of the last PASS gate, per-repo commits / heads
/ file and line counts, unit and example counts, the provisioned platforms, the
ledgers). Every figure is `{"value": …, "source": "<command or file>"}`.

**It is a snapshot.** Heads, commit counts, line counts and `dirty` go stale at
the next commit. Whoever quotes the file (the README section, the
announcement) reruns the script first.

```bash
bash tools/porting/numbers.sh [--gate OUT_DIR] [--out FILE]
```

- `--gate OUT_DIR`: the gate OUT to read the test figures from. Without it:
  the newest (by directory name) directory under `$TMPDIR/kt-gate/` (fallback
  `$(cygpath -u -F 28)/Temp/kt-gate/`, then `/tmp/kt-gate/`) whose
  `progress.txt` ends with a `__GATE__:PASS:` line and whose `summary.json`
  says `"verdict": "PASS"` for a gate of the whole tree (`.gate.argv` contains
  `all`; a partial gate such as `kkore -- -n 15` is skipped). An explicit
  `--gate` must satisfy the same checks.
- `--out FILE`: default `docs/dev/launch/numbers.json`.
- Needs `node` (exit 2 if missing). Exit 3 = BLOCKED: no PASS gate, or the gate
  data is not as expected (a `(bash_version, suite)` pair twice or missing in
  `cells.tsv`, a ledger that does not parse).
- Runs in Git-bash and in MSYS2 with identical output except
  `generated.timestamp`; about 10 s on Windows (many `git` calls).

Notes on the figures:

- `tests.runtimes.*.duration_ms` is the gate's own total of the cells'
  durations, not wall time (cells run in parallel) and not exactly the sum of
  the `duration_ms` column of `cells.tsv` (the source text gives both numbers).
- Root `tracked_files` counts the 4 submodule gitlinks and `.gitmodules`.
  Root `dirty` is true when a submodule has uncommitted changes.
- `sh_lines` / `md_lines` are `git ls-files -z … | xargs -0 cat | wc -l`, equal
  to the sum of the `total` lines of `xargs -0 wc -l` and safe for file names
  with spaces.
- A unit file is a tracked `*.sh` outside `tests/` and `examples/` whose first
  512 bytes contain a line beginning `kk.unit `. The five kkore system units
  are read from the `for __kk_m in kuse klib kerr kvar kcfg` line of
  `kbool.sh` (`kuse.sh` is the loader and has no `kk.unit` line).
- `platforms` is static: the lab VM versions come from `tools/vmlab/README.md`
  ("Versions recorded at creation"); the script warns on stderr if a version
  string is no longer in that file. The Windows host OS string is
  `baseline.os` of `docs/dev/launch_ledger.json`. Gate results are the
  ledger's, not this file's.
