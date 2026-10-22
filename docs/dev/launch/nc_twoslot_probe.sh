# two-slot probe, N runs per flavour: A listens, c1 connects and stays open,
# B listens on the same port, c2 connects; where does c2 land?
ulimit -v 1000000
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
one() { # LABEL ARGV... (PORT placeholder) -> prints B_bound c2_served_by
  local lab=$1; shift; local port=$(( 30000 + RANDOM % 20000 )) d="$T/$lab" wa wb c1 c2 pa pb
  local -a argv=("${@//PORT/$port}"); mkdir -p "$d"; mkfifo "$d/ina" "$d/inb"
  timeout -k 1 12 "${argv[@]}" <"$d/ina" >"$d/outa" 2>"$d/erra" & pa=$!; exec {wa}>"$d/ina"; sleep 0.4
  exec {c1}<>"/dev/tcp/127.0.0.1/$port" || { echo "c1fail"; return; }; printf 'one\n' >&$c1; sleep 0.3
  local lst; lst=$(ss -ltnH "sport = :$port" 2>/dev/null | wc -l)
  timeout -k 1 12 "${argv[@]}" <"$d/inb" >"$d/outb" 2>"$d/errb" & pb=$!; exec {wb}>"$d/inb"; sleep 0.4
  local bb=no; grep -qiE 'listening' "$d/errb" && bb=yes
  local lst2; lst2=$(ss -ltnH "sport = :$port" 2>/dev/null | wc -l)
  exec {c2}<>"/dev/tcp/127.0.0.1/$port" 2>/dev/null && printf 'two\n' >&$c2; sleep 0.4
  local who=none; grep -q two "$d/outb" && who=B; grep -q two "$d/outa" && who=A
  echo "listeners_during_A_conn=$lst after_B=$lst2 B_bound=$bb c2_served_by=$who"
  exec {wa}>&- {wb}>&- {c1}>&- ; { exec {c2}>&-; } 2>/dev/null; kill $pa $pb 2>/dev/null; wait $pa $pb 2>/dev/null; rm -rf "$d"
}
echo "== $(nc -h 2>&1 | head -1)"; for i in $(seq 20); do one obsd nc -l -N -v -n 127.0.0.1 PORT; done | sort | uniq -c
echo "== socat $(socat -V 2>/dev/null | grep -m1 version)"; for i in $(seq 10); do one socat socat -d -d TCP4-LISTEN:PORT,bind=127.0.0.1,reuseaddr STDIO; done | sort | uniq -c
echo "== ncat $(ncat --version 2>&1 | head -1)"; command -v ncat >/dev/null && for i in $(seq 10); do one ncat ncat -l -v -n 127.0.0.1 PORT; done | sort | uniq -c
