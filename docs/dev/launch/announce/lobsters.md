**Title:** kbool: Free Pascal-style classes, units and a class library for bash 5.1+

**URL:** https://github.com/Keksov/kbool

**Tags:** `show`, `unix`, `programming`

Tick "I am the author of the story at this URL".

Lobsters has no `shell` tag (checked on <https://lobste.rs/tags> on 2026-10-31). It does have
`vibecoding` ("Using AI/LLM, coding tools"). Whether to add it is the owner's call: the post is
about the toolkit, not about the AI workflow, but the project was developed with AI assistance, and
some readers filter that tag.

**Author comment:**

I wrote kbool for bash scripts that have grown past functions and globals but cannot move to
another language. It gives them units loaded by name, classes declared as `class … end` with the
method bodies as plain bash functions, and ports of FPC and Delphi classes (TStringList,
TDictionary, TIniFile, TRegEx …). It was developed with AI assistance: Claude sessions write the
code from task cards, and I make the design decisions and merge after review and a test gate. The
plans and decisions are public under docs/dev/.

The part I found most interesting is the portability layer: the test suite runs on 13 CI
configurations (bash 5.1 to 5.3, glibc and musl, macOS, FreeBSD, Windows), and docs/portability.md
lists every difference that broke something, such as mawk reading `nan == 0` as true, FreeBSD's
emulated `/dev/fd`, and `\b` spelled differently per C library, with the test that pins each fix.
docs/benchmarks.md has the costs, including when not to use it.
