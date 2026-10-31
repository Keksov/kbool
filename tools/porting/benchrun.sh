#!/usr/bin/env bash
# benchrun.sh -- writes docs/dev/launch/bench.json (or --out FILE): what kbool costs, measured on THIS
# machine with THIS bash, each figure with the command behind it. Measures only; changes no library code.
#
# usage: benchrun.sh [--runs N] [--out FILE]      run from the kbool root with the bash under test:
#            bash tools/porting/benchrun.sh --out /tmp/bench.json
#        env BENCH_HEADS="root=abc1234 kcl=... kklass=... kkore=... ktests=..."  replaces the git short SHAs
#            (a lab VM gets the tree without .git/; the host passes its heads in)
# output: JSON {platform, bash, cpu, date, kbool_head, runs, headline:{ID:{value,unit,median_of,runs,source}},
#         raw:{"<bench path>":{exit,wall_ms,output}}}. A figure that could not be measured has "value": null
#         and a "reason" (never a guess).
#   headline: 14 figures, the median of N runs (default 3) of the machine-readable rows of the benches'
#             own output (an explicit pattern per figure below) and of in-process baselines.
#   raw:      the full output of ONE more run (after the N) of every kcl/*/bench.sh and
#             kklass/bench/kklass_bench.sh, with its exit code and wall time.
# Every bench runs under `timeout -k 10 600`; a failing bench does not stop the collector.
# exit: 0 ok, 2 node missing / bad usage
export LC_ALL=C

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUNS=3
OUT="$ROOT/docs/dev/launch/bench.json"

while (( $# )); do
    case $1 in
        --runs) RUNS=${2:-}; shift 2 || { echo "benchrun.sh: --runs needs a number" >&2; exit 2; } ;;
        --out)  OUT=${2:-};  shift 2 || { echo "benchrun.sh: --out needs a file" >&2; exit 2; } ;;
        -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "benchrun.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ $RUNS =~ ^[1-9][0-9]*$ ]] || { echo "benchrun.sh: --runs must be a positive integer" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "benchrun.sh: node not found" >&2; exit 2; }
[[ -f $ROOT/kbool.sh ]] || { echo "benchrun.sh: $ROOT/kbool.sh not found" >&2; exit 2; }

# Windows-style path for node when cygpath exists, else the path itself
wpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m -- "$1"; else printf '%s' "$1"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/benchrun.XXXXXX") || { echo "benchrun.sh: mktemp failed" >&2; exit 2; }
CHILD=""
cleanup() { [[ -n $CHILD ]] && kill "$CHILD" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

FIGS=$WORK/figs.tsv     # id <TAB> unit <TAB> source <TAB> run <TAB> value | NA:reason
RAWS=$WORK/raws.tsv     # bench path <TAB> exit <TAB> wall_ms <TAB> output file
: > "$FIGS"; : > "$RAWS"

now_us() { local t="${EPOCHREALTIME/[.,]/}"; NOW_US="${t#0}"; }
# fix1 US_TOTAL DIVISOR_US -> FIX="a.b" (value in units of DIVISOR_US, one decimal; no fork)
fix1() { local x10=$(( $1 * 10 / $2 )); FIX="$(( x10 / 10 )).$(( x10 % 10 ))"; }
# fix3 US_TOTAL ITERS -> FIX="a.bcd" (microseconds per iteration, three decimals)
fix3() { local x=$(( $1 * 1000 / $2 )); printf -v FIX '%d.%03d' $(( x / 1000 )) $(( x % 1000 )); }
fig() { # id unit source run value-or-NA:reason
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FIGS"
}

# run_bounded OUTFILE CMD... -> runs CMD under timeout -k 10 600 with stdout+stderr in OUTFILE; RC, WALL_MS set.
# The child is a recorded pid so the EXIT/INT/TERM trap can stop it.
run_bounded() {
    local of=$1 t0 t1; shift
    now_us; t0=$NOW_US
    timeout -k 10 600 "$@" > "$of" 2>&1 &
    CHILD=$!
    wait "$CHILD"; RC=$?
    CHILD=""
    now_us; t1=$NOW_US
    WALL_MS=$(( (t1 - t0) / 1000 ))
}

# pat FILE REGEX -> PAT="<first capture group>" of the first matching line; rc 1 when no line matches.
# bash [[ =~ ]], line by line, so one pattern is one explicit row of the bench's own output.
pat() {
    local line; PAT=""
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        if [[ $line =~ $2 ]]; then PAT=${BASH_REMATCH[1]}; return 0; fi
    done < "$1"
    return 1
}

# ---- the figures taken from a bench's own output ----------------------------------------------------
# one entry per figure: id | unit | file key | source text | row pattern (first group = the number)
# kklass_bench.sh rows are `  <label padded>  <n>.<d> us/<kind>  (total N ms)`
# tdictionary rows are `  <label padded>  <n> us/call  (a.bcd ms)`; tregex rows `  <label padded>  <n>.<d> us/call`
BENCH_KLASS=kklass/bench/kklass_bench.sh
BENCH_DICT=kcl/tdictionary/bench.sh
BENCH_REGEX=kcl/tregex/bench.sh
FIGSPEC=(
 "kklass_new|us/instance|K|row '.new (first 60)' of $BENCH_KLASS|^[[:space:]]*\.new \(first 60\)[[:space:]]+([0-9]+\.[0-9]+) us/inst"
 "kklass_method_call|us/call|K|row 'method call (echo body)' of $BENCH_KLASS|^[[:space:]]*method call \(echo body\)[[:space:]]+([0-9]+\.[0-9]+) us/call"
 "kklass_property_read|us/read|K|row 'property read' of $BENCH_KLASS|^[[:space:]]*property read[[:space:]]+([0-9]+\.[0-9]+) us/read"
 "kklass_computed_read|us/read|K|row 'computed read @1000 live' of $BENCH_KLASS|^[[:space:]]*computed read @1000 live \(F7: forks per read\)[[:space:]]+([0-9]+\.[0-9]+) us/read"
 "kklass_delete_at_1000|us/delete|K|row '.delete @1000 live instances' of $BENCH_KLASS|^[[:space:]]*\.delete @1000 live instances \([0-9]+ fns\)[[:space:]]+([0-9]+\.[0-9]+) us/del"
 "tdictionary_add|us/op|D|row 'Add (insert)' of $BENCH_DICT|^[[:space:]]*Add \(insert\)[[:space:]]+([0-9]+) us/call"
 "tdictionary_get|us/op|D|row 'GetItem (direct call)' of $BENCH_DICT|^[[:space:]]*GetItem \(direct call\)[[:space:]]+([0-9]+) us/call"
 "tregex_ismatch|us/op|R|row 'TRegEx.isMatch (static-proc dispatch)' of $BENCH_REGEX|^[[:space:]]*TRegEx\.isMatch \(static-proc dispatch\)[[:space:]]+([0-9]+\.[0-9]+) us/call"
)
declare -A KEYFILE_RUN=()

extract_figs() { # run-index ; reads $WORK/bench-K-<run>.txt etc.
    local run=$1 spec id unit key src rx f rcf
    for spec in "${FIGSPEC[@]}"; do
        IFS='|' read -r id unit key src rx <<< "$spec"
        # the regexes contain no '|' : the spec is split on it above
        f=$WORK/bench-$key-$run.txt; rcf=$WORK/bench-$key-$run.rc
        if [[ ! -s $f ]]; then fig "$id" "$unit" "$src" "$run" "NA:no output from the bench"; continue; fi
        if pat "$f" "$rx"; then
            fig "$id" "$unit" "$src" "$run" "$PAT"
        else
            fig "$id" "$unit" "$src" "$run" "NA:pattern did not match any line of the bench output (bench exit $(< "$rcf"))"
        fi
    done
}

# ---- in-process baselines ------------------------------------------------------------------------------
__empty_fn() { :; }
FN_ITERS=100000
CS_ITERS=200
LOAD_REPEAT=5

load_ms() { # CODE  -> LOAD_MS_FIX = mean wall ms over LOAD_REPEAT fresh `bash -c CODE`, or LOAD_MS_ERR=reason
    local i t0 t1 tot=0 rc
    LOAD_MS_FIX=""; LOAD_MS_ERR=""
    for (( i = 0; i < LOAD_REPEAT; i++ )); do
        now_us; t0=$NOW_US
        "$BASH" -c "$1" _ "$ROOT" > "$WORK/load.out" 2>&1; rc=$?
        now_us; t1=$NOW_US
        if (( rc != 0 )); then LOAD_MS_ERR="child exit $rc: $(head -c 200 "$WORK/load.out" | tr '\n' ' ')"; return 1; fi
        tot=$(( tot + t1 - t0 ))
    done
    fix1 $(( tot / LOAD_REPEAT )) 1000; LOAD_MS_FIX=$FIX
}

SRC_FN="a loop of $FN_ITERS calls of an empty function f() { :; } in this shell, EPOCHREALTIME around the loop (no fork inside; the loop's own cost is included)"
SRC_CS="a loop of $CS_ITERS x=\$(true) in this shell, EPOCHREALTIME around the loop (one fork per iteration)"
SRC_SRC="EPOCHREALTIME around a child '$BASH -c \"source KBOOL/kbool.sh\"' started from this shell; mean of $LOAD_REPEAT children per run (includes the child's bash start-up)"
SRC_TSL="EPOCHREALTIME around a child '$BASH -c \"source KBOOL/kbool.sh; kk.uses tstringlist\"'; mean of $LOAD_REPEAT children per run (includes the child's bash start-up)"
SRC_DU="EPOCHREALTIME around a child '$BASH -c \"source KBOOL/kbool.sh; kk.uses dateutils\"'; mean of $LOAD_REPEAT children per run (includes the child's bash start-up)"

# the 15-method Pascal-DSL class: no row in kklass_bench.sh, measured here with generated classes
DSL_CLASSES=10
SRC_DSL="generated in benchrun.sh (kklass_bench.sh has no such row): $DSL_CLASSES distinct classes, each 'class TBenchPN / public / var A / var B / 15 x proc / end', its 15 method bodies as functions and 'build TBenchPN' (the fork-free build of kklass_pascal.sh), eval'd in one shell after kk.uses kklass_pascal; EPOCHREALTIME around the $DSL_CLASSES evals, mean per class (text generation is outside the timing)"

dsl_build_ms() { # run-index -> prints nothing; sets DSL_FIX or DSL_ERR. Runs in a fresh child shell so classes do not accumulate across runs.
    local run=$1 gen="$WORK/dsl-gen.sh" rc
    cat > "$gen" <<'EOS'
ROOT=$1; RUN=$2; NCLS=$3
source "$ROOT/kbool.sh" || exit 11
kk.uses kklass_pascal || exit 12
now_us() { local t="${EPOCHREALTIME/[.,]/}"; NOW_US="${t#0}"; }
texts=()
for (( c = 0; c < NCLS; c++ )); do
    n="TBenchP${RUN}N$c"
    txt="class $n"$'\n    public\n        var A\n        var B\n'
    for (( i = 1; i <= 15; i++ )); do txt+="        proc M$i"$'\n'; done
    txt+=$'end\n'
    for (( i = 1; i <= 15; i++ )); do txt+="$n.M$i() { echo m$i \$A; }"$'\n'; done
    txt+="build $n"
    texts+=("$txt")
done
now_us; t0=$NOW_US
for (( c = 0; c < NCLS; c++ )); do eval "${texts[c]}" || exit 13; done
now_us; t1=$NOW_US
# the last class must work, or the figure is void
"TBenchP${RUN}N$((NCLS - 1)).new" chk || exit 14
chk.M15 > /dev/null || exit 15
x=$(( (t1 - t0) * 10 / NCLS / 1000 ))
printf '%d.%d\n' $(( x / 10 )) $(( x % 10 ))
EOS
    DSL_FIX=$("$BASH" "$gen" "$ROOT" "$run" "$DSL_CLASSES" 2> "$WORK/dsl.err"); rc=$?
    DSL_ERR=""
    if (( rc != 0 )); then DSL_ERR="generator exit $rc: $(head -c 200 "$WORK/dsl.err" | tr '\n' ' ')"; DSL_FIX=""; fi
}

# ---- the N headline runs ----------------------------------------------------------------------------------
cd "$ROOT" || exit 2
echo "benchrun: $RUNS headline runs, then the raw pass (bash $BASH_VERSION)" >&2
for (( run = 1; run <= RUNS; run++ )); do
    echo "benchrun: run $run/$RUNS" >&2
    # baselines
    now_us; t0=$NOW_US
    for (( i = 0; i < FN_ITERS; i++ )); do __empty_fn; done
    now_us; t1=$NOW_US
    fix3 $(( t1 - t0 )) $FN_ITERS; fig empty_function_call us/call "$SRC_FN" $run "$FIX"
    now_us; t0=$NOW_US
    for (( i = 0; i < CS_ITERS; i++ )); do x=$(true); done
    now_us; t1=$NOW_US
    fix3 $(( t1 - t0 )) $CS_ITERS; fig command_substitution us/call "$SRC_CS" $run "$FIX"

    if load_ms 'source "$1/kbool.sh"'; then fig source_kbool ms "$SRC_SRC" $run "$LOAD_MS_FIX"
    else fig source_kbool ms "$SRC_SRC" $run "NA:$LOAD_MS_ERR"; fi
    if load_ms 'source "$1/kbool.sh" && kk.uses tstringlist'; then fig uses_tstringlist ms "$SRC_TSL" $run "$LOAD_MS_FIX"
    else fig uses_tstringlist ms "$SRC_TSL" $run "NA:$LOAD_MS_ERR"; fi
    if load_ms 'source "$1/kbool.sh" && kk.uses dateutils'; then fig uses_dateutils ms "$SRC_DU" $run "$LOAD_MS_FIX"
    else fig uses_dateutils ms "$SRC_DU" $run "NA:$LOAD_MS_ERR"; fi

    dsl_build_ms $run
    if [[ -n $DSL_FIX ]]; then fig pascal_class_build_15_methods ms "$SRC_DSL" $run "$DSL_FIX"
    else fig pascal_class_build_15_methods ms "$SRC_DSL" $run "NA:$DSL_ERR"; fi

    # the three benches the figures are read from
    for kv in "K:$BENCH_KLASS" "D:$BENCH_DICT" "R:$BENCH_REGEX"; do
        key=${kv%%:*}; b=${kv#*:}
        run_bounded "$WORK/bench-$key-$run.txt" "$BASH" "$ROOT/$b"
        echo "$RC" > "$WORK/bench-$key-$run.rc"
    done
    extract_figs $run
done

# ---- the raw pass: ONE run of every bench ------------------------------------------------------------------
n=0
for b in "$BENCH_KLASS" $(cd "$ROOT" && ls kcl/*/bench.sh | sort); do
    n=$(( n + 1 ))
    echo "benchrun: raw $b" >&2
    run_bounded "$WORK/raw-$n.txt" "$BASH" "$ROOT/$b"
    printf '%s\t%s\t%s\t%s\n' "$b" "$RC" "$WALL_MS" "$(wpath "$WORK/raw-$n.txt")" >> "$RAWS"
done

# ---- meta -------------------------------------------------------------------------------------------------------
platform_uname=$(uname -srm 2>/dev/null)
case $platform_uname in
    MINGW*|MSYS*|CYGWIN*)
        rootw=$(cygpath -w / 2>/dev/null | tr 'A-Z' 'a-z')
        case $rootw in
            *msys*) PLATFORM="Windows (MSYS2) - $platform_uname" ;;
            *git*)  PLATFORM="Windows (Git-bash) - $platform_uname" ;;
            *)      PLATFORM="Windows - $platform_uname" ;;
        esac ;;
    *)
        pretty=""
        [[ -r /etc/os-release ]] && pretty=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-}")
        PLATFORM="${pretty:+$pretty - }$platform_uname" ;;
esac
CPU=unknown
if [[ -r /proc/cpuinfo ]]; then
    while IFS= read -r line; do
        if [[ $line == "model name"*:* ]]; then CPU=${line#*:}; CPU=${CPU# }; break; fi
    done < /proc/cpuinfo
fi
HEADS=""
if [[ -n ${BENCH_HEADS:-} ]]; then
    HEADS=$BENCH_HEADS
else
    for r in root:. kcl:kcl kklass:kklass kkore:kkore ktests:ktests; do
        nm=${r%%:*}; dir=$ROOT/${r#*:}
        sha=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null) || sha=unknown
        if [[ $sha != unknown ]] && [[ -n $(git -C "$dir" status --porcelain 2>/dev/null) ]]; then sha+="-dirty"; fi
        HEADS+="${HEADS:+ }$nm=$sha"
    done
fi
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- the JSON (built by node, LF only) -----------------------------------------------------------------------
read -r -d '' JS <<'EOF'
const fs = require("fs");
const [figsF, rawsF, outF] = process.argv.slice(1, 4);
const env = process.env;
const lines = f => fs.readFileSync(f, "utf8").split("\n").filter(l => l !== "");
const order = [], by = {};
for (const l of lines(figsF)) {
    const [id, unit, source, run, val] = l.split("\t");
    if (!by[id]) { by[id] = { unit, source, runs: [], reasons: [] }; order.push(id); }
    const f = by[id];
    if (val.startsWith("NA:")) { f.runs[Number(run) - 1] = null; f.reasons.push("run " + run + ": " + val.slice(3)); }
    else f.runs[Number(run) - 1] = Number(val);
}
const headline = {};
for (const id of order) {
    const f = by[id], ok = f.runs.filter(v => v !== null).sort((a, b) => a - b);
    let value = null;
    if (ok.length) value = ok.length % 2 ? ok[(ok.length - 1) / 2] : (ok[ok.length / 2 - 1] + ok[ok.length / 2]) / 2;
    const o = { value, unit: f.unit, median_of: ok.length, runs: f.runs, source: f.source };
    if (f.reasons.length) o.reason = f.reasons.join("; ");
    headline[id] = o;
}
const raw = {};
for (const l of lines(rawsF)) {
    const [b, rc, wall, file] = l.split("\t");
    raw[b] = { exit: Number(rc), wall_ms: Number(wall), output: fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n") };
}
const heads = {};
for (const kv of env.BR_HEADS.split(" ")) { const i = kv.indexOf("="); if (i > 0) heads[kv.slice(0, i)] = kv.slice(i + 1); }
const doc = {
    platform: env.BR_PLATFORM, bash: env.BR_BASH, cpu: env.BR_CPU, date: env.BR_DATE,
    kbool_head: heads, runs: Number(env.BR_RUNS), headline, raw
};
fs.writeFileSync(outF, JSON.stringify(doc, null, 2) + "\n");
EOF
mkdir -p "$(dirname "$OUT")" 2>/dev/null
BR_PLATFORM=$PLATFORM BR_BASH=$BASH_VERSION BR_CPU=$CPU BR_DATE=$DATE BR_HEADS=$HEADS BR_RUNS=$RUNS \
    node -e "$JS" "$(wpath "$FIGS")" "$(wpath "$RAWS")" "$(wpath "$OUT")" || { echo "benchrun.sh: node failed" >&2; exit 2; }
echo "benchrun: wrote $OUT" >&2
exit 0
