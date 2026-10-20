#!/bin/sh
# provision/apk.sh -- provision the Alpine lab VM (kb-alpine). POSIX sh (busybox ash);
# run as root:
#   doas -n sh apk.sh            the "clean" state: bash git, kb's login shell bash, sshd key-only
#   doas -n sh apk.sh --gnu      the "clean-gnu" additions (GNU tools, below), nothing else
#   doas -n sh apk.sh PACKAGE... install exactly these packages (and nothing else)
# Idempotent. `doas -n` needs `permit nopass :wheel` (create/alpine.sh writes it from the
# root console: setup-alpine's own `-a` rule is `permit persist :wheel`, which wants a
# password that kb does not have).
#
# --gnu installs: coreutils sed grep findutils diffutils gawk procps-ng util-linux perl
# curl openssl netcat-openbsd tzdata. A name that is not in the index is reported
# ("apk.sh: MISSING <pkg>") and skipped; only procps-ng has a fallback, procps, which is
# reported too ("apk.sh: using procps").
set -eu
[ "$(id -u)" = 0 ] || { echo "apk.sh: must run as root" >&2; exit 2; }
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABUSER=${LABUSER:-kb}
CORE="bash git"
GNU="coreutils sed grep findutils diffutils gawk procps-ng util-linux perl curl openssl netcat-openbsd tzdata"
MODE=clean
if [ $# -gt 0 ]; then
  if [ "$1" = --gnu ]; then MODE=gnu; else MODE=list; fi
fi

# The NAT's DNS (10.0.2.3) drops a few percent of the lookups on this host and apk
# reports "DNS: transient error": pin the CDN's addresses while apk runs (removed
# again at exit) and retry.
PINS="151.101.2.132 151.101.66.132 151.101.130.132 151.101.194.132"
pin_on() {
  for ip in $PINS; do
    grep -q "^$ip dl-cdn.alpinelinux.org\$" /etc/hosts || echo "$ip dl-cdn.alpinelinux.org" >>/etc/hosts
  done
}
pin_off() { sed -i '/ dl-cdn\.alpinelinux\.org$/d' /etc/hosts; }
trap pin_off EXIT
pin_on

retry() {
  n=1
  while :; do
    if "$@"; then return 0; fi
    [ "$n" -lt 8 ] || return 1
    n=$((n + 1)); echo "apk.sh: retry $n/8: $*"; sleep 3
  done
}

retry apk update

case $MODE in
  clean)
    # passwordless doas for the wheel group (kb is in it)
    mkdir -p /etc/doas.d
    echo 'permit nopass :wheel' >/etc/doas.d/20-wheel.conf

    # shellcheck disable=SC2086
    retry apk add $CORE

    # login shell must be bash: vmlab.sh run quotes with printf %q
    sed -i "s#^\($LABUSER:.*:\)[^:]*\$#\1/bin/bash#" /etc/passwd
    grep "^$LABUSER:" /etc/passwd

    # ssh: key only (the main sshd_config includes sshd_config.d/*.conf first; first value wins)
    mkdir -p /etc/ssh/sshd_config.d
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' >/etc/ssh/sshd_config.d/00-kbool-lab.conf
    sshd -t
    rc-service sshd reload

    # ACPI power button (vmlab `down`): linux-virt's `button` driver does not register an
    # input device for VirtualBox's fixed power button, so acpid never hears it. The
    # `tiny-power-button` module does, and signals init: SIGUSR2 (12) = busybox poweroff
    # (its default SIGINT would be "ctrlaltdel" = reboot). `button` is blacklisted so it
    # does not claim the device first.
    printf 'blacklist button\noptions tiny-power-button power_signal=12\n' >/etc/modprobe.d/kbool-lab.conf
    grep -qx tiny-power-button /etc/modules || echo tiny-power-button >>/etc/modules
    rmmod button 2>/dev/null || true
    modprobe tiny-power-button power_signal=12 2>/dev/null || true
    ;;
  gnu)
    pkgs=
    for p in $GNU; do
      if [ -n "$(apk search -e "$p")" ]; then
        pkgs="$pkgs $p"
      elif [ "$p" = procps-ng ] && [ -n "$(apk search -e procps)" ]; then
        echo "apk.sh: MISSING procps-ng"; echo "apk.sh: using procps"
        pkgs="$pkgs procps"
      else
        echo "apk.sh: MISSING $p"
      fi
    done
    # shellcheck disable=SC2086
    retry apk add $pkgs
    ;;
  list)
    retry apk add "$@"
    ;;
esac

apk cache clean 2>/dev/null || true
rm -rf /var/cache/apk/* 2>/dev/null || true
echo "apk.sh: done ($MODE)"
