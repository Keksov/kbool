# kbool — security notes

This project is a Bash OOP framework and class library. Its object model is a
**code generator**: class/method bodies are stored as strings and materialized via
`eval` and template substitution. That is by design (analogous to compilation).
The hardening below (see [`optimization_ledger.json`](docs/dev/optimization_ledger.json))
neutralizes paths where **untrusted input** could reach code execution, and
documents the by-design string-eval APIs that must only receive trusted input.

## Trust boundaries — pass only trusted (developer-authored) input

- **Class / method / property / instance names** (`defineClass`, `kk._build_class_runtime`,
  `.new`) are validated as bash identifiers before interpolation. Do not attempt
  to derive them from untrusted external data — validation will reject non-identifiers.
- **Method bodies / constructor bodies** are executed as code. They are the class
  author's own source; never build them from untrusted input.
- **`string.format` (tstringhelper)** takes a caller-supplied `printf` format
  (Pascal `Format` semantics). Do not pass an untrusted format string.
- **`kt_assert_success` / `kt_assert_failure` (ktests)** run their argument via
  `bash -c`. They are a test-author convenience; pass only trusted command strings.
- **The unit loader and the configuration** (`kbool.sh`, `kk.uses`, `kk.project`,
  config files, `KBOOL_HOME` / `KBOOL_CONFIG`): what is trusted and what is
  treated as data is in [kkore/README.md §5](kkore/README.md#5-security-notes).

## Hardening applied

- **Arithmetic-eval RCE fixed** — `string.toInteger` / `string.toInt64` validate
  input as a decimal integer before any `$(( ))`, so input like `a[$(cmd)]` can no
  longer execute `cmd`.
- **Identifier validation** in `kk._build_class_runtime` (class, parent, and every
  member name) closes the low-level class-builder as an injection vector.
- **`eval` removed from the method-dispatch cache** (`.call` / `.parent` use namerefs).
- **Property values round-trip verbatim** — the getter uses `printf`, not `echo -e`,
  so values with backslashes or a leading `-n` are not mangled.
- **Config keys validated** before `kc.alias` builds a `declare` nameref.
- **Test paths passed via environment**, not spliced into `bash -c`, in the ktests
  runner and fixtures (`printf %q`), so paths with quotes/spaces cannot break out.
- **Secure temp files** — `tfile` encrypt/decrypt uses `mktemp` (unpredictable name,
  atomic replace) instead of a predictable `.$$` name.
- **Class-build scratch file** — `kk._fn_text` (kklass round 5 / P14, the
  fork-free `declare -f` capture) creates one file per shell under `$TMPDIR`,
  named from `$SRANDOM` (not the seedable `$RANDOM`); a name where anything
  exists (`-e`/`-L`) is skipped and the new descriptor must be a regular file
  (noclobber refuses only an existing regular file). The file is deleted at
  once with `command /usr/bin/rm` (else `/bin/rm`, else the rm PATH hashes —
  a function cannot stand in for it); if the delete fails, that one file is
  reported and the fast path is off for the shell. Only two READ descriptors
  stay open (inherited by children); the write side is opened per capture or
  per `build` and every capture is framed by a random marker, so a process
  writing into the file cannot forge a capture (the marker must occur
  exactly twice); the file is created under `umask 077` (mode 0600 — the
  caller's umask is restored; on MSYS/Cygwin `noacl` mounts the ACL of
  `$TMPDIR` applies), so a child running as another user cannot write it;
  same-user children are trusted (they could edit the scripts); `-ef` before each capture
  keeps a caller's reopened descriptor numbers out of it. The state is an
  indexed array (arrays never come from the environment) bound to `$BASHPID`.
- **Legacy prototypes** that did not validate names and could override the hardened
  `defineClass` were moved to `kklass/experimental/` (never sourced in production)
  and deleted in kklass round 6 / P16 (they remain in the git history only).

## Reporting

These are internal libraries. If you find an input path that reaches code execution
from untrusted data and is not listed as a trust boundary above, treat it as a bug.
