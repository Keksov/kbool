#!/usr/bin/env bash
# notes.sh - a notes service in bash: an HTTP server of about 150 lines.
#
#   bash examples/notes.sh [--port=N | -p N] [--address=A] [--data=FILE]
#
# Defaults: port 8080, address 127.0.0.1, data file notes.ini in the current
# directory. The notes live in that INI file, so they survive a restart.
#
#   GET    /              this help
#   GET    /notes         every note, one line "ID: TEXT"
#   POST   /notes         add the request body as a note -> 201 and its ID
#   GET    /notes/ID      one note (404 if there is none)
#   DELETE /notes/ID      remove it -> 204 (404 if there is none)
#   GET    /search?q=WORD the notes that contain WORD as a whole word, any case
#   POST   /quit          stop the server
#
# Try it:  curl -s localhost:8080/notes -d 'buy milk'     (see notes_session.sh)
#
# What it shows: the Pascal-style class syntax (kklass), three library units
# (thttpserver, tinifile, tregex) and one idea - the handlers run in THIS
# shell, so the objects they use stay alive between requests.
#
# A handler is a method of TNotes. It gets the request ($1), the response ($2)
# and the route data ($3). It reads the request with direct calls
# ($1.RouteParam id; id=$RESULT) and answers with $2.Code = ... and $2.Write.
# Every variable of a handler is `local`.

EX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$EX_DIR/../kcl/thttpserver/thttpapplication.sh" || exit 1   # loads kbool.sh
kk.uses tinifile tregex || exit 1

# The network listener is GNU netcat, or else socat. On Windows (Git-bash)
# netcat comes with MSYS2 (the server picks it up from $KCL_NC or the PATH).
if [[ -z "${KCL_NC:-}" ]] && ! type -P nc >/dev/null; then
    for notes_nc in /c/msys64/usr/bin/nc.exe /c/bin/msys64/usr/bin/nc.exe; do
        [[ -x "$notes_nc" ]] && { export KCL_NC="$notes_nc"; break; }
    done
fi

# ---------------------------------------------------------------------------
# TNotes - the notes and the HTTP routes that work on them. The notes are the
# keys of section [notes] of an INI file: id = text.
# ---------------------------------------------------------------------------
class TNotes
    public
        constructor Create
        destructor  Destroy
        proc Help
        proc List
        proc Add
        proc Show
        proc Remove
        proc Search
        proc Quit
        proc NotFound
    private
        var  _ini
        func _Ids
end

TNotes.Create() {
    _ini="${__inst__}_ini"
    TMemIniFile.new "$_ini" "$1"            # reads the file if it exists
}

TNotes.Destroy() {
    "$_ini.delete"
}

# _Ids - RESULT = the note ids in ascending order, e.g. "1 2 5". A bash
# indexed array is walked in index order, so filling byid[id] sorts the ids.
TNotes._Ids() {
    local keys=() byid=() key id
    "$_ini.ReadSection" notes keys
    for key in "${keys[@]}"; do
        if [[ "$key" =~ ^[1-9][0-9]{0,8}$ ]]; then
            byid[key]=1
        fi
    done
    RESULT=""
    for id in "${!byid[@]}"; do
        RESULT+="$id "
    done
}

TNotes.Help() {
    $2.Write 'notes service
  GET    /notes          list the notes ("ID: TEXT")
  POST   /notes          add the request body as a note
  GET    /notes/ID       show one note
  DELETE /notes/ID       delete one note
  GET    /search?q=WORD  notes containing WORD as a whole word
  POST   /quit           stop the server
'
}

TNotes.List() {
    local ids id text out=""
    $this._Ids
    ids="$RESULT"
    for id in $ids; do
        "$_ini.ReadString" notes "$id" ""
        out+="$id: $RESULT"$'\n'
    done
    $2.Write "$out"
}

TNotes.Add() {
    local text ids id=0 last
    $1.Content
    text="$RESULT"
    if [[ "$text" == *$'\n'* || "$text" == *$'\r'* ]]; then
        $2.Code = 400
        $2.Write $'a note is one line\n'
        return 0
    fi
    text="${text#"${text%%[![:space:]]*}"}"       # trim: the INI file would
    text="${text%"${text##*[![:space:]]}"}"       # trim it on reload anyway
    if [[ -z "$text" ]]; then
        $2.Code = 400
        $2.Write $'the note is empty\n'
        return 0
    fi
    $this._Ids
    ids="$RESULT"
    for last in $ids; do id=$last; done           # the largest id
    id=$(( id + 1 ))
    "$_ini.WriteString" notes "$id" "$text"
    "$_ini.UpdateFile"
    $2.Code = 201
    $2.Write "$id"$'\n'
}

TNotes.Show() {
    local id
    $1.RouteParam id
    id="$RESULT"
    if [[ "$id" =~ ^[1-9][0-9]{0,8}$ ]] && "$_ini.ValueExists" notes "$id"; then
        "$_ini.ReadString" notes "$id" ""
        $2.Write "$RESULT"$'\n'
    else
        $this.NotFound "$@"
    fi
}

TNotes.Remove() {
    local id
    $1.RouteParam id
    id="$RESULT"
    if [[ "$id" =~ ^[1-9][0-9]{0,8}$ ]] && "$_ini.ValueExists" notes "$id"; then
        "$_ini.DeleteKey" notes "$id"
        "$_ini.UpdateFile"
        $2.Code = 204
    else
        $this.NotFound "$@"
    fi
}

# Search: the word must be [A-Za-z0-9_]+, so it is safe inside a regular
# expression. \b is a word boundary; the flag i ignores case. TRegEx runs on
# the C library's POSIX regex, and kbool makes \b work on every platform.
TNotes.Search() {
    local word ids id out=""
    if ! $1.QueryField q || ! [[ "$RESULT" =~ ^[A-Za-z0-9_]+$ ]]; then
        $2.Code = 400
        $2.Write $'use /search?q=WORD (letters, digits, underscore)\n'
        return 0
    fi
    word="$RESULT"
    $this._Ids
    ids="$RESULT"
    for id in $ids; do
        "$_ini.ReadString" notes "$id" ""
        if TRegEx.isMatch "$RESULT" '\b'"$word"'\b' i; then
            out+="$id: $RESULT"$'\n'
        fi
    done
    $2.Write "$out"
}

TNotes.Quit() {
    App.Terminate                               # the response is still sent
    $2.Write $'bye\n'
}

TNotes.NotFound() {
    $2.Code = 404
    $2.Write $'not found\n'
}
build TNotes

# ---------------------------------------------------------------------------
# The application: the options, the routes, the server loop.
# ---------------------------------------------------------------------------
THttpApplication.new App "$@"                   # "$@" = the command line
if ! App.Initialize; then                       # --port / -p / --address
    echo "usage: ${0##*/} [--port=N | -p N] [--address=A] [--data=FILE]   (N: 1-65535)" >&2
    App.delete
    exit 2
fi
ths._backend                                    # which listener will the server use?
if [[ "$__THS_BACKEND" != gnu && "$__THS_BACKEND" != socat ]]; then
    echo "notes: no network listener - install GNU netcat or socat (apt install socat) [$__THS_BACKEND_WHY]" >&2
    App.delete
    exit 2
fi
App.GetOptionValue "" data
notes_file="${RESULT:-notes.ini}"
TNotes.new Notes "$notes_file"

# First match wins, so the catch-all comes last: anything else is a 404.
App.RegisterRoute /             GET    Notes.Help
App.RegisterRoute /notes        GET    Notes.List
App.RegisterRoute /notes        POST   Notes.Add
App.RegisterRoute /notes/:id    GET    Notes.Show
App.RegisterRoute /notes/:id    DELETE Notes.Remove
App.RegisterRoute /search       GET    Notes.Search
App.RegisterRoute /quit         POST   Notes.Quit
App.RegisterRoute /*rest        ALL    Notes.NotFound

App.Address; notes_addr="$RESULT"
App.Port; notes_port="$RESULT"
echo "notes: listening on http://$notes_addr:$notes_port/ (data: $notes_file)"

notes_rc=0
App.Run || notes_rc=$?
if (( notes_rc != 0 )); then
    App.Server
    "$RESULT.LastError"
    echo "notes: the server stopped: $RESULT" >&2
fi
Notes.delete
App.delete
exit "$notes_rc"
