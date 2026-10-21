#!/usr/bin/env bash
# vmlab.sh -- drive the kb-* lab VMs (VirtualBox, headless, ssh) from the host.
# Plain bash, no kbool. See README.md in this directory. `vmlab.sh --help`.

set -u

# MSYS/Git-bash rewrites POSIX-looking arguments for native programs; it is
# switched off for the ssh call only (rssh): remote commands like
# "/usr/bin/bash ..." must reach the VM untouched. Local paths given to the
# native ssh are converted explicitly (cygpath -w).

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${VMLAB_ROOT:-$(cd "$HERE/../.." && pwd)}
CONF=${VMLAB_CONF:-$HERE/vms.conf}
VBOXMANAGE=${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}
KEY=${VMLAB_KEY:-$HOME/.ssh/kbool_vmlab}
KNOWN=${VMLAB_KNOWN_HOSTS:-$HOME/.ssh/kbool_vmlab_known_hosts}
DRY=0; [[ ${VMLAB_DRY:-0} == 1 ]] && DRY=1
BOOT_WAIT=${VMLAB_BOOT_WAIT:-180}
DOWN_WAIT=${VMLAB_DOWN_WAIT:-60}
RUN_TIMEOUT=${VMLAB_TIMEOUT:-600}
POLL=${VMLAB_POLL:-3}

exec 3>&1   # fd 3: where DRY lines go (survives $(...) captures)

declare -A C_PORT=() C_BASH=() C_USER=()
VM_NAMES=()
STARTED=()      # VMs this invocation started: powered off again by the EXIT trap
DRYDIR=
SSHA=()
POWEROFF_CMD='sudo -n poweroff || doas -n poweroff || sudo -n shutdown -p now'

usage() {
  cat <<'EOF'
usage: vmlab.sh CMD [NAME] [args]      NAME = a VM row of vms.conf (kb-*)

  status                                  one line per VM: name state snapshots
  up NAME                                 start headless, wait until ssh answers
  down NAME                               poweroff over ssh if the guest answers, else acpi power button, then hard poweroff
  reset NAME [SNAP]                       down + restore snapshot (default clean)
  snapshot NAME SNAP [--replace]          down + take snapshot
  run NAME -- CMD...                      run CMD in the VM (one arg = command line verbatim; rc = CMD's rc)
  shell NAME                              interactive ssh (for the owner)
  sync NAME [--from-github [--ref R]]     working tree (tar) or a fresh clone -> ~/kbool
  fetch NAME REMOTE_DIR HOST_DIR          copy a remote directory to the host
  gate NAME [--snapshot S] [--from-github] [--out DIR] [--env NAME=VALUE]... [-- GATE_ARGS...]
                                          reset, up, sync, ktests gate, fetch, down

exit codes:
   0  ok
   2  usage error, or NAME refused (not a kb-* row of vms.conf)
  10  VBoxManage failed
  11  boot wait timed out (VMLAB_BOOT_WAIT, default 180 s)
  12  snapshot absent
  13  snapshot exists (use --replace)
  14  gate: results not fetched (the gate's own rc is on stderr)
  else  the remote command's rc (run, gate; 124 = timeout, 255 = ssh failed)

env: VBOXMANAGE VMLAB_DRY=1 VMLAB_BOOT_WAIT VMLAB_DOWN_WAIT VMLAB_TIMEOUT
     VMLAB_POLL VMLAB_ROOT VMLAB_KEY VMLAB_KNOWN_HOSTS (see README.md)
EOF
}

err() { printf 'vmlab: %s\n' "$*" >&2; }
usage_err() { err "$*"; err "try: vmlab.sh --help"; exit 2; }

# ---------------------------------------------------------------- vms.conf

load_conf() {
  local n os port mem cpus disk bashp user first=1
  [[ -r $CONF ]] || { err "cannot read $CONF"; exit 2; }
  while IFS=$'\t' read -r n os port mem cpus disk bashp user || [[ -n $n ]]; do
    user=${user%$'\r'}
    if (( first )); then
      first=0
      [[ $n == name ]] || { err "$CONF: first line must be the header (name os port ...)"; exit 2; }
      continue
    fi
    [[ -n $n ]] || continue
    VM_NAMES+=("$n"); C_PORT[$n]=$port; C_BASH[$n]=$bashp; C_USER[$n]=$user
  done <"$CONF"
}

# Refuse (rc 2) everything that is not a lab VM.
need_vm() {
  local n=${1-}
  if [[ ! $n =~ ^kb-[a-z0-9]+$ ]] || [[ -z ${C_PORT[$n]-} ]]; then
    err "refused: '$n' is not a lab VM (must match ^kb-[a-z0-9]+\$ and be a row of $CONF)"
    exit 2
  fi
}

need_snap_name() {
  [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage_err "bad snapshot name '${1-}'"
}

# ---------------------------------------------------------------- VBoxManage

dry_line() { printf 'DRY: %s\n' "$*" >&3; }

dry_state() {   # NAME -> current simulated state
  local f=$DRYDIR/$1.state
  [[ -f $f ]] || printf '%s\n' "${VMLAB_DRY_STATE:-poweroff}" >"$f"
  cat "$f"
}

dry_snaps_file() {   # NAME -> path of the simulated snapshot list
  local f=$DRYDIR/$1.snaps s
  if [[ ! -f $f ]]; then
    : >"$f"
    for s in ${VMLAB_DRY_SNAPS-clean}; do printf '%s\n' "$s" >>"$f"; done
  fi
  printf '%s' "$f"
}

dry_vbm() {   # answers VBoxManage queries without VBoxManage
  local f s
  case ${1-} in
    showvminfo)
      s=$(dry_state "$2")
      [[ $s == absent ]] && return 1
      printf 'name="%s"\nVMState="%s"\n' "$2" "$s" ;;
    snapshot)
      f=$(dry_snaps_file "$2")
      case ${3-} in
        list)   awk 'NR==1{print "SnapshotName=\"" $0 "\""; next} {print "SnapshotName-" NR-1 "=\"" $0 "\""}' "$f" ;;
        take)   printf '%s\n' "$4" >>"$f" ;;
        delete) grep -Fxv -- "$4" "$f" >"$f.tmp"; mv "$f.tmp" "$f" ;;
      esac ;;
    startvm) printf 'running\n' >"$DRYDIR/$2.state" ;;
    controlvm)
      case ${3-} in
        acpipowerbutton) [[ ${VMLAB_DRY_STATE:-poweroff} == running ]] || printf 'poweroff\n' >"$DRYDIR/$2.state" ;;
        poweroff)        printf 'poweroff\n' >"$DRYDIR/$2.state" ;;
      esac ;;
  esac
  return 0
}

vbm() {
  if (( DRY )); then
    dry_line "VBoxManage $*"
    dry_vbm "$@"
    return $?
  fi
  "$VBOXMANAGE" "$@"
}

vm_state() {   # NAME -> VMState value, or "absent"
  local s
  s=$(vbm showvminfo "$1" --machinereadable 2>/dev/null | tr -d '\r' | sed -n 's/^VMState="\(.*\)"$/\1/p')
  printf '%s\n' "${s:-absent}"
}

vm_snaps() {   # NAME -> snapshot names, one per line
  vbm snapshot "$1" list --machinereadable 2>/dev/null | tr -d '\r' \
    | sed -n 's/^SnapshotName\(-[0-9]*\)*="\(.*\)"$/\2/p'
}

has_snap() { vm_snaps "$1" | grep -Fxq -- "$2"; }

# ---------------------------------------------------------------- ssh

winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

build_ssh() {   # NAME -> SSHA
  local n=$1
  SSHA=(ssh -i "$(winpath "$KEY")" -p "${C_PORT[$n]}" -o BatchMode=yes -o ConnectTimeout=10
        -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$(winpath "$KNOWN")"
        "${C_USER[$n]}@127.0.0.1")
}

# rssh NAME SECS REMOTE_COMMAND_STRING   (stdin/stdout pass through)
# DRY_DRAIN=1 rssh ...  : in DRY mode read stdin to EOF before printing, so the
# output order of a pipeline is deterministic.
rssh() {
  local n=$1 secs=$2 rcmd=$3
  build_ssh "$n"
  if (( DRY )); then
    [[ ${DRY_DRAIN-} == 1 ]] && cat >/dev/null
    dry_line "${SSHA[*]} $rcmd"
    [[ ( $rcmd == true || $rcmd == "$POWEROFF_CMD" ) && ${VMLAB_DRY_SSH_FAIL:-0} == 1 ]] && return 255
    if [[ $rcmd == "$POWEROFF_CMD" ]]; then
      [[ ${VMLAB_DRY_SSH_POWEROFF-} == ignore ]] || printf 'poweroff\n' >"$DRYDIR/$n.state"
      return 255   # the connection drops
    fi
    [[ $rcmd == *ktests/tools/gate.sh* && -n ${VMLAB_DRY_GATE_RC-} ]] && return "$VMLAB_DRY_GATE_RC"
    case ${VMLAB_DRY_FETCH_FAIL-} in
      1|out) [[ $rcmd == 'tar -cf - -C ~/gate-out .' ]] && return 255 ;;
    esac
    case ${VMLAB_DRY_FETCH_FAIL-} in
      1|vm) [[ $rcmd == 'cat ~/vm.txt' ]] && return 255 ;;
    esac
    return 0
  fi
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' timeout -k 30 "$secs" "${SSHA[@]}" "$rcmd"
}

# Quote a remote path for the remote shell; a leading ~/ stays live.
rq() {
  case $1 in
    '~')   printf '~' ;;
    '~/'*) printf '~/%q' "${1:2}" ;;
    *)     printf '%q' "$1" ;;
  esac
}

# ---------------------------------------------------------------- VM control

# do_down NAME: poweroff over ssh when the guest answers (wait), else acpi power
# button (wait), else hard poweroff. rc 0 / 10.
do_down() {
  local n=$1 st t0
  st=$(vm_state "$n")
  case $st in
    absent) err "VM $n does not exist in VirtualBox"; return 10 ;;
    poweroff|aborted|saved) return 0 ;;
  esac
  if [[ $st == running ]] && rssh "$n" 30 true </dev/null >/dev/null 2>&1; then
    rssh "$n" 30 "$POWEROFF_CMD" </dev/null >/dev/null 2>&1 || true   # the connection drops: rc ignored
    t0=$SECONDS
    while (( SECONDS - t0 < DOWN_WAIT )); do
      [[ $(vm_state "$n") == poweroff ]] && return 0
      sleep 1
    done
    err "$n did not power off within ${DOWN_WAIT}s after the ssh poweroff: acpi power button"
  fi
  vbm controlvm "$n" acpipowerbutton >/dev/null 2>&1 || true
  t0=$SECONDS
  while (( SECONDS - t0 < DOWN_WAIT )); do
    [[ $(vm_state "$n") == poweroff ]] && return 0
    sleep 1
  done
  err "$n did not power off within ${DOWN_WAIT}s: hard poweroff"
  vbm controlvm "$n" poweroff >/dev/null 2>&1 || { err "controlvm poweroff failed for $n"; return 10; }
  t0=$SECONDS
  while (( SECONDS - t0 < 30 )); do
    [[ $(vm_state "$n") == poweroff ]] && return 0
    sleep 1
  done
  return 0
}

cmd_up() {
  local n=$1 st t0
  st=$(vm_state "$n")
  case $st in
    absent) err "VM $n does not exist in VirtualBox"; return 10 ;;
    running) ;;
    *)
      STARTED+=("$n")   # registered first: an interrupted start is powered off too
      vbm startvm "$n" --type headless >/dev/null || { err "startvm $n failed (state was $st)"; return 10; } ;;
  esac
  t0=$SECONDS
  while :; do
    rssh "$n" 30 true </dev/null >/dev/null 2>&1 && return 0
    if (( SECONDS - t0 >= BOOT_WAIT )); then
      err "$n: ssh did not answer within ${BOOT_WAIT}s"
      return 11
    fi
    sleep "$POLL"
  done
}

cmd_down() { do_down "$1"; }

cmd_reset() {
  local n=$1 snap=${2:-clean}
  need_snap_name "$snap"
  do_down "$n" || return $?
  has_snap "$n" "$snap" || { err "$n has no snapshot '$snap'"; return 12; }
  vbm snapshot "$n" restore "$snap" >/dev/null || { err "snapshot restore failed for $n/$snap"; return 10; }
}

cmd_snapshot() {
  local n=$1 snap=${2-} replace=0
  [[ -n $snap ]] || usage_err "snapshot NAME SNAP [--replace]"
  need_snap_name "$snap"
  case ${3-} in '') ;; --replace) replace=1 ;; *) usage_err "snapshot: unknown option '$3'" ;; esac
  do_down "$n" || return $?
  if has_snap "$n" "$snap"; then
    (( replace )) || { err "$n already has snapshot '$snap' (use --replace)"; return 13; }
    vbm snapshot "$n" delete "$snap" >/dev/null || { err "snapshot delete failed for $n/$snap"; return 10; }
  fi
  vbm snapshot "$n" take "$snap" >/dev/null || { err "snapshot take failed for $n/$snap"; return 10; }
}

cmd_status() {
  local n st sn
  for n in "${VM_NAMES[@]}"; do
    st=$(vm_state "$n"); sn=-
    [[ $st == absent ]] || sn=$(vm_snaps "$n" | paste -sd, -)
    printf '%s %s %s\n' "$n" "$st" "${sn:--}"
  done
}

cmd_run() {
  local n=$1; shift
  [[ ${1-} == -- ]] && shift
  (( $# )) || usage_err "run NAME -- CMD..."
  local c
  if (( $# == 1 )); then c=$1                     # one string: a remote command line, verbatim
  else c=$(printf '%q ' "$@"); c=${c% }; fi       # several words: each quoted
  rssh "$n" "$RUN_TIMEOUT" "$c"
}

cmd_shell() {
  local n=$1
  build_ssh "$n"
  if (( DRY )); then dry_line "${SSHA[*]}"; return 0; fi
  exec "${SSHA[@]}"
}

# ---------------------------------------------------------------- sync / fetch

sub_paths() {   # ROOT -> submodule paths, one per line
  git -C "$1" submodule status 2>/dev/null | sed -E 's/^.[0-9a-f]+ //; s/ \([^)]*\)$//'
}

emit_repo() {   # DIR PREFIX : NUL-separated regular files of one repo
  local f
  while IFS= read -r -d '' f; do
    [[ -f $1/$f ]] || continue          # deleted files, gitlinks (directories)
    printf '%s\0' "$2$f"
  done < <(git -C "$1" ls-files -co --exclude-standard -z)
}

sync_list() {   # ROOT -> NUL-separated list of the working tree's files
  local root=$1 p
  emit_repo "$root" ""
  while IFS= read -r p; do
    [[ -n $p ]] || continue
    if [[ ! -e $root/$p/.git ]]; then err "sync: submodule $p is not initialised, skipped"; continue; fi
    emit_repo "$root/$p" "$p/"
  done < <(sub_paths "$root")
}

tar_pack() {   # ROOT ; stdin = NUL-separated names ; stdout = tar stream
  if (( DRY )); then
    local n=0 f
    while IFS= read -r -d '' f; do
      n=$((n + 1))
      [[ ${VMLAB_DRY_LIST:-0} == 1 ]] && dry_line "entry $f"
    done
    dry_line "tar -C $1 --null -T - -cf -"
    dry_line "tar entries=$n"
    return 0
  fi
  tar -C "$1" --null -T - -cf -
}

tar_unpack() {   # DIR ; stdin = tar stream
  if (( DRY )); then
    cat >/dev/null
    dry_line "tar -xf - -C $1"
    return 0
  fi
  tar -xf - -C "$1"
}

pipe_rc() {   # PIPESTATUS values -> the last non-zero one (ssh side first), else 0
  local a=("$@") i
  for (( i = ${#a[@]} - 1; i >= 0; i-- )); do
    (( a[i] != 0 )) && return "${a[i]}"
  done
  return 0
}

host_shas() {   # ROOT -> "kbool=SHA[-dirty]" / "PATH=SHA[-dirty]" lines
  local root=$1 p sha d label
  for p in . $(sub_paths "$root" | tr '\n' ' '); do
    sha=$(git -C "$root/$p" rev-parse HEAD 2>/dev/null) || sha=unknown
    d=
    [[ -n $(git -C "$root/$p" status --porcelain 2>/dev/null) ]] && d=-dirty
    label=$p; [[ $p == . ]] && label=kbool
    printf '%s=%s%s\n' "$label" "$sha" "$d"
  done
}

cmd_sync() {
  local n=$1 gh=0 ref= c ps
  shift
  while (( $# )); do
    case $1 in
      --from-github) gh=1 ;;
      --ref) shift; ref=${1-}; [[ $ref =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || usage_err "sync: bad --ref '$ref'" ;;
      *) usage_err "sync: unknown option '$1'" ;;
    esac
    shift
  done
  [[ -z $ref || $gh == 1 ]] || usage_err "sync: --ref needs --from-github"
  if (( gh )); then
    c='rm -rf ~/kbool && git clone --recurse-submodules'
    [[ -z $ref ]] || c+=" --branch $ref"
    c+=' https://github.com/Keksov/kbool.git ~/kbool'
    rssh "$n" "$RUN_TIMEOUT" "$c" </dev/null
    return $?
  fi
  sync_list "$ROOT" | tar_pack "$ROOT" \
    | DRY_DRAIN=1 rssh "$n" "$RUN_TIMEOUT" 'rm -rf ~/kbool.new && mkdir ~/kbool.new && tar -xf - -C ~/kbool.new && rm -rf ~/kbool && mv ~/kbool.new ~/kbool'
  ps=("${PIPESTATUS[@]}")
  pipe_rc "${ps[@]}"
}

cmd_fetch() {
  local n=$1 remote=${2-} host=${3-} ps
  [[ -n $remote && -n $host ]] || usage_err "fetch NAME REMOTE_DIR HOST_DIR"
  (( DRY )) || mkdir -p "$host" || { err "cannot create $host"; return 1; }
  rssh "$n" "$RUN_TIMEOUT" "tar -cf - -C $(rq "$remote") ." </dev/null | tar_unpack "$host"
  ps=("${PIPESTATUS[@]}")
  pipe_rc "${ps[@]}"
}

# ---------------------------------------------------------------- gate

default_out_root() {
  local base=${TMPDIR:-}
  if [[ -z $base ]]; then
    if [[ -n ${LOCALAPPDATA:-} ]] && command -v cygpath >/dev/null 2>&1; then
      base=$(cygpath -u "$LOCALAPPDATA")/Temp
    else
      base=/tmp
    fi
  fi
  printf '%s/kb-vmlab' "$base"
}

cmd_gate() {
  local n=$1 snap=clean gh=0 out= gargs=() grc=0 rc envs=() envq= envt= e
  shift
  while (( $# )); do
    case $1 in
      --snapshot) shift; snap=${1-}; need_snap_name "$snap" ;;
      --env)
        shift; e=${1-}
        [[ $e == *=* && ${e%%=*} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || usage_err "gate: --env needs NAME=VALUE (NAME = ^[A-Za-z_][A-Za-z0-9_]*\$), got '$e'"
        envs+=("$e") ;;
      --from-github) gh=1 ;;
      --out) shift; out=${1-}; [[ -n $out ]] || usage_err "gate: --out needs a directory" ;;
      --) shift; gargs=("$@"); break ;;
      *) usage_err "gate: unknown option '$1'" ;;
    esac
    shift
  done
  (( ${#gargs[@]} )) || gargs=(--rerun-failed 1 all)
  [[ -n $out ]] || out="$(default_out_root)/$(date +%Y%m%d-%H%M%S)-$n-$snap"
  printf 'vmlab out=%s\n' "$out"

  cmd_reset "$n" "$snap" || return $?
  cmd_up "$n" || return $?
  if (( gh )); then cmd_sync "$n" --from-github || return $?; else cmd_sync "$n" || return $?; fi

  local bashp=${C_BASH[$n]} shas=() l vmtxt gcmd
  while IFS= read -r l; do shas+=("$l"); done < <(host_shas "$ROOT")
  vmtxt='{ uname -a; if [ -r /etc/os-release ]; then cat /etc/os-release; else freebsd-version; fi; '
  for e in "${envs[@]}"; do
    envq+="${e%%=*}=$(printf '%q' "${e#*=}") "   # NAME=<%q VALUE> prefix of the gate command
    envt+=" $(printf '%q' "env: $e")"            # extra line of vm.txt
  done
  vmtxt+="$(printf '%q' "$bashp") --version | head -n 1; printf '%s\\n' $(printf '%q ' "${shas[@]}")$envt; } > ~/vm.txt"
  rssh "$n" "$RUN_TIMEOUT" "$vmtxt" </dev/null || return $?

  gcmd="rm -rf ~/gate-out; cd ~/kbool && ${envq}KT_GATE_BASHES=$(printf '%q' "$bashp") timeout -k 120 9000 bash ktests/tools/gate.sh --out ~/gate-out $(printf '%q ' "${gargs[@]}")"
  rssh "$n" 9300 "${gcmd% }" </dev/null
  grc=$?

  local lost=
  cmd_fetch "$n" '~/gate-out' "$out" || lost+=" ~/gate-out"
  if (( DRY )); then
    rssh "$n" "$RUN_TIMEOUT" 'cat ~/vm.txt' </dev/null >/dev/null || lost+=" ~/vm.txt"
  else
    rssh "$n" "$RUN_TIMEOUT" 'cat ~/vm.txt' </dev/null >"$out/vm.txt" || lost+=" ~/vm.txt"
  fi

  do_down "$n"; rc=$?
  if (( rc == 0 )); then
    local keep=() s
    for s in "${STARTED[@]}"; do [[ $s == "$n" ]] || keep+=("$s"); done
    STARTED=("${keep[@]}")
  fi
  if [[ -n $lost ]]; then
    err "gate rc=$grc but results not fetched:$lost"
    return 14
  fi
  return $grc
}

# ---------------------------------------------------------------- main

on_exit() {
  local rc=$? n
  trap - EXIT INT TERM
  for n in "${STARTED[@]}"; do
    err "powering off $n (started by this invocation)"
    do_down "$n" || true
  done
  [[ -z $DRYDIR ]] || rm -rf "$DRYDIR"
  exit "$rc"
}

main() {
  local cmd rc
  (( $# )) || { usage >&2; exit 2; }
  case $1 in -h|--help|help) usage; exit 0 ;; esac
  cmd=$1; shift
  load_conf
  case $cmd in
    status|up|down|reset|snapshot|run|shell|sync|fetch|gate) ;;
    *) usage_err "unknown command '$cmd'" ;;
  esac
  if [[ $cmd != status ]]; then
    (( $# )) || usage_err "$cmd needs a VM NAME"
    need_vm "$1"
  fi
  if (( DRY )); then DRYDIR=$(mktemp -d "${TMPDIR:-/tmp}/vmlab-dry.XXXXXX") || exit 2; fi
  if [[ $cmd != shell ]]; then
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
  fi
  case $cmd in
    status)   cmd_status; rc=$? ;;
    up)       cmd_up "$@"; rc=$?; (( rc == 0 )) && STARTED=() ;;   # `up` alone leaves the VM running
    down)     cmd_down "$@"; rc=$? ;;
    reset)    cmd_reset "$@"; rc=$? ;;
    snapshot) cmd_snapshot "$@"; rc=$? ;;
    run)      cmd_run "$@"; rc=$? ;;
    shell)    cmd_shell "$@"; rc=$? ;;
    sync)     cmd_sync "$@"; rc=$? ;;
    fetch)    cmd_fetch "$@"; rc=$? ;;
    gate)     cmd_gate "$@"; rc=$? ;;
  esac
  exit "$rc"
}

main "$@"
