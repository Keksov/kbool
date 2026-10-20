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
| `run NAME -- CMD...` | run CMD in the VM via ssh: ONE argument is sent verbatim as the remote command line, TWO OR MORE are each quoted with `printf %q`; timeout `VMLAB_TIMEOUT` (600) s; rc = CMD's rc |
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

## kb-ubuntu -- manual install

Status (2026-10-20): `create/ubuntu.sh` (VirtualBox *unattended* install) does
not finish reliably on this host. VirtualBox 7.1.12 runs on the Hyper-V
platform backend here (`HM: ... AMD-V is not available` -> NEM; Core Isolation
is on). In 5 attempts the guest hung 2 times (one vCPU at 100 %, guest clock
stalled, black or frozen console: once 15 s after boot, once ~8 min into the
subiquity "downloading and installing security updates" step), one attempt was
stopped too early by the script, and the others were interrupted by hand.
Hence this checklist for the owner. `create/ubuntu.sh` and `provision/apt.sh`
are kept (the script is the same recipe, automated).

Where things are: ISO `C:\var\vbox\kb-lab\iso\ubuntu-24.04.5-live-server-amd64.iso`
(sha256 checked against `SHA256SUMS` in the same folder); VM folder
`C:\var\vbox\kb-lab\` (the VM folder `kb-ubuntu\` is created by VirtualBox);
ssh key `~/.ssh/kbool_vmlab` (+ `.pub`, created, no passphrase).

1. VirtualBox: new VM `kb-ubuntu`, folder `C:\var\vbox\kb-lab`, type Linux /
   Ubuntu (64-bit), 4096 MB RAM, 4 CPUs, a new 20 GB dynamic VDI on a SATA
   controller, ISO above in the optical drive. Settings: Network adapter 1 =
   NAT with port forward `ssh`, TCP, host `127.0.0.1`:2221 -> guest 22;
   Audio off; USB off. (CLI equivalent: the `createvm`/`modifyvm`/`storagectl`
   lines of `create/ubuntu.sh`, without the `unattended` call.)
2. Start it and install Ubuntu Server 24.04 with these choices: English,
   keyboard US, "Ubuntu Server" (not minimized), network: DHCP default,
   no proxy, default mirror, entire disk (no LVM needed, default is fine),
   server name `kb-ubuntu`, your name `kb`, user name `kb`, a password (keep it:
   it is needed once, below), **Install OpenSSH server: yes**, no featured
   snaps, no Ubuntu Pro. If the installer hangs: power the VM off and retry
   (it is intermittent) - at the "downloading and installing security
   updates" step you may also choose to continue without updates.
3. Reboot into the installed system, log in as `kb`, then in the VM:
   `sudo timedatectl set-timezone UTC`.
4. Guest additions (optional, not needed by vmlab): skip.
5. Put the lab key in (from the host, Git-bash; the password is asked once):
   `ssh-copy-id -i ~/.ssh/kbool_vmlab.pub -p 2221 kb@127.0.0.1`
   then `bash tools/vmlab/vmlab.sh up kb-ubuntu && bash tools/vmlab/vmlab.sh run kb-ubuntu -- true`
   must succeed (vmlab refuses until `kb-ubuntu` answers on 2221).
6. Provision (first run asks for the password via `sudo -S`, later NOPASSWD):
   ```
   bash tools/vmlab/vmlab.sh run kb-ubuntu -- sh -c 'cat > /tmp/apt.sh' < tools/vmlab/provision/apt.sh
   ssh -i ~/.ssh/kbool_vmlab -p 2221 kb@127.0.0.1 'sudo bash /tmp/apt.sh'     # asks the password once
   bash tools/vmlab/vmlab.sh run kb-ubuntu -- rm -f /tmp/apt.sh
   ```
   `apt.sh` installs the package list of the L1.2 card (bash git coreutils sed
   grep findutils diffutils gawk procps util-linux perl curl openssl
   netcat-openbsd tzdata locales; then one by one socat ncat netcat-traditional
   nodejs python3 uuid-runtime), keeps mawk as `awk` and OpenBSD `nc`, runs
   `locale-gen en_US.UTF-8 de_DE.UTF-8 ru_RU.UTF-8`, sets `kb ALL=(ALL)
   NOPASSWD:ALL`, disables unattended-upgrades and the apt timers, sets sshd to
   key-only, and makes bash the login shell of `kb`.
7. Record the versions into this README (a section "kb-ubuntu -- versions"):
   ```
   bash tools/vmlab/vmlab.sh run kb-ubuntu -- bash -c 'lsb_release -d; bash --version | head -1; dpkg-query -W gawk sed grep coreutils findutils netcat-openbsd'
   bash tools/vmlab/vmlab.sh run kb-ubuntu -- bash -c 'readlink -f "$(command -v nc)"; update-alternatives --display nc; locale -a; LC_ALL=ru_RU.UTF-8 bash -c "echo \$EPOCHREALTIME"'
   ```
8. Snapshot: `bash tools/vmlab/vmlab.sh snapshot kb-ubuntu clean`
   (a later re-provision: `... snapshot kb-ubuntu clean --replace`).
9. Check: `bash tools/vmlab/vmlab.sh status` shows `kb-ubuntu poweroff ... clean`;
   `reset` + `up` + `run kb-ubuntu -- bash -c 'bash --version | head -1; sudo -n true && echo sudo-ok'` + `down` works;
   `sync kb-ubuntu` then `run kb-ubuntu -- ls ~/kbool`.

Note: `vmlab.sh run NAME -- ...` has two forms. With exactly ONE argument
after `--` the string is the remote command line, sent verbatim (pipes, `;`,
`$VAR` are interpreted by the remote shell):
`run kb-ubuntu -- 'uname -a | head -1; echo $0'`. With TWO OR MORE arguments
each word is quoted with `printf %q` and nothing is interpreted:
`run kb-ubuntu -- echo 'a b;c'` prints `a b;c`.
