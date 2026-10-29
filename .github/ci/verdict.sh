#!/bin/sh
# .github/ci/verdict.sh OUT RC NAME -- the CI row's verdict (launch L5.1).
# The one place for the job-summary text and the exit-code mapping, for every
# platform (POSIX sh: it also runs on macOS, FreeBSD host, git-bash, msys2).
#
#   OUT   the gate's --out dir (OUT/progress.txt holds the gate's output)
#   RC    the exit code of the setup + gate (a row that could not run: 5)
#   NAME  the row's display name (summary heading)
#
# Mapping (DL11):
#   0                       green
#   3 (ENV), 4 (FLAKY)      ::warning:: and green -- ONLY when OUT/progress.txt
#                           holds a __GATE__ line (the gate really ran)
#   anything else           red, exit code RC: 1 FAIL/CRASH/STRAY/TIMEOUT cell,
#                           2 usage error, 5 platform setup failure (package
#                           install, user, missing bash, docker pull), 124
#                           timeout, and 3|4 WITHOUT a __GATE__ line (an ENV
#                           that is the whole setup, not a verdict)
set -u

out=${1:-}
rc=${2:-}
name=${3:-?}
prog=$out/progress.txt
sum=${GITHUB_STEP_SUMMARY:-/dev/null}

line=
[ -n "$out" ] && [ -f "$prog" ] && line=$(grep -h '^__GATE__' "$prog" 2>/dev/null | tail -1)

case $rc in
    '' | *[!0-9]*) verdict="red (exit code '$rc' is not a number)"; rc=1; mapped=1 ;;
    0) verdict=green; mapped=0 ;;
    3 | 4)
        if [ -n "$line" ]; then
            verdict="green with a warning (ENV/FLAKY do not fail CI, DL11)"; mapped=0
        else
            verdict="red (exit $rc without a __GATE__ line: the gate did not run to a verdict)"; mapped=$rc
        fi ;;
    *) verdict="red"; mapped=$rc ;;
esac

{
    echo "### gate ($name): exit $rc, $verdict"
    echo '```'
    if [ -f "$prog" ]; then
        grep -hE '^gate [0-9]|^ *\[FAIL\]|FLAKY|^__GATE__' "$prog" 2>/dev/null | tail -40
    else
        echo "no progress.txt in '$out'"
    fi
    echo '```'
} >> "$sum" 2>/dev/null

echo "gate ($name): exit $rc, $verdict; ${line:-no __GATE__ line}"

case $rc:$mapped in
    3:0 | 4:0) echo "::warning::gate ($name) verdict ${line:-exit $rc} (ENV/FLAKY do not fail CI, DL11)" ;;
    *:0) ;;
    *) echo "::error::gate ($name) is red: exit $rc, ${line:-no __GATE__ line}" ;;
esac
exit "$mapped"
