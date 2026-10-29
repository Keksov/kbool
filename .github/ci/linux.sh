#!/bin/sh
# .github/ci/linux.sh -- run the kbool gate inside a Linux container (launch L5.1).
# One script for every docker row of ci.yml (bash:X-alpine, debian, ubuntu,
# fedora). POSIX sh: the image's `sh` is busybox ash or dash. Run as root:
#   docker run --rm -v "$PWD:/src:ro" -v "$OUT:/out" IMAGE sh /src/.github/ci/linux.sh
# Installs the package set of tools/vmlab/provision/{apk,apt,dnf}.sh (alpine: its
# GNU list; apt/dnf: CORE + socat), copies the tree to a non-root user `kb` (the
# tests assume a normal user: chmod 000 does not stop root) and runs the gate
# there. The gate's OUT dir is copied to /out and the exit code is the gate's.
# A platform setup failure (packages after 5 tries, user, missing tool) exits 5,
# never 3: ci.yml's verdict (verdict.sh) maps 3|4 to green only with a
# __GATE__ line.
set -eu

fail() { echo "linux.sh: $*" >&2; exit 5; }

# retry CMD... : 5 tries, 5 s apart
retry() {
    n=1
    while :; do
        if "$@"; then return 0; fi
        [ "$n" -lt 5 ] || return 1
        n=$((n + 1)); echo "linux.sh: retry $n/5: $*"; sleep 5
    done
}

if command -v apk >/dev/null 2>&1; then pm=apk
elif command -v apt-get >/dev/null 2>&1; then pm=apt
elif command -v dnf >/dev/null 2>&1; then pm=dnf
else fail "no package manager (apk, apt-get, dnf) in this image"
fi

case $pm in
    apk)
        # apk.sh GNU list, unchanged from L5.0 (bash itself is the image's, /usr/local/bin)
        PKGS="git coreutils sed grep findutils diffutils gawk procps-ng util-linux perl curl openssl netcat-openbsd socat tzdata"
        # shellcheck disable=SC2086
        retry apk add --no-cache $PKGS || fail "apk add failed"
        adduser -D -s /usr/local/bin/bash kb || fail "adduser kb failed"
        ;;
    apt)
        # apt.sh CORE + socat
        PKGS="bash git coreutils sed grep findutils diffutils gawk procps util-linux perl curl openssl netcat-openbsd tzdata locales socat"
        export DEBIAN_FRONTEND=noninteractive
        retry apt-get update || fail "apt-get update failed"
        # shellcheck disable=SC2086
        retry apt-get install -y $PKGS || fail "apt-get install failed"
        # gawk is installed beside mawk, which stays the default awk; nc stays OpenBSD (apt.sh)
        if [ -x /usr/bin/mawk ]; then update-alternatives --set awk /usr/bin/mawk || fail "update-alternatives awk"; fi
        if [ -x /bin/nc.openbsd ]; then update-alternatives --set nc /bin/nc.openbsd || fail "update-alternatives nc"; fi
        # locales for the locale-dependent tests (apt.sh)
        LOCALES="en_US.UTF-8 de_DE.UTF-8 ru_RU.UTF-8"
        . /etc/os-release
        if [ "$ID" = debian ]; then
            # Debian's locale-gen takes no arguments: it generates what /etc/locale.gen lists
            for l in $LOCALES; do
                sed -i "s/^# *\($l UTF-8\)\$/\1/" /etc/locale.gen
                grep -qx "$l UTF-8" /etc/locale.gen || fail "$l missing in /etc/locale.gen"
            done
            locale-gen || fail "locale-gen failed"
        else
            # shellcheck disable=SC2086
            locale-gen $LOCALES || fail "locale-gen failed"
        fi
        useradd -m -s /bin/bash kb || fail "useradd kb failed"
        ;;
    dnf)
        # dnf.sh CORE + socat (the langpacks are in CORE)
        PKGS="bash git-core coreutils sed grep findutils diffutils gawk procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru socat"
        # shellcheck disable=SC2086
        retry dnf install -y $PKGS || fail "dnf install failed"
        useradd -m -s /bin/bash kb || fail "useradd kb failed"
        ;;
esac

[ -d /home/kb ] || fail "/home/kb does not exist"
cp -a /src /home/kb/kbool || fail "cannot copy /src to /home/kb/kbool"
chown -R kb:kb /home/kb/kbool || fail "chown failed"
command -v bash >/dev/null 2>&1 || fail "no bash in the image"
command -v su >/dev/null 2>&1 || fail "no su in the image"
bash --version | head -1
if [ -r /etc/os-release ]; then ( . /etc/os-release; echo "$PRETTY_NAME" ); fi

set +e
su kb -c 'cd ~/kbool && bash ktests/tools/gate.sh --out ~/gate-out --rerun-failed 1 --timeout 900 all'
rc=$?
set -e
cp -a /home/kb/gate-out/. /out/ 2>/dev/null || true
exit "$rc"
