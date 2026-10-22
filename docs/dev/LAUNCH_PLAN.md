# kbool public launch — portability, CI, packaging, release (2026-10-20)

**Status: PLANNED. Owner decisions DL1–DL4 taken (quiz 2026-10-20); DL5–DL9
are supervisor defaults the owner may override. Steps are split into tasks
with an executor each (§3); the Sonnet task cards are in
[LAUNCH_TASKS.md](LAUNCH_TASKS.md). No task started.**
Ledger: [`launch_ledger.json`](launch_ledger.json). This file and the ledger
move to `docs/dev/` in L6 (DL3).

**Precondition:** the ktests gate plan (GATE_PLAN.md, G4 + final critic — the
other session) is closed and committed: `ktests/tools/gate.sh` is the test
driver on Windows, inside every VM and in CI. The current uncommitted
README.md / ktests / `kcl/math/tests/018` changes belong to that work.

## 1. Why

The code is ready; the first five minutes of a stranger are not:

| finding (2026-10-20) | consequence |
|---|---|
| tested only on Windows (Git-bash 5.2.37, MSYS2 5.3.9) | most bash users are on Linux/macOS/BSD — "doesn't work on Ubuntu" is the first comment |
| 813 scripts start with `#!/bin/bash`, 1 with `#!/usr/bin/env bash` | FreeBSD has bash in `/usr/local/bin`; on macOS `/bin/bash` is 3.2 |
| every tracked file is mode `100644` (no exec bit), `core.fileMode=false` | `./examples/demo.sh` does not run on Linux |
| no `.gitattributes` (tree is LF, `core.autocrlf=false` here) | a Windows contributor with `autocrlf=true` gets CRLF scripts that break |
| 32 tracked files stored CRLF (found by L0.1): 26 × `kcl/tdirectory/tests/*.sh` start with `#!/bin/bash\r`, plus 2 LICENSE, ledgers, a doc | those tests cannot run on Linux; fixed in L0.1 |
| no bash version guard in `kbool.sh` | on an old bash: an obscure error instead of "bash ≥ X needed" |
| version features in use: 5.0 `EPOCHREALTIME` (22 files), 5.1 features (9 places), 5.2 only `patsub_replacement` (already handled) | 5.1 support (RHEL 9, Ubuntu 22.04) looks cheap — to be measured |
| `thttpserver` is built around GNU netcat 0.7.1 | GNU netcat is absent from Ubuntu, Debian, Fedora, Alpine (they ship OpenBSD nc / ncat / busybox nc); on them the suite fails instead of SKIPping |
| *(L0.5, [PORTING.md](PORTING.md))* the ktests harness reads cygwin-only `/proc/PID/{ppid,pgid,sid,winpid}` (H1) | on Linux the stray check is blind (`strays: none` proves nothing); FreeBSD/macOS have no `/proc` |
| *(L0.5)* `gate.sh` starts every segment with `env --default-signal` (H4, GNU coreutils ≥ 8.31) | no gate starts on Alpine-clean, FreeBSD, macOS |
| *(L0.5, confirmed on this machine)* `EPOCHREALTIME` has a **comma** under `ru_RU`/`de_DE` locales; `${EPOCHREALTIME/./}` then computes garbage (H7). L0.7 measured: the library units already used comma-safe forms; the 28 unsafe sites were the runner's group-stop KILL deadline (`ktest_runner.sh`, a hang path no test exercises) plus test/bench timings | fixed in L0.7; a regression test for the group-stop deadline under a comma locale goes to L2.1 |
| *(L0.5)* the 5.0 floor comes from the harness and a few kcl units; kkore and the kklass runtime need at most 4.4 statically | the library floor could sit below the harness floor (L4 measures) |
| no CI (`.github` absent in all five repos) | no public proof that it works |
| no LICENSE in kbool, kkore, ktests (kcl, kklass: MIT) | legally unusable |
| no tag / release in any repo | nothing to announce, no compatibility promise |
| GitHub descriptions stale (kkore: "File manger for KKlass framework"), no topics | first impression |
| README is a 424-line reference; first screen is `KBOOL_HOME` / header shapes | no pitch, no "why" |
| ~30 PLAN.md / `*_ledger.json`, REVIEW.md, OPTIMIZATION_PLAN.md in unit folders and roots | noise for a visitor |
| stale paths (`kklass/examples/README.md`: `cd lib/kklass`) | caught immediately |

## 2. Decisions

| id | decision | by |
|---|---|---|
| DL1 | VM matrix: **Ubuntu 24.04, Debian 13, Fedora (current), Alpine (current), FreeBSD** (current RELEASE; 15.x preferred). Exact versions fixed and recorded at L1. Newer/other releases (Ubuntu 26.04, FreeBSD 14.x) go to the CI matrix where they are cheap | owner 2026-10-20 |
| DL2 | minimum bash: **measure 5.1 first (L4), then decide** 5.1 vs 5.2 from the cost report | owner 2026-10-20 |
| DL3 | internal development files → **`docs/dev/`** of each repo, links updated | owner 2026-10-20 |
| DL4 | AI-assisted development is told **openly, as part of the story**: a README section + the announcement (process: plan → worker → review → gate; numbers) | owner 2026-10-20 |
| DL5 | **macOS only through GitHub Actions** (free macOS runners for public repos); FreeBSD in the lab catches most BSD-userland issues first. No Mac hardware, no rented cloud Mac | default |
| DL6 | **dedicated lab VMs** `kb-<os>` (NAT + SSH port forward, snapshot `clean`, every run starts from `clean`); the owner's existing VMs ("Ubuntu 24.02.2", "OLHCV", the `<inaccessible>` entry) are never touched | default |
| DL7 | **MIT** for kbool, kkore, ktests (same holder and text as kcl/kklass) | default |
| DL8 | lab tooling lives in **`kbool/tools/vmlab/`**, the portability scanner in **`kbool/tools/porting/`**; host side is plain bash under Git-bash + `VBoxManage.exe` + Windows OpenSSH | default |
| DL9 | **delegation**: well-specified technical tasks go to **Sonnet 5.5, effort high**; design, core-layer changes, triage judgment and public prose go to an Opus worker; every task is reviewed by the supervisor (§3) | owner 2026-10-20 |

| DL10 | the host runs VBS / Memory integrity, so VirtualBox fell back to the Hyper-V (NEM) backend and the Ubuntu installer hung in 2 of 5 runs (L1.2, 2026-10-20) → the owner **turns off Memory integrity and the Windows hypervisor** (`bcdedit /set hypervisorlaunchtype off`, reboot) so VirtualBox gets AMD-V. Rollback after the lab work: Memory integrity on + `bcdedit /set hypervisorlaunchtype auto` | owner 2026-10-20 |

Pending owner decisions (asked when the data is in): **OG1** GNU-tool policy
(L3), **OG2** minimum bash (L4), **OG3** pushing a CI branch (L5), **OG4**
GitHub description/topics text (L6), **OG5** version number (L8), **OG6** the
announcement texts and where/when to post (L8). The owner posts; nothing is
published or pushed by an agent.

## 3. Delegation model

| executor | who | gets |
|---|---|---|
| **S** | Sonnet 5.5, effort high — `Agent(model: "sonnet", effort: "high")` | a task whose inputs and write scope can be listed, whose every decision is already made in its card, and whose acceptance is a command with an expected result |
| **O** | Opus worker — `Agent(model: "opus")` | design; changes in the core layers (kkore, the kklass runtime, the ktests harness) even when small; triage that needs judgment; public-facing prose |
| **SV** | the supervisor session | finalizes a card before dispatch, reviews every report against the live tree, runs the closing gate, commits, asks the owner |
| **OW** | the owner | OG1–OG6, VM installs the scripts could not automate, pushes, posts |

Rules:

* **An S brief = [LAUNCH_TASKS.md](LAUNCH_TASKS.md) §0 (the common preamble)
  + the one task card**, pasted verbatim. Nothing else is needed; a card that
  needs more context is not ready for S.
* Cards marked **draft** (later phases) depend on earlier results; SV
  completes them (inputs, exact rules, acceptance) before dispatch. A card is
  ready when it has no "TBD", no "decide", no "as appropriate".
* An S task that meets a choice its card does not make **stops and reports
  BLOCKED** with the options; SV decides (or escalates to O / OW) and
  re-dispatches. S never "picks something reasonable".
* Fix work is split into **batches**: an O (or SV) triage turns findings into
  rows with a fixed fix rule; S applies a batch (card template L*.fix in
  LAUNCH_TASKS.md §L2).
* Same review rigor for S as for O: SV re-runs the acceptance commands itself;
  S reports must carry literal command output, not summaries.
* **One gate at a time on the machine**, and no Windows gate while a VM gate
  runs (shared CPU — timing tests). One lab VM running at a time by default.

**DL9a — delegation rules from experience (owner, 2026-10-22)**, after L0–L2.7:

1. **Opus as analyst and critic — always worth it.** Analysis tasks (PORTING,
   triage) and an independent read-only **critic after every O task that
   touches a core layer** (kkore, kklass runtime, ktests harness) or that is
   large (> ~300 changed lines). The critic is cheap relative to the task and
   found what the worker and the gate did not (L2.1: 12 findings; L2.7-C: the
   change met the tests but not the owner's intent). A small reviewed diff
   (e.g. L2.7-K, 85 lines) may skip the critic — the SV records why.
2. **Opus for large changes — but cut small.** An O task should be one
   subsystem × one concern, ideally ≤ ~300 changed lines, each with its own
   gate and commit. L2.1 (25 files, +940) showed that a regression in a big
   diff costs hours to find and every review round risks a new one.
3. **Sonnet can take more.** With a card that states goal, checks and stop
   rules, Sonnet High handled long multi-step work with uncertainty (the five
   lab VMs, console automation). Default new tasks to S when the card can be
   written; O only for design, judgment and the core layers.
4. **Card quality is the main lever.** Most returns (BLOCKED/PARTIAL/rework)
   came from gaps in the SV's cards, not from the executors. Before dispatching
   a non-trivial card, let a Sonnet pass "find ambiguities, unverifiable
   criteria and wrong assumptions in this card" and fix what it finds.
5. **Check a "uniform behaviour" decision against the owner's own motivating
   examples as real-tool tests** (L2.7-C round 1 passed every test and missed
   them).

## 4. Phases and tasks

`dep` = tasks that must be committed (or, for SV/OW items, done) first.

### L0 — inventory + repository basics (no VM)

| id | ex | task | dep |
|---|---|---|---|
| L0.1 | S | LICENSE (MIT) for kbool, kkore, ktests; `.gitattributes` (LF) in all five repos | — |
| L0.2 | S | portability scanner `tools/porting/scan.sh` + `docs/dev/launch/inventory.tsv` (fixed pattern list P01–P32) | — |
| L0.3 | S | external-tool table per unit `docs/dev/launch/tools.tsv` (static) | L0.2 |
| L0.4 | S | bash feature map by version `docs/dev/launch/bashfeatures.tsv` | L0.2 |
| L0.5 | O | `docs/dev/PORTING.md`: ranked hazards from L0.2–L0.4, the netcat question, OG1 options with data; final package lists for L1 provisioning | L0.2–L0.4 |
| L0.6 | SV | review + commit; finalize the L1 cards' package lists from L0.5; fold PORTING.md §9 into this plan | L0.5 |
| L0.7 | S | **comma-locale fix** (H7): every `EPOCHREALTIME` decimal-point split made locale-proof by fixed rewrite rules; Windows gate under `LC_ALL=ru_RU.UTF-8` | L0.6; runs in a gap with no lab VM running |

### L1 — the VM lab (`tools/vmlab/`)

| id | ex | task | dep |
|---|---|---|---|
| L1.1 | S | `vmlab.sh` core (status/up/down/reset/shell/run/sync/fetch/gate/snapshot) per the spec in the card + dry-run tests | L0.1 |
| L1.2 | S | create + provision **kb-ubuntu** (unattended install, 2 attempts max, else a manual checklist for the owner) | L1.1, L0.6 |
| L1.3 | S | create + provision **kb-debian**, **kb-fedora** (same recipe as L1.2) | L1.2 |
| L1.4 | S | create + provision **kb-freebsd**, **kb-alpine** (official image / console scripting, timeboxed; else manual checklist); snapshots `clean` (no GNU tools) and `clean-gnu` | L1.2 |
| L1.5 | OW | manual installs for whatever L1.2–L1.4 could not automate (checklists from S) | as needed |
| L1.6 | SV | acceptance: `vmlab.sh run` + `sync` + `fetch` on all five; `gate` attempted (its harness may not work on Linux yet — that is L2.1). **Until L2.1 lands, a VM's `strays: none` and STRAY-free cells are no evidence** (H1) | L1.2–L1.5 |

Provisioning content per OS = PORTING.md §7 (locales `en_US`/`de_DE`/`ru_RU.UTF-8`,
tzdata, perl, curl, openssl, the nc flavours for the L2.5 probes; FreeBSD:
`fdescfs` on `/dev/fd` in both snapshots, H14).

### L2 — Linux (Ubuntu, Debian, Fedora)

| id | ex | task | dep |
|---|---|---|---|
| L2.1 | O | the **test harness on Linux and FreeBSD** (PORTING.md §3): process table without cygwin `/proc` fields (H1), `env --default-signal` (H4), the harness one-liners H5–H8 (BSD `sed -i`, `s/\r$//` under BSD sed, …); Windows behaviour unchanged. L3.1 depends on H4 | L1.6 |
| L2.2 | S | shebangs → `#!/usr/bin/env bash`; exec bit for every tracked file starting with `#!`; **plus** the 3 header tests that assert `#!/bin/bash` (kcl/tests/001:67, kklass/tests/141:85, kkore/tests/013:46) and the shebang strings the kklass generators emit (kklass_compiler.sh:260, kklass_kkp.sh:336/346) — a literal-string substitution, so S despite DL9 | L0.6 |
| L2.3 | S | bash version guard at the top of `kbool.sh` (exact code in the card; floor 5.2 until OG2) | L2.2 |
| L2.4 | S | gate on kb-ubuntu, kb-debian, kb-fedora → `docs/dev/launch/L2_failures.tsv` (+ minimal repro per failure); plus one run on kb-debian under `LC_ALL=de_DE.UTF-8`; **no fixes** | L2.1–L2.3, L0.7 |
| L2.5 | O | triage of L2_failures: cause per row, fix rule per row, batches; thttpserver: detect + SKIP as the floor plus a second backend (OpenBSD nc if the probe passes, else socat — PORTING.md §4); until then its suite SKIPs on the Linux VMs | L2.4 |
| L2.6 | S | fix batches (card template L*.fix), one batch per dispatch; Windows 5.2 + 5.3 gate stays green | L2.5 |
| L2.7 | O | fixes the triage assigned to O (core layers, netcat) | L2.5 |
| L2.7-H | O | **inserted 2026-10-22 (owner: "the sooner the better")**: TSed literal-replace helpers — `quoteRe`, `quoteRepl`, `addReplace`, `TSed.replace`, `TSed.replaceInFile` per `kcl/tutil/HELPERS_PLAN.md` §2 (H1); kcl/tsed only, own gate; runs between L2.7-M and L2.7-N so L2.8's closing gate covers it on the VMs; critic after (storage change touches every TSed test). H2 of that plan (TGrep/TFind) is L6.0, after L5 | L2.7-C |
| L2.8 | SV | closing gate: Windows ×2 + three VMs; re-run `scan.sh`, diff vs L0 inventory, **and walk the PORTING.md §2.7 list of lexical misses by hand** (the scan cannot see them); commit | L2.6, L2.7 |

### L3 — non-GNU userland (Alpine/busybox, FreeBSD)

| id | ex | task | dep |
|---|---|---|---|
| L3.1 | S | gate on kb-alpine and kb-freebsd, each from `clean` AND `clean-gnu` → `L3_failures.tsv` + repros; no fixes | L2.8 |
| L3.2 | SV/OW | **OG1** with the L3.1 numbers (recommendation: core tool-free; wrapper units require the GNU tool, resolved by name `gsed`/`gawk`/`gfind`/`ggrep`/…, clear error naming the package; their tests SKIP with that reason) | L3.1 |
| L3.3 | O | the tool-resolution helper in kkore + its tests (per OG1) | L3.2 |
| L3.4 | S | move the wrapper units and their tests onto the helper (mechanical, list of call sites from `tools.tsv`) | L3.3 |
| L3.5 | O → S | triage of the remaining L3 rows → fix batches (as L2.5 → L2.6) | L3.1 |
| L3.6 | SV | closing gate: Windows ×2 + five VMs (Alpine/FreeBSD: both snapshots); commit | L3.4, L3.5 |

### L4 — bash 5.1 measurement

| id | ex | task | dep |
|---|---|---|---|
| L4.1 | S | build bash 5.1.16, 5.0.18, 4.4.23, 3.2.57 from GNU tarballs (signature checked) in kb-debian under `/opt/bash-X`; snapshot `clean-bashes` | L2.8 |
| L4.2 | S | gate on 5.1.16 → `L4_failures.tsv`, each row mapped to a `bashfeatures.tsv` feature; the kkore + kklass suites also on 5.0.18 and 4.4.23 (can the library floor sit below the harness floor?); guard check script `tools/vmlab/checks/guard.sh` run on 3.2/4.4/5.0/5.1 | L4.1, L2.3 |
| L4.3 | O | cost report (fix size, speed impact, risk) + recommendation | L4.2 |
| L4.4 | OW | **OG2** | L4.3 |
| L4.5 | O → S | if 5.1: fixes (O for core, S batches) + 5.1 joins the gate permanently; guard floor set | L4.4 |

### L5 — CI (GitHub Actions, kbool repo, submodules recursive)

| id | ex | task | dep |
|---|---|---|---|
| L5.1 | S | `.github/workflows/ci.yml` per the matrix in the card (Linux containers, macOS, FreeBSD VM action, Windows Git-bash + MSYS2); YAML validated locally | L3.6 |
| L5.2 | OW | **OG3**: allow pushing branch `launch-ci` (and later merging) | L5.1 |
| L5.3 | S | CI round-trips: read failed jobs (`gh run view --log-failed`), write `L5_failures.tsv`; no fixes | L5.2 |
| L5.4 | O → S | macOS / CI-only triage → fix batches; repeat L5.3 until green | L5.3 |
| L5.5 | SV | badge; owner merges | L5.4 |

### L6 — repository hygiene + documentation

| id | ex | task | dep |
|---|---|---|---|
| L6.0 | S | `kcl/tutil/HELPERS_PLAN.md` §3 (H2): TGrep `quiet` var + `TGrep.contains` + `TGrep.countMatching`, `TFind.quoteGlob`; cards from the L2.7-H pattern; after L5 so the CI matrix exists | L2.7-H, L5.5 |
| L6.1 | S | markdown link checker `tools/porting/mdlinks.sh` (relative links + `#anchors`, all five repos) + its tests | L0.1 |
| L6.2 | S | DL3: `git mv` internal files to `docs/dev/` per the file list in the card; fix every link; `mdlinks.sh` clean | L6.1 |
| L6.3 | S | move the current README reference text to `docs/reference.md` verbatim; anchors fixed; doctest still passes | L6.2 |
| L6.4 | S | collect project numbers → `docs/dev/launch/numbers.json` (tests per runtime from the last gate summary, commits per repo, rounds and findings closed from the ledgers, units, examples) | L5.5 |
| L6.5 | O | README front door (pitch, Pascal DSL first snippet, why, install, platforms from CI, requirements from tools.tsv), comparison with existing projects, "How it was built" (DL4, numbers from L6.4). Messaging point (owner, 2026-10-21): **one API across bash versions and platforms** — claim it only as far as the CI matrix proves it; name what still depends on GNU tools (per OG1) | L6.3, L6.4 |
| L6.6 | S | stale-path / small-fix list from the card (examples README etc.); submodule READMEs point to the kbool front door | L6.2 |
| L6.7 | S | CHANGELOG drafts per repo from `git log` (grouped by round/phase) | L6.2 |
| L6.8 | O | fresh-reader critic of README + docs (no repo context) | L6.5–L6.7 |
| L6.9 | SV/OW | **OG4** repo descriptions + topics; owner applies (or S runs the approved `gh repo edit` lines on the owner's go) | L6.5 |

### L7 — showcase

| id | ex | task | dep |
|---|---|---|---|
| L7.1 | SV | demo spec (endpoints, config, data, the curl session) — completes card L7.2 | L6.5 |
| L7.2 | S | the demo in `examples/` + its test in the gate | L7.1 |
| L7.3 | S | terminal recording in kb-ubuntu (asciinema → cast, agg → GIF) by the script in the card | L7.2 |
| L7.4 | S | benchmark runs in kb-ubuntu (existing `kklass/bench`, unit `bench.sh` files) → `numbers.json` section | L5.5 |
| L7.5 | O | benchmarks page (methodology + numbers) | L7.4 |

### L8 — release + launch

| id | ex | task | dep |
|---|---|---|---|
| L8.1 | S | **literal fresh install**: kb-ubuntu and kb-freebsd from `clean`, `sync --from-github`, follow the README word by word; every friction point recorded; no fixes | L6.8, owner push |
| L8.2 | O → S | fixes from L8.1 | L8.1 |
| L8.3 | OW | **OG5** version | L8.2 |
| L8.4 | S | coordinated tags + GitHub Releases in all five repos — prepares the exact commands and notes; runs them only on the owner's go | L8.3 |
| L8.5 | O | announcement drafts: Habr (ru), Lazarus/FPC forum + Delphi-PRAXiS (soft launch, ~1 week of feedback), Show HN, r/bash, r/commandline, lobste.rs; prepared answers ("why not Python", speed, AI-assisted development) | L8.2 |
| L8.6 | OW | **OG6**, posts | L8.5 |

## 5. Order and risk

L0 → L1 → L2 → L3 → L4 → L5 → L6 → L7 → L8; inside a phase the `dep`
column rules. L6.1–L6.3 may run beside L2–L4 (no gate contention: docs only,
but their commit waits for a free gate). Main risks: VM automation for
Alpine/FreeBSD (fallback: owner checklist, L1.5); the ktests harness on
Linux (L2.1, before any triage); thttpserver's GNU-netcat dependency (L2.5);
timing tests in VMs (the gate's ENV/FLAKY classes); FreeBSD CI speed (smoke
subset); macOS-only issues found only by CI round-trips (L3 reduces them).
