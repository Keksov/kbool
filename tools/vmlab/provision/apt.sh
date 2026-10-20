#!/usr/bin/env bash
# provision/apt.sh -- provision an Ubuntu/Debian lab VM. Run as root:
#   sudo -S -p '' bash apt.sh [PACKAGE...]      (first time: password on stdin)
#   sudo -n bash apt.sh [PACKAGE...]            (later: NOPASSWD is in place)
# Idempotent. With no PACKAGE the default lists below are installed.
set -eu
[ "$(id -u)" = 0 ] || { echo "apt.sh: must run as root" >&2; exit 2; }

LABUSER=${LABUSER:-kb}
# CORE: a missing name is fatal. OPTIONAL: installed one by one; a missing
# name is reported ("apt.sh: MISSING <pkg>") and skipped, never substituted.
CORE="bash git coreutils sed grep findutils diffutils gawk procps util-linux perl curl openssl netcat-openbsd tzdata locales"
OPTIONAL="socat ncat netcat-traditional nodejs python3 uuid-runtime"
if [ $# -gt 0 ]; then CORE="$*"; OPTIONAL=; fi
LOCALES="en_US.UTF-8 de_DE.UTF-8 ru_RU.UTF-8"

# passwordless sudo for the lab user
f=/etc/sudoers.d/$LABUSER
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$LABUSER" >"$f.tmp"
chmod 0440 "$f.tmp"
visudo -cf "$f.tmp" >/dev/null
mv "$f.tmp" "$f"

# packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
# shellcheck disable=SC2086
apt-get install -y $CORE
for p in $OPTIONAL; do
  if apt-get install -y "$p"; then :; else echo "apt.sh: MISSING $p"; fi
done

# gawk is installed beside mawk, which stays the default awk; nc stays OpenBSD
if [ -x /usr/bin/mawk ]; then update-alternatives --set awk /usr/bin/mawk; fi
if [ -x /bin/nc.openbsd ]; then update-alternatives --set nc /bin/nc.openbsd; fi

# locales (needed for the locale-dependent tests)
# shellcheck disable=SC2086
locale-gen $LOCALES

# no background apt activity while a gate runs
systemctl disable --now unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer 2>&1 || true

# ssh: key only
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' >/etc/ssh/sshd_config.d/00-kbool-lab.conf
sshd -t
systemctl reload ssh 2>/dev/null || systemctl restart ssh

apt-get clean

# login shell must be bash: vmlab.sh run quotes with printf %q
sh_now=$(getent passwd "$LABUSER" | cut -d: -f7)
if [ "$sh_now" != /usr/bin/bash ] && [ "$sh_now" != /bin/bash ]; then
  chsh -s /usr/bin/bash "$LABUSER"
fi
getent passwd "$LABUSER" | cut -d: -f1,7
echo "apt.sh: done"
