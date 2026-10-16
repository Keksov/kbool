#!/bin/bash
# Master test runner - finds and executes all tests.sh in kbool subdirectories
# Usage: ./tests.sh [OPTIONS]
#
# Stray-process guard (ktests round 5, P3b): after EACH suite and once more at
# the end, every process of this sweep's SESSION that was started during the
# sweep and whose parent is gone (ktests/tools/strays.sh --session self
# --since START: the strict orphan rule; marker or not — a leaked `sleep`,
# `nc`, `awk` counts) is listed with the suite that was running when it
# started, stopped, and the sweep FAILS — a leak is a bug (2026-10-16: a killed
# run left a ktests tree and 8 storm workers running for ~5 h). One /proc scan
# per suite, no fork unless something is found. A test that runs a nested
# sweep narrows it with KT_STRAYS_MATCH=TEXT (only processes whose command
# line contains TEXT). A TERM/INT/HUP to the sweep stops the running suite,
# checks once more and exits 128+N (see _kt_master_signal).

set -o pipefail

# Get the kbool root directory
KBOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# the sweep's start: the stray guard only looks at processes started after it
__kt_sweep_start="$EPOCHREALTIME"

# Load test framework
source "$KBOOL_DIR/ktests/ktest.sh"
source "$KBOOL_DIR/ktests/tools/strays.sh"

# Parse command line arguments
kt_runner_parse_args "$@"

# Show test execution info
kt_test_section "Starting Master Test Suite"

# Find all tests.sh files using explicit directories
test_scripts=()

# Walk through directories level by level
process_dir() {
    local base_dir="$1"
    
    # Check if tests.sh exists in tests subdirectory of current dir
    # But skip the master tests directory itself
    if [[ -f "$base_dir/tests/tests.sh" && "$base_dir" != "$KBOOL_DIR" ]]; then
        test_scripts+=("$base_dir/tests/tests.sh")
    fi
    
    # Look for subdirectories (non-hidden)
    for entry in "$base_dir"/*; do
        if [[ -d "$entry" && ! "$(basename "$entry")" =~ ^\. ]]; then
            process_dir "$entry"
        fi
    done
}

process_dir "$KBOOL_DIR"

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

# --- stray-process guard ------------------------------------------------------
__kt_suite_names=() __kt_suite_t0=() __kt_stray_rows=()
declare -A __kt_stray_suites=()
__kt_stray_opts=( --session self )
[[ -n "${KT_STRAYS_MATCH:-}" ]] && __kt_stray_opts+=( --match "$KT_STRAYS_MATCH" )

# _kt_master_strays LABEL — rc 0: no orphan started during the sweep; rc 1:
# they were reported (each with the suite running when it started), stopped,
# and recorded for the final summary. A process found is looked at again 1 s
# later: one that was just ending (a run's group watchdog at work) is no leak.
_kt_master_strays() {
    local label="$1" p i s c
    kt_strays_scan "${__kt_stray_opts[@]}" "$__kt_sweep_start"
    (( RESULT == 0 )) && return 0
    _kt_strays_nap_open; _kt_strays_nap 1; _kt_strays_nap_close
    kt_strays_scan "${__kt_stray_opts[@]}" "$__kt_sweep_start"
    (( RESULT == 0 )) && return 0
    echo "[WARN] $RESULT stray process(es) found after $label:"
    for p in "${KT_STRAYS[@]}"; do
        s="(before the first suite)"
        for (( i = 0; i < ${#__kt_suite_t0[@]}; i++ )); do
            (( KT_STRAYS_START[$p] >= __kt_suite_t0[i] )) && s="${__kt_suite_names[i]}"
        done
        __kt_stray_suites["$s"]=1
        c="${KT_STRAYS_CMD[$p]//$'\n'/ }"; (( ${#c} > 100 )) && c="${c:0:97}..."
        printf '    pid %s ppid %s age %ss orphan=%s started during %s: %s\n' "$p" \
            "${KT_STRAYS_PPID[$p]}" "${KT_STRAYS_AGE[$p]}" "${KT_STRAYS_FLAG[$p]}" "$s" "$c"
        __kt_stray_rows+=( "pid $p (${KT_STRAYS_FLAG[$p]}) started during $s: $c" )
    done
    if kt_strays_stop "${__kt_stray_opts[@]}" "$__kt_sweep_start"; then
        echo "[WARN] stopped them, none left"
    else
        echo "[WARN] $RESULT could NOT be stopped:"
        kt_strays_print '    '
    fi
    return 1
}

# A TERM/INT/HUP to the sweep (P3b review round 2, F5) stops the running
# suite instead of orphaning it: each suite runs as a BACKGROUND job this
# shell waits on (a trap is deferred while a foreground child runs; `wait`
# returns at once), and the trap TERMs it — the suite wrappers `exec`
# ktests.sh, so the TERM lands on its trap, which stops its run group. Then
# the stray check runs once more and the sweep exits 128+N. The suite gets
# 15 s to end (ktests.sh needs <= ~6 s), then KILL.
# The job is started under `set -m` (P3b review round 2, N1): a `&` job of a
# shell WITHOUT job control starts with SIGINT/SIGQUIT IGNORED — and a signal
# ignored on entry cannot be trapped, so every suite, test file and unit saw
# INT as SIG_IGN (kcl/thttpserver 006 failed). With job control it keeps the
# default INT and leads a process group of its own: the TERM goes to the
# whole group; INT/HUP are forwarded as TERM; Ctrl-Z (TSTP) suspends the
# group with this shell (kt_runner_group_suspend) and resumes it on CONT.
# The suite ignores TTOU/TTIN (a background group on a `stty tostop` terminal
# would stop at its first write — ktests' own groups do the same). Its stdin
# is the sweep's, as before (with job control a `&` job keeps stdin).
__kt_suite_pid="" __kt_cur=""
_kt_master_signal() {
    local i
    trap '' TERM INT HUP
    echo ""
    echo "[WARN] the sweep was interrupted (exit $1) while running ${__kt_cur:-no suite}"
    if [[ -n "$__kt_suite_pid" ]]; then
        kill -TERM -- "-$__kt_suite_pid" 2>/dev/null || kill -TERM "$__kt_suite_pid" 2>/dev/null
        kill -CONT -- "-$__kt_suite_pid" 2>/dev/null || kill -CONT "$__kt_suite_pid" 2>/dev/null
        _kt_strays_nap_open
        for (( i = 0; i < 150; i++ )); do
            kill -0 "$__kt_suite_pid" 2>/dev/null || break
            _kt_strays_nap 0.1
        done
        _kt_strays_nap_close
        kill -KILL -- "-$__kt_suite_pid" 2>/dev/null || kill -KILL "$__kt_suite_pid" 2>/dev/null
        wait "$__kt_suite_pid" 2>/dev/null
    fi
    _kt_master_strays "the interrupted sweep (${__kt_cur:-no suite})"
    if (( ${#__kt_stray_rows[@]} > 0 )); then
        echo "[WARN] ${#__kt_stray_rows[@]} stray process(es) left by the sweep:"
        printf '  - %s\n' "${__kt_stray_rows[@]}"
    fi
    exit "$1"
}
trap '_kt_master_signal 143' TERM
trap '_kt_master_signal 130' INT
trap '_kt_master_signal 129' HUP
__kt_susp=0
trap '__kt_susp=1; kt_runner_group_suspend "$__kt_suite_pid"' TSTP

for script in "${test_scripts[@]}"; do
    echo ""
    kt_test_section "Running $script"

    echo $script
    _kt_strays_ms "$EPOCHREALTIME"
    __kt_suite_names+=( "$script" ); __kt_suite_t0+=( "$REPLY" )
    __kt_cur="$script"
    set -m
    ( trap '' TTOU TTIN; exec bash "$script" "$@" ) &
    __kt_suite_pid=$!
    set +m
    while :; do
        __kt_susp=0
        wait "$__kt_suite_pid"; __kt_suite_rc=$?
        (( __kt_susp )) || break
    done
    __kt_suite_pid=""
    if (( __kt_suite_rc == 0 )); then
        passed_scripts+=("$script")
    else
        failed_scripts+=("$script")
    fi
    _kt_master_strays "$script"
done
__kt_cur=""
_kt_master_strays "the last suite (final check)"

# a suite that left a stray fails, whatever its own verdict
if (( ${#__kt_stray_suites[@]} > 0 )); then
    __kt_keep=()
    for script in "${passed_scripts[@]}"; do
        if [[ -n "${__kt_stray_suites["$script"]+x}" ]]; then
            failed_scripts+=("$script (left stray processes)")
        else
            __kt_keep+=("$script")
        fi
    done
    passed_scripts=("${__kt_keep[@]}")
    for script in "${!__kt_stray_suites[@]}"; do
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

if (( ${#__kt_stray_rows[@]} > 0 )); then
    echo ""
    echo "[WARN] ${#__kt_stray_rows[@]} stray process(es) left by the sweep:"
    printf '  - %s\n' "${__kt_stray_rows[@]}"
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
