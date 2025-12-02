#!/bin/bash
# Master test runner - finds and executes all tests.sh in kbool subdirectories
# Usage: ./tests.sh [OPTIONS]

set -o pipefail

# Get the kbool root directory
KBOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load test framework
source "$KBOOL_DIR/ktests/ktest.sh"

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

for script in "${test_scripts[@]}"; do
    echo ""
    kt_test_section "Running $script"
    
    echo $script
    if bash "$script" "$@"; then
        passed_scripts+=("$script")
    else
        failed_scripts+=("$script")
    fi
done

# Display final results
echo ""
echo "=========================================="
echo "Master Test Suite Results"
echo "=========================================="
echo "Passed: ${#passed_scripts[@]}"
echo "Failed: ${#failed_scripts[@]}"

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
