#!/usr/bin/env bash
# Test runner for the examples (notes.sh) using ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../ktests/ktests.sh" "$SCRIPT_DIR" "Examples Test Suite" "$@"
