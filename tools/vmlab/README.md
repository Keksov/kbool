# vmlab -- the kbool lab VMs

`vmlab.sh` drives the lab VMs (VirtualBox, headless, ssh over a NAT port
forward to `127.0.0.1`) from the Windows host. Plain bash, no kbool needed;
it runs under Git-bash (and MSYS2 bash).

```
bash tools/vmlab/vmlab.sh --help
bash tools/vmlab/vmlab.sh status
bash tools/vmlab/vmlab.sh gate kb-ubuntu            # reset -> up -> sync -> gate -> fetch -> down
```

## VMs: `vms.conf`

TSV with a header line:

```
name	os	port	mem	cpus	disk_gb	bash	user
kb-ubuntu	ubuntu-24.04	2221	4096	4	20	/usr/bin/bash	kb
...
```

`port` is the host port forwarded to the VM's sshd, `bash` the VM's bash
(`KT_GATE_BASHES` for the gate), `user` the ssh user.

**Safety.** Every command that takes a NAME refuses (rc 2, a message, nothing
is called) a name that does not match `^kb-[a-z0-9]+$` or is not a `name` row
of `vms.conf`. The owner's other VMs ("Ubuntu 24.02.2", "OLHCV", ...) can
therefore not be touched through this script.

## Commands

`vmlab.sh CMD NAME [args]`

| cmd | behaviour |
|---|---|
| `status` | one line per VM: `name state snapshots` (`absent` if VirtualBox does not know it; snapshots comma-joined, `-` for none) |
| `up NAME` | start headless if not running; wait up to `VMLAB_BOOT_WAIT` (180) s until ssh answers. The VM is left running |
| `down NAME` | ACPI power button, wait up to `VMLAB_DOWN_WAIT` (60) s for `poweroff`, else hard `controlvm poweroff`. A stopped VM is left alone |
| `reset NAME [SNAP]` | `down`, then restore snapshot (default `clean`) |
| `snapshot NAME SNAP [--replace]` | `down`, then take `SNAP`; an existing `SNAP` is rc 13 unless `--replace` (deletes it first) |
| `run NAME -- CMD...` | run CMD in the VM via ssh (words quoted with `printf %q`); timeout `VMLAB_TIMEOUT` (600) s; rc = CMD's rc |
| `shell NAME` | interactive ssh (for the owner) |
| `sync NAME [--from-github [--ref R]]` | put the code in `~/kbool` of the VM: the host working tree (tar), or a fresh `git clone --recurse-submodules` of GitHub |
| `fetch NAME REMOTE_DIR HOST_DIR` | copy a remote directory to the host (`tar` over ssh) |
| `gate NAME [--snapshot S] [--from-github] [--out DIR] [-- GATE_ARGS...]` | the whole cycle, below |

Snapshot names match `^[A-Za-z0-9][A-Za-z0-9._-]*$`.

### sync (working tree)

For the root and every submodule (`git submodule status`): the files of
`git ls-files -co --exclude-standard -z` that exist as regular files (deleted
files and submodule gitlinks are dropped), prefixed with the submodule path.
`tar --null -T -` packs them from the root; the VM unpacks into
`~/kbool.new` and swaps it for `~/kbool` (`tar -xf - -C DIR` is all the VM
side needs: GNU tar, bsdtar and busybox tar all do). No `.git` directories
are copied.

### gate

`reset NAME S` (default `clean`) -> `up` -> `sync` -> write `~/vm.txt`
(`uname -a`, `/etc/os-release` or `freebsd-version`, the VM's bash version,
the host SHA of the root and each submodule, `-dirty` appended when
`git status --porcelain` is not empty) -> run in the VM

```
rm -rf ~/gate-out; cd ~/kbool && KT_GATE_BASHES=<bash column> timeout -k 120 9000 \
    bash ktests/tools/gate.sh --out ~/gate-out GATE_ARGS
```

(default `GATE_ARGS`: `--rerun-failed 1 all`; ssh timeout 9300 s) -> `fetch`
`~/gate-out` into OUT and `~/vm.txt` to `OUT/vm.txt` -> `down`. If a fetch fails the exit code is 14 (below); otherwise the exit code
is the gate's. OUT defaults to
`${TMPDIR:-$LOCALAPPDATA/Temp}/kb-vmlab/<YYYYmmdd-HHMMSS>-<name>-<snap>` and
is printed first: `vmlab out=OUT`.

### The cleanup trap

On EXIT, INT and TERM the invocation powers off (`down`) every VM it started
itself, never one that was already running. `up` alone, when it succeeds,
leaves the VM running on purpose; when it fails (boot timeout) or is
interrupted, the VM is powered off. `shell` has no trap.

## Exit codes

| rc | meaning |
|---|---|
| 0 | ok |
| 2 | usage error, or NAME refused |
| 10 | VBoxManage failed (also: VM unknown to VirtualBox) |
| 11 | boot wait timed out |
| 12 | snapshot absent |
| 13 | snapshot exists (use `--replace`) |
| 14 | `gate`: the results (`~/gate-out` or `~/vm.txt`) could not be fetched; returned whatever the gate's own rc was, which is then printed on stderr (`vmlab: gate rc=N but results not fetched: …`). The VM is powered off regardless |
| else | the remote command's rc (`run`, `gate`; 124 = timeout, 255 = ssh failed) |

## Environment

| variable | default | meaning |
|---|---|---|
| `VBOXMANAGE` | `/c/Program Files/Oracle/VirtualBox/VBoxManage.exe` | |
| `VMLAB_BOOT_WAIT` | 180 | seconds `up` waits for ssh |
| `VMLAB_DOWN_WAIT` | 60 | seconds `down` waits for the ACPI shutdown |
| `VMLAB_TIMEOUT` | 600 | seconds for one ssh call of `run`, `sync`, `fetch` |
| `VMLAB_POLL` | 3 | seconds between ssh probes in `up` |
| `VMLAB_ROOT` | the repository the script lives in | tree that `sync` and `gate` ship |
| `VMLAB_KEY` | `~/.ssh/kbool_vmlab` | ssh key (never printed or copied) |
| `VMLAB_KNOWN_HOSTS` | `~/.ssh/kbool_vmlab_known_hosts` | |

ssh is always `ssh -i KEY -p PORT -o BatchMode=yes -o ConnectTimeout=10 -o
StrictHostKeyChecking=accept-new -o UserKnownHostsFile=KNOWN USER@127.0.0.1`
under `timeout -k 30 N`.

## Dry run and tests

`VMLAB_DRY=1` executes nothing: every VBoxManage, ssh and tar call is printed
as one line `DRY: <argv>`, and the answers come from a simulation:

* state: `VMLAB_DRY_STATE` (default `poweroff`; `absent` = unknown VM) is the
  starting state; `startvm` makes it `running`, `acpipowerbutton` and
  `controlvm poweroff` make it `poweroff`. With `VMLAB_DRY_STATE=running` the
  ACPI button is ignored (to test the hard-poweroff fallback);
* snapshots: `VMLAB_DRY_SNAPS` (space separated, default `clean`);
  `take`/`delete` update the list for the rest of the invocation;
* ssh: `true` succeeds, unless `VMLAB_DRY_SSH_FAIL=1`;
* `VMLAB_DRY_GATE_RC=N`: the remote gate call returns N;
* `VMLAB_DRY_FETCH_FAIL=out|vm|1`: the fetch of `~/gate-out`, of `~/vm.txt`, or of both fails;
* `VMLAB_DRY_LIST=1` prints each file `sync` would pack as `DRY: entry PATH`.

```
bash tools/vmlab/tests/run.sh     # PASS n/n, rc 0/1; runs under either bash
```

The tests never touch the real tree or a VM: they build a tiny repo with one
submodule in a temp directory.
