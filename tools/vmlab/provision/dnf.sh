#!/usr/bin/env bash
# provision/dnf.sh -- provision a Fedora lab VM. Run as root:
#   sudo -n bash dnf.sh [PACKAGE...]      (kb has NOPASSWD from the cloud-init seed of create/fedora.sh)
#   bash dnf.sh [PACKAGE...]              (as root)
# Idempotent. With no PACKAGE the default lists below are installed.
set -eu
[ "$(id -u)" = 0 ] || { echo "dnf.sh: must run as root" >&2; exit 2; }
export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH   # guest control's root has no sbin in PATH

LABUSER=${LABUSER:-kb}
# CORE: a missing name is fatal. OPTIONAL: installed one by one; a missing
# name is reported ("dnf.sh: MISSING <pkg>") and skipped, never substituted.
CORE="bash git-core coreutils sed grep findutils diffutils gawk procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru"
OPTIONAL="socat nodejs python3"
if [ $# -gt 0 ]; then CORE="$*"; OPTIONAL=; fi

# passwordless sudo for the lab user
f=/etc/sudoers.d/$LABUSER
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$LABUSER" >"$f.tmp"
chmod 0440 "$f.tmp"
visudo -cf "$f.tmp" >/dev/null
mv "$f.tmp" "$f"

# packages
# shellcheck disable=SC2086
dnf install -y $CORE
for p in $OPTIONAL; do
  if dnf install -y "$p"; then :; else echo "dnf.sh: MISSING $p"; fi
done

# no background package-manager activity while a gate runs
if systemctl cat dnf-makecache.timer >/dev/null 2>&1; then
  systemctl disable --now dnf-makecache.timer 2>&1 || true
fi

# ssh: key only (the main sshd_config includes sshd_config.d/*.conf first; first value wins)
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' >/etc/ssh/sshd_config.d/00-kbool-lab.conf
sshd -t
systemctl enable sshd
systemctl reload sshd 2>/dev/null || systemctl restart sshd

dnf clean all

# login shell must be bash: vmlab.sh run quotes with printf %q
sh_now=$(getent passwd "$LABUSER" | cut -d: -f7)
if [ "$sh_now" != /usr/bin/bash ] && [ "$sh_now" != /bin/bash ]; then
  usermod -s /usr/bin/bash "$LABUSER"
fi
getent passwd "$LABUSER" | cut -d: -f1,7
echo "dnf.sh: done"
