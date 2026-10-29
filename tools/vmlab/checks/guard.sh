#!/usr/bin/env bash
# checks/guard.sh -- kbool bash-version guard check (lab VMs; written for kb-debian, card L4.2).
# For every /opt/bash-*/bin/bash (sorted by version) and /usr/bin/bash, two probes:
#   kbool.sh            : source "$KBOOL_DIR/kbool.sh"
#   tstringlist.sh      : source "$KBOOL_DIR/kcl/tstringlist/tstringlist.sh"
# Each probe runs as `"$B" -c 'source "$1"' _ FILE >out 2>err; rc=$?` (rc is taken outside
# the probed bash, which may abort its -c script on a `bad substitution`).
#   upload:  vmlab.sh run VM -- sh -c 'cat > /tmp/guard.sh' < tools/vmlab/checks/guard.sh
#   run:     vmlab.sh run VM -- 'bash /tmp/guard.sh [KBOOL_DIR]'      (default ~/kbool)
# Output per probe: "<ver> <probe> rc=N <ok|UNEXPECTED>" then stderr, each line "  err: ...".
# Expectation: the floor is the first `^__KK_BASH_MIN=` line of KBOOL_DIR/kbool.sh; below it
#   rc=2 and stderr contains `kbool: bash >= `; at/above it rc=0 and empty stderr.
# rc: 0 all ok; 1 any UNEXPECTED; 2 usage.
export LC_ALL=C
if (( $# > 1 )); then echo "usage: guard.sh [KBOOL_DIR]" >&2; exit 2; fi
D=${1:-$HOME/kbool}
[[ -f $D/kbool.sh ]] || { echo "guard.sh: no $D/kbool.sh" >&2; exit 2; }
floor=$(sed -n 's/^__KK_BASH_MIN=\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' "$D/kbool.sh" | head -n 1)
[[ -n $floor ]] || { echo "guard.sh: no __KK_BASH_MIN in $D/kbool.sh" >&2; exit 2; }
echo "floor=$floor dir=$D"

t=$(mktemp -d) || { echo "guard.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$t"' EXIT

# bash list sorted by version
bashes=$(for b in /opt/bash-*/bin/bash; do
  [[ -x $b ]] || continue
  v=${b#/opt/bash-}; v=${v%%/*}
  printf '%s %s\n' "$v" "$b"
done | sort -t. -k1,1n -k2,2n -k3,3n | cut -d' ' -f2)
[[ -x /usr/bin/bash ]] && bashes="$bashes
/usr/bin/bash"

BAD=0
while IFS= read -r B; do
  [[ -n $B ]] || continue
  ver=$("$B" -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null)
  full=$("$B" -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null)
  below=0
  [[ $(printf '%s\n%s\n' "$ver" "$floor" | sort -t. -k1,1n -k2,2n | head -n 1) == "$ver" && $ver != "$floor" ]] && below=1
  for probe in kbool tstringlist; do
    case $probe in
      kbool) f=$D/kbool.sh ;;
      tstringlist) f=$D/kcl/tstringlist/tstringlist.sh ;;
    esac
    "$B" -c 'source "$1"' _ "$f" >"$t/out" 2>"$t/err"; rc=$?
    if (( below )); then
      if (( rc == 2 )) && grep -q 'kbool: bash >= ' "$t/err"; then v=ok; else v=UNEXPECTED; fi
    else
      if (( rc == 0 )) && [[ ! -s $t/err ]]; then v=ok; else v=UNEXPECTED; fi
    fi
    [[ $v == ok ]] || BAD=1
    printf '%s (%s) %s rc=%d %s\n' "$ver" "$full" "$probe" "$rc" "$v"
    [[ -s $t/out ]] && sed 's/^/  out: /' "$t/out"
    [[ -s $t/err ]] && sed 's/^/  err: /' "$t/err"
  done
done <<< "$bashes"
exit "$BAD"
