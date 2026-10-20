#!/usr/bin/env bash
# create/fedora.sh -- create and provision the lab VM kb-fedora from the official
# Fedora Cloud Base image (cloud-init NoCloud), up to "ready for a snapshot".
# VirtualBox 7.1.12 `unattended install` does not know Fedora 44, so there is no
# installer: the qcow2 cloud image is converted to a VDI and booted; cloud-init
# fetches its config from a throw-away HTTP server on the host (named in the VM's
# SMBIOS serial number, reached from the guest as 10.0.2.2 through the NAT):
#   1. check the image against its CHECKSUM      2. clonemedium qcow2 -> VDI, resize
#   3. createvm / modifyvm (+ serial log)         4. seed (meta-data, user-data) + http server
#   5. vmlab up (first boot, cloud-init)          6. provision/dnf.sh through sudo
#   7. VM off, seed pointer + serial port removed (the VM is left POWERED OFF)
# Afterwards:  bash tools/vmlab/vmlab.sh snapshot kb-fedora clean
#
#   create/fedora.sh        whole recipe (refuses, rc 13, if kb-fedora exists)
# rc: 13 kb-fedora exists; 10 VBoxManage / http server failed; 11 boot timeout;
#     2 usage / missing image, checksum, python or key; 1 other failure.
# env: KB_LAB_DIR (/c/var/vbox/kb-lab)  KB_IMG (newest Fedora-Cloud-Base-Generic-
#      *.x86_64.qcow2 in KB_LAB_DIR/img, with its *-CHECKSUM next to it)
#      KB_SCRATCH (seed dir, server log, serial log)  KB_PYTHON (python)
#      KB_HTTP_PORT (8099)  VMLAB_BOOT_WAIT (900 here)  VBOXMANAGE  VMLAB_KEY
#
# Without a working converter in VirtualBox: convert the qcow2 inside kb-ubuntu
# (`qemu-img convert -O vdi`, see README "kb-fedora") and put the VDI where
# step 2 puts it. No other converter, no binaries downloaded to the host.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VMLAB=$HERE/../vmlab.sh
DNF_SH=$HERE/../provision/dnf.sh
VBOXMANAGE=${VBOXMANAGE:-/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}
KEY=${VMLAB_KEY:-$HOME/.ssh/kbool_vmlab}
LAB=${KB_LAB_DIR:-/c/var/vbox/kb-lab}
NAME=kb-fedora
PORT=2223
HTTP_PORT=${KB_HTTP_PORT:-8099}
PY=${KB_PYTHON:-python}
SCR=${KB_SCRATCH:-${SCRATCH:-${TMPDIR:-/tmp}}}
DMI='VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial'

err() { printf 'create/fedora: %s\n' "$*" >&2; }
vbm() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$VBOXMANAGE" "$@"; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

SRV=; STARTED=0; FINISHED=0; SEED=
stop_server() {
  if [[ -n $SRV ]]; then
    kill "$SRV" 2>/dev/null
    wait "$SRV" 2>/dev/null
    err "http server (pid $SRV) stopped"
    SRV=
  fi
}
cleanup() {
  stop_server
  [[ -n $SEED ]] && rm -rf "$SEED"
  if (( STARTED )) && [[ $FINISHED != 1 ]]; then
    err "failed or interrupted: powering $NAME off"
    vbm controlvm "$NAME" poweroff >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

[[ $# -eq 0 ]] || { err "usage: fedora.sh"; exit 2; }
[[ -r $KEY && -r $KEY.pub ]] || { err "lab key $KEY(.pub) missing"; exit 2; }
command -v "$PY" >/dev/null 2>&1 || { err "no python ($PY) for the seed http server"; exit 2; }

# --- 1. the image and its checksum
IMG=${KB_IMG:-}
[[ -n $IMG ]] || IMG=$(ls "$LAB"/img/Fedora-Cloud-Base-Generic-*.x86_64.qcow2 2>/dev/null | sort -V | tail -1)
[[ -n $IMG && -r $IMG ]] || { err "no Fedora-Cloud-Base-Generic-*.x86_64.qcow2 in $LAB/img"; exit 2; }
SUM=$(ls "$(dirname "$IMG")"/Fedora-Cloud-*-CHECKSUM 2>/dev/null | sort -V | tail -1)
[[ -n $SUM ]] || { err "no Fedora-Cloud-*-CHECKSUM next to $IMG"; exit 2; }
out=$(cd "$(dirname "$IMG")" && sha256sum -c --ignore-missing "$SUM" 2>/dev/null)
[[ $out == "$(basename "$IMG"): OK" ]] || { err "checksum of $IMG not OK ($out)"; exit 2; }
err "image $(basename "$IMG"): checksum OK"

if vbm showvminfo "$NAME" >/dev/null 2>&1; then
  err "$NAME already exists; refusing (delete it by hand first)"; exit 13
fi
mkdir -p "$SCR" "$LAB"

# --- 2. VDI (clonemedium reads qcow2), 20 GB (cloud-init grows the root filesystem)
VDIP=$LAB/$NAME/$NAME.vdi
[[ ! -e $VDIP ]] || { err "$VDIP exists already; refusing"; exit 13; }
mkdir -p "$LAB/$NAME"
vbm clonemedium "$(wp "$IMG")" "$(wp "$VDIP")" --format VDI >/dev/null \
  || { err "clonemedium failed: convert with qemu-img in kb-ubuntu (see README)"; rm -f "$VDIP"; exit 10; }
vbm modifymedium disk "$(wp "$VDIP")" --resize 20480 || exit 10

# --- 3. the VM
vbm createvm --name "$NAME" --ostype Fedora_64 --basefolder "$(wp "$LAB")" --register >/dev/null || exit 10
vbm modifyvm "$NAME" --memory 4096 --cpus 4 --firmware bios --nic1 nat \
    --nat-pf1 "ssh,tcp,127.0.0.1,$PORT,,22" --nat-localhostreachable1 on \
    --audio-enabled off --usb off \
    --uart1 0x3F8 4 --uart-mode1 file "$(wp "$SCR/fedora-serial.log")" || exit 10
vbm storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 2 || exit 10
vbm storageattach "$NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$(wp "$VDIP")" || exit 10

# --- 4. the seed and the host http server
SEED=$(mktemp -d "$SCR/kbseed.XXXXXX") || exit 2
printf 'instance-id: kb-fedora-1\nlocal-hostname: kb-fedora\n' >"$SEED/meta-data"
: >"$SEED/vendor-data"   # empty: saves cloud-init ten 404 retries
{
  printf '#cloud-config\nusers:\n  - name: kb\n    shell: /bin/bash\n'
  printf '    sudo: "ALL=(ALL) NOPASSWD:ALL"\n    lock_passwd: true\n    ssh_authorized_keys:\n'
  printf '      - %s\n' "$(cat "$KEY.pub")"
  printf 'ssh_pwauth: false\n'
} >"$SEED/user-data"
vbm setextradata "$NAME" "$DMI" "ds=nocloud;s=http://10.0.2.2:$HTTP_PORT/" || exit 10

SLOG=$SCR/fedora-http.log
: >"$SLOG"
timeout -k 5 1800 "$PY" -u -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$(wp "$SEED")" >"$SLOG" 2>&1 &
SRV=$!
err "http server started, pid $SRV (127.0.0.1:$HTTP_PORT, directory seed)"
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q 'Serving HTTP' "$SLOG" && break; sleep 1; done
grep -q 'Serving HTTP' "$SLOG" || { err "http server did not start: $(cat "$SLOG")"; exit 10; }

# --- 5. first boot; cloud-init fetches the seed, creates kb, installs the key
STARTED=1
KH=${VMLAB_KNOWN_HOSTS:-$HOME/.ssh/kbool_vmlab_known_hosts}
[[ -f $KH ]] && ssh-keygen -R "[127.0.0.1]:$PORT" -f "$KH" >/dev/null 2>&1
VMLAB_BOOT_WAIT=${VMLAB_BOOT_WAIT:-900} bash "$VMLAB" up "$NAME"; rc=$?
(( rc == 0 )) || { err "vmlab up failed (rc $rc); see $SLOG and $SCR/fedora-serial.log"; exit "$rc"; }
if grep -q 'GET /user-data' "$SLOG" && grep -q 'GET /meta-data' "$SLOG"; then
  err "cloud-init fetched the seed: $(grep -c '"GET /' "$SLOG") GET lines in $SLOG"
else
  err "ssh answers but the log shows no seed fetch"; exit 1
fi
stop_server

# --- 6. provision (kb has NOPASSWD from the seed)
bash "$VMLAB" run "$NAME" -- true || { err "vmlab run $NAME -- true failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- sh -c 'cat > /tmp/dnf.sh' <"$DNF_SH" || exit 1
bash "$VMLAB" run "$NAME" -- 'sudo -n bash /tmp/dnf.sh' || { err "provision/dnf.sh failed"; exit 1; }
bash "$VMLAB" run "$NAME" -- rm -f /tmp/dnf.sh

# --- 7. later boots must not look for the seed; no serial port; VM off
bash "$VMLAB" down "$NAME" || exit 1
vbm setextradata "$NAME" "$DMI" || exit 10
vbm modifyvm "$NAME" --uart1 off || exit 10

FINISHED=1
err "$NAME ready (powered off). Next: bash tools/vmlab/vmlab.sh snapshot $NAME clean"
