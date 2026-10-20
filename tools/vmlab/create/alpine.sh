#!/usr/bin/env bash
# create/alpine.sh -- create and provision the lab VM kb-alpine from the official Alpine
# "virt" ISO with `setup-alpine -f` (answer file typed on the VGA console); both
# snapshots are taken.
#   1. ISO + .sha256 (download if absent), verify
#   2. createvm / modifyvm (NAT ssh 2224) / 12 GB VDI, ISO in the DVD slot
#   3. boot headless; root console (no password): type the answer file, then
#      `setup-alpine -e -f` + poweroff; detach the ISO, boot from disk, wait for ssh
#      (the whole step is retried, up to 4 times: see "DNS" below)
#   4. root console of the installed system: `permit nopass :wheel` for doas
#   5. provision/apk.sh over ssh with doas; vmlab snapshot clean
#   6. provision/apk.sh --gnu; vmlab snapshot clean-gnu
# The VM is left powered off.
#
#   create/alpine.sh         whole recipe (refuses, rc 13, if kb-alpine exists)
# rc: 13 kb-alpine exists; 10 VBoxManage failed; 11 console / install step failed;
#     2 usage / missing ISO, checksum or key; 1 other failure.
# env: KB_LAB_DIR (/c/var/vbox/kb-lab)  KB_ALPINE_VER (newest x.y.z listed under
#      latest-stable; set it to pin one, e.g. 3.24.2)  KB_SCRATCH (screenshots)
#      KB_AL_BOOT_WAIT (60 s)  KB_AL_TRIES (4)  VBOXMANAGE  VMLAB_KEY
#
# DNS. The NAT's resolver (10.0.2.3) drops a few percent of the lookups on this host and
# musl/apk then print "DNS: transient error (try again later)"; setup-alpine cannot retry
# (it left no bootable system in 4 of 4 first attempts). So the live system gets the four
# A records of dl-cdn.alpinelinux.org (Fastly) in /etc/hosts, and /etc/apk/repositories
# gets dl-cdn main + community by URL, because the answer file's `APKREPOSOPTS="-1"` needs
# mirrors.alpinelinux.org, which does not resolve reliably either (the step then only
# warns "No mirror found" and the URL lines stay). provision/apk.sh pins the same addresses
# while it runs and retries. The installed system's /etc/hosts keeps the install-time lines
# until apk.sh removes them.
#
# Console typing: US layout, one line per keyboardputstring + Enter (scancode 1c 9c).
# Screenshot: VBoxManage controlvm kb-alpine screenshotpng X.png
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMLAB=$HERE/../vmlab.sh
APK_SH=$HERE/../provision/apk.sh
VBOXMANAGE=${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}
KEY=${VMLAB_KEY:-$HOME/.ssh/kbool_vmlab}
LAB=${KB_LAB_DIR:-/c/var/vbox/kb-lab}
NAME=kb-alpine
PORT=2224
SCR=${KB_SCRATCH:-${SCRATCH:-${TMPDIR:-/tmp}}}
BOOT_WAIT=${KB_AL_BOOT_WAIT:-60}
TRIES=${KB_AL_TRIES:-4}
BASEURL=https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64
PINS="151.101.2.132 151.101.66.132 151.101.130.132 151.101.194.132"

err() { printf 'create/alpine: %s\n' "$*" >&2; }
vbm() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$VBOXMANAGE" "$@"; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

STARTED=0; FINISHED=0
cleanup() {
  if (( STARTED )) && [[ $FINISHED != 1 ]]; then
    err "failed or interrupted: powering $NAME off (screenshot: $SCR/alpine-fail.png)"
    vbm controlvm "$NAME" screenshotpng "$(wp "$SCR/alpine-fail.png")" >/dev/null 2>&1 || true
    vbm controlvm "$NAME" poweroff >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

ctype() {   # type LINE + Enter on the VGA console; $2 = seconds to wait afterwards (default 2)
  vbm controlvm "$NAME" keyboardputstring "$1" >/dev/null || return 1
  vbm controlvm "$NAME" keyboardputscancode 1c 9c >/dev/null || return 1
  sleep "${2:-2}"
}
vmstate() { vbm showvminfo "$NAME" --machinereadable 2>/dev/null | sed -n 's/^VMState="\(.*\)"$/\1/p'; }
wait_state() {   # STATE SECONDS
  local t=$(( SECONDS + $2 ))
  while (( SECONDS < t )); do [[ $(vmstate) == "$1" ]] && return 0; sleep 3; done
  return 1
}
wait_run() {     # CMD SECONDS : until `vmlab run` of CMD succeeds
  local t=$(( SECONDS + $2 ))
  while (( SECONDS < t )); do
    bash "$VMLAB" run "$NAME" -- "$1" >/dev/null 2>&1 && return 0
    sleep 4
  done
  return 1
}

[[ $# -eq 0 ]] || { err "usage: alpine.sh"; exit 2; }
[[ -r $KEY && -r $KEY.pub ]] || { err "lab key $KEY(.pub) missing"; exit 2; }
if vbm showvminfo "$NAME" >/dev/null 2>&1; then
  err "$NAME already exists; refusing (delete it by hand first)"; exit 13
fi
mkdir -p "$SCR" "$LAB/iso"

# --- 1. the ISO
VER=${KB_ALPINE_VER:-}
if [[ -z $VER ]]; then
  VER=$(curl -sS --fail --max-time 60 "$BASEURL/" | grep -o 'href="alpine-virt-[0-9][0-9.]*-x86_64\.iso"' \
        | sed 's/href="alpine-virt-//; s/-x86_64\.iso"//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
  [[ -n $VER ]] || { err "could not list $BASEURL/ (set KB_ALPINE_VER)"; exit 2; }
fi
ISOF=alpine-virt-$VER-x86_64.iso
if [[ ! -e $LAB/iso/$ISOF ]]; then
  curl -sS --fail --max-time 120 -o "$LAB/iso/$ISOF.sha256" "$BASEURL/$ISOF.sha256" || exit 2
  timeout -k 30 1500 curl -sS --fail -o "$LAB/iso/$ISOF" "$BASEURL/$ISOF" || { err "download failed"; exit 2; }
fi
out=$(cd "$LAB/iso" && sha256sum -c "$ISOF.sha256" 2>/dev/null)
[[ $out == "$ISOF: OK" ]] || { err "checksum of $ISOF not OK ($out)"; exit 2; }
err "ISO $ISOF: checksum OK"
MAJMIN=${VER%.*}   # 3.24

# --- 2. the VM
VDIP=$LAB/$NAME/$NAME.vdi
[[ ! -e $VDIP ]] || { err "$VDIP exists already; refusing"; exit 13; }
mkdir -p "$LAB/$NAME"
vbm createvm --name "$NAME" --ostype Linux_64 --basefolder "$(wp "$LAB")" --register >/dev/null || exit 10
vbm modifyvm "$NAME" --memory 2048 --cpus 4 --firmware bios --nic1 nat \
    --nat-pf1 "ssh,tcp,127.0.0.1,$PORT,,22" --nat-localhostreachable1 on \
    --audio-enabled off --usb off --boot1 dvd --boot2 disk || exit 10
vbm createmedium disk --filename "$(wp "$VDIP")" --size 12288 --format VDI >/dev/null || exit 10
vbm storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 2 || exit 10
vbm storageattach "$NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$(wp "$VDIP")" || exit 10
vbm storageattach "$NAME" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$(wp "$LAB/iso/$ISOF")" || exit 10

# --- 3. install from the ISO, retried
KH=${VMLAB_KNOWN_HOSTS:-$HOME/.ssh/kbool_vmlab_known_hosts}
PUB=$(cat "$KEY.pub")
STARTED=1
ok=0
for (( try = 1; try <= TRIES; try++ )); do
  err "install attempt $try/$TRIES"
  if [[ $(vmstate) != poweroff ]]; then vbm controlvm "$NAME" poweroff >/dev/null 2>&1; wait_state poweroff 60; fi
  vbm storageattach "$NAME" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$(wp "$LAB/iso/$ISOF")" || exit 10
  vbm startvm "$NAME" --type headless >/dev/null || exit 10
  sleep "$BOOT_WAIT"
  ctype root 3
  ctype "cat > /tmp/a <<'EOF'"
  for line in \
    'KEYMAPOPTS="us us"' \
    'HOSTNAMEOPTS="-n kb-alpine"' \
    'INTERFACESOPTS="auto lo' \
    'iface lo inet loopback' \
    'auto eth0' \
    'iface eth0 inet dhcp"' \
    'DNSOPTS="-d lab 10.0.2.3"' \
    'TIMEZONEOPTS="-z UTC"' \
    'PROXYOPTS="none"' \
    'APKREPOSOPTS="-1"' \
    'USEROPTS="-a -u kb"' \
    "USERSSHKEY=\"$PUB\"" \
    'SSHDOPTS="-c openssh"' \
    'NTPOPTS="-c busybox"' \
    'DISKOPTS="-m sys /dev/sda"' \
    'EOF'; do
    ctype "$line"
  done
  pin=; for ip in $PINS; do pin="$pin echo '$ip dl-cdn.alpinelinux.org' >> /etc/hosts;"; done
  ctype "$pin printf '%s\n' https://dl-cdn.alpinelinux.org/alpine/v$MAJMIN/main https://dl-cdn.alpinelinux.org/alpine/v$MAJMIN/community >> /etc/apk/repositories; ifconfig eth0 up; udhcpc -i eth0 -q; ERASE_DISKS=/dev/sda setup-alpine -e -f /tmp/a; poweroff" 5
  if ! wait_state poweroff 1500; then err "attempt $try: the VM did not power off in 25 min"; continue; fi
  # boot from disk
  vbm storageattach "$NAME" --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive || exit 10
  [[ -f $KH ]] && ssh-keygen -R "[127.0.0.1]:$PORT" -f "$KH" >/dev/null 2>&1
  vbm startvm "$NAME" --type headless >/dev/null || exit 10
  if wait_run true 150; then ok=1; break; fi
  err "attempt $try: no ssh after the install (screenshot: $SCR/alpine-try$try.png)"
  vbm controlvm "$NAME" screenshotpng "$(wp "$SCR/alpine-try$try.png")" >/dev/null 2>&1
done
(( ok )) || { err "setup-alpine produced no reachable system in $TRIES attempts"; exit 11; }
err "ssh answers"

# --- 4. root console of the installed system: doas without a password for wheel
ctype root 3
ctype "echo 'permit nopass :wheel' > /etc/doas.d/20-wheel.conf" 3
ctype exit
bash "$VMLAB" run "$NAME" -- 'doas -n true' || { err "doas -n true failed"; exit 11; }

# --- 5. provision/apk.sh, clean
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/apk.sh' <"$APK_SH" || exit 1
bash "$VMLAB" run "$NAME" -- 'doas -n sh /tmp/apk.sh' || { err "provision/apk.sh failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- "bash -c 'cat <(echo ok)'" | grep -qx ok || { err "process substitution does not work"; exit 1; }
bash "$VMLAB" run "$NAME" -- 'doas rm -f /tmp/apk.sh'
bash "$VMLAB" snapshot "$NAME" clean || exit 1

# --- 6. clean-gnu
bash "$VMLAB" up "$NAME" || exit 1
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/apk.sh' <"$APK_SH" || exit 1
bash "$VMLAB" run "$NAME" -- 'doas -n sh /tmp/apk.sh --gnu' || { err "provision/apk.sh --gnu failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- 'doas rm -f /tmp/apk.sh'
bash "$VMLAB" snapshot "$NAME" clean-gnu || exit 1

FINISHED=1
err "$NAME ready (powered off, snapshots clean and clean-gnu)"
