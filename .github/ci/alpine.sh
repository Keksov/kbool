#!/bin/sh
# .github/ci/alpine.sh -- run the kbool gate inside an official bash:X image
# (Alpine/musl, the image's own bash in /usr/local/bin). Run as root:
#   docker run --rm -v "$PWD:/src:ro" -v "$OUT:/out" bash:X sh /src/.github/ci/alpine.sh
# Installs the GNU list of tools/vmlab/provision/apk.sh, copies the tree to a
# non-root user (the tests assume a normal user: chmod 000 does not stop root)
# and runs the gate there. The gate's OUT dir is copied to /out; the exit code
# is the gate's.
set -eu

GNU="git coreutils sed grep findutils diffutils gawk procps-ng util-linux perl curl openssl netcat-openbsd socat tzdata"
n=1
# shellcheck disable=SC2086
until apk add --no-cache $GNU; do
    [ "$n" -lt 5 ] || exit 3
    n=$((n + 1)); echo "alpine.sh: retry $n/5: apk add"; sleep 5
done

adduser -D -s /usr/local/bin/bash kb
cp -a /src /home/kb/kbool
chown -R kb:kb /home/kb/kbool
bash --version | head -1

set +e
su kb -c 'cd ~/kbool && bash ktests/tools/gate.sh --out ~/gate-out --rerun-failed 1 --timeout 900 all'
rc=$?
set -e
cp -a /home/kb/gate-out/. /out/ 2>/dev/null || true
exit "$rc"
