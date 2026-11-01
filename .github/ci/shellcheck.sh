#!/usr/bin/env bash
# .github/ci/shellcheck.sh -- the ShellCheck guard of ci.yml (job `lint`).
#
#     bash .github/ci/shellcheck.sh          # from the kbool root; SHELLCHECK=path overrides
#
# Not a general lint: a full ShellCheck run over kbool is >2000 findings, nearly
# all of them kbool's own idioms ($this.Method, `obj.Prop = v`, nameref locals,
# ${a[@]@a} guards, `>&$fd`). It runs only checks that are clean today, so a
# finding is new code bringing back a known bug pattern:
#   BASE    every .sh of the tree, tests included (not docs/: review repros):
#           bug patterns -- unquoted "$@"/$*, `for f in $(ls)`, `2>&1 >f`,
#           reading and writing one file in a pipeline, `local` outside a
#           function, impossible tests, unreachable case branches, `x=x`, ...
#   STRICT  kbool.sh, kkore/*.sh, kklass/*.sh (the core, not its examples/),
#           every kcl unit folder, examples/*.sh: also the
#           kcl contract's rc rules and plain-script hazards -- `local x=$(cmd)`
#           (SC2155, hides cmd's rc), `cd` without a check (SC2164), `read`
#           without -r (SC2162), word-split $(cmd) (SC2046, SC2207), `ls`
#           parsing (SC2010, SC2012), `~` in quotes (SC2088), ...
# A check that turns out to clash with an idiom is dropped from its list (say
# why in the commit), never silenced line by line.
# rc 0 = clean; 1 = findings (printed, and as ::error annotations under CI);
# 2 = no shellcheck.
set -u

SC=${SHELLCHECK:-shellcheck}
if ! "$SC" --version >/dev/null 2>&1; then
    echo "shellcheck.sh: no shellcheck (install it or set SHELLCHECK=path)" >&2
    exit 2
fi
"$SC" --version | sed -n 2p

BASE=SC2038,SC2044,SC2045,SC2048,SC2054,SC2068,SC2069,SC2070,SC2076,SC2081,SC2091,SC2094
BASE+=,SC2102,SC2105,SC2106,SC2107,SC2125,SC2140,SC2152,SC2157,SC2165,SC2168,SC2172,SC2193
BASE+=,SC2200,SC2201,SC2203,SC2205,SC2210,SC2211,SC2216,SC2217,SC2218,SC2219,SC2220
BASE+=,SC2221,SC2222,SC2242,SC2259,SC2260,SC2269,SC2270
STRICT=SC2006,SC2010,SC2012,SC2046,SC2066,SC2088,SC2116,SC2155,SC2162,SC2164,SC2207,SC2231

# lint LIST FIND-ARGS... : shellcheck -i LIST over the files find selects
lint() {
    local list=$1
    shift
    find "$@" -print0 | xargs -0 -r "$SC" -s bash -f gcc -i "$list"
}

out=$(
    lint "$BASE" . -name '*.sh' -not -path '*/.git/*' -not -path '*/docs/*' -not -path './.tmp/*'
    lint "$STRICT" kbool.sh kkore examples kcl -maxdepth 2 -name '*.sh' -type f \
        -not -path '*/tests/*'
    lint "$STRICT" kklass -maxdepth 1 -name '*.sh' -type f
)
if [[ -z $out ]]; then
    echo "shellcheck.sh: clean"
    exit 0
fi
printf '%s\n' "$out"
if [[ -n ${GITHUB_ACTIONS-} ]]; then
    printf '%s\n' "$out" | sed -n 's|^\./||; s|^\([^:]*\):\([0-9]*\):\([0-9]*\): [a-z]*: \(.*\)$|::error file=\1,line=\2,col=\3::\4|p'
fi
echo "shellcheck.sh: $(printf '%s\n' "$out" | wc -l) finding(s)" >&2
exit 1
