# docs/dev — development history

Plans, ledgers, reviews and coverage notes: how kbool was built, kept as
history. None of it is needed to use the toolkit; the user documentation lives
in the READMEs and the `docs/` of each unit.

Each repo keeps its own history under its own `docs/dev/`:

| repo | what is under `docs/dev/` |
|---|---|
| `kcl/` | `PLAN.md`, `REVIEW.md`, `kcl_ledger.json`; per unit `<unit>/PLAN.md`, `<unit>/<unit>_ledger.json`, `<unit>/TEST_COVERAGE_NOTES.md`; `review-2026-09-06/` (the review reports and their repro scripts) |
| `kklass/` | `PLAN.md`, `USES_PLAN.md`, `OPTIMIZATION.md`, `kklass_ledger.json`, `uses_ledger.json` |
| `ktests/` | `PLAN.md`, `GATE_PLAN.md`, `ktests_ledger.json`, `gate_ledger.json` |

The rule: `<repo>/<dir>/<file>` lives at `<repo>/docs/dev/<dir>/<file>`.

In this repo (the root):

- [PORTING.md](PORTING.md) — the portability analysis (other platforms).
- [launch/](launch/) — the analysis behind the public launch (inventories,
  triage tables, probes).

These files are a record, not a promise: paths and numbers in them are as of
the day they were written.
