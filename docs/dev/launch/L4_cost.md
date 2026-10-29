# L4.3 — what would bash 5.1 support cost?

Date 2026-10-29. Investigation only: the host tree is unchanged except this
file. All runs in kb-debian, snapshot `clean-bashes` (`/opt/bash-5.1.16/bin/bash`,
system `/usr/bin/bash` 5.2.37), on the synced VM copy `~/kbool` with the floor
lowered there (`sed -i 's/^__KK_BASH_MIN=5\.2$/__KK_BASH_MIN=5.1/' ~/kbool/kbool.sh`,
`grep` gave `56:__KK_BASH_MIN=5.1`). Host tree at kbool `6719809`. Input:
[`L4_runs.md`](L4_runs.md), [`L4_failures.tsv`](L4_failures.tsv) (L4.2: 14 files fail
on 5.1.16). Probe scripts and their raw output: the card's scratch folder
(`…/scratchpad/launch/L4.3/probes/`, `…/L4.3/proto/` = the prototype diff), not in
the tree.

**Result in one line:** the 14 files come from **three** bash-5.1 differences, not
four or five; all three have small fixes (10 changed lines of library/harness code
plus test changes of +15/−3 lines), and with them every affected suite passes on 5.1.16 and stays
identical on 5.2.37. One L4.2 failure (ktests 051) did not reproduce here (it passed
twice on 5.1.16, once inside the whole ktests suite); its L4.2 cause stays unexplained.

## 1. Root causes

### Baseline in this card (before any change, 5.1.16 and 5.2.37, one gate each)

`KT_GATE_BASHES="/opt/bash-5.1.16/bin/bash;/usr/bin/bash" bash ktests/tools/gate.sh --out ~/g_before_N --timeout 600 SUITE [-- -n SEL]`:

| suite (selection) | 5.1.16 | 5.2.37 |
|---|---|---|
| `kcl -- -n 202` | FAIL 7/8 (202_math) | PASS 8/8 |
| `kcl/thttpserver` | FAIL 418/536 (all 10 files) | PASS 536/536 |
| `kklass -- -n 147` | FAIL 24/26 (C1, C2) | PASS 26/26 |
| `ktests -- -n 51,53` | FAIL 33/35 (053 only: 2 fails) | PASS 35/35 |

**051_GateVerdicts passed on 5.1.16 here** (it ran alone with 053, not under the whole
ktests suite as in L4.2). See (d).

### (a) kcl/thttpserver ×10 — `declare -f` prints `>&"$fd"` as `&> "$fd"`: confirmed

Bash 5.1's function printer (used by `declare -f`, `typeset -f`, **and by `export -f` /
`set -a`**, which put the same text into the environment) prints a redirection
`>&WORD` whose WORD is quoted as `&> WORD`. `&>` means "stdout **and stderr** to the
FILE named WORD", so after the round trip the command writes into a file called `3`
(or `10`, …) in the current directory instead of to descriptor 3. 5.2 prints it
unchanged.

Minimal repro (`probes/minimal.sh`, export path):

```bash
exec 3>fd3; g() { printf x >&"$fd"; }; fd=3; export -f g; export fd; bash -c g; exec 3>&-
```

| | fd 3 got | a file named `3` |
|---|---|---|
| 5.1.16, `>&"$fd"` | `[]` | `[x]` |
| 5.1.16, `>&$fd` (unquoted) | `[x]` | none |
| 5.2.37, both forms | `[x]` | none |

Which shapes are affected (`probes/deparse.sh`: `declare -f` of 22 shapes on both
bashes; only the lines that differ in meaning are marked):

| source | 5.1.16 prints | 5.2.37 prints | meaning changed on 5.1 |
|---|---|---|---|
| `>&"$fd"` | `&> "$fd"` | `>&"$fd"` | **yes** |
| `1>&"$fd"` | `&> "$fd"` | `>&"$fd"` | **yes** |
| `>& "$fd"` | `&> "$fd"` | `>&"$fd"` | **yes** |
| `>&"${fd}"` | `&> "${fd}"` | `>&"${fd}"` | **yes** |
| `>&"$f"x` | `&> "$f"x` | `>&"$f"x` | **yes** |
| `{ …; } >&"$fd"` | `} &> "$fd"` | `} >&"$fd"` | **yes** |
| `2>/dev/null >&"$fd"` / `>&"$fd" 2>/dev/null` | `… &> "$fd"` | unchanged | **yes** |
| `umask >&"$p"` | `umask &> "$p"` | unchanged | **yes** |
| `>&$fd` (unquoted) | `1>&$fd` | `>&$fd` | no (same meaning) |
| `<&"$fd"`, `0<&"$fd"` | `0<&"$fd"` | `<&"$fd"` | no |
| `2>&"$fd"`, `3>&"$fd"`, `exec 5>&"$fd"`, `exec {n}>&"$fd"`, `exec {n}>&-`, `>&2`, `2>&1`, `&>"$f"`, `&>>"$f"`, `>"$f" 2>&1` | identical on both | | no |

So the bad shape is exactly: **an output duplication onto descriptor 1 (implicit or
`1>&`) whose target word contains a quote.** Unquoted `>&$fd` and any other
descriptor number are safe.

**Code paths that print a function and read it back** (where this bites):

1. `build` (kklass_pascal): every member body is read with `kk._fn_text`
   (kklass/kklass_pascal.sh:186, loop :263-290) = `declare -f` (kklass/kklass.sh:870,
   fallback :899) and re-created through `implement`/`eval`. **Every Pascal-style class
   of every kcl unit** (29 unit files call `build`, 40 with benches and examples) goes
   through it at load time.
2. `kk.register_static_methods` (kklass/kklass.sh:2543-2545: `kk._fn_text` + `eval`).
3. The declaration sink snapshot (kklass/kklass_decl.sh:532 keeps the `declare -f`
   text, :595-596 `eval`s it back when the sink closes).
4. The compiled cache: `kklass_compiler.sh:318` writes `declare -f` of every class
   function into the `.ckk` file, which is later `source`d. A cache **compiled on
   5.1** carries the broken text and is read by any bash later (the cache format,
   `__KK_CKK_FORMAT`, does not record the bash version).
5. Any child that inherits functions through `export -f` or `set -a` (bash's own
   export, same printer): user scripts (exactly kcl 202_math, see (b)) and the
   ktests threaded workers (ktests/ktest_runner.sh:1306 exports 12 functions).

Plain `defineClass`/`implement` with a string body and plain functions are **not**
printed.

**Every hit in the five repos** (`git ls-files --recurse-submodules`, all `.sh`/`.kk`/
`.kkp`, 902 files; grep for `>&` followed by a quote or `$`, `1>&`, `<&`, `N>&`;
comment lines dropped). Tests and examples have **no** hit of the bad shape.

| file:line | code | reaches a round trip? |
|---|---|---|
| kcl/thttpserver/thttpmessage.sh:865 | `printf '%s' "$__ths_out" 2>/dev/null >&"$__ths_fd"` in `THttpResponse.SendContent` | **yes** — path 1 (`build THttpResponse`, :872): the 10 thttpserver failures |
| kcl/math/math.sh:877 | `printf 'pi\n' 2>/dev/null >&"$__MATH_FE_IN"` in `math._fe_spawn` | **yes** — path 5 (a `set -a` parent's child): 202_math |
| kcl/math/math.sh:1070 | `printf '%s\n' "$__m_req" 2>/dev/null >&"$__MATH_FE_IN"` in `math._fe` | **yes** — path 5, same |
| kklass/kklass.sh:870 | `{ …; declare -f -- "$1"; … } >&"$__kk_ft_w"` in `kk._fn_text` | only path 5 (a `set -a` script's child that calls an inherited kklass function): the capture lands in a file named after the fd, falls back to `$( )`, and leaves that file in the cwd. Not hit by any test |
| kklass/kklass.sh:999 | `umask >&"$__kk_ft_p"` in `kk._fn_text_open` | same as :870 |
| ktests/ktest_runner.sh:967 | `printf 'done\n' >&"$__kt_fd" 2>/dev/null` in `kt_runner_group_close` | no today (called directly, ktests.sh:203; not in the export list :1306) — would break if ever exported |
| kcl/thttpserver/bench.sh:261 | `printf 'GET …' >&"$c"` in `raw_get` | no (a plain function of the bench script, after both `build` lines) |
| kcl/tpipe/tpipe.sh:762, :764 | `… >&$__tpi_sf` inside a double-quoted trap string | no (a string, not a redirection, when printed; unquoted anyway) |

### (b) kcl `202_math.sh` — the same printer bug, through `set -a`

kcl/tests/202_math.sh:84-97: a parent runs `set -a; source math.sh; math.sin 1`, then
a child that only inherits the exported functions calls `math.sin 1`. On 5.1 the
inherited `math._fe_spawn` carries `printf 'pi\n' 2>/dev/null &> "$__MATH_FE_IN"`:
the engine probe goes into a file named after the descriptor, the probe read times
out, `math._fe_start` returns 1 → `rc=1 sin=`. A child that `source`s math.sh itself
gets fresh, correct definitions (`child: rc=0` in the same test line). Not a separate
cause: with the two math.sh lines unquoted, 202 passes on 5.1.16 (§2).

### (c) kklass `147_Round6.sh` C1, C2 — the EXIT trap after a `set -e` exit runs in the function's scope on 5.1

Not a kklass bug: a bash difference that the test pins to the 5.2 behaviour.
Minimal repro (`probes/minimal.sh`):

```bash
bash -c 'f() { local v=inside; false; }; trap '\''echo "trap sees v=[${v-unset}]"'\'' EXIT; set -e; f'
```

5.1.16: `trap sees v=[inside]`; 5.2.37: `trap sees v=[unset]`. In 5.2 a `set -e` exit
unwinds the function's locals before the EXIT trap; 5.1 runs the trap inside the
function's scope.

In kklass terms (`probes/c1.sh`: a method body that fails under `set -e`, and one that
calls `exit 3`; the EXIT handler prints what `kk.frameReset` tests):

```
5.1.16 sete: frames=1 props-nameref=yes y=[set]    FUNCNAME=[onexit kk._run_frame_body kk._invoke kk._exec a.boom main]
5.1.16 exit: frames=1 props-nameref=yes y=[byeval] FUNCNAME=[onexit kk._run_frame_body kk._invoke kk._exec a.bye main]
5.2.37 sete: frames=1 props-nameref=no  y=[unset]  FUNCNAME=[onexit kk._run_frame_body kk._invoke kk._exec a.boom main]
5.2.37 exit: frames=1 props-nameref=yes y=[byeval] FUNCNAME=[onexit kk._run_frame_body kk._invoke kk._exec a.bye main]
```

`kk.frameReset` (kklass/kklass.sh:1334-1343) returns at once when `[[ -R __kk_props ]]`
(:1336) — "the trap runs inside the body, the frame is live" — which is the
documented no-op for an explicit `exit` (kklass_book.md "EXIT Handlers and `set -e`";
147 C3). On 5.1 a `set -e` exit is that same case, so the frame stays (1),
`localvar_unset` stays on, a private method called from the handler is called from
inside class A (no warning), and an `unset` in the handler's helper hides instead of
revealing. Measured C1 on 5.1.16:
`trap rc=1 frames=1 lvu=on|reset rc=0|after frames=1/1/1 lvu=on|secret ran|unset reveals x=[UNSET]|again rc=0 frames=1 lvu=on|rc=1`.
The same two fails on 5.0.18 (L4.2) have the same cause.

(A plain one-level function behaves differently again: an explicit `exit` there runs
the trap outside the function on 5.1 and inside on 5.2 (`probes/exittrap.out`).
What counts for kklass is the method shape above: on 5.1 both a `set -e` exit and an
explicit `exit` leave the handler inside the body.)

### (d) ktests `053_GateReports.sh` — `[[ -v assoc["$key"] ]]` expands the key twice on 5.1; `051_GateVerdicts.sh` — not reproduced

**053.** Reproduced by hand (`probes/r053.sh`: 053's section D with 5.1.16 first on
PATH). The inner gate's first attempt is right (`total=3 passed=2 failed=1`); its
`--rerun-failed` attempt runs the runner with `-n 2` and the rerun log shows the file
**twice**: `Total tests: 2 / Passed: 0 / Failed: 2`, `[FAIL] 002_t<TAB>a"b.sh` twice
→ `FAIL 0/2`. `kt_runner_find_tests` (ktests/ktest_runner.sh:466-471) finds `002_*.sh`
under two of its padding patterns and removes duplicates with
`[[ ! -v seen["$f"] ]]` (:490). On 5.1 `-v` expands the subscript a second time, so a
key holding `"` is never found. Minimal repro (`probes/vkey.sh`):

| key | 5.1.16 `[[ -v s["$k"] ]]` | 5.1.16 `${s["$k"]+x}` | 5.2.37 both |
|---|---|---|---|
| `plain`, `a<TAB>b` | yes | yes | yes |
| `t"b`, `t\b`, `t]b`, `t$b`, `t'b`, `002_t<TAB>a"b.sh` | **no** | yes | yes |

The same double expansion hits `unset a["$k"]` (the word is expanded before `unset`
sees it, then again by `unset`; `probes/unsetkey.sh`): on 5.1.16 the keys `t"b t\b t]b
t$b t'b` are **kept**, and the key `@` or `*` **empties the whole array**
(`probes/edgekey.sh`: `delete old[rc=0 left=]`); `unset 'a[$k]'` (quoted, expanded by
`unset` only) is right on both. Further latent hits of this class in code (no test
uses such keys, so nothing fails today): kkore/kcfg.sh:30 `kc.exists`
(`[[ -v __KLIB_CONFIG["$key"] ]]`), kkore/kcfg.sh:36 `kc.delete` and kkore/kvar.sh:140
`kv.free` (`unset NAME["$key"]`). Every other `unset "a[$i]"` in code has a numeric
index (tlist, tstringlist, tcustomapplication, ktest_runner pids, suitejob) and is
safe.

**051.** In L4.2 (the whole gate, ktests cell with 8 workers, on 5.1.16) the inner
gate's `hang` cell line shows `TIMEOUT … 149.8s … (timeout 10s, group stopped)`: the
cell was still being stopped when `kt051_gate`'s own `timeout -k 10 150` (051:35)
ended the inner gate, which therefore never wrote `cells/003/result` → the
`No such file or directory` at 051:39. So the 149.8 s **is** the cause of the 051
failure, but what made the stop that slow is not known. Here 051 **passed on 5.1.16**
three times: alone with 053 (baseline), inside the whole ktests suite after the fixes,
and inside the whole gate after the fixes (§2). It is therefore not a deterministic
5.1 failure. Not isolated further (the cell does `read -t 25` on a pty,
gate_fixtures/hang/suite/001_hang.sh; whether a 5.1 `read` reacts to the stop signal
later under load is the first thing to look at). Estimate to isolate: one O card of
~2 h with repeated whole-suite runs on 5.1 and 5.2 (it may be a load flake that 5.2
can show too).

## 2. Fix per cause (prototyped in the VM copy)

Applied with `patch -p1` in `~/kbool` (the full diff = the hunks below).

**Cause A — the `>&"$fd"` printer bug (fixes (a) and (b)).** Drop the quotes: the
target is always a validated descriptor number (`kk.isInt` at thttpmessage.sh:688;
`exec {var}` results in kklass.sh; `MATH_FE[1]` or empty in math.sh; digits-only check
at ktest_runner.sh:966). 5.1 prints the unquoted form as `1>&$fd` (same meaning).
An empty or closed fd keeps the old result on both bashes (`probes/minimal.sh`:
`empty fd: unquoted rc=1 err=[] quoted rc=1 err=[]; closed fd 77: unquoted rc=1 quoted rc=1`),
which matters for math.sh:877, whose fd may be empty on purpose.

(hunks of math.sh, thttpmessage.sh, kklass.sh :870/:999, ktest_runner.sh :967, 008_Contract.sh in the diff below)

6 code lines: kcl 3 (unit: math, thttpserver), kklass 2 (core), ktests 1 (harness);
plus 2 test lines (008 pins the source text of SendContent; the first prototype run
without this test change failed 008 on **both** bashes with `writes=0` — the test,
not the code). Risk: none for the meaning (a digits-only word); the one thing it
touches is the style rule "quote every expansion" — a lint (ShellCheck SC2086) would
flag these lines, so each needs a comment saying why it is unquoted. A test should
pin it: a static check over the five repos that no `>&"…"`/`1>&"…"` remains in code
(the grep above as a test), because a new one is invisible on 5.2/5.3.

**Cause B — the EXIT trap scope after `set -e` (fixes (c)).** Test-only (kklass
core unchanged): 147 detects the bash behaviour with the minimal repro and expects the
"trap inside the body" outcome where bash gives it, which is the outcome the book
already documents for an explicit `exit`.

(hunks of 147_Round6.sh in the diff below)

0 code lines, test +13/−1 lines (kklass). Plus (not prototyped, docs) one sentence in
kklass/docs/kklass_book.md "EXIT Handlers and `set -e`": on bash 5.1 a `set -e` exit
in a body also runs the handler inside the body's scope (like an explicit `exit`), so
`kk.frameReset` is a no-op there and `localvar_unset` stays on in the handler. Risk:
none for code; the user-visible 5.1 difference (an `unset` in a handler's helper hides
rather than reveals) stays and is documented, not fixed — a library fix would need
`kk.frameReset` to tell "trap inside a live body" from "trap inside a dead body",
and the measured state does not show that on 5.1 (the handler sees the same FUNCNAME
chain and the body's locals for a `set -e` exit and for an explicit `exit`,
`probes/c1.out`). The test pins the 5.1
behaviour by detection, not by version number.

**Cause C — assoc subscript expanded twice by `-v` / `unset` on 5.1 (fixes (d) 053, and
the latent kkore hits).**

(hunks of ktest_runner.sh :490, kcfg.sh, kvar.sh in the diff below)

4 lines: ktests 1 (harness), kkore 3 (core). The `-n $key` / `-z $key` guards keep
5.2 identical for the empty key: there the new forms alone would print `bad array
subscript` (and `kc.delete ''` would return 1 instead of 0) — measured in
`probes/edgekey.out`; for every other key tried (`@ * plain t"b 'a b' 0`) old and new
give the same rc and the same remaining keys on 5.2.37. `kv.free` already refuses an
empty name (kvar.sh:136). Risk: low; the `@`/`*` key behaviour of `kc.delete` changes
on 5.1 only (from "empties the table" to "removes that key", as 5.2 does). A test
should pin it: kkore 003 with keys `t"b`, `a]b`, `@` for kc.set/exists/delete, and a
ktests runner test with a quote in a file name and `-n` (053 covers it through the
gate).

### The whole prototype diff

Against the host tree (`diff -ru`; applied with `patch -p1` in `~/kbool`); 38 changed lines in 8 files:

```diff
--- a/kcl/math/math.sh
+++ b/kcl/math/math.sh
@@ -874,7 +874,7 @@
     # `2>/dev/null` FIRST: redirections apply left to right, so a bad fd (the
     # co-process already disposed of, see above) made `>&fd 2>/dev/null` print
     # `Bad file descriptor` before stderr was redirected (launch L3.5-5)
-    if printf 'pi\n' 2>/dev/null >&"$__MATH_FE_IN"; then
+    if printf 'pi\n' 2>/dev/null >&$__MATH_FE_IN; then
         IFS= read -r -t "$__MATH_FE_TIMEOUT" -u "$__MATH_FE_OUT" __m_probe 2>/dev/null || __m_rc=$?
         if (( __m_rc == 0 )) && [[ -n $__m_probe ]]; then
             __MATH_FE_UP=1
@@ -1067,7 +1067,7 @@
         kk.debug "math: request of ${#__m_req} characters exceeds this awk's line buffer ($__MATH_FE_LINEMAX)"
         REPLY=""; return 1
     fi
-    printf '%s\n' "$__m_req" 2>/dev/null >&"$__MATH_FE_IN" || {
+    printf '%s\n' "$__m_req" 2>/dev/null >&$__MATH_FE_IN || {
         math._fe_drop; REPLY=""; return 1
     }
     # `read -t` costs ~410 us per call on BOTH bashes here (measured 5.2.37 and
--- a/kcl/thttpserver/tests/008_Contract.sh
+++ b/kcl/thttpserver/tests/008_Contract.sh
@@ -138,8 +138,8 @@
 
 kt_test_start "SendContent writes with ONE printf to the fd, stderr silenced before the fd redirection"
 b="$(sed -n '/^THttpResponse.SendContent()/,/^}/p' "$MSG")"
-nw=0; while IFS= read -r l; do [[ "$l" == *'>&"$__ths_fd"'* ]] && nw=$(( nw + 1 )); done <<< "$b"
-if [[ $nw -eq 1 && "$b" == *"printf '%s' \"\$__ths_out\" 2>/dev/null >&\"\$__ths_fd\""* ]]; then kt_test_pass "one write"; else kt_test_fail "writes=$nw"; fi
+nw=0; while IFS= read -r l; do [[ "$l" == *'>&$__ths_fd'* ]] && nw=$(( nw + 1 )); done <<< "$b"
+if [[ $nw -eq 1 && "$b" == *"printf '%s' \"\$__ths_out\" 2>/dev/null >&\$__ths_fd"* ]]; then kt_test_pass "one write"; else kt_test_fail "writes=$nw"; fi
 
 kt_test_start "scope: thttpserver.sh is a unit whose dependencies are \`kk.uses kklass_pascal || return\` and \`kk.uses thttpmessage thttprouter tstopwatch || return\`, with no \`source\` line (kklass/USES_PLAN.md U4 rule 3, amendment b); declares exactly the two transports + TNetcatTransport + TSocatTransport (L2.7-N2) + THttpServer; the application is in its own file"
 srcs="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$UNIT" || :)"
--- a/kcl/thttpserver/thttpmessage.sh
+++ b/kcl/thttpserver/thttpmessage.sh
@@ -862,7 +862,7 @@
         __ths_out+="$__ths_body"
     fi
     _contentSent=1
-    if ! printf '%s' "$__ths_out" 2>/dev/null >&"$__ths_fd"; then
+    if ! printf '%s' "$__ths_out" 2>/dev/null >&$__ths_fd; then
         kk.debug "Error: THttpResponse.SendContent: the write to fd $__ths_fd failed"
         return 1
     fi
--- a/kklass/kklass.sh
+++ b/kklass/kklass.sh
@@ -867,7 +867,7 @@
         # `|| :` — a redirection that cannot be opened must not end a set -e caller
         {
             if [[ -n $__kk_ft_w ]]; then
-                { printf '%s\n' "$__kk_ft_m"; declare -f -- "$1"; printf '%s\n' "$__kk_ft_m"; } >&"$__kk_ft_w"
+                { printf '%s\n' "$__kk_ft_m"; declare -f -- "$1"; printf '%s\n' "$__kk_ft_m"; } >&$__kk_ft_w
             else
                 { printf '%s\n' "$__kk_ft_m"; declare -f -- "$1"; printf '%s\n' "$__kk_ft_m"; } >>"${__kk_ft[8]}/$__kk_ft_r"
             fi && { IFS= read -r -N 16777216 -u "$__kk_ft_r" __kk_ft_t || :; }   # P17: -N (see above)
@@ -996,7 +996,7 @@
     { exec {__kk_ft_p}>"$__kk_ft_f.u"; } 2>/dev/null || { __kk_ft[4]=$(( __kk_ft[4] + 1 )); return 1; }
     if [[ -f ${__kk_ft[8]}/$__kk_ft_p ]]; then                   # a regular file: created now
         __kk_ft_pc=1
-        umask >&"$__kk_ft_p"
+        umask >&$__kk_ft_p
         { IFS= read -r __kk_ft_u <"$__kk_ft_f.u"; } 2>/dev/null || __kk_ft_u=""
     fi
     { exec {__kk_ft_p}>&-; } 2>/dev/null
--- a/kklass/tests/147_Round6.sh
+++ b/kklass/tests/147_Round6.sh
@@ -370,6 +370,10 @@
 # ===========================================================================
 # §C kk.frameReset (DR21)
 # ===========================================================================
+# bash 5.1 runs the EXIT trap of a `set -e` exit inside a function in that
+# function's scope (5.2+ unwinds it first; launch L4.3): there the body's frame
+# is live and kk.frameReset is the documented no-op, as for an explicit exit (C3)
+sete_scope=$("$BASH" -c 'f() { local v=in; false; }; trap '\''echo "${v-out}"'\'' EXIT; set -e; f')
 cat > "$TMPD/C1.sh" <<'EOF'
 source "$KBOOL_ROOT/kbool.sh"; kk.uses kklass
 declareClass A ""
@@ -407,6 +411,12 @@
 secret ran
 unset reveals x=[1]
 again rc=0 frames=0 lvu=off"
+[[ $sete_scope == in ]] && want="trap rc=1 frames=1 lvu=on
+reset rc=0
+after frames=1/1/1 lvu=on
+secret ran
+unset reveals x=[UNSET]
+again rc=0 frames=1 lvu=on"
 check "C1" "$want|rc=1" "$OUT|rc=$RC"
 
 cat > "$TMPD/C2.sh" <<'EOF'
@@ -422,7 +432,9 @@
 EOF
 kt_test_start "C2 the caller had localvar_unset ON before the call (kklass did not turn it on): kk.frameReset clears the frame but leaves the option on; a method call in the handler works"
 case_run C2
-check "C2" "after frames=0 lvu=on|show frames=1|end frames=0 lvu=on|rc=1" "${OUT//$'\n'/|}|rc=$RC"
+want="after frames=0 lvu=on|show frames=1|end frames=0 lvu=on"
+[[ $sete_scope == in ]] && want="after frames=1 lvu=on|show frames=2|end frames=1 lvu=on"
+check "C2" "$want|rc=1" "${OUT//$'\n'/|}|rc=$RC"
 
 cat > "$TMPD/C3.sh" <<'EOF'
 source "$KBOOL_ROOT/kbool.sh"; kk.uses kklass
--- a/kkore/kcfg.sh
+++ b/kkore/kcfg.sh
@@ -27,13 +27,13 @@
 # Check if config key exists
 kc.exists() {
     local key="$1"
-    [[ -v __KLIB_CONFIG["$key"] ]]
+    [[ -n $key && -n ${__KLIB_CONFIG[$key]+x} ]]
 }
 
 # Delete config value
 kc.delete() {
     local key="$1"
-    unset __KLIB_CONFIG["$key"]
+    [[ -z $key ]] || unset '__KLIB_CONFIG[$key]'
 }
 
 # Get all config keys
--- a/kkore/kvar.sh
+++ b/kkore/kvar.sh
@@ -137,5 +137,5 @@
         ke.reportError "variable name cannot be empty"
         return 1
     fi
-    unset __KLIB_VARS["$var_name"]
+    unset '__KLIB_VARS[$var_name]'
 }
--- a/ktests/ktest_runner.sh
+++ b/ktests/ktest_runner.sh
@@ -487,7 +487,7 @@
     declare -A seen
     for f in "${test_files[@]}"; do
         f=$(kt_runner_clean_filename "$f")
-        if [[ ! -v seen["$f"] ]]; then
+        if [[ -z ${seen["$f"]+x} ]]; then
             seen["$f"]=1
             cleaned+=("$f")
         fi
@@ -964,7 +964,7 @@
 kt_runner_group_close() {
     local __kt_fd="${1:-}"
     [[ -n "$__kt_fd" && "$__kt_fd" != *[!0-9]* ]] || return 0
-    printf 'done\n' >&"$__kt_fd" 2>/dev/null
+    printf 'done\n' >&$__kt_fd 2>/dev/null
     exec {__kt_fd}>&-
     return 0
 }
```

### Before / after (VM, `probes/runset.sh`, one gate per line, both bashes)

| suite | before 5.1.16 | before 5.2.37 | after 5.1.16 | after 5.2.37 |
|---|---|---|---|---|
| `kcl -- -n 202` | FAIL 7/8 | PASS 8/8 | PASS 8/8 | PASS 8/8 |
| `kcl/math` | (L4.2: PASS 199/199) | — | PASS 199/199 | PASS 199/199 |
| `kcl/thttpserver` | FAIL 418/536 | PASS 536/536 | FAIL 535/536 → PASS 536/536 | FAIL 535/536 → PASS 536/536 |
| `kklass` (all) | (L4.2: FAIL 855 counted, 2 fails) | — | PASS 855/855 | PASS 855/855 |
| `kkore` (all) | (L4.2: PASS 759/759) | — | PASS 759/759 | PASS 759/759 |
| `ktests` (all) | (L4.2: FAIL 659/664) | — | PASS 664/664 (1m46s) | PASS 664/664 (1m33s) |
| **`all`** (30 cells, `--rerun-failed 1`) | (L4.2 R1: FAIL 9412/9536, 4 cells) | — | **PASS 9536/9536, 30/30 cells, 5m57s** | **PASS 9536/9536, 30/30 cells, 5m14s** |

The thttpserver arrow: the first prototype run (without the 008 test change) failed
`[FAIL] writes=0 (008_Contract.sh)` on both bashes — 008 pins the source text of
`SendContent`; with the two test lines changed the suite passes (it is inside the
`all` run, which ran after that change: `5.1.16 kcl/thttpserver PASS 536 536`,
`5.2.37 kcl/thttpserver PASS 536 536` in `~/g_after_all/cells.tsv`). The `all` run's
machine line: `__GATE__:PASS:60:60:0:0:0:0:0:19072:19072` — no FLAKY, no rerun used;
ktests 051 passed inside it on 5.1.16. The 5.2.37 counts are the same as before the
change everywhere (identical totals, 0 fails).

## 3. Speed

**No hot path changes.** Method call and `.new` are untouched: Cause A changes the
quoting of one redirection in `kk._fn_text`/`kk._fn_text_open` (class **build** only,
once per member) and in two math engine calls and one HTTP write; Cause B changes
only a test; Cause C touches `kc.exists`/`kc.delete`/`kv.free` and the test runner's
file discovery — none of them is in a call path of kklass.

Measured anyway on 5.2.37 (VM, `probes/speed.sh`, min of 5 runs each, two rounds,
then a third copy of the patched tree to see the noise):

| tree | 1000 `kk._fn_text` captures (build path) | `kk.uses thttpserver` in a fresh child |
|---|---|---|
| before (`~/kbool_a`, patch reversed) | 239.5 / 231.0 / 213.7 / 219.0 ms | 448 / 444 ms |
| after (`~/kbool`) | 268.1 / 255.3 / 201.3 / 217.2 ms | 449 / 461 ms |
| after, second copy (`~/kbool_b`) | 230.8 / 217.9 ms | — |

The spread between two identical copies (201–231 ms) is as large as any before/after
difference, so there is no measurable change. The redirection itself, in isolation
(`probes/redirbench.sh`, 20000 `printf x >&FD` per run, three runs each): 5.2.37
quoted 11.1–11.3 µs, unquoted 10.6–10.8 µs per call; 5.1.16 quoted 12.7–13.1 µs,
unquoted 12.1–13.0 µs — the unquoted form is not slower.

## 4. Ongoing cost of keeping 5.1

* **Gate:** one more bash per gate run. The whole gate on 5.1.16 took **9m06s** in
  kb-debian (L4.2 R1: `tests 9412/9536  9m06s`). On the Windows host the two-runtime
  gate is ~28 min (GATE_FOR_AGENTS.md); there is no 5.1 on the Windows host, so 5.1
  would run in the lab VM or in CI only, not in the developer gate.
* **CI:** the image exists — `curl -s 'https://hub.docker.com/v2/repositories/library/bash/tags?name=5.1'`
  lists `5.1.16-alpine3.22` (last updated 2026-10-24), `5.1.16`, `5.1-alpine3.22`,
  `5.1` (34 tags). One more matrix row in `.github/workflows/ci.yml` beside
  `bash:5.2.37-alpine3.22`; it runs in parallel (one more job of the same length, no
  longer wall time).
* **The class of 5.1-only bugs to keep avoiding** (each is invisible on 5.2/5.3, so it
  needs a static check or a 5.1 run to be caught):
  1. `>&"WORD"` / `1>&"WORD"` in any function body (Cause A) — silently writes to a
     file; only bites after `declare -f`/`export -f`, i.e. in every kklass `build`
     member.
  2. `[[ -v a["$k"] ]]` and `unset a["$k"]` with keys that may hold `" \ ] $ '`, `@`,
     `*` (Cause C) — wrong answers, or the whole array emptied.
  3. EXIT-trap scope after `set -e` (Cause B) — a behaviour to document and test by
     detection.
  4. From 5.2's side, things kbool must keep not relying on: `patsub_replacement` is
     ON by default only in 5.2+ (kbool already writes replacements that are literal on
     both — tawk.sh:261, tsed.sh:318, thttpmessage.sh:72), and the 5.2 fixes above.
* **5.2 features kbool would have to keep not using** (bashfeatures.tsv; a grep of
  code shows none used now): F24 `${a[@]@k}` (key/value pairs of an assoc array in one
  word list — useful to copy or snapshot an instance's data array in one assignment,
  e.g. the kklass roadmap item "instance snapshot/restore across a subshell"); F25
  `patsub_replacement` (not useful — kbool avoids it on purpose); F26
  `varredir_close` (auto-close of `{fd}` redirections — would remove some `exec
  {fd}>&-` bookkeeping, a small help), `globskipdots`, `noexpand_translation` (no use).
  Only `@k` would be of real use; none is needed for the launch.

## 5. Who gains

Current distributions whose `/bin/bash` is 5.1 (package pages, fetched 2026-10-29):

| distribution | bash | source | end of support |
|---|---|---|---|
| Ubuntu 22.04 LTS (jammy) | `5.1-6ubuntu1.1` (updates/security) | https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedSources&source_name=bash&exact_match=true&status=Published&distro_series=https://api.launchpad.net/1.0/ubuntu/jammy (packages.ubuntu.com answered `Internal Server Error`) | standard support May 2027, ESM May 2032 (https://ubuntu.com/about/release-cycle) |
| Debian 11 (bullseye) | `5.1-2+deb11u1` | https://packages.debian.org/bullseye/bash | LTS `2024-08-15 - 2026-08-31` (https://wiki.debian.org/LTS) — **already ended** |
| RHEL 9 | `bash-5.1.8-9.el9` (via its rebuilds below) | — | Full support 2027-05-31, Maintenance 2032-05-31 (Red Hat life-cycle API: https://access.redhat.com/product-life-cycles/api/v1/products?name=Red%20Hat%20Enterprise%20Linux) |
| AlmaLinux 9 | `bash-5.1.8-9.el9.x86_64.rpm` | https://repo.almalinux.org/almalinux/9/BaseOS/x86_64/os/Packages/ | active 31 May 2027, security 31 May 2032 (https://wiki.almalinux.org/release-notes/) |
| Rocky Linux 9 | `bash-5.1.8-9.el9.x86_64.rpm` | https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/Packages/b/ | follows RHEL 9 (the Rocky version page returned 404; not verified) |

5.2 for contrast: Debian 12 `5.2.15-2`, Debian 13 `5.2.37-2`
(packages.debian.org/bookworm|trixie/bash), Ubuntu 24.04 `5.2.21-2ubuntu4` (Launchpad,
noble), RHEL 10 family `bash-5.2.26-6.el10` (Rocky 10 BaseOS) — every current major
release of these families ships 5.2.

So 5.1 support buys exactly the **previous** generation: Ubuntu 22.04 (standard
support to May 2027) and the RHEL 9 family (to 2032 in maintenance). Debian 11 is out
of support. macOS ships 3.2 (out of reach either way).

## 6. bash 5.0 and 4.4

Out of reach without redesign (from L4_runs.md, no new runs): kklass needs 5.1 by
design — a nameref bound to an array element read in `$(( ))` gives 0 on 5.0/4.4
(kklass.sh:1383; probe P1: `0 / [7] / 1` vs 5.1 `14 / [7] / 8`, 22 failing files),
`SRANDOM` (F23, 5.1; the `kk._fn_text` marker and the scratch file name rely on it),
`${!x@a}` on an array element name is empty before 5.1 (kuse.sh:1570-1571, P2), and
4.4 has no `localvar_unset` (kklass.sh:1451, printed on every method call) and no
`EPOCHREALTIME`/`EPOCHSECONDS` (the harness timers read empty; F18). 5.0.18 failed 24
kklass/kkore files, 4.4.23 39 (L4.2 R2/R3). Each of these is a core mechanism, not a
spot fix.

## 7. Recommendation (OG2)

**Recommendation: choose 5.1 as the floor**, on one condition: 5.1 stays in the
automatic checks for good (a CI row and the lab-VM gate), because its bugs cannot be
seen on 5.2 or 5.3.

The facts that decide it:

1. **The cost is small and known.** The 14 failing files come from three bash 5.1
   differences. Fixing them changes 10 lines of code (6 in kcl/kklass/ktests for the
   redirection, 4 in kkore/ktests for array keys) and a few test lines. With these
   changes every suite passes on 5.1.16 — 9536 of 9536 tests — and 5.2.37 gives exactly
   the same results as before. Nothing gets slower.
2. **Who gains is real but limited to the previous generation of Linux.** Ubuntu 22.04
   LTS (standard support until May 2027) and Red Hat Enterprise Linux 9 with its free
   rebuilds AlmaLinux 9 and Rocky Linux 9 (supported until 2032) ship bash 5.1. Debian
   11 is already out of support. Every current release of these families (Ubuntu
   24.04, Debian 12/13, RHEL 10) already has 5.2.
3. **The price that does not go away:** a fourth bash in the checks (one more parallel
   CI job — the `bash:5.1.16-alpine3.22` image exists — and ~6 min in the lab VM), plus
   two habits: never write `>&"$fd"` (write `>&$fd`), and never test or delete array
   keys with `[[ -v a["$k"] ]]` / `unset a["$k"]` (use `${a[$k]+x}` / `unset 'a[$k]'`).
   A static test catches both. One 5.2 feature (`${a[@]@k}`) stays unusable; we do
   not use it today.

**If 5.2 is chosen instead:** nothing has to be fixed now; the guard already says 5.2.
Causes A–C then need no fix (they cannot occur on 5.2/5.3, which the guard
enforces), and no 5.1 run is needed in the checks.

**What L4.5 would contain if 5.1 is chosen** (one card per line, in this order):

| card | kind | what | size |
|---|---|---|---|
| L4.5-1 | S | Cause A: the 6 unquoted redirections (math.sh:877, :1070; thttpmessage.sh:865; kklass.sh:870, :999; ktest_runner.sh:967), each with a one-line comment why; 008_Contract lines 141-142; a new static test that no `>&"…"` / `1>&"…"` exists in code | small (~1 h) |
| L4.5-2 | S | Cause C: ktest_runner.sh:490, kcfg.sh:30/:36, kvar.sh:140; kkore 003 cases with keys `t"b`, `a]b`, `@` for kc.set/exists/delete and kv.free | small (~1 h) |
| L4.5-3 | S | Cause B: 147 C1/C2 expectation by detection (the diff above); one sentence in kklass_book.md "EXIT Handlers and `set -e`" | small (~30 min) |
| L4.5-4 | O | 051 on 5.1 under load: repeated whole-suite runs on 5.1 and 5.2 in the lab VM; isolate why the `hang` cell's stop took 149.8 s in L4.2 | ~2 h |
| L4.5-5 | S | floor: `__KK_BASH_MIN=5.1` in kbool.sh, guard.sh expectations (5.1 loads, 5.0 refused), the requirement in README/PORTING, bashfeatures summary note | small |
| L4.5-6 | S | 5.1 in the standing checks: the `bash:5.1.16-alpine3.22` row (goes with L5.1) and the kb-debian `clean-bashes` 5.1 gate as a phase-gate step | small |

All S cards follow the prototype in §2; the gate of each: the touched suites on
5.1.16 and 5.2.37 in kb-debian plus the Windows gate (5.2/5.3) for regressions.

