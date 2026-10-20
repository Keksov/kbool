#!/usr/bin/env bash
# Tests of tools/vmlab/vmlab.sh. Everything runs under VMLAB_DRY=1: no
# VirtualBox, no ssh, no VM. Prints `PASS n/n` (rc 0) or the failures (rc 1).
# Run with either bash:  bash tools/vmlab/tests/run.sh

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
V=$HERE/../vmlab.sh

T=$(mktemp -d "${TMPDIR:-/tmp}/vmlab-test.XXXXXX") || exit 1
KILLPID=
cleanup() {
  [[ -z $KILLPID ]] || kill "$KILLPID" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

unset VMLAB_DRY_GATE_RC VMLAB_DRY_FETCH_FAIL VMLAB_DRY_STATE VMLAB_DRY_SNAPS VMLAB_DRY_SSH_FAIL VMLAB_DRY_LIST VMLAB_BOOT_WAIT \
      VMLAB_DOWN_WAIT VMLAB_TIMEOUT VMLAB_POLL VMLAB_ROOT VMLAB_CONF VBOXMANAGE
export TMPDIR=$T VMLAB_DRY=1

N=0 NFAIL=0
FAILS=()
t_eq() {   # NAME EXPECTED ACTUAL
  N=$((N + 1))
  if [[ $2 == "$3" ]]; then return 0; fi
  NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: expected [$2] got [$3]")
}
t_has() {  # NAME TEXT FIXED_PATTERN
  N=$((N + 1))
  if [[ $2 == *"$3"* ]]; then return 0; fi
  NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: missing [$3] in:" "$2")
}
t_no() {   # NAME TEXT FIXED_PATTERN
  N=$((N + 1))
  if [[ $2 != *"$3"* ]]; then return 0; fi
  NFAIL=$((NFAIL + 1)); FAILS+=("FAIL $1: unexpected [$3] in:" "$2")
}

sq() { sed -E "s/(probe )+/probe /g; s/probe $/probe/"; }   # squeeze repeated probes
run_v() { OUT=$("$BASH" "$V" "$@" 2>&1); RC=$?; }

# seq_of TEXT label=fixed-pattern ... : the labels of the lines of TEXT, in
# line order (a line gets the first label whose pattern it contains).
seq_of() {
  local text=$1 line p out=
  shift
  while IFS= read -r line; do
    for p in "$@"; do
      if [[ $line == *"${p#*=}"* ]]; then out+="${p%%=*} "; break; fi
    done
  done <<<"$text"
  printf '%s' "${out% }"
}

U=kb-ubuntu
PATS=("restore=snapshot $U restore" "start=startvm $U --type headless" "probe=127.0.0.1 true"
      "sync=tar -xf - -C ~/kbool.new" "vmtxt=> ~/vm.txt" "gate=gate.sh" "fetch=tar -cf - -C ~/gate-out"
      "catvm=cat ~/vm.txt" "acpi=controlvm $U acpipowerbutton" "poweroff=controlvm $U poweroff"
      "take=snapshot $U take" "delete=snapshot $U delete")

# ---- a tiny repo with one submodule (the real tree is never touched)
G=(git -c user.name=t -c user.email=t@example.invalid -c protocol.file.allow=always)
S=$T/subsrc R=$T/repo
mkdir -p "$S/tsed" "$R"
"${G[@]}" init -q "$S" && "${G[@]}" -C "$S" checkout -q -b main 2>/dev/null
printf '#!/bin/bash\n' >"$S/tsed/tsed.sh"; printf '#!/bin/bash\n' >"$S/tsed/gone.sh"
printf 'ignored.tmp\n' >"$S/.gitignore"
"${G[@]}" -C "$S" add -A && "${G[@]}" -C "$S" commit -q -m sub
"${G[@]}" init -q "$R" && "${G[@]}" -C "$R" checkout -q -b main 2>/dev/null
printf '#!/bin/bash\n' >"$R/kbool.sh"; printf '*.log\n' >"$R/.gitignore"
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -q -m root
"${G[@]}" -C "$R" submodule add -q "$S" kcl >/dev/null 2>&1
"${G[@]}" -C "$R" commit -q -m addsub
printf 'new\n' >"$R/root_new.sh"; printf 'x\n' >"$R/x.log"
printf 'new\n' >"$R/kcl/untracked_new.sh"; printf 'x\n' >"$R/kcl/ignored.tmp"
rm -f "$R/kcl/tsed/gone.sh"
ROOT_SHA=$(git -C "$R" rev-parse HEAD); SUB_SHA=$(git -C "$R/kcl" rev-parse HEAD)

# ---- help / usage
run_v --help;  t_eq "help rc" 0 "$RC"; t_has "help rc table" "$OUT" "13  snapshot exists"
run_v;         t_eq "no args rc" 2 "$RC"
run_v frobnicate; t_eq "unknown cmd rc" 2 "$RC"

# ---- refused names: rc 2, message, and nothing was called
for name in 'Ubuntu 24.02.2' OLHCV kb-unknown '../x' '' kb-UBUNTU 'kb-ubuntu;x'; do
  run_v up "$name"
  t_eq "refuse up [$name] rc" 2 "$RC"
  t_has "refuse up [$name] msg" "$OUT" "refused"
  t_no "refuse up [$name] nothing called" "$OUT" "DRY:"
done
for c in down reset snapshot run shell sync fetch gate; do
  run_v "$c" OLHCV x y
  t_eq "refuse $c rc" 2 "$RC"
  t_no "refuse $c nothing called" "$OUT" "DRY:"
done
OUT=$(VMLAB_DRY=0 VBOXMANAGE=/nonexistent/VBoxManage "$BASH" "$V" up 'Ubuntu 24.02.2' 2>&1); RC=$?
t_eq "refuse real mode rc (VBoxManage never reached)" 2 "$RC"

# ---- status
run_v status
t_eq "status rc" 0 "$RC"
t_eq "status lines" "kb-ubuntu poweroff clean|kb-debian poweroff clean|kb-fedora poweroff clean|kb-alpine poweroff clean|kb-freebsd poweroff clean" \
  "$(printf '%s\n' "$OUT" | grep -v '^DRY:' | paste -sd'|' -)"
VMLAB_DRY_STATE=running VMLAB_DRY_SNAPS="clean s2" run_v status
t_has "status running + 2 snapshots" "$OUT" "kb-alpine running clean,s2"
VMLAB_DRY_STATE=absent run_v status
t_has "status absent" "$OUT" "kb-fedora absent -"

# ---- up
run_v up $U
t_eq "up rc" 0 "$RC"
t_eq "up order" "start probe" "$(seq_of "$OUT" "${PATS[@]}")"
t_has "up ssh line" "$OUT" "-p 2221 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
t_has "up known hosts" "$OUT" "kbool_vmlab_known_hosts kb@127.0.0.1 true"
VMLAB_DRY_STATE=running run_v up $U
t_eq "up on a running VM: no start" "probe" "$(seq_of "$OUT" "${PATS[@]}")"
VMLAB_DRY_STATE=absent run_v up $U
t_eq "up absent rc" 10 "$RC"
VMLAB_DRY_SSH_FAIL=1 VMLAB_BOOT_WAIT=2 VMLAB_POLL=1 run_v up $U
t_eq "up boot timeout rc" 11 "$RC"
t_eq "up boot timeout: trap powers the VM off" "start probe acpi" "$(seq_of "$OUT" "${PATS[@]}" | sq)"

# ---- down
run_v down $U
t_eq "down on a stopped VM rc" 0 "$RC"
t_no "down on a stopped VM: no controlvm" "$OUT" "controlvm"
VMLAB_DRY_STATE=running VMLAB_DOWN_WAIT=2 run_v down $U
t_eq "down fallback rc" 0 "$RC"
t_eq "down fallback order" "acpi poweroff" "$(seq_of "$OUT" "${PATS[@]}")"

# ---- reset
run_v reset $U
t_eq "reset rc" 0 "$RC"
t_eq "reset restores clean" "restore" "$(seq_of "$OUT" "${PATS[@]}")"
t_has "reset restores clean (line)" "$OUT" "DRY: VBoxManage snapshot $U restore clean"
VMLAB_DRY_STATE=running VMLAB_DOWN_WAIT=1 run_v reset $U
t_eq "reset of a running VM: down first" "acpi poweroff restore" "$(seq_of "$OUT" "${PATS[@]}")"
run_v reset $U nosuch
t_eq "reset absent snapshot rc" 12 "$RC"
t_no "reset absent snapshot: no restore" "$OUT" "restore"
VMLAB_DRY_SNAPS="clean other" run_v reset $U other
t_has "reset to another snapshot" "$OUT" "DRY: VBoxManage snapshot $U restore other"
run_v reset $U -x
t_eq "reset bad snapshot name rc" 2 "$RC"

# ---- snapshot
run_v snapshot $U clean
t_eq "snapshot exists rc" 13 "$RC"
t_eq "snapshot exists: nothing taken" "" "$(seq_of "$OUT" "${PATS[@]}")"
run_v snapshot $U clean --replace
t_eq "snapshot --replace rc" 0 "$RC"
t_eq "snapshot --replace order" "delete take" "$(seq_of "$OUT" "${PATS[@]}")"
run_v snapshot $U fresh
t_eq "snapshot new rc" 0 "$RC"
t_eq "snapshot new order" "take" "$(seq_of "$OUT" "${PATS[@]}")"
t_has "snapshot new line" "$OUT" "DRY: VBoxManage snapshot $U take fresh"

# ---- run / fetch / sync --from-github
run_v run kb-alpine -- echo 'a b' '$x'
t_eq "run rc" 0 "$RC"
t_has "run line" "$OUT" '-p 2224 '
t_has "run quoting" "$OUT" 'kb@127.0.0.1 echo a\ b \$x'
run_v run $U
t_eq "run without command rc" 2 "$RC"
run_v fetch $U '~/gate-out' "$T/f"
t_eq "fetch order" "fetch" "$(seq_of "$OUT" "${PATS[@]}")"
t_has "fetch ssh side" "$OUT" 'kb@127.0.0.1 tar -cf - -C ~/gate-out .'
t_has "fetch host side" "$OUT" "DRY: tar -xf - -C $T/f"
run_v sync kb-freebsd --from-github --ref v1.0
t_has "sync github" "$OUT" 'rm -rf ~/kbool && git clone --recurse-submodules --branch v1.0 https://github.com/Keksov/kbool.git ~/kbool'
run_v sync $U --ref v1.0
t_eq "sync --ref alone rc" 2 "$RC"

# ---- gate
VMLAB_ROOT=$R run_v gate $U
t_eq "gate rc" 0 "$RC"
FIRST=$(printf "%s" "$OUT" | head -n 1)
[[ $FIRST == "vmlab out=$T/kb-vmlab/"*"-kb-ubuntu-clean" ]]; t_eq "gate first line (default out)" 0 "$?"
t_has "gate out name" "$OUT" "-$U-clean"
t_eq "gate order" "restore start probe sync vmtxt gate fetch catvm acpi" "$(seq_of "$OUT" "${PATS[@]}")"
t_has "gate default GATE_ARGS" "$OUT" 'KT_GATE_BASHES=/usr/bin/bash timeout -k 120 9000 bash ktests/tools/gate.sh --out ~/gate-out --rerun-failed 1 all'
t_has "gate cd" "$OUT" 'cd ~/kbool && KT_GATE_BASHES='
t_no "gate: clean power-off needs no hard poweroff" "$OUT" "controlvm $U poweroff"
t_has "gate vm.txt uname" "$OUT" '{ uname -a; if [ -r /etc/os-release ]; then cat /etc/os-release; else freebsd-version; fi; /usr/bin/bash --version | head -n 1;'
t_has "gate vm.txt shas" "$OUT" "printf '%s\\n' kbool=$ROOT_SHA-dirty kcl=$SUB_SHA-dirty ;"
t_has "gate fetches into out" "$OUT" "DRY: tar -xf - -C $T/kb-vmlab/"
VMLAB_ROOT=$R run_v gate kb-freebsd --snapshot s2 --out "$T/o" --from-github -- --changed 'a b'
t_eq "gate options rc" 12 "$RC"   # snapshot s2 does not exist in the default list
t_has "gate --out first line" "$OUT" "vmlab out=$T/o"
t_no "gate with absent snapshot starts nothing" "$OUT" "startvm"
VMLAB_ROOT=$R VMLAB_DRY_SNAPS="clean s2" run_v gate kb-freebsd --snapshot s2 --out "$T/o" --from-github -- --changed 'a b'
t_eq "gate options rc (snapshot present)" 0 "$RC"
t_eq "gate options first line" "vmlab out=$T/o" "$(printf '%s' "$OUT" | head -n 1)"
t_has "gate restores s2" "$OUT" "DRY: VBoxManage snapshot kb-freebsd restore s2"
t_has "gate GATE_ARGS after --" "$OUT" 'KT_GATE_BASHES=/usr/local/bin/bash timeout -k 120 9000 bash ktests/tools/gate.sh --out ~/gate-out --changed a\ b'
t_has "gate from github" "$OUT" 'git clone --recurse-submodules https://github.com/Keksov/kbool.git ~/kbool'
t_no "gate from github: no tar of the tree" "$OUT" "kbool.new"
t_has "gate into --out" "$OUT" "DRY: tar -xf - -C $T/o"
VMLAB_ROOT=$R VMLAB_DRY_SSH_FAIL=1 VMLAB_BOOT_WAIT=1 VMLAB_POLL=1 run_v gate $U --out "$T/o2"
t_eq "gate boot timeout rc" 11 "$RC"
t_eq "gate boot timeout: ends with power-off" "acpi" "$(seq_of "$OUT" "${PATS[@]}" | sed 's/.* //')"
t_no "gate boot timeout: never reached sync" "$OUT" "kbool.new"

# ---- gate: results not fetched (rc 14)
VMLAB_ROOT=$R VMLAB_DRY_FETCH_FAIL=out run_v gate $U --out "$T/o3"
t_eq "gate: fetch of gate-out fails -> rc 14" 14 "$RC"
t_has "gate fetch failure message" "$OUT" "vmlab: gate rc=0 but results not fetched: ~/gate-out"
t_eq "gate fetch failure: VM still powered off" "gate fetch catvm acpi" "$(seq_of "$OUT" "${PATS[@]}" | sed 's/.* \(gate fetch catvm acpi\)$/\1/')"
VMLAB_ROOT=$R VMLAB_DRY_FETCH_FAIL=vm run_v gate $U --out "$T/o3"
t_eq "gate: fetch of vm.txt fails -> rc 14" 14 "$RC"
VMLAB_ROOT=$R VMLAB_DRY_GATE_RC=1 VMLAB_DRY_FETCH_FAIL=1 run_v gate $U --out "$T/o3"
t_eq "gate rc 1 + fetch fails -> rc 14" 14 "$RC"
t_has "gate rc 1 + fetch fails: message carries the gate rc" "$OUT" "vmlab: gate rc=1 but results not fetched: ~/gate-out ~/vm.txt"
t_eq "gate rc 1 + fetch fails: VM powered off" "acpi" "$(seq_of "$OUT" "${PATS[@]}" | sed 's/.* //')"
VMLAB_ROOT=$R VMLAB_DRY_GATE_RC=1 run_v gate $U --out "$T/o3"
t_eq "gate rc 1, fetch ok -> rc 1" 1 "$RC"

# ---- sync file list
VMLAB_ROOT=$R VMLAB_DRY_LIST=1 run_v sync $U
t_eq "sync rc" 0 "$RC"
LIST=$(printf '%s\n' "$OUT" | sed -n 's/^DRY: entry //p' | LC_ALL=C sort | paste -sd'|' -)
t_eq "sync file list" ".gitignore|.gitmodules|kbool.sh|kcl/.gitignore|kcl/tsed/tsed.sh|kcl/untracked_new.sh|root_new.sh" "$LIST"
t_no "sync: no .git entries" "$OUT" "entry .git/"
t_no "sync: no nested .git entries" "$OUT" "/.git/"
t_no "sync: no gitlink dir" "$OUT" "entry kcl
"
t_eq "sync order" "sync" "$(seq_of "$OUT" "${PATS[@]}")"
t_has "sync remote command" "$OUT" 'kb@127.0.0.1 rm -rf ~/kbool.new && mkdir ~/kbool.new && tar -xf - -C ~/kbool.new && rm -rf ~/kbool && mv ~/kbool.new ~/kbool'
t_has "sync tar side" "$OUT" "DRY: tar -C $R --null -T - -cf -"

# ---- TERM during a wait: the trap powers off what this invocation started
VMLAB_DRY_SSH_FAIL=1 VMLAB_BOOT_WAIT=100 VMLAB_POLL=1 "$BASH" "$V" up $U >"$T/term.out" 2>&1 &
KILLPID=$!
for _ in $(seq 1 100); do
  grep -q '127.0.0.1 true' "$T/term.out" 2>/dev/null && break
  sleep 0.2
done
kill -TERM "$KILLPID"
wait "$KILLPID"; RC=$?
KILLPID=
t_eq "TERM rc" 143 "$RC"
t_eq "TERM: the VM this invocation started is powered off" "acpi" "$(seq_of "$(cat "$T/term.out")" "${PATS[@]}" | sed 's/.* //')"

# ---- no state left behind
t_eq "dry state dirs removed" 0 "$(find "$T" -maxdepth 1 -name 'vmlab-dry.*' | wc -l | tr -d ' ')"

if (( NFAIL == 0 )); then
  echo "PASS $N/$N"
  exit 0
fi
printf '%s\n' "${FAILS[@]}"
echo "FAIL $NFAIL of $N"
exit 1
