#!/usr/bin/env bash
# provision/apt.sh -- provision an Ubuntu/Debian lab VM. Run as root:
#   sudo -S -p '' bash apt.sh [PACKAGE...]      (first time: password on stdin)
#   sudo -n bash apt.sh [PACKAGE...]            (later: NOPASSWD is in place)
# Idempotent. With no PACKAGE the default lists below are installed.
set -eu
[ "$(id -u)" = 0 ] || { echo "apt.sh: must run as root" >&2; exit 2; }

export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH   # guest control's root has no sbin in PATH
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
. /etc/os-release
if [ "$ID" = debian ]; then
  # Debian's locale-gen takes no arguments: it generates what /etc/locale.gen lists
  for l in $LOCALES; do
    sed -i "s/^# *\($l UTF-8\)\$/\1/" /etc/locale.gen
    grep -qx "$l UTF-8" /etc/locale.gen || { echo "apt.sh: $l missing in /etc/locale.gen" >&2; exit 1; }
  done
  locale-gen
else
  # shellcheck disable=SC2086
  locale-gen $LOCALES
fi

# no background apt activity while a gate runs (Debian has no unattended-upgrades by default)
for u in unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer; do
  if systemctl cat "$u" >/dev/null 2>&1; then systemctl disable --now "$u" 2>&1 || true; fi
done

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
