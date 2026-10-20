#!/usr/bin/env bash
# create/ubuntu.sh -- create and provision the lab VM kb-ubuntu (Ubuntu 24.04
# server, VirtualBox unattended install), up to "ready for a snapshot":
#   1. createvm / modifyvm / disk       2. unattended install, headless
#   3. wait for guest additions         4. openssh-server + the lab ssh key
#   5. provision/apt.sh                 (the VM is left running)
# Afterwards:  bash tools/vmlab/vmlab.sh snapshot kb-ubuntu clean
#
#   create/ubuntu.sh                 whole recipe (refuses if kb-ubuntu exists)
#   create/ubuntu.sh --finish PWFILE steps 3-5 only, for a kb-ubuntu whose install
#                                    was done by this script (PWFILE = its password
#                                    file; deleted at exit like the generated one)
# rc 13 if kb-ubuntu already exists; 10 VBoxManage failed; 11 install timeout;
# 2 usage / missing ISO or key.
# env: KB_LAB_DIR (/c/var/vbox/kb-lab)  KB_ISO (newest ubuntu-24.04.*-live-server
#      in KB_LAB_DIR/iso)  KB_SCRATCH (dir for the one-shot password file)
#      KB_INSTALL_WAIT (2700 s)  VBOXMANAGE  VMLAB_KEY
#
# Two facts about VirtualBox 7.1.12 + Ubuntu 24.04.5 this script works around:
# * the stock post-install template ends with `usermod -a -G vboxsf kb`, but
#   cloud-init creates `kb` only at the first boot of the installed system, so
#   usermod fails (exit 6) and subiquity reports the whole install as failed and
#   stops at "An error occurred. Press enter to start a shell" -> the script
#   passes a copy of the template without that line (--post-install-template);
# * the autoinstall file has no `ssh:` section, so openssh-server is not
#   installed -> step 4 installs it through guest control (kb + sudo; root cannot
#   log in through guest control).
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMLAB=$HERE/../vmlab.sh
APT_SH=$HERE/../provision/apt.sh
VBOXMANAGE=${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}
KEY=${VMLAB_KEY:-$HOME/.ssh/kbool_vmlab}
LAB=${KB_LAB_DIR:-/c/var/vbox/kb-lab}
NAME=kb-ubuntu
WAIT=${KB_INSTALL_WAIT:-2700}
SCR=${KB_SCRATCH:-${SCRATCH:-${TMPDIR:-/tmp}}}

err() { printf 'create/ubuntu: %s\n' "$*" >&2; }
vbm() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$VBOXMANAGE" "$@"; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

PW=; PIT=; STARTED=0; FINISHED=0
cleanup() {
  [[ -n $PW ]] && rm -f "$PW"
  [[ -n $PIT ]] && rm -f "$PIT"
  if (( STARTED )) && [[ $FINISHED != 1 ]]; then
    err "failed or interrupted: powering $NAME off"
    vbm controlvm "$NAME" poweroff >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

FINISH_ONLY=0
if [[ ${1-} == --finish ]]; then
  FINISH_ONLY=1; PW=${2-}
  [[ -r $PW ]] || { err "usage: ubuntu.sh --finish PWFILE"; PW=; exit 2; }
elif [[ $# -gt 0 ]]; then
  err "usage: ubuntu.sh [--finish PWFILE]"; exit 2
fi

[[ -r $KEY && -r $KEY.pub ]] || { err "lab key $KEY(.pub) missing"; exit 2; }

if (( ! FINISH_ONLY )); then
  ISO=${KB_ISO:-}
  if [[ -z $ISO ]]; then
    ISO=$(ls "$LAB"/iso/ubuntu-24.04.*-live-server-amd64.iso 2>/dev/null | sort -V | tail -1)
  fi
  [[ -n $ISO && -r $ISO ]] || { err "no Ubuntu 24.04 live-server ISO in $LAB/iso"; exit 2; }

  if vbm showvminfo "$NAME" >/dev/null 2>&1; then
    err "$NAME already exists; refusing (delete it by hand first)"; exit 13
  fi

  mkdir -p "$SCR" "$LAB"
  PW=$(mktemp "$SCR/kbpw.XXXXXX") || exit 2
  chmod 600 "$PW"
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 >"$PW"
  [[ $(wc -c <"$PW") -eq 20 ]] || { err "password generation failed"; exit 2; }
  printf '\n' >>"$PW"

  # post-install template: the stock one minus `usermod -a -G vboxsf <user>`
  STOCK=$(dirname "$VBOXMANAGE")/UnattendedTemplates/debian_postinstall.sh
  [[ -r $STOCK ]] || { err "VirtualBox template $STOCK not found"; exit 2; }
  PIT=$(mktemp "$SCR/kbpit.XXXXXX") || exit 2
  sed '/^log_command_in_target usermod -a -G vboxsf /d' "$STOCK" >"$PIT"
  [[ $(grep -c usermod "$STOCK") -eq 1 && $(grep -c usermod "$PIT") -eq 0 ]] \
    || { err "unexpected VirtualBox post-install template (usermod line not found once)"; exit 2; }

  LABW=$(wp "$LAB")
  VDI=$(wp "$LAB/$NAME/$NAME.vdi")

  vbm createvm --name "$NAME" --ostype Ubuntu_64 --basefolder "$LABW" --register >/dev/null || exit 10
  vbm modifyvm "$NAME" --memory 4096 --cpus 4 --nic1 nat \
      --nat-pf1 "ssh,tcp,127.0.0.1,2221,,22" --audio-enabled off --usb off || exit 10
  vbm createmedium disk --filename "$VDI" --size 20480 --variant Standard >/dev/null || exit 10
  vbm storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 2 || exit 10
  vbm storageattach "$NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$VDI" || exit 10

  STARTED=1
  vbm unattended install "$NAME" --iso="$(wp "$ISO")" --user=kb --password-file="$(wp "$PW")" \
      --full-user-name=kb --hostname=kb-ubuntu.lab --time-zone=UTC --locale=en_US \
      --post-install-template="$(wp "$PIT")" \
      --install-additions --start-vm=headless 2>&1 \
    | sed -E 's/^( *(user-|admin-)?password = ).*/\1<redacted>/'
  [[ ${PIPESTATUS[0]} -eq 0 ]] || exit 10
fi
STARTED=1

# --- wait for guest additions (run level >= 2)
t0=$SECONDS
while :; do
  lvl=$(vbm showvminfo "$NAME" --machinereadable 2>/dev/null | tr -d '\r' \
        | sed -n 's/^GuestAdditionsRunLevel=//p')
  [[ ${lvl:-0} =~ ^[0-9]+$ ]] && (( ${lvl:-0} >= 2 )) && break
  if (( SECONDS - t0 >= WAIT )); then err "guest additions not up after ${WAIT}s"; exit 11; fi
  sleep 30
done
err "guest additions run level $lvl after $((SECONDS - t0))s"

# guest control: `--exe /bin/sh -- -c '...'` (the arguments after -- follow argv[0]).
gc() {   # USER SCRIPT
  vbm guestcontrol "$NAME" run --username "$1" --passwordfile "$(wp "$PW")" --exe /bin/sh -- -c "$2"
}

# The run level already reaches 2 inside the installer (before the target system
# exists); guest control as kb/root works only after the install finished and the
# system rebooted. Retry every 15 s until the same KB_INSTALL_WAIT deadline.
gc_retry() {   # USER SCRIPT WHAT
  until gc "$1" "$2" >/dev/null 2>&1; do
    if (( SECONDS - t0 >= WAIT )); then err "$3 failed (guest control unusable after ${WAIT}s)"; exit 10; fi
    sleep 15
  done
}

# --- openssh-server (not in the autoinstall file), then the lab key for kb.
# root cannot log in through guest control (its password is locked) and a password
# must not appear on a command line: the password file is copied into the guest,
# fed to `sudo -S` from there and removed in the same command.
install_sshd() {
  local g; g=/tmp/$(basename "$PW")
  vbm guestcontrol "$NAME" copyto --username kb --passwordfile "$(wp "$PW")" \
      --target-directory /tmp/ "$(wp "$PW")" >/dev/null 2>&1 || return 1
  gc kb "chmod 600 $g; sudo -S -p '' sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -o DPkg::Lock::Timeout=300 update && apt-get -o DPkg::Lock::Timeout=300 install -y openssh-server && systemctl enable --now ssh' <$g; rc=\$?; rm -f $g; exit \$rc"
}
until install_sshd >/dev/null 2>&1; do
  if (( SECONDS - t0 >= WAIT )); then err "installing openssh-server failed (guest control unusable after ${WAIT}s)"; exit 10; fi
  sleep 15
done
pub=$(cat "$KEY.pub")
gc_retry kb "umask 077; mkdir -p /home/kb/.ssh; touch /home/kb/.ssh/authorized_keys; grep -qxF '$pub' /home/kb/.ssh/authorized_keys || echo '$pub' >> /home/kb/.ssh/authorized_keys; chmod 700 /home/kb/.ssh; chmod 600 /home/kb/.ssh/authorized_keys" "installing the ssh key"

# a (re)created VM has a new ssh host key: drop the old one from vmlab's own known_hosts
# (StrictHostKeyChecking=accept-new then records the new one)
KH=${VMLAB_KNOWN_HOSTS:-$HOME/.ssh/kbool_vmlab_known_hosts}
[[ -f $KH ]] && ssh-keygen -R "[127.0.0.1]:2221" -f "$KH" >/dev/null 2>&1

bash "$VMLAB" run "$NAME" -- true || { err "vmlab run $NAME -- true failed"; exit 1; }

# --- provision (first run: sudo -S with the password on stdin)
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/apt.sh' <"$APT_SH" || exit 1
bash "$VMLAB" run "$NAME" -- sudo -S -p '' bash /tmp/apt.sh <"$PW" || { err "provision/apt.sh failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- rm -f /tmp/apt.sh

FINISHED=1
err "$NAME ready (running). Next: bash tools/vmlab/vmlab.sh snapshot $NAME clean"
