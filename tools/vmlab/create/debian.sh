#!/usr/bin/env bash
# create/debian.sh -- create and provision the lab VM kb-debian (Debian 13
# "trixie" netinst, VirtualBox unattended install = preseed), up to "ready for a
# snapshot":
#   1. createvm / modifyvm / disk       2. unattended install, headless
#   3. wait for guest additions         4. sudo + openssh-server + the lab ssh key
#   5. provision/apt.sh                 (the VM is left running)
# Afterwards:  bash tools/vmlab/vmlab.sh snapshot kb-debian clean
#
#   create/debian.sh                 whole recipe (refuses if kb-debian exists)
#   create/debian.sh --finish PWFILE steps 3-5 only, for a kb-debian whose install
#                                    was done by this script (PWFILE = its password
#                                    file; deleted at exit like the generated one)
# rc 13 if kb-debian already exists; 10 VBoxManage failed; 11 install timeout;
# 2 usage / missing ISO or key.
# env: KB_LAB_DIR (/c/var/vbox/kb-lab)  KB_ISO (newest debian-13.*-amd64-netinst
#      in KB_LAB_DIR/iso)  KB_SCRATCH (dir for the one-shot password file)
#      KB_INSTALL_WAIT (2700 s)  VBOXMANAGE  VMLAB_KEY
#
# Differences from create/ubuntu.sh (VirtualBox 7.1.12, Debian 13.x preseed):
# * `--package-selection-adjustment=minimal`: tasksel "minimal" + openssh-server
#   (without it the preseed installs the default task set, i.e. a desktop);
# * the preseed sets a root password (= the user's), so guest control logs in as
#   root: no sudo exists in a minimal install (and `kb` is in no sudo group).
#   Step 4 installs sudo + openssh-server as root and step 5 runs apt.sh as root;
# * the stock post-install template is used as is: its `usermod -a -G vboxsf kb`
#   runs from the preseed late_command, after the user exists.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMLAB=$HERE/../vmlab.sh
APT_SH=$HERE/../provision/apt.sh
VBOXMANAGE=${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}
KEY=${VMLAB_KEY:-$HOME/.ssh/kbool_vmlab}
LAB=${KB_LAB_DIR:-/c/var/vbox/kb-lab}
NAME=kb-debian
PORT=2222
WAIT=${KB_INSTALL_WAIT:-2700}
SCR=${KB_SCRATCH:-${SCRATCH:-${TMPDIR:-/tmp}}}

err() { printf 'create/debian: %s\n' "$*" >&2; }
vbm() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$VBOXMANAGE" "$@"; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

PW=; STARTED=0; FINISHED=0
cleanup() {
  [[ -n $PW ]] && rm -f "$PW"
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
  [[ -r $PW ]] || { err "usage: debian.sh --finish PWFILE"; PW=; exit 2; }
elif [[ $# -gt 0 ]]; then
  err "usage: debian.sh [--finish PWFILE]"; exit 2
fi

[[ -r $KEY && -r $KEY.pub ]] || { err "lab key $KEY(.pub) missing"; exit 2; }

if (( ! FINISH_ONLY )); then
  ISO=${KB_ISO:-}
  if [[ -z $ISO ]]; then
    ISO=$(ls "$LAB"/iso/debian-13.*-amd64-netinst.iso 2>/dev/null | sort -V | tail -1)
  fi
  [[ -n $ISO && -r $ISO ]] || { err "no Debian 13 netinst ISO in $LAB/iso"; exit 2; }

  if vbm showvminfo "$NAME" >/dev/null 2>&1; then
    err "$NAME already exists; refusing (delete it by hand first)"; exit 13
  fi

  mkdir -p "$SCR" "$LAB"
  PW=$(mktemp "$SCR/kbpw.XXXXXX") || exit 2
  chmod 600 "$PW"
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 >"$PW"
  [[ $(wc -c <"$PW") -eq 20 ]] || { err "password generation failed"; exit 2; }
  printf '\n' >>"$PW"

  LABW=$(wp "$LAB")
  VDI=$(wp "$LAB/$NAME/$NAME.vdi")

  vbm createvm --name "$NAME" --ostype Debian_64 --basefolder "$LABW" --register >/dev/null || exit 10
  vbm modifyvm "$NAME" --memory 4096 --cpus 4 --nic1 nat \
      --nat-pf1 "ssh,tcp,127.0.0.1,$PORT,,22" --audio-enabled off --usb off || exit 10
  vbm createmedium disk --filename "$VDI" --size 20480 --variant Standard >/dev/null || exit 10
  vbm storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 2 || exit 10
  vbm storageattach "$NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$VDI" || exit 10

  STARTED=1
  vbm unattended install "$NAME" --iso="$(wp "$ISO")" --user=kb --password-file="$(wp "$PW")" \
      --full-user-name=kb --hostname=kb-debian.lab --time-zone=UTC --locale=en_US \
      --package-selection-adjustment=minimal \
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
# The password file holds the password of kb and (same value, set by the preseed) of root.
gc() {   # USER SCRIPT
  vbm guestcontrol "$NAME" run --username "$1" --passwordfile "$(wp "$PW")" --exe /bin/sh -- -c "$2"
}

# Guest control as root works only after the install finished and the system
# rebooted (the run level is already 2 inside the installer): retry every 15 s
# until the same KB_INSTALL_WAIT deadline.
gc_retry() {   # USER SCRIPT WHAT
  until gc "$1" "$2" >/dev/null 2>&1; do
    if (( SECONDS - t0 >= WAIT )); then err "$3 failed (guest control unusable after ${WAIT}s)"; exit 10; fi
    sleep 15
  done
}

# --- sudo (not in a minimal install) and openssh-server (normally there already
# through the preseed), then the lab key for kb.
gc_retry root "export DEBIAN_FRONTEND=noninteractive PATH=/usr/local/sbin:/usr/sbin:/sbin:\$PATH; apt-get -o DPkg::Lock::Timeout=300 update && apt-get -o DPkg::Lock::Timeout=300 install -y sudo openssh-server && systemctl enable --now ssh" "installing sudo/openssh-server"
pub=$(cat "$KEY.pub")
gc_retry root "umask 077; install -d -m 700 -o kb -g kb /home/kb/.ssh; touch /home/kb/.ssh/authorized_keys; grep -qxF '$pub' /home/kb/.ssh/authorized_keys || echo '$pub' >> /home/kb/.ssh/authorized_keys; chown kb:kb /home/kb/.ssh/authorized_keys; chmod 600 /home/kb/.ssh/authorized_keys" "installing the ssh key"

# a (re)created VM has a new ssh host key: drop the old one from vmlab's own known_hosts
# (StrictHostKeyChecking=accept-new then records the new one)
KH=${VMLAB_KNOWN_HOSTS:-$HOME/.ssh/kbool_vmlab_known_hosts}
[[ -f $KH ]] && ssh-keygen -R "[127.0.0.1]:$PORT" -f "$KH" >/dev/null 2>&1

bash "$VMLAB" run "$NAME" -- true || { err "vmlab run $NAME -- true failed"; exit 1; }

# --- provision as root through guest control (kb has no sudo yet; apt.sh writes
# /etc/sudoers.d/kb itself)
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/apt.sh' <"$APT_SH" || exit 1
gc root "bash /tmp/apt.sh" || { err "provision/apt.sh failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- rm -f /tmp/apt.sh

FINISHED=1
err "$NAME ready (running). Next: bash tools/vmlab/vmlab.sh snapshot $NAME clean"
