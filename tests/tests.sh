#!/usr/bin/env bash
# Master test runner - finds and executes all tests.sh in kbool subdirectories
# Usage: ./tests.sh [OPTIONS]
#
# The suite-job machinery (discovery, the job-control group per suite, the
# TERM/INT/HUP/TSTP handling, the stray check) lives in
# ktests/tools/suitejob.sh (gate G1, DG5), shared with ktests/tools/gate.sh;
# this file is discovery + loop + summary on top of it.
#
# Stray-process guard (ktests round 5, P3b): after EACH suite and once more at
# the end, every process of this sweep's SESSION that was started during the
# sweep and whose parent is gone (ktests/tools/strays.sh --session self
# --since START: the strict orphan rule; marker or not — a leaked `sleep`,
# `nc`, `awk` counts) is listed with the suite that was running when it
# started, stopped, and the sweep FAILS — a leak is a bug (2026-10-16: a killed
# run left a ktests tree and 8 storm workers running for ~5 h). One /proc scan
# per suite, no fork unless something is found (kt_suitejob_strays). A test
# that runs a nested sweep narrows it with KT_STRAYS_MATCH=TEXT (only
# processes whose command line contains TEXT). A TERM/INT/HUP to the sweep
# stops the running suite, checks once more and exits 128+N (see
# _kt_master_signal).

set -o pipefail

# Get the kbool root directory
KBOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# the sweep's start: the stray guard only looks at processes started after it
__kt_sweep_start="$EPOCHREALTIME"

# Load test framework
source "$KBOOL_DIR/ktests/ktest.sh"
source "$KBOOL_DIR/ktests/tools/strays.sh"
source "$KBOOL_DIR/ktests/tools/suitejob.sh"

# Parse command line arguments
kt_runner_parse_args "$@"

# Show test execution info
kt_test_section "Starting Master Test Suite"

# Find all tests.sh files: DIR/tests/tests.sh under the root, level by level
# (the root's own tests/ — this file — skipped, hidden dirs skipped)
kt_suitejob_discover "$KBOOL_DIR"
test_scripts=( "${KT_SUITEJOB_SUITES[@]}" )

# KT_MASTER_SUITES=TEXT: run only the suites whose path contains TEXT (a sweep
# of one or a few suites through the master's own machinery: job control,
# signal handling, the stray guard)
if [[ -n "${KT_MASTER_SUITES:-}" ]]; then
    __kt_sel=()
    for script in "${test_scripts[@]}"; do
        [[ "$script" == *"$KT_MASTER_SUITES"* ]] && __kt_sel+=("$script")
    done
    test_scripts=("${__kt_sel[@]}")
fi

if [[ ${#test_scripts[@]} -eq 0 ]]; then
    kt_test_error "No test scripts found in $KBOOL_DIR"
    exit 1
fi

# Show test scripts to be executed in info mode
if [[ "$VERBOSITY" == "info" ]]; then
    echo "Found ${#test_scripts[@]} test script(s):"
    for script in "${test_scripts[@]}"; do
        echo "  - $script"
    done
    echo ""
fi

# Execute all test scripts
failed_scripts=()
passed_scripts=()

# --- stray-process guard: the sweep's window and the optional narrowing -------
kt_suitejob_init "$__kt_sweep_start" "${KT_STRAYS_MATCH:-}"

# A TERM/INT/HUP to the sweep (P3b review round 2, F5) stops the running
# suite instead of orphaning it: each suite runs as a BACKGROUND job this
# shell waits on (kt_suitejob_run: a trap is deferred while a foreground child
# runs; `wait` returns at once), and the trap stops it (kt_suitejob_signal:
# TERM to its group — the suite wrappers `exec` ktests.sh, so the TERM lands
# on its trap, which stops its run group — 15 s grace, then KILL). Then the
# stray check runs once more and the sweep exits 128+N.
# The job is started under `set -m` (P3b review round 2, N1): a `&` job of a
# shell WITHOUT job control starts with SIGINT/SIGQUIT IGNORED — and a signal
# ignored on entry cannot be trapped, so every suite, test file and unit saw
# INT as SIG_IGN (kcl/thttpserver 006 failed). With job control it keeps the
# default INT and leads a process group of its own: the TERM goes to the
# whole group; INT/HUP are forwarded as TERM; Ctrl-Z (TSTP) suspends the
# group with this shell (kt_suitejob_tstp) and resumes it on CONT.
# The suite ignores TTOU/TTIN (a background group on a `stty tostop` terminal
# would stop at its first write — ktests' own groups do the same). Its stdin
# is the sweep's, as before (with job control a `&` job keeps stdin).
_kt_master_signal() {
    trap '' TERM INT HUP
    echo ""
    echo "[WARN] the sweep was interrupted (exit $1) while running ${KT_SUITEJOB_CUR:-no suite}"
    kt_suitejob_signal "$1"
    kt_suitejob_strays "the interrupted sweep (${KT_SUITEJOB_CUR:-no suite})"
    if (( ${#KT_SUITEJOB_STRAY_ROWS[@]} > 0 )); then
        echo "[WARN] ${#KT_SUITEJOB_STRAY_ROWS[@]} stray process(es) left by the sweep:"
        printf '  - %s\n' "${KT_SUITEJOB_STRAY_ROWS[@]}"
    fi
    exit "$1"
}
trap '_kt_master_signal 143' TERM
trap '_kt_master_signal 130' INT
trap '_kt_master_signal 129' HUP
trap 'kt_suitejob_tstp' TSTP

for script in "${test_scripts[@]}"; do
    echo ""
    kt_test_section "Running $script"

    echo $script
    kt_suitejob_run "$script" "$BASH" "$script" "$@"   # the running bash, not the first one on PATH (PORTING H8)
    if (( KT_SUITEJOB_RC == 0 )); then
        passed_scripts+=("$script")
    else
        failed_scripts+=("$script")
    fi
    kt_suitejob_strays "$script"
done
KT_SUITEJOB_CUR=""
kt_suitejob_strays "the last suite (final check)"

# a suite that left a stray fails, whatever its own verdict
if (( ${#KT_SUITEJOB_STRAY_LABELS[@]} > 0 )); then
    __kt_keep=()
    for script in "${passed_scripts[@]}"; do
        if [[ -n "${KT_SUITEJOB_STRAY_LABELS["$script"]+x}" ]]; then
            failed_scripts+=("$script (left stray processes)")
        else
            __kt_keep+=("$script")
        fi
    done
    passed_scripts=("${__kt_keep[@]}")
    for script in "${!KT_SUITEJOB_STRAY_LABELS[@]}"; do
        [[ " ${test_scripts[*]} " == *" $script "* ]] || failed_scripts+=("$script (stray processes)")
    done
fi

# Display final results
echo ""
echo "=========================================="
echo "Master Test Suite Results"
echo "=========================================="
echo "Passed: ${#passed_scripts[@]}"
echo "Failed: ${#failed_scripts[@]}"

if (( ${#KT_SUITEJOB_STRAY_ROWS[@]} > 0 )); then
    echo ""
    echo "[WARN] ${#KT_SUITEJOB_STRAY_ROWS[@]} stray process(es) left by the sweep:"
    printf '  - %s\n' "${KT_SUITEJOB_STRAY_ROWS[@]}"
fi

if [[ ${#failed_scripts[@]} -gt 0 ]]; then
    echo ""
    echo "Failed test scripts:"
    for script in "${failed_scripts[@]}"; do
        echo "  - $script"
    done
    echo ""
    exit 1
else
    echo ""
    echo "All test suites passed."
    exit 0
fi
