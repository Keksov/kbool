#!/bin/sh
# provision/pkg.sh -- provision the FreeBSD lab VM (kb-freebsd). POSIX sh; run as root:
#   sudo -n sh pkg.sh            the "clean" state: sudo bash git, sshd key-only, fdescfs, pkg clean
#   sudo -n sh pkg.sh --gnu      the "clean-gnu" additions: GNU tools (below), nothing else
#   sudo -n sh pkg.sh PACKAGE... install exactly these packages (and nothing else)
# Idempotent. create/freebsd.sh does the very first bootstrap from the root console
# (the image has no sudo yet) and runs this file afterwards over ssh.
#
# --gnu installs one package at a time; a package that does not exist is reported
# ("pkg.sh: MISSING <pkg>") and skipped, never substituted.
set -eu
[ "$(id -u)" = 0 ] || { echo "pkg.sh: must run as root" >&2; exit 2; }
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABUSER=${LABUSER:-kb}
CORE="sudo bash git"
GNU="coreutils gsed gawk findutils gnugrep diffutils netcat curl perl5 socat"
MODE=clean
if [ $# -gt 0 ]; then
  if [ "$1" = --gnu ]; then MODE=gnu; else MODE=list; fi
fi

# the pkg mirrors (SRV records) are flaky from this lab: retry a few times
retry() {
  n=1
  while :; do
    if "$@"; then return 0; fi
    [ "$n" -lt 4 ] || return 1
    n=$((n + 1)); echo "pkg.sh: retry $n/4: $*"; sleep 5
  done
}

# The VM image ships /usr/local/etc/pkg/repos/FreeBSD.conf enabling FreeBSD-base
# (pkgbase), which is not reachable here and makes every `pkg install` fail with
# "Unable to update repository FreeBSD-base". Only ports are installed from pkg.
mkdir -p /usr/local/etc/pkg/repos
echo 'FreeBSD-base: { enabled: no }' >/usr/local/etc/pkg/repos/FreeBSD.conf

case $MODE in
  clean)
    # passwordless sudo for the lab user
    mkdir -p /usr/local/etc/sudoers.d
    f=/usr/local/etc/sudoers.d/$LABUSER
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$LABUSER" >"$f.tmp"
    chmod 0440 "$f.tmp"
    mv "$f.tmp" "$f"

    # shellcheck disable=SC2086
    retry env ASSUME_ALWAYS_YES=yes pkg install -y $CORE

    # login shell must be bash: vmlab.sh run quotes with printf %q
    pw usermod "$LABUSER" -s /usr/local/bin/bash

    # process substitution needs /dev/fd (H14)
    grep -q '^fdesc[[:space:]]*/dev/fd[[:space:]]' /etc/fstab || echo 'fdesc /dev/fd fdescfs rw 0 0' >>/etc/fstab
    mount | grep -q '^fdescfs on /dev/fd ' || mount /dev/fd

    # sshd: key only (first value wins in sshd_config: put ours on top)
    if ! grep -q '^# kbool lab' /etc/ssh/sshd_config; then
      { printf '# kbool lab\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n'
        cat /etc/ssh/sshd_config; } >/etc/ssh/sshd_config.new
      mv /etc/ssh/sshd_config.new /etc/ssh/sshd_config
    fi
    sshd -t
    sysrc sshd_enable=YES
    service sshd reload

    pkg clean -y
    ;;
  gnu)
    for p in $GNU; do
      if retry env ASSUME_ALWAYS_YES=yes pkg install -y "$p"; then :; else echo "pkg.sh: MISSING $p"; fi
    done
    pkg clean -y
    ;;
  list)
    # shellcheck disable=SC2086
    retry env ASSUME_ALWAYS_YES=yes pkg install -y "$@"
    pkg clean -y
    ;;
esac

grep "^$LABUSER:" /etc/passwd
echo "pkg.sh: done ($MODE)"
