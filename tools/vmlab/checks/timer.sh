#!/usr/bin/env bash
# checks/timer.sh -- guest timer stall check (lab VMs; written for kb-alpine, card L1.7).
# 60 x `sleep 1` and 60 x `read -t 1` on an idle FIFO, each wait timed with BOTH
# EPOCHREALTIME (wall clock, us) and /proc/uptime (monotonic, 10 ms), so a wall-clock
# step can be told from a stall. overshoot = measured - 1000 ms.
#   upload:  vmlab.sh run VM -- sh -c 'cat > /tmp/timer.sh' < tools/vmlab/checks/timer.sh
#   run:     vmlab.sh run VM -- 'bash /tmp/timer.sh'          (about 2 min)
# Output (ms): "sleep n=60 min=.. med=.. p95=.. max=.. (uptime: p95=.. max=..)" and the
# same "read ..." line (nearest rank: med = 30th, p95 = 57th of 60 sorted), then an info
# block (kernel, clocksource, clockevent, kernel config, ntpd, dmesg lines).
# rc: 0 ok; 1 uptime-based p95 > 500 ms or max > 2000 ms in either series;
#     2 invalid measurement (a read returned before its timeout, or no FIFO).
export LC_ALL=C
N=${TIMER_N:-60}

d=$(mktemp -d) || { echo "timer.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$d"' EXIT
mkfifo "$d/f" || { echo "timer.sh: mkfifo failed" >&2; exit 2; }
exec 3<>"$d/f"

stat_line() {   # LABEL "wall values" "uptime values" -> prints line, sets P95UP MAXUP
  local label=$1 w u
  local -a ws us
  read -r -a ws < <(printf '%s\n' $2 | sort -n | tr '\n' ' ')
  read -r -a us < <(printf '%s\n' $3 | sort -n | tr '\n' ' ')
  local n=${#ws[@]} i50 i95
  i50=$(( (n * 50 + 99) / 100 - 1 )); i95=$(( (n * 95 + 99) / 100 - 1 ))
  printf '%s n=%d min=%d med=%d p95=%d max=%d (uptime: p95=%d max=%d)\n' "$label" "$n" \
    "${ws[0]}" "${ws[i50]}" "${ws[i95]}" "${ws[n-1]}" "${us[i95]}" "${us[n-1]}"
  (( ${us[i95]} > 500 || ${us[n-1]} > 2000 )) && BAD=1
}

uptime_cs() { local up _; read -r up _ </proc/uptime; up=${up/./}; echo $((10#$up)); }

BAD=0; INVALID=0
w_sleep=; u_sleep=; w_read=; u_read=
for ((i = 0; i < N; i++)); do
  t0=${EPOCHREALTIME//[.,]/}; c0=$(uptime_cs)
  sleep 1
  t1=${EPOCHREALTIME//[.,]/}; c1=$(uptime_cs)
  w_sleep="$w_sleep $(( (t1 - t0) / 1000 - 1000 ))"
  u_sleep="$u_sleep $(( (c1 - c0) * 10 - 1000 ))"
done
for ((i = 0; i < N; i++)); do
  t0=${EPOCHREALTIME//[.,]/}; c0=$(uptime_cs)
  read -t 1 -u 3 _x; rc=$?
  t1=${EPOCHREALTIME//[.,]/}; c1=$(uptime_cs)
  (( rc > 128 )) || INVALID=1
  w_read="$w_read $(( (t1 - t0) / 1000 - 1000 ))"
  u_read="$u_read $(( (c1 - c0) * 10 - 1000 ))"
done

stat_line sleep "$w_sleep" "$u_sleep"
stat_line read "$w_read" "$u_read"
if (( INVALID )); then echo "timer.sh: invalid measurement (a read did not time out)"; exit 2; fi

echo "--- info"
echo "uname -r: $(uname -r)"
echo "cmdline: $(cat /proc/cmdline)"
echo "current_clocksource: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>&1)"
echo "available_clocksource: $(cat /sys/devices/system/clocksource/clocksource0/available_clocksource 2>&1)"
echo "clockevent0: $(cat /sys/devices/system/clockevents/clockevent0/current_device 2>&1)"
if [[ -r /boot/config-$(uname -r) ]]; then
  grep -E '^CONFIG_(HZ=|NO_HZ|HZ_|HALTPOLL|CPU_IDLE)' "/boot/config-$(uname -r)"
else
  echo "(no /boot/config-$(uname -r))"
fi
echo "ntpd: $(ps | grep '[n]tpd' || echo none)"
{ dmesg 2>/dev/null || doas -n dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null || echo '(dmesg not readable)'; } \
  | grep -E 'clocksource|tsc|hpet|kvm-clock|\(dmesg not readable\)'
(( BAD )) && exit 1
exit 0
