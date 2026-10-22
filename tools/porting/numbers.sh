#!/usr/bin/env bash
# numbers.sh -- writes docs/dev/launch/numbers.json: every project figure the
# README (L6.5) and the announcement (L8.5) quote, each as
# {"value": ..., "source": "<exact command or file>"}.
# A SNAPSHOT: heads and counts go stale at the next commit; rerun before quoting.
#
# usage: numbers.sh [--gate OUT_DIR] [--out FILE]
# exit:  0 ok, 2 node missing / bad usage, 3 BLOCKED (no PASS gate, data not as expected)
export LC_ALL=C

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GATE_ARG=""
OUT="$ROOT/docs/dev/launch/numbers.json"

while (( $# )); do
    case $1 in
        --gate) GATE_ARG=${2:-}; shift 2 || { echo "numbers.sh: --gate needs a directory" >&2; exit 2; } ;;
        --out)  OUT=${2:-};      shift 2 || { echo "numbers.sh: --out needs a file" >&2; exit 2; } ;;
        -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "numbers.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v node >/dev/null 2>&1 || { echo "numbers.sh: node not found" >&2; exit 2; }

# Windows-style path for node when cygpath exists, else the path itself
wpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m -- "$1"; else printf '%s' "$1"; fi; }

# --- JSON helpers (compact JSON is built here; node pretty-prints it at the end)
jesc() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; printf '%s' "$s"; }
jstr() { printf '"%s"' "$(jesc "$1")"; }
jbool() { if [[ $1 == 1 ]]; then printf 'true'; else printf 'false'; fi; }
# leaf VALUE_JSON SOURCE_TEXT
leaf() { printf '{"value":%s,"source":%s}' "$1" "$(jstr "$2")"; }
# jarr word... -> ["a","b"]
jarr() { local out="" w; for w in "$@"; do out+="${out:+,}$(jstr "$w")"; done; printf '[%s]' "$out"; }
die3() { echo "numbers.sh: BLOCKED: $*" >&2; exit 3; }

# --- 1. the gate OUT -------------------------------------------------------
gate_kind() { # summary.json (native path) -> prints "<verdict> all" when the gate ran the whole tree (argv has "all")
    node -e 'try{const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(j.verdict)+(j.gate.argv.includes("all")?" all":" partial"))}catch(e){process.stdout.write("?")}' "$1"
}
gate_ok() { # dir -> 0 when progress.txt ends with a PASS line and summary.json says PASS for an "all" gate
    local d=$1 last
    [[ -f $d/progress.txt && -f $d/summary.json ]] || return 1
    last=$(tail -n 1 "$d/progress.txt")
    [[ $last == __GATE__:PASS:* ]] || return 1
    [[ $(gate_kind "$(wpath "$d/summary.json")") == "PASS all" ]]
}

if [[ -n $GATE_ARG ]]; then
    GATE_DIR=${GATE_ARG%/}
    [[ -d $GATE_DIR ]] || die3 "--gate: not a directory: $GATE_ARG"
    gate_ok "$GATE_DIR" || die3 "--gate $GATE_ARG is not a PASS gate OUT of the whole tree (progress.txt last line __GATE__:PASS:..., summary.json verdict PASS and argv containing 'all')"
else
    if [[ -n ${TMPDIR:-} ]]; then
        ROOT_TMP=$TMPDIR
    elif command -v cygpath >/dev/null 2>&1; then
        ROOT_TMP="$(cygpath -u -F 28)/Temp"
    else
        ROOT_TMP=/tmp
    fi
    GATE_DIR=""
    if [[ -d $ROOT_TMP/kt-gate ]]; then
        while IFS= read -r name; do
            [[ -d $ROOT_TMP/kt-gate/$name ]] || continue
            if gate_ok "$ROOT_TMP/kt-gate/$name"; then GATE_DIR=$ROOT_TMP/kt-gate/$name; break; fi
        done < <(ls -1 "$ROOT_TMP/kt-gate" | sort -r)
    fi
    [[ -n $GATE_DIR ]] || die3 "no PASS gate OUT of the whole tree under $ROOT_TMP/kt-gate (need progress.txt last line __GATE__:PASS:..., summary.json verdict PASS and argv containing 'all'); pass --gate OUT_DIR"
fi

read -r -d '' JS_TESTS <<'EOF'
const fs = require("fs");
const die = m => { process.stderr.write("numbers.sh: BLOCKED: " + m + "\n"); process.exit(3); };
const sum = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const cells = fs.readFileSync(process.argv[2], "utf8").split("\n").filter(l => l !== "");
const prog = fs.readFileSync(process.argv[3], "utf8").split("\n").filter(l => l !== "");
const L = (value, source) => ({ value, source });
const out = sum.gate.out, sj = out + "/summary.json", ct = out + "/cells.tsv", pt = out + "/progress.txt";
const hdr = cells[0].split("\t");
const col = n => { const i = hdr.indexOf(n); if (i < 0) die("cells.tsv has no column " + n); return i; };
const ib = col("bash_version"), is = col("suite"), it = col("total"), ir = col("repeat"), idur = col("duration_ms");
const vers = sum.bashes.map(b => b.version);
const per = {}, seen = {}, dur = {};
for (const v of vers) { per[v] = {}; dur[v] = 0; }
for (const l of cells.slice(1)) {
    const f = l.split("\t"), v = f[ib], s = f[is];
    if (!(v in per)) die("cells.tsv: bash_version " + v + " not in summary.json .bashes");
    const k = v + "\t" + s;
    if (seen[k]) die("cells.tsv: (bash_version, suite) appears twice: " + v + " " + s);
    seen[k] = 1;
    if (f[ir] === undefined) die("cells.tsv: short row for " + v + " " + s);
    const t = Number(f[it]), d = Number(f[idur]);
    if (!Number.isFinite(t) || !Number.isFinite(d)) die("cells.tsv: non-numeric total/duration for " + v + " " + s);
    per[v][s] = t; dur[v] += d;
}
const want = sum.gate.options.suites;
for (const v of vers) {
    const have = Object.keys(per[v]);
    if (have.length !== want.length || !want.every(s => s in per[v]))
        die("cells.tsv: runtime " + v + " does not have exactly one row per suite of gate.options.suites (" + have.length + " rows, " + want.length + " suites)");
}
const runtimes = {}, per_suite = {}, suites = {};
let both = 0;
for (const v of vers) {
    const t = sum.totals[v], src = k => sj + " .totals[\"" + v + "\"]." + k;
    runtimes[v] = {
        total_tests: L(t.total_tests, src("total_tests")),
        passed_tests: L(t.passed_tests, src("passed_tests")),
        cells: L(t.cells, src("cells")),
        duration_ms: L(t.duration_ms, src("duration_ms") + " (the gate's own total of the cells' durations, not wall time; the cells.tsv duration_ms column itself sums to " + dur[v] + ")")
    };
    both += t.total_tests;
    per_suite[v] = L(per[v], ct + " (columns bash_version=" + v + ", suite, total)");
    suites[v] = L(Object.keys(per[v]).length, ct + " (distinct suite ids, bash_version=" + v + ")");
}
const last = prog[prog.length - 1];
if (!last.startsWith("__GATE__:")) die("progress.txt last line is not a __GATE__ line");
process.stdout.write(JSON.stringify({
    runtimes,
    total_both_runtimes: L(both, "sum of .totals[*].total_tests in " + sj),
    gate: {
        out: L(sum.gate.out, sj + " .gate.out"),
        line: L(last, pt + " (last line; VERDICT:cells:pass:fail:flaky:env:timeout:stray:passed:total, combined over the runtimes)"),
        verdict: L(sum.verdict, sj + " .verdict"),
        exit: L(sum.exit, sj + " .exit"),
        repos: L(sum.gate.repos, sj + " .gate.repos")
    },
    per_suite,
    suites
}));
EOF

read -r -d '' JS_WIN <<'EOF'
const fs = require("fs");
const sum = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const name = p => { const b = String(p).replace(/\\/g, "/").split("/").filter(x => x).pop().toLowerCase();
    return b === "git" ? "Git-bash" : b.startsWith("msys") ? "MSYS2" : b; };
process.stdout.write(JSON.stringify({
    value: sum.bashes.map(b => ({ name: name(b.runtime), bash: b.version })),
    source: sum.gate.out + "/summary.json .bashes"
}));
EOF

read -r -d '' JS_LEDGERS <<'EOF'
const fs = require("fs"), path = require("path");
const root = process.argv[1];
const res = [];
for (const a of process.argv.slice(2)) {
    const i = a.indexOf(":"), repo = a.slice(0, i), rel = a.slice(i + 1);
    const dir = repo === "kbool" ? root : path.join(root, repo);
    let j;
    try { j = JSON.parse(fs.readFileSync(path.join(dir, rel), "utf8")); }
    catch (e) { process.stderr.write("numbers.sh: BLOCKED: ledger " + repo + "/" + rel + " does not parse\n"); process.exit(3); }
    const p = j.phases;
    const phases = Array.isArray(p) ? { kind: "array", count: p.length }
        : (p !== null && typeof p === "object") ? { kind: "object", count: Object.keys(p).length }
        : { kind: null, count: null };
    res.push({ repo, path: rel, phases, named_rounds: Object.keys(j).filter(k => /^round[0-9]+$/.test(k)).length });
}
process.stdout.write(JSON.stringify(res));
EOF

read -r -d '' JS_FMT <<'EOF'
const fs = require("fs"), path = require("path");
const obj = JSON.parse(fs.readFileSync(0, "utf8"));
const isLeaf = o => o && typeof o === "object" && !Array.isArray(o) && Object.keys(o).length === 2 && "value" in o && "source" in o;
function fmt(o, ind) {
    if (isLeaf(o)) {
        const v = o.value, s = JSON.stringify(o.source);
        if (Array.isArray(v) && v.some(x => x && typeof x === "object"))
            return '{"value": [\n' + v.map(x => ind + "    " + JSON.stringify(x)).join(",\n") + "\n" + ind + '  ], "source": ' + s + "}";
        return '{"value": ' + JSON.stringify(v) + ', "source": ' + s + "}";
    }
    if (o && typeof o === "object" && !Array.isArray(o))
        return "{\n" + Object.keys(o).map(k => ind + "  " + JSON.stringify(k) + ": " + fmt(o[k], ind + "  ")).join(",\n") + "\n" + ind + "}";
    return JSON.stringify(o);
}
const file = process.argv[1];
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, fmt(obj, "") + "\n");
EOF

TESTS_JSON=$(node -e "$JS_TESTS" "$(wpath "$GATE_DIR/summary.json")" "$(wpath "$GATE_DIR/cells.tsv")" "$(wpath "$GATE_DIR/progress.txt")") || exit $?
WIN_JSON=$(node -e "$JS_WIN" "$(wpath "$GATE_DIR/summary.json")") || exit $?

# --- 2. repos --------------------------------------------------------------
REPOS=(kbool kcl kklass kkore ktests)
repo_dir() { if [[ $1 == kbool ]]; then printf '%s' "$ROOT"; else printf '%s' "$ROOT/$1"; fi; }
repo_cmd() { if [[ $1 == kbool ]]; then printf '%s' "$2"; else printf '(cd %s && %s)' "$1" "$2"; fi; }

REPOS_JSON=""
KBOOL_HEAD=""; KBOOL_DIRTY=0
for r in "${REPOS[@]}"; do
    d=$(repo_dir "$r")
    cd "$d" || die3 "cannot cd to $d"
    commits=$(git rev-list --count HEAD)
    head=$(git log -1 --format=%h)
    dirty=0; [[ -n $(git status --porcelain --untracked-files=no) ]] && dirty=1
    mapfile -t dates < <(git log --format=%ad --date=short | sort)
    first=${dates[0]}; last=${dates[${#dates[@]}-1]}
    tracked=$(git ls-files | wc -l | tr -d ' ')
    sh_files=$(git ls-files -z -- '*.sh' | tr -cd '\0' | wc -c | tr -d ' ')
    md_files=$(git ls-files -z -- '*.md' | tr -cd '\0' | wc -c | tr -d ' ')
    sh_lines=0; (( sh_files > 0 )) && sh_lines=$(git ls-files -z -- '*.sh' | xargs -0 cat | wc -l | tr -d ' ')
    md_lines=0; (( md_files > 0 )) && md_lines=$(git ls-files -z -- '*.md' | xargs -0 cat | wc -l | tr -d ' ')
    tnote=""
    [[ $r == kbool ]] && tnote=" (counts the 4 submodule gitlinks and .gitmodules)"
    if [[ $r == kbool ]]; then KBOOL_HEAD=$head; KBOOL_DIRTY=$dirty; fi
    REPOS_JSON+="${REPOS_JSON:+,}$(jstr "$r"):{"
    REPOS_JSON+="\"commits\":$(leaf "$commits" "$(repo_cmd "$r" 'git rev-list --count HEAD')"),"
    REPOS_JSON+="\"head\":$(leaf "$(jstr "$head")" "$(repo_cmd "$r" 'git log -1 --format=%h')"),"
    REPOS_JSON+="\"dirty\":$(leaf "$(jbool "$dirty")" "$(repo_cmd "$r" 'git status --porcelain --untracked-files=no')"" non-empty (tracked files only; for kbool a modified submodule counts)"),"
    REPOS_JSON+="\"first_commit_date\":$(leaf "$(jstr "$first")" "$(repo_cmd "$r" "git log --format=%ad --date=short | sort")"" first line (author date)"),"
    REPOS_JSON+="\"last_commit_date\":$(leaf "$(jstr "$last")" "$(repo_cmd "$r" "git log --format=%ad --date=short | sort")"" last line (author date)"),"
    REPOS_JSON+="\"tracked_files\":$(leaf "$tracked" "$(repo_cmd "$r" 'git ls-files | wc -l')$tnote"),"
    REPOS_JSON+="\"sh_files\":$(leaf "$sh_files" "$(repo_cmd "$r" "git ls-files -z -- '*.sh'")"" (NUL count)"),"
    REPOS_JSON+="\"sh_lines\":$(leaf "$sh_lines" "$(repo_cmd "$r" "git ls-files -z -- '*.sh' | xargs -0 cat | wc -l")"" (= sum of the totals of xargs -0 wc -l)"),"
    REPOS_JSON+="\"md_files\":$(leaf "$md_files" "$(repo_cmd "$r" "git ls-files -z -- '*.md'")"" (NUL count)"),"
    REPOS_JSON+="\"md_lines\":$(leaf "$md_lines" "$(repo_cmd "$r" "git ls-files -z -- '*.md' | xargs -0 cat | wc -l")"" (= sum of the totals of xargs -0 wc -l)")"
    REPOS_JSON+="}"
done
cd "$ROOT" || exit 1

# --- 3. units --------------------------------------------------------------
# unit files of a repo (cwd = the repo): tracked *.sh outside tests/ and examples/
# whose first 512 bytes hold a line beginning "kk.unit "; prints the paths
unit_files() {
    local f h
    while IFS= read -r -d '' f; do
        [[ /$f == */tests/* || /$f == */examples/* ]] && continue
        h=""
        IFS= read -r -d '' -N 512 h < "$f"
        [[ $'\n'$h == *$'\n'kk.unit\ * ]] && printf '%s\n' "$f"
    done < <(git ls-files -z -- '*.sh')
}

cd "$ROOT/kcl" || die3 "cannot cd to kcl"
mapfile -t KCL_UNITS < <(unit_files)
declare -A seen_dir=()
KCL_FOLDERS=(); KCL_NAMES=()
for f in "${KCL_UNITS[@]}"; do
    b=${f##*/}; KCL_NAMES+=("${b%.sh}")
    if [[ $f == */* ]]; then
        dir=${f%%/*}
        if [[ -z ${seen_dir[$dir]:-} ]]; then seen_dir[$dir]=1; KCL_FOLDERS+=("$dir"); fi
    fi
done
mapfile -t KCL_FOLDERS < <(printf '%s\n' "${KCL_FOLDERS[@]}" | sort)
mapfile -t KCL_NAMES < <(printf '%s\n' "${KCL_NAMES[@]}" | sort)
cd "$ROOT/kklass" || die3 "cannot cd to kklass"
mapfile -t KK_UNITS < <(unit_files)
KK_NAMES=(); for f in "${KK_UNITS[@]}"; do b=${f##*/}; KK_NAMES+=("${b%.sh}"); done
mapfile -t KK_NAMES < <(printf '%s\n' "${KK_NAMES[@]}" | sort)
cd "$ROOT" || exit 1

SYS_LINE=$(grep -n 'for __kk_m in kuse klib kerr kvar kcfg' kbool.sh | head -n 1)
[[ -n $SYS_LINE ]] || die3 "kbool.sh no longer has the 'for __kk_m in kuse klib kerr kvar kcfg' line"
SYS_NO=${SYS_LINE%%:*}
SYS_TXT=${SYS_LINE#*:}; SYS_TXT=${SYS_TXT#*" in "}; SYS_TXT=${SYS_TXT%%;*}
read -r -a KO_NAMES <<< "$SYS_TXT"

UNIT_NOTE="a unit file = a tracked *.sh outside tests/ and examples/ whose first 512 bytes hold a line beginning 'kk.unit '"
UNITS_JSON="\"kcl\":{"
UNITS_JSON+="\"folders\":$(leaf "{\"count\":${#KCL_FOLDERS[@]},\"names\":$(jarr "${KCL_FOLDERS[@]}")}" "kcl/<dir>/ holding at least one unit file; $UNIT_NOTE"),"
UNITS_JSON+="\"unit_files\":$(leaf "{\"count\":${#KCL_NAMES[@]},\"names\":$(jarr "${KCL_NAMES[@]}")}" "$UNIT_NOTE (cd kcl; git ls-files -z -- '*.sh'; names without .sh)")"
UNITS_JSON+="},\"kklass\":{"
UNITS_JSON+="\"unit_files\":$(leaf "{\"count\":${#KK_NAMES[@]},\"names\":$(jarr "${KK_NAMES[@]}")}" "$UNIT_NOTE (cd kklass; git ls-files -z -- '*.sh'; names without .sh)")"
UNITS_JSON+="},\"kkore\":{"
UNITS_JSON+="\"system_units\":$(leaf "{\"count\":${#KO_NAMES[@]},\"names\":$(jarr "${KO_NAMES[@]}")}" "kbool.sh:$SYS_NO (the for-loop over the system units; kuse.sh is the loader and carries no kk.unit line)")"
UNITS_JSON+="}"

# --- 4. examples -----------------------------------------------------------
EX_N=$(git -C kklass ls-files 'examples/[0-9]*.sh' | wc -l | tr -d ' ')
TH_N=$(git -C kcl ls-files 'thttpserver/examples/*.sh' | wc -l | tr -d ' ')

# --- 5. platforms ----------------------------------------------------------
VMLAB_README=tools/vmlab/README.md
vm() { # name os bash os_token bash_token
    local name=$1 os=$2 bsh=$3
    grep -qF -- "$4" "$VMLAB_README" || echo "numbers.sh: warning: $VMLAB_README no longer mentions '$4'" >&2
    grep -qF -- "$5" "$VMLAB_README" || echo "numbers.sh: warning: $VMLAB_README no longer mentions '$5'" >&2
    printf '%s:%s' "$(jstr "$name")" "$(leaf "{\"os\":$(jstr "$os"),\"bash\":$(jstr "$bsh")}" "$VMLAB_README \"## $name\" / \"### Versions recorded at creation\"")"
}
VMS_JSON="$(vm kb-ubuntu 'Ubuntu 24.04.5 LTS' 5.2.21 '24.04.5' '5.2.21'),"
VMS_JSON+="$(vm kb-debian 'Debian GNU/Linux 13.7 (trixie)' 5.2.37 '13.7' '5.2.37'),"
VMS_JSON+="$(vm kb-fedora 'Fedora 44' 5.3.9 'Fedora release 44' '5.3.9'),"
VMS_JSON+="$(vm kb-freebsd 'FreeBSD 15.1-RELEASE' 5.3.20 '15.1-RELEASE' '5.3.20'),"
VMS_JSON+="$(vm kb-alpine 'Alpine Linux 3.24.2' 5.3.9 '3.24.2' '5.3.9')"
LAUNCH_LEDGER=docs/dev/launch_ledger.json
WIN_OS=$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).baseline.os||""))' "$(wpath "$ROOT/$LAUNCH_LEDGER")")
[[ -n $WIN_OS ]] || die3 "$LAUNCH_LEDGER has no baseline.os (the Windows host OS string)"
PLATFORMS_JSON="{\"note\":\"provisioned lab VMs and Windows runtimes; gate results are the ledger's, not this file's\","
PLATFORMS_JSON+="\"vms\":{$VMS_JSON},"
PLATFORMS_JSON+="\"windows\":{\"runtimes\":$WIN_JSON,\"os\":$(leaf "$(jstr "$WIN_OS")" "$LAUNCH_LEDGER baseline.os")}}"

# --- 6. ledgers ------------------------------------------------------------
LEDGER_ARGS=()
for r in "${REPOS[@]}"; do
    while IFS= read -r p; do
        LEDGER_ARGS+=("$r:$p")
    done < <(git -C "$(repo_dir "$r")" ls-files | grep '_ledger\.json$' | sort)
done
LEDGERS_VALUE=$(node -e "$JS_LEDGERS" "$(wpath "$ROOT")" "${LEDGER_ARGS[@]}") || exit $?

# --- 7. assemble -----------------------------------------------------------
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOST=$(hostname)
ALL="{\"tests\":$TESTS_JSON"
ALL+=",\"repos\":{$REPOS_JSON}"
ALL+=",\"units\":{$UNITS_JSON}"
ALL+=",\"examples\":$(leaf "$EX_N" "git -C kklass ls-files 'examples/[0-9]*.sh' | wc -l")"
ALL+=",\"thttpserver_examples\":$(leaf "$TH_N" "git -C kcl ls-files 'thttpserver/examples/*.sh' | wc -l")"
ALL+=",\"platforms\":$PLATFORMS_JSON"
ALL+=",\"ledgers\":$(leaf "$LEDGERS_VALUE" "git -C <repo> ls-files | grep '_ledger\\.json\$' | sort, over kbool kcl kklass kkore ktests; each file parsed with node (phases = top-level key; named_rounds = top-level keys matching ^round[0-9]+\$)")"
ALL+=",\"generated\":{\"timestamp\":$(jstr "$TS"),\"host\":$(jstr "$HOST"),\"kbool_head\":$(jstr "$KBOOL_HEAD"),\"kbool_dirty\":$(jbool "$KBOOL_DIRTY")}}"

printf '%s' "$ALL" | node -e "$JS_FMT" "$(wpath "$OUT")" || exit $?
echo "numbers.sh: wrote $OUT (gate $GATE_DIR)" >&2
