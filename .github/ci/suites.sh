#!/bin/sh
# .github/ci/suites.sh -- the gate's SUITE words for a CI row (POSIX sh: every
# platform of ci.yml runs it). Reads GATE_SUITES (ci.yml: the manual run's
# `suites` input; push, pull_request and workflow_call leave it empty) and
# prints the words for gate.sh, one line: `all` when GATE_SUITES is empty or
# unset. Words are split on spaces and commas. Exit 2 (a message on stderr,
# nothing printed) on a word that is no plain suite id: letters, digits and
# `_ . / -` only, not starting with `-` (no gate.sh option slips in); gate.sh
# itself refuses an unknown suite before anything runs.
#
# A run whose words are not exactly `all` is a PARTIAL gate: verdict.sh says so
# in the job summary and as a warning. It is a quick intermediate check only,
# never the gate that closes a phase.
set -f
s=${GATE_SUITES:-}
IFS=' ,'
out=
for w in $s; do
    case $w in
        '') continue ;;
        -* | *[!A-Za-z0-9_./-]*)
            echo "suites.sh: '$w' is no suite id (letters, digits, _ . / - only; not starting with -)" >&2
            exit 2 ;;
    esac
    out="$out${out:+ }$w"
done
[ -n "$out" ] || out=all
printf '%s\n' "$out"
