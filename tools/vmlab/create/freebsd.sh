#!/usr/bin/env bash
# create/freebsd.sh -- create and provision the lab VM kb-freebsd from the official
# FreeBSD VM image (15.x, UFS, VMDK; no installer): both snapshots are taken.
#   1. image + CHECKSUM.SHA256 (download if absent), verify, xz -dk
#   2. clonemedium VMDK -> VDI, resize 20 GB, createvm / modifyvm (NAT ssh 2225)
#   3. boot headless; root console scripted with `controlvm keyboardputstring`
#      (the image has no root password): sshd on, user kb (wheel), the lab key
#   4. still on the root console: pkg install sudo bash git, sudoers, kb's shell -> bash
#   5. provision/pkg.sh over ssh with sudo (key-only sshd, fdescfs, pkg clean)
#   6. vmlab snapshot clean
#   7. provision/pkg.sh --gnu (GNU tools), vmlab snapshot clean-gnu
# The VM is left powered off.
#
#   create/freebsd.sh        whole recipe (refuses, rc 13, if kb-freebsd exists)
# rc: 13 kb-freebsd exists; 10 VBoxManage failed; 11 console step failed / ssh never
#     answered; 2 usage / missing image, checksum or key; 1 other failure.
# env: KB_LAB_DIR (/c/var/vbox/kb-lab)  KB_FB_REL (newest 15.x-RELEASE listed on
#      download.freebsd.org; set it to pin one, e.g. 15.1)  KB_SCRATCH (screenshots)
#      KB_FB_BOOT_WAIT (120 s before the first console line)  VBOXMANAGE  VMLAB_KEY
#
# Console typing: US layout, one line per keyboardputstring + Enter (scancode 1c 9c),
# 5 s apart. Screenshot for debugging: VBoxManage controlvm kb-freebsd screenshotpng X.png
# (the image has no serial console; the log would stay empty).
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMLAB=$HERE/../vmlab.sh
PKG_SH=$HERE/../provision/pkg.sh
VBOXMANAGE=${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}
KEY=${VMLAB_KEY:-$HOME/.ssh/kbool_vmlab}
LAB=${KB_LAB_DIR:-/c/var/vbox/kb-lab}
NAME=kb-freebsd
PORT=2225
SCR=${KB_SCRATCH:-${SCRATCH:-${TMPDIR:-/tmp}}}
BOOT_WAIT=${KB_FB_BOOT_WAIT:-120}
BASEURL=https://download.freebsd.org/releases/VM-IMAGES

err() { printf 'create/freebsd: %s\n' "$*" >&2; }
vbm() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$VBOXMANAGE" "$@"; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

STARTED=0; FINISHED=0
cleanup() {
  if (( STARTED )) && [[ $FINISHED != 1 ]]; then
    err "failed or interrupted: powering $NAME off (screenshot: $SCR/freebsd-fail.png)"
    vbm controlvm "$NAME" screenshotpng "$(wp "$SCR/freebsd-fail.png")" >/dev/null 2>&1 || true
    vbm controlvm "$NAME" poweroff >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# type LINE + Enter on the VGA console
ctype() {
  vbm controlvm "$NAME" keyboardputstring "$1" >/dev/null || return 1
  vbm controlvm "$NAME" keyboardputscancode 1c 9c >/dev/null || return 1
  sleep 5
}
# wait (up to $2 s) until `vmlab run` of $1 succeeds
wait_run() {
  local t=$(( SECONDS + $2 ))
  while (( SECONDS < t )); do
    bash "$VMLAB" run "$NAME" -- "$1" >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}

[[ $# -eq 0 ]] || { err "usage: freebsd.sh"; exit 2; }
[[ -r $KEY && -r $KEY.pub ]] || { err "lab key $KEY(.pub) missing"; exit 2; }
command -v xz >/dev/null 2>&1 || { err "no xz"; exit 2; }
if vbm showvminfo "$NAME" >/dev/null 2>&1; then
  err "$NAME already exists; refusing (delete it by hand first)"; exit 13
fi
mkdir -p "$SCR" "$LAB/img"

# --- 1. the image: newest 15.x-RELEASE, checksum, xz -dk
REL=${KB_FB_REL:-}
if [[ -z $REL ]]; then
  REL=$(curl -sS --fail --max-time 60 "$BASEURL/" | grep -o 'href="15\.[0-9]*-RELEASE/"' \
        | sed 's/href="//; s/-RELEASE\/"//' | sort -V | tail -1)
  [[ -n $REL ]] || { err "could not list $BASEURL/ (set KB_FB_REL)"; exit 2; }
fi
IMGX=FreeBSD-$REL-RELEASE-amd64-ufs.vmdk.xz
SUMF=$LAB/img/FreeBSD-$REL-RELEASE-CHECKSUM.SHA256
if [[ ! -e $LAB/img/$IMGX ]]; then
  [[ -e $SUMF ]] || curl -sS --fail --max-time 120 -o "$SUMF" "$BASEURL/$REL-RELEASE/amd64/Latest/CHECKSUM.SHA256" || exit 2
  timeout -k 30 3000 curl -sS --fail -o "$LAB/img/$IMGX" "$BASEURL/$REL-RELEASE/amd64/Latest/$IMGX" || { err "download failed"; exit 2; }
fi
[[ -r $SUMF ]] || { err "no $SUMF next to the image"; exit 2; }
want=$(sed -n "s/^SHA256 ($IMGX) = //p" "$SUMF")
got=$(sha256sum "$LAB/img/$IMGX" | cut -d' ' -f1)
[[ -n $want && $want == "$got" ]] || { err "checksum of $IMGX not OK (want '$want' got '$got')"; exit 2; }
err "image $IMGX: checksum OK"
VMDK=$LAB/img/FreeBSD-$REL-RELEASE-amd64-ufs.vmdk
[[ -e $VMDK ]] || xz -dk "$LAB/img/$IMGX" || exit 1

# --- 2. VDI (20 GB: the image's growfs grows the root filesystem), the VM
VDIP=$LAB/$NAME/$NAME.vdi
[[ ! -e $VDIP ]] || { err "$VDIP exists already; refusing"; exit 13; }
mkdir -p "$LAB/$NAME"
vbm clonemedium "$(wp "$VMDK")" "$(wp "$VDIP")" --format VDI >/dev/null || { err "clonemedium failed"; rm -f "$VDIP"; exit 10; }
vbm closemedium disk "$(wp "$VMDK")" >/dev/null 2>&1   # clonemedium registered the source; the file stays
vbm modifymedium disk "$(wp "$VDIP")" --resize 20480 || exit 10
vbm createvm --name "$NAME" --ostype FreeBSD_64 --basefolder "$(wp "$LAB")" --register >/dev/null || exit 10
vbm modifyvm "$NAME" --memory 4096 --cpus 4 --firmware bios --rtc-use-utc on --nic1 nat \
    --nat-pf1 "ssh,tcp,127.0.0.1,$PORT,,22" --nat-localhostreachable1 on \
    --audio-enabled off --usb off || exit 10
vbm storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 2 || exit 10
vbm storageattach "$NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$(wp "$VDIP")" || exit 10

# --- 3. boot, root console
KH=${VMLAB_KNOWN_HOSTS:-$HOME/.ssh/kbool_vmlab_known_hosts}
[[ -f $KH ]] && ssh-keygen -R "[127.0.0.1]:$PORT" -f "$KH" >/dev/null 2>&1
STARTED=1
vbm startvm "$NAME" --type headless >/dev/null || exit 10
err "booting; ${BOOT_WAIT}s before the console login"
sleep "$BOOT_WAIT"
PUB=$(cat "$KEY.pub")
for line in \
  root \
  "sysrc sshd_enable=YES" \
  "pw useradd kb -m -G wheel -s /bin/sh" \
  "mkdir -p /home/kb/.ssh" \
  "echo '$PUB' > /home/kb/.ssh/authorized_keys" \
  "chown -R kb:kb /home/kb/.ssh && chmod 700 /home/kb/.ssh && chmod 600 /home/kb/.ssh/authorized_keys" \
  "service sshd start"; do
  ctype "$line" || { err "console typing failed"; exit 11; }
done
wait_run true 90 || { err "ssh as kb does not answer after the console steps"; exit 11; }
err "ssh answers"

# --- 4. root console again: sudo, bash, git (the image has no sudo yet)
# The image enables the FreeBSD-base (pkgbase) repository, which is not reachable:
# disable it first (provision/pkg.sh keeps that). The pkg mirrors are flaky: retry.
ctype "echo 'FreeBSD-base: { enabled: no }' > /usr/local/etc/pkg/repos/FreeBSD.conf; for i in 1 2 3 4; do env ASSUME_ALWAYS_YES=yes pkg bootstrap && pkg install -y sudo bash git && break; sleep 5; done; echo 'kb ALL=(ALL) NOPASSWD: ALL' > /usr/local/etc/sudoers.d/kb && chmod 440 /usr/local/etc/sudoers.d/kb && pw usermod kb -s /usr/local/bin/bash && touch /tmp/kb-console.done" \
  || exit 11
wait_run 'test -f /tmp/kb-console.done' 900 || { err "console package step did not finish in 15 min"; exit 11; }
ctype exit
bash "$VMLAB" run "$NAME" -- 'sudo -n true' || { err "sudo -n true failed"; exit 11; }

# --- 5. provision/pkg.sh through sudo
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/pkg.sh' <"$PKG_SH" || exit 1
bash "$VMLAB" run "$NAME" -- 'sudo -n sh /tmp/pkg.sh' || { err "provision/pkg.sh failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- "bash -c 'cat <(echo ok)'" | grep -qx ok || { err "process substitution does not work"; exit 1; }
bash "$VMLAB" run "$NAME" -- 'sudo rm -f /tmp/pkg.sh /tmp/kb-console.done'

# --- 6. snapshot clean
bash "$VMLAB" snapshot "$NAME" clean || exit 1

# --- 7. clean-gnu
bash "$VMLAB" up "$NAME" || exit 1
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/pkg.sh' <"$PKG_SH" || exit 1
bash "$VMLAB" run "$NAME" -- 'sudo -n sh /tmp/pkg.sh --gnu' || { err "provision/pkg.sh --gnu failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- 'sudo rm -f /tmp/pkg.sh'
bash "$VMLAB" snapshot "$NAME" clean-gnu || exit 1

FINISHED=1
err "$NAME ready (powered off, snapshots clean and clean-gnu)"
