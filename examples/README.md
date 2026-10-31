# examples
## notes.sh - a notes service in bash

An HTTP service in about 170 lines of code, in the Pascal-style class syntax
of kbool. Run it and talk to it with `curl`:

```bash
bash examples/notes.sh                 # http://127.0.0.1:8080/, notes in ./notes.ini
curl -s localhost:8080/notes -d 'buy milk'     # 1
curl -s localhost:8080/notes                   # 1: buy milk
curl -s -X POST localhost:8080/quit            # bye
```

Options: `--port=N` (or `-p N`), `--address=A`, `--data=FILE`.

| request | answer |
|---|---|
| `GET /` | the help text |
| `GET /notes` | one line `ID: TEXT` per note |
| `POST /notes` (the note is the body) | `201` and the new ID; `400` for an empty or multi-line note |
| `GET /notes/ID`, `DELETE /notes/ID` | the text / `204`; `404` for an unknown ID |
| `GET /search?q=WORD` | the notes that contain WORD as a whole word, any case; `400` for a bad WORD |
| `POST /quit` | `200 bye`, then the server stops |
| anything else | `404` |

What it shows: one class (`TNotes`) whose methods are the route handlers; the
notes in an INI file (`TMemIniFile`), so they survive a restart; the search
with `TRegEx` and `\b`; the server itself (`THttpApplication`). The handlers run
in the server's own shell, so the objects stay alive between requests.

## notes_session.sh - the same, scripted
`bash examples/notes_session.sh` starts the service on a free port with a
temporary file, prints and runs a short curl session (add, list, search,
delete, quit), and leaves nothing behind.

## Requirements
bash 5.1 or newer, `curl`, and a listener for the server: GNU netcat 0.7.1
(on Windows the one from MSYS2) or `socat` 1.7.4 or newer (`apt install
socat`). The service is plain HTTP without authentication: keep it on
127.0.0.1. Its test is [tests/](tests/001_Notes.sh), suite id `examples`.
