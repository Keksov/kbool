#!/usr/bin/env bash
# notes_session.sh - a scripted curl session against notes.sh, for a first look
# (and for a terminal recording):
#
#   bash examples/notes_session.sh
#
# It starts notes.sh on a free port with a temporary data file, prints each
# curl command before it runs it, and stops the server with POST /quit. The
# temporary files are removed and no process is left behind.

EX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)" || exit 1
SERVER_PID=""

# Whatever happens: stop the server (if it still runs) and remove the files.
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# The proxy settings of the machine must not catch requests to localhost.
export NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1

# start_server - try a few random ports until the server prints its listening line.
start_server() {
    local try i
    local -a runner=()
    if type -P timeout >/dev/null; then
        runner=(timeout -k 5 120)               # a safety net, not needed normally
    fi
    for (( try = 0; try < 5; try++ )); do
        PORT=$(( 20000 + (RANDOM * 32768 + RANDOM) % 20000 ))
        : > "$WORK/out"
        "${runner[@]}" bash "$EX_DIR/notes.sh" --port="$PORT" --data="$WORK/notes.ini" \
            >"$WORK/out" 2>"$WORK/err" </dev/null &
        SERVER_PID=$!
        for (( i = 0; i < 150; i++ )); do        # up to 30 s
            if [[ -s "$WORK/out" ]] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
                break
            fi
            sleep 0.2
        done
        if [[ -s "$WORK/out" ]]; then
            return 0
        fi
        wait "$SERVER_PID" 2>/dev/null
        if (( $? == 2 )); then                   # no network listener at all
            cat "$WORK/err" >&2
            return 2
        fi
    done
    cat "$WORK/err" >&2
    return 1
}

# show_args ARG... - print a command the way a shell user would type it.
show_args() {
    local a
    printf '$'
    for a in "$@"; do
        if [[ "$a" =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then
            printf ' %s' "$a"
        else
            printf " '%s'" "$a"
        fi
    done
    printf '\n'
}

# run ARG... - print the command, then run it. The listening line is printed a
# moment before the first connection is accepted, so a refused connection
# (curl exit 7) is simply tried again.
run() {
    local i rc
    show_args "$@"
    for (( i = 0; i < 50; i++ )); do
        rc=0
        "$@" || rc=$?
        if (( rc != 7 )); then
            return 0
        fi
        sleep 0.2
    done
}

start_server || exit $?
cat "$WORK/out"
H="localhost:$PORT"

run curl -s "$H/"
run curl -s "$H/notes" -d 'buy milk'
run curl -s "$H/notes" -d 'call Alice about the milk'
run curl -s "$H/notes" -d 'fix the bike'
run curl -s "$H/notes"
run curl -s "$H/search?q=milk"
run curl -s -X DELETE "$H/notes/2"
run curl -s "$H/notes"
run curl -s -X POST "$H/quit"

wait "$SERVER_PID"
echo "server exited: $?"
SERVER_PID=""
