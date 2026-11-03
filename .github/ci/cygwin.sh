#!/usr/bin/env bash
# .github/ci/cygwin.sh OUT -- run the kbool gate in Cygwin's own bash and tools
# (the windows `cygwin` row of ci.yml). Started with Cygwin's bash.exe from the
# Git-bash step, from the kbool root; OUT is the gate's --out dir (any
# spelling cygpath takes). Exit code: the gate's; 5 when Cygwin is not usable.
#
# Cygwin is NOT the MSYS2 runtime of the other two Windows rows: drives are at
# /cygdrive/c (not /c), its grep/sed/gawk keep the CR of a CRLF line, and its
# bash reports OSTYPE=cygwin like MSYS2's does (docs/portability.md). PATH holds
# Cygwin's /usr/bin and Windows' System32 only, so no Git-bash or MSYS2 tool
# leaks in (mixed runtimes break process control, L2.8-o1).
set -u

fail() { echo "cygwin.sh: $*" >&2; exit 5; }

[[ $OSTYPE == cygwin* ]] || fail "not a Cygwin bash: OSTYPE=$OSTYPE"
{ read -r v < /proc/version; } 2>/dev/null
[[ ${v:-} == CYGWIN_NT* ]] || fail "not the Cygwin runtime: /proc/version='${v:-}'"
[[ -n ${1:-} ]] || fail "usage: cygwin.sh OUT"

export PATH=/usr/local/bin:/usr/bin
sys=$(cygpath -u "${SYSTEMROOT:-C:\\Windows}") || fail "cygpath failed"
export PATH="$PATH:$sys/System32:$sys"
unset MSYSTEM TMPDIR
export KT_GATE_BASHES=/usr/bin/bash

out=$(cygpath -u "$1") || fail "cygpath $1 failed"
mkdir -p "$out" || fail "cannot create $out"

for t in bash git gawk sed grep find diff timeout nc; do
    command -v "$t" >/dev/null 2>&1 || fail "no $t in Cygwin"
done
echo "$v"
bash --version | sed -n 1p
for t in sed gawk grep nc; do
    printf '%-5s %s\n' "$t" "$(cygcheck -f "$(command -v "$t")" 2>/dev/null)"
done

bash ktests/tools/gate.sh --out "$out" --rerun-failed 1 --timeout 900 all
