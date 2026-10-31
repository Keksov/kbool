#!/usr/bin/env bash
# 001_Notes.sh - examples/notes.sh, the launch demo, run exactly as a user runs
# it (`bash examples/notes.sh --port=N --data=FILE` in a child bash); the test
# is the curl client. The socket helpers are the ones of the thttpserver suite
# (kcl/thttpserver/tests/_ths_socket.sh): random port, bounded waits, the
# backend detection - and with no usable backend (or no curl, no timeout) every
# case passes with "SKIP: <reason>".
#
#   0. no socket: a bad --port -> exit 2 + usage; no network listener -> exit 2
#   1. one server: every endpoint and status (the 400 / 404 paths, the
#      whole-word case-insensitive search), POST /quit ends the process
#   2. a restart on the same data file: the notes are still there, ids go on
#   3. the default data file (notes.ini in the current directory)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NOTES="$ROOT_DIR/examples/notes.sh"
UNIT_DIR="$ROOT_DIR/kcl/thttpserver"        # the helpers' unit (ths._backend)

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
source "$UNIT_DIR/tests/_ths_socket.sh"
cd "$TMP" || exit 1

# slurp FILE -> SL, the exact bytes (trailing newlines kept; $(<f) would drop them)
slurp() { SL=""; IFS= read -r -d '' SL < "$1" || :; }

# have_all - the socket cases can run: a backend, timeout(1) and curl
have_all() { ths_have_nc && type -P curl >/dev/null; }

# skip_all TITLE... - one visible SKIP case per title
skip_all() {
    if ! type -P curl >/dev/null && ths_have_nc; then
        local t
        for t in "$@"; do kt_test_start "$t"; kt_test_pass "SKIP: needs curl"; done
    else
        ths_skip "$@"
    fi
}

kt_test_section "001: examples/notes.sh"

# ===========================================================================
kt_test_section "0. no socket"
# ===========================================================================

kt_test_start "--port=70000 -> exit 2, one usage line on stderr, nothing on stdout"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
    rc=0; "$KT_TIMEOUT" -k 10 120 "$BASH" "$NOTES" --port=70000 --data="$TMP/x.ini" >"$TMP/bad.out" 2>"$TMP/bad.err" </dev/null || rc=$?
    mapfile -t EL < "$TMP/bad.err"
    if [[ $rc -eq 2 && ${#EL[@]} -eq 1 && "${EL[0]}" == "usage: "*"--port=N"* && ! -s "$TMP/bad.out" ]]; then
        kt_test_pass "exit 2: '${EL[0]}'"
    else
        kt_test_fail "exit=$rc stderr=(${EL[*]}) stdout='$(<"$TMP/bad.out")'"
    fi
fi

kt_test_start "no network listener (KCL_NC=/no/such/nc) -> exit 2, one line on stderr naming what to install, nothing on stdout"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
    rc=0; KCL_NC=/no/such/nc "$KT_TIMEOUT" -k 10 120 "$BASH" "$NOTES" --port=28999 --data="$TMP/x.ini" >"$TMP/bad.out" 2>"$TMP/bad.err" </dev/null || rc=$?
    mapfile -t EL < "$TMP/bad.err"
    if [[ $rc -eq 2 && ${#EL[@]} -eq 1 && "${EL[0]}" == "notes: "*"install"*"netcat"*"socat"* && ! -s "$TMP/bad.out" ]]; then
        kt_test_pass "exit 2: '${EL[0]:0:70}...'"
    else
        kt_test_fail "exit=$rc stderr=(${EL[*]}) stdout='$(<"$TMP/bad.out")'"
    fi
fi

# ===========================================================================
kt_test_section "1. one server, every endpoint"
# ===========================================================================

D1_TITLES=(
    "starts and prints 'notes: listening on http://127.0.0.1:PORT/ (data: FILE)' as its first line"
    "GET / -> 200, the help text lists the endpoints and ends with a newline"
    "GET /notes with no notes -> 200, empty body"
    "POST /notes (3 notes, then a multibyte one from a file) -> 201 and the ids 1, 2, 3, 4"
    "POST /notes with an empty body, a blank body, a body with LF or CR -> 400 each; nothing was stored"
    "GET /notes -> 'ID: TEXT' lines in id order, multibyte bytes intact"
    "GET /notes/ID -> 200 and the text; an unknown id, a non-number, 0 and a leading zero -> 404"
    "DELETE /notes/ID -> 204 and no body; the same again -> 404; DELETE /notes/abc -> 404; the next POST gets max+1"
    "GET /search?q=milk -> the whole-word matches, any case (milkshake is not one); q=MILK is the same; no match -> 200 empty"
    "GET /search with a bad word (a-b, a b, empty, missing) -> 400"
    "anything else -> 404: PUT /notes, DELETE /notes, POST /search, GET /nope, GET /notes/"
    "POST /quit -> 200 'bye'; the server exits 0 by itself, stderr is empty, its temp dir is gone"
)
if ! have_all; then
    skip_all "${D1_TITLES[@]}"
elif ! ths_launch n1 "$NOTES" "--port={PORT}" "--data=$TMP/main.ini"; then
    for t in "${D1_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "notes.sh never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    U="http://127.0.0.1:$THS_PORT"
    ths_curl "$TMP/a1" "$U/"; slurp "$TMP/a1"; ca="$CURL_CODE"; ba="$SL"
    ths_curl "$TMP/a2" "$U/notes"; slurp "$TMP/a2"; cb="$CURL_CODE"; bb="$SL"
    post=""
    ths_curl "$TMP/p1" -X POST --data-binary 'buy milk' "$U/notes"; slurp "$TMP/p1"; post+="$CURL_CODE:${SL%$'\n'}:${#SL} "
    ths_curl "$TMP/p2" -X POST --data-binary 'call Alice about the Milk' "$U/notes"; slurp "$TMP/p2"; post+="$CURL_CODE:${SL%$'\n'} "
    ths_curl "$TMP/p3" -X POST --data-binary 'milkshake only' "$U/notes"; slurp "$TMP/p3"; post+="$CURL_CODE:${SL%$'\n'} "
    printf '%s' 'значение 1' > "$TMP/mb.body"
    ths_curl "$TMP/p4" -X POST --data-binary "@$TMP/mb.body" "$U/notes"; slurp "$TMP/p4"; post+="$CURL_CODE:${SL%$'\n'}"
    bad=""
    printf '%s' '' > "$TMP/empty.body"
    printf '%s' '   ' > "$TMP/blank.body"
    printf 'two\nlines' > "$TMP/lf.body"
    printf 'two\rlines' > "$TMP/cr.body"
    for f in empty blank lf cr; do
        ths_curl "$TMP/b_$f" -X POST --data-binary "@$TMP/$f.body" "$U/notes"; bad+="$CURL_CODE "
    done
    ths_curl "$TMP/l1" "$U/notes"; slurp "$TMP/l1"; cl="$CURL_CODE"; bl="$SL"
    sh=""
    ths_curl "$TMP/s1" "$U/notes/2"; slurp "$TMP/s1"; sh+="$CURL_CODE:${SL%$'\n'}:${#SL} "
    ths_curl "$TMP/s2" "$U/notes/99"; sh+="$CURL_CODE "
    ths_curl "$TMP/s3" "$U/notes/abc"; sh+="$CURL_CODE "
    ths_curl "$TMP/s4" "$U/notes/0"; sh+="$CURL_CODE "
    ths_curl "$TMP/s5" "$U/notes/01"; sh+="$CURL_CODE"
    ths_curl "$TMP/q1" "$U/search?q=milk"; slurp "$TMP/q1"; q1="$CURL_CODE:$SL"
    ths_curl "$TMP/q2" "$U/search?q=MILK"; slurp "$TMP/q2"; q2="$CURL_CODE:$SL"
    ths_curl "$TMP/q3" "$U/search?q=bik"; slurp "$TMP/q3"; q3="$CURL_CODE:${#SL}"
    del=""
    ths_curl "$TMP/d1" -X DELETE "$U/notes/2"; del+="$CURL_CODE:$(wc -c < "$TMP/d1" | tr -d ' ') "
    ths_curl "$TMP/d2" -X DELETE "$U/notes/2"; del+="$CURL_CODE "
    ths_curl "$TMP/d3" -X DELETE "$U/notes/abc"; del+="$CURL_CODE "
    ths_curl "$TMP/d4" -X POST --data-binary 'fix the bike' "$U/notes"; slurp "$TMP/d4"; del+="$CURL_CODE:${SL%$'\n'}"
    ths_curl "$TMP/q4" "$U/search?q=bike"; slurp "$TMP/q4"; q4="$CURL_CODE:$SL"
    qb=""
    ths_curl "$TMP/e1" "$U/search?q=a-b"; qb+="$CURL_CODE "
    ths_curl "$TMP/e2" "$U/search?q=a%20b"; qb+="$CURL_CODE "
    ths_curl "$TMP/e3" "$U/search?q="; qb+="$CURL_CODE "
    ths_curl "$TMP/e4" "$U/search"; qb+="$CURL_CODE"
    nf=""
    ths_curl "$TMP/n1" -X PUT --data-binary x "$U/notes"; nf+="$CURL_CODE "
    ths_curl "$TMP/n2" -X DELETE "$U/notes"; nf+="$CURL_CODE "
    ths_curl "$TMP/n3" -X POST --data-binary x "$U/search"; nf+="$CURL_CODE "
    ths_curl "$TMP/n4" "$U/nope"; nf+="$CURL_CODE "
    ths_curl "$TMP/n5" "$U/notes/"; nf+="$CURL_CODE"
    ths_curl "$TMP/z" -X POST --data-binary x "$U/quit"; slurp "$TMP/z"; cq="$CURL_CODE:$SL"
    ths_reap 60
    mapfile -t OUT < "$THS_DIR/out"

    kt_test_start "${D1_TITLES[0]}"
    if [[ "${OUT[0]:-}" == "notes: listening on http://127.0.0.1:$THS_PORT/ (data: $TMP/main.ini)" ]]; then kt_test_pass "'${OUT[0]:0:50}...'"; else kt_test_fail "first line '${OUT[0]:-}'"; fi

    kt_test_start "${D1_TITLES[1]}"
    if [[ "$ca" == 200 && "$ba" == *"GET    /notes "* && "$ba" == *"POST   /notes "* && "$ba" == *"DELETE /notes/ID"* && "$ba" == *"/search?q=WORD"* && "$ba" == *"POST   /quit"* && "$ba" == *$'\n' ]]; then
        kt_test_pass "200, the endpoint list"
    else
        kt_test_fail "code=$ca body='${ba:0:150}'"
    fi

    kt_test_start "${D1_TITLES[2]}"
    if [[ "$cb" == 200 && -z "$bb" ]]; then kt_test_pass "200, empty"; else kt_test_fail "code=$cb body='$bb'"; fi

    kt_test_start "${D1_TITLES[3]}"
    if [[ "$post" == "201:1:2 201:2 201:3 201:4" ]]; then kt_test_pass "$post"; else kt_test_fail "'$post'"; fi

    kt_test_start "${D1_TITLES[4]}"
    if [[ "$bad" == "400 400 400 400 " && "$bl" == *"4: "* && "$bl" != *"5: "* ]]; then kt_test_pass "400 400 400 400, ids still end at 4"; else kt_test_fail "'$bad' list='$bl'"; fi

    kt_test_start "${D1_TITLES[5]}"
    exp=$'1: buy milk\n2: call Alice about the Milk\n3: milkshake only\n4: значение 1\n'
    if [[ "$cl" == 200 && "$bl" == "$exp" ]]; then kt_test_pass "4 lines"; else kt_test_fail "code=$cl body='$bl'"; fi

    kt_test_start "${D1_TITLES[6]}"
    if [[ "$sh" == "200:call Alice about the Milk:26 404 404 404 404" ]]; then kt_test_pass "$sh"; else kt_test_fail "'$sh'"; fi

    kt_test_start "${D1_TITLES[7]}"
    if [[ "$del" == "204:0 404 404 201:5" ]]; then kt_test_pass "$del"; else kt_test_fail "'$del'"; fi

    kt_test_start "${D1_TITLES[8]}"
    exp=$'200:1: buy milk\n2: call Alice about the Milk\n'
    if [[ "$q1" == "$exp" && "$q2" == "$exp" && "$q3" == "200:0" && "$q4" == $'200:5: fix the bike\n' ]]; then
        kt_test_pass "milk = MILK = lines 1 and 2; bik = none; bike = 5"
    else
        kt_test_fail "milk='$q1' MILK='$q2' bik='$q3' bike='$q4'"
    fi

    kt_test_start "${D1_TITLES[9]}"
    if [[ "$qb" == "400 400 400 400" ]]; then kt_test_pass "$qb"; else kt_test_fail "'$qb'"; fi

    kt_test_start "${D1_TITLES[10]}"
    if [[ "$nf" == "404 404 404 404 404" ]]; then kt_test_pass "$nf"; else kt_test_fail "'$nf'"; fi

    kt_test_start "${D1_TITLES[11]}"
    e="$(<"$THS_DIR/err")"; left="$(ls -A "$THS_DIR/tmp")"
    if [[ "$cq" == $'200:bye\n' && $THS_TERMED -eq 0 && $THS_RC -eq 0 && -z "$e" && -z "$left" ]]; then
        kt_test_pass "200 bye, exit 0, no stderr, no temp files"
    else
        kt_test_fail "quit='$cq' termed=$THS_TERMED exit=$THS_RC stderr='${e:0:200}' tmp='$left'"
    fi
fi

# ===========================================================================
kt_test_section "2. a restart on the same data file"
# ===========================================================================

D2_TITLES=(
    "the INI file holds [notes] and the notes as id=text"
    "a new server on the same file lists the same notes, and the next POST continues the ids"
)
if ! have_all; then
    skip_all "${D2_TITLES[@]}"
elif [[ ! -f "$TMP/main.ini" ]]; then
    for t in "${D2_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "no data file from section 1"; done
elif ! ths_launch n2 "$NOTES" "--port={PORT}" "--data=$TMP/main.ini"; then
    for t in "${D2_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "notes.sh never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    U="http://127.0.0.1:$THS_PORT"
    slurp "$TMP/main.ini"; ini="$SL"
    ths_curl "$TMP/r1" "$U/notes"; slurp "$TMP/r1"; r1="$CURL_CODE:$SL"
    ths_curl "$TMP/r2" -X POST --data-binary 'after restart' "$U/notes"; slurp "$TMP/r2"; r2="$CURL_CODE:$SL"
    ths_curl "$TMP/r3" "$U/notes/5"; slurp "$TMP/r3"; r3="$CURL_CODE:$SL"
    ths_curl "$TMP/r4" -X POST --data-binary x "$U/quit"
    ths_reap 60

    kt_test_start "${D2_TITLES[0]}"
    if [[ "$ini" == *"[notes]"* && "$ini" == *$'\n1=buy milk\n'* && "$ini" == *$'\n5=fix the bike'* && "$ini" != *$'\n2='* ]]; then
        kt_test_pass "[notes], 1=buy milk, 5=fix the bike, no 2="
    else
        kt_test_fail "file: '$ini'"
    fi

    kt_test_start "${D2_TITLES[1]}"
    exp=$'200:1: buy milk\n3: milkshake only\n4: значение 1\n5: fix the bike\n'
    if [[ "$r1" == "$exp" && "$r2" == $'201:6\n' && "$r3" == $'200:fix the bike\n' && $THS_TERMED -eq 0 && $THS_RC -eq 0 ]]; then
        kt_test_pass "the same 4 notes, new id 6, exit 0"
    else
        kt_test_fail "list='$r1' post='$r2' get='$r3' termed=$THS_TERMED exit=$THS_RC"
    fi
fi

# ===========================================================================
kt_test_section "3. the default data file"
# ===========================================================================

D3_TITLE="without --data the notes go to notes.ini in the current directory"
if ! have_all; then
    skip_all "$D3_TITLE"
elif ! ths_launch n3 "$NOTES" "--port={PORT}"; then
    kt_test_start "$D3_TITLE"; kt_test_fail "notes.sh never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"
else
    U="http://127.0.0.1:$THS_PORT"
    ths_curl "$TMP/f1" -X POST --data-binary 'in the current directory' "$U/notes"; slurp "$TMP/f1"; f1="$CURL_CODE:$SL"
    ths_curl "$TMP/f2" -X POST --data-binary x "$U/quit"
    ths_reap 60
    mapfile -t OUT < "$THS_DIR/out"
    kt_test_start "$D3_TITLE"
    ini=""; [[ -f "$TMP/notes.ini" ]] && slurp "$TMP/notes.ini" && ini="$SL"
    if [[ "$f1" == $'201:1\n' && "$ini" == *"1=in the current directory"* && "${OUT[0]:-}" == *"(data: notes.ini)" && $THS_RC -eq 0 ]]; then
        kt_test_pass "201:1, notes.ini written, banner names it"
    else
        kt_test_fail "post='$f1' ini='$ini' first='${OUT[0]:-}' exit=$THS_RC"
    fi
fi

kt_test_log "001_Notes.sh completed"
