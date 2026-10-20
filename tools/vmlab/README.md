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

## kb-ubuntu

Ubuntu 24.04 Server lab VM (name `kb-ubuntu`, ssh port 2221, user `kb`, bash
`/usr/bin/bash`, snapshot `clean`). Created 2026-10-20 by `create/ubuntu.sh`
(+ `provision/apt.sh`); the VM and the ISO live in `C:\var\vbox\kb-lab\`
(ISO `iso\ubuntu-24.04.5-live-server-amd64.iso`, checked against the
`SHA256SUMS` next to it). The VM itself is not part of the repository: it is
rebuilt with this recipe.

```
bash tools/vmlab/create/ubuntu.sh                  # whole recipe, ~15 min; leaves the VM running
bash tools/vmlab/vmlab.sh snapshot kb-ubuntu clean
```

`create/ubuntu.sh` refuses (rc 13) if `kb-ubuntu` exists. It generates a random
20-character password in `$KB_SCRATCH` (never printed, deleted at exit; the
`unattended` output is filtered), runs `createvm`/`modifyvm` (4096 MB, 4 CPUs,
NAT with `ssh,tcp,127.0.0.1,2221,,22`, audio and USB off), a 20 GB dynamic VDI
on SATA, `unattended install --install-additions --start-vm=headless`, waits for
the guest additions (`GuestAdditionsRunLevel>=2`, retrying guest control every
15 s until `KB_INSTALL_WAIT`, 45 min), installs the lab key into
`/home/kb/.ssh/authorized_keys`, then pipes `provision/apt.sh` through
`vmlab.sh run` (`sudo -S` once with the password; later NOPASSWD). A recreated VM has a new
ssh host key: the script removes the old `[127.0.0.1]:2221` entry from `~/.ssh/kbool_vmlab_known_hosts` first.
`create/ubuntu.sh --finish PWFILE` repeats only the steps after the install
(for a VM whose install this script did).

Things the script works around (VirtualBox 7.1.12, Ubuntu 24.04.5 autoinstall):

* The stock post-install template ends with `usermod -a -G vboxsf kb`, but
  cloud-init creates `kb` only at the first boot of the installed system, so
  `usermod` exits 6, subiquity reports "install failed" and stops at "An error
  occurred. Press enter to start a shell" (the system on disk is complete, but it
  is never rebooted). The script passes `--post-install-template` with a copy of
  the stock template without that line.
* The generated autoinstall file has no `ssh:` section: openssh-server is not
  installed. The script installs it through guest control as `kb` with `sudo -S`
  (the password file is copied into the guest, 0600, and removed in the same
  command; root cannot log in through guest control, its password is locked; the
  password is never on a command line).
* `guestcontrol run --exe /bin/sh -- -c '...'`: the arguments after `--` follow
  argv[0] (`-- sh -c ...` fails with `sh: 0: cannot open sh`).
* The guest-additions run level is already 2 inside the installer; guest control
  as `kb` works only after the reboot into the installed system.

Execution engine (host with VBS/HVCI and the Windows hypervisor off,
`HypervisorPresent=False`), from `C:\var\vbox\kb-lab\kb-ubuntu\Logs\VBox.log`:

```
HM: HMR3Init: AMD-V w/ nested paging
HM: Using AMD-V implementation 2.0
```

(no "fall back to NEM"). With the Hyper-V backend (VBS on) the unattended install
hung in 2 of 5 runs; with AMD-V it ran through (511 s until the
guest additions reported run level 2 in the final run, 963 s in an earlier one).

### Versions recorded at creation (2026-10-20)

`lsb_release -d`: `Ubuntu 24.04.5 LTS`; kernel `6.8.0-147-generic`; guest
additions 7.1.12 r169651. `bash --version | head -1`:
`GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)`.
`dpkg-query -W` (all of the `apt.sh` list installed; no name was missing):

```
bash 5.2.21-2ubuntu4              git 1:2.43.0-1ubuntu7.4         coreutils 9.4-3ubuntu6.3
sed 4.9-2ubuntu0.24.04.1          grep 3.11-4build1               findutils 4.9.0-5build1
diffutils 1:3.10-1ubuntu0.1       gawk 1:5.2.1-2ubuntu0.1         mawk 1.3.4.20240123-1build1
procps 2:4.0.4-4ubuntu3.3         util-linux 2.39.3-9ubuntu6.6    perl 5.38.2-3.2ubuntu0.6
curl 8.5.0-2ubuntu10.16           openssl 3.0.13-0ubuntu3.16      netcat-openbsd 1.226-1ubuntu2
tzdata 2026e-0ubuntu0.24.04.1     locales 2.39-0ubuntu8.9         socat 1.8.0.0-4ubuntu0.1
ncat 7.94+git20230807.3be01efb1+dfsg-3build2                      netcat-traditional 1.10-48
nodejs 18.19.1+dfsg-6ubuntu5      python3 3.12.3-0ubuntu2.1       uuid-runtime 2.39.3-9ubuntu6.6
openssh-server 1:9.6p1-3ubuntu13.20
```

* `awk` -> `/usr/bin/mawk` (default, gawk installed beside it; `update-alternatives --set awk /usr/bin/mawk`).
* `readlink -f "$(command -v nc)"` -> `/usr/bin/nc.openbsd`; `update-alternatives --display nc`:
  `nc - manual mode ... link currently points to /bin/nc.openbsd` (`apt.sh` runs
  `update-alternatives --set nc /bin/nc.openbsd` after installing
  ncat/netcat-traditional; the explicit `--set` was needed or at least harmless).
* `locale -a`: `C C.utf8 de_DE.utf8 en_US.utf8 POSIX ru_RU.utf8`.
* `LC_ALL=ru_RU.UTF-8 bash -c 'echo $EPOCHREALTIME'` -> `1792525361,596565` (a comma, as required).
* sshd: `/etc/ssh/sshd_config.d/00-kbool-lab.conf` has `PasswordAuthentication no`
  and `KbdInteractiveAuthentication no`; `unattended-upgrades`, `apt-daily.timer`,
  `apt-daily-upgrade.timer` are disabled; `/etc/sudoers.d/kb` is `kb ALL=(ALL) NOPASSWD:ALL` (0440);
  login shell of `kb` is `/bin/bash`.

Notes: `vmlab.sh sync`/`run` need the VM up (`up` first). Right after
`reset` + `up` the ACPI power button may be ignored for a while (one `down`
fell back to the hard poweroff after 60 s; later ones took 2.5 s and 15 s) - harmless
here, every gate starts with a `reset`.

## kb-ubuntu -- manual install

Fallback only. Status (2026-10-20): with VBS/HVCI and the Windows hypervisor
off (VirtualBox on AMD-V) `create/ubuntu.sh` works (section "kb-ubuntu" above).
On the Hyper-V platform backend (VBS on; `HM: ... AMD-V is not available` ->
NEM) the unattended install was unreliable: in 5 attempts the guest hung 2
times (one vCPU at 100 %, guest clock stalled, black or frozen console: once 15 s
after boot, once ~8 min into the subiquity "downloading and installing security
updates" step). If the unattended install ever fails again on a host, use this
checklist. `create/ubuntu.sh` and `provision/apt.sh` are the same recipe,
automated.

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

## kb-debian

Debian 13 "trixie" lab VM (name `kb-debian`, ssh port 2222, user `kb`, bash
`/usr/bin/bash`, snapshot `clean`). Created 2026-10-20 by `create/debian.sh`
(+ `provision/apt.sh`); VM and ISO live in `C:\var\vbox\kb-lab\` (ISO
`iso\debian-13.7.0-amd64-netinst.iso` from
`https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/`, checked against
`iso\SHA256SUMS.debian` = that folder's `SHA256SUMS`; the plain `SHA256SUMS`
in `iso\` is the Ubuntu one). The VM is not part of the repository.

```
bash tools/vmlab/create/debian.sh                  # whole recipe, ~12 min; leaves the VM running
bash tools/vmlab/vmlab.sh snapshot kb-debian clean
```

Same structure as `create/ubuntu.sh` (refuses with rc 13 if the VM exists,
random one-shot password file, `--finish PWFILE`, port forward
`ssh,tcp,127.0.0.1,2222,,22`, 4096 MB / 4 CPUs / 20 GB). Differences, all verified
on VirtualBox 7.1.12 + Debian 13.7 (preseed):

* `unattended install ... --package-selection-adjustment=minimal`: without it the
  preseed installs the default task set (a desktop); with it `tasksel minimal` +
  `openssh-server`. The VM has 369 packages, 1.5 GB used.
* The stock post-install template is used unchanged: its `usermod -a -G vboxsf kb`
  runs from the preseed `late_command`, after the user exists (no Ubuntu-style
  failure; `/var/log/vboxpostinstall.log` ends `Final exit code: 0`).
* The preseed sets the root password to the user's password, so guest control logs
  in as `root`. A minimal install has no `sudo` and `kb` is in no sudo group, hence
  the script installs `sudo` and `openssh-server` as root through guest control,
  puts the lab key into `/home/kb/.ssh`, and runs `provision/apt.sh` as root through
  guest control (it writes `/etc/sudoers.d/kb`); `vmlab.sh run` works afterwards.
* The guest additions' run level 2 was reached 451 s after the start (same retry
  loop as for Ubuntu).

`provision/apt.sh` became distro-aware, Ubuntu behaviour unchanged:
`export PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH` (the root of guest control has
no sbin in PATH); on Debian (`ID=debian` in `/etc/os-release`) the locales are
enabled by uncommenting `en_US.UTF-8 de_DE.UTF-8 ru_RU.UTF-8` in `/etc/locale.gen`
and running `locale-gen` without arguments (Debian's `locale-gen` takes none); the
`systemctl disable --now` of `unattended-upgrades.service`, `apt-daily.timer`,
`apt-daily-upgrade.timer` is done per unit and only for units that exist (Debian
has no `unattended-upgrades`).

Execution engine, from `C:\var\vbox\kb-lab\kb-debian\Logs\VBox.log`:

```
HM: HMR3Init: AMD-V w/ nested paging
HM: Using AMD-V implementation 2.0
```

### Versions recorded at creation (2026-10-20)

`cat /etc/debian_version`: `13.7` (`Debian GNU/Linux 13 (trixie)`); kernel
`6.12.107+deb13-amd64`; guest additions 7.1.12 (`vboxadd-service` active).
`bash --version | head -1`: `GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu)`.
`dpkg-query -W` (all of the `apt.sh` list installed; no name was missing):

```
bash 5.2.37-2+b10          git 1:2.47.3-0+deb13u1        coreutils 9.7-3
sed 4.9-2+deb13u1          grep 3.11-4                   findutils 4.10.0-3
diffutils 1:3.10-4         gawk 1:5.2.1-2+b1             mawk 1.3.4.20250131-1
procps 2:4.0.4-9           util-linux 2.41.5-0+deb13u1   perl 5.40.1-6+deb13u1
curl 8.14.1-2+deb13u7      openssl 3.5.7-1~deb13u3       netcat-openbsd 1.229-1
tzdata 2026c-0+deb13u1     locales 2.41-12+deb13u4       socat 1.8.0.3-1+deb13u1
ncat 7.95+dfsg-3           netcat-traditional 1.10-50    nodejs 20.19.2+dfsg-1+deb13u3
python3 3.13.5-1           uuid-runtime 2.41.5-0+deb13u1 openssh-server 1:10.0p1-7+deb13u4
sudo 1.9.16p2-3+deb13u2
```

* `awk` -> `/usr/bin/mawk` (manual mode; gawk would be the "best version").
* `readlink -f "$(command -v nc)"` -> `/usr/bin/nc.openbsd`; `update-alternatives --display nc`:
  `nc - manual mode ... link currently points to /bin/nc.openbsd`.
* `locale -a`: `C C.utf8 de_DE.utf8 en_US.utf8 POSIX ru_RU.utf8`.
* `LC_ALL=ru_RU.UTF-8 bash -c 'echo $EPOCHREALTIME'` -> `1792528394,107867` (a comma).
* sshd: `sshd -T` shows `passwordauthentication no`, `kbdinteractiveauthentication no`;
  `apt-daily.timer` and `apt-daily-upgrade.timer` disabled; `/etc/sudoers.d/kb` is
  `kb ALL=(ALL) NOPASSWD:ALL` (0440); login shell of `kb` is `/bin/bash`.
* A minimal Debian has no `lsb_release`: use `/etc/os-release`.

## kb-fedora

Fedora 44 lab VM (name `kb-fedora`, ssh port 2223, user `kb`, bash `/usr/bin/bash`,
snapshot `clean`). Created 2026-10-21 by `create/fedora.sh` (+ `provision/dnf.sh`)
from the official **Fedora Cloud Base** image, not from an installer: VirtualBox
7.1.12 `unattended install` rejects Fedora 44 (see "kb-fedora -- manual install").
VM, image and checksum live in `C:\var\vbox\kb-lab\` (`img\Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2`
and `img\Fedora-Cloud-44-1.7-x86_64-CHECKSUM` from
`https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/`;
`sha256sum -c --ignore-missing` says `OK`). The VM is not part of the repository.

```
# put the qcow2 and its CHECKSUM into C:\var\vbox\kb-lab\img\ first (not into iso\)
bash tools/vmlab/create/fedora.sh                  # whole recipe, ~8 min; leaves the VM powered OFF
bash tools/vmlab/vmlab.sh snapshot kb-fedora clean
```

The script (refuses with rc 13 if `kb-fedora` exists):

1. checks the qcow2 against the CHECKSUM file next to it;
2. `VBoxManage clonemedium <qcow2> kb-fedora.vdi --format VDI` (VirtualBox reads
   qcow2 itself; no `qemu-img` needed) and `modifymedium --resize 20480` (cloud-init
   grows the btrfs root: 20 GB);
3. `createvm --ostype Fedora_64`, 4096 MB, 4 CPUs, BIOS, NAT with
   `ssh,tcp,127.0.0.1,2223,,22` and `--nat-localhostreachable1 on`, audio/USB off,
   the VDI on SATA, and a serial console written to `$KB_SCRATCH/fedora-serial.log`
   (`--uart1 0x3F8 4 --uart-mode1 file ...`) for debugging;
4. the cloud-init **NoCloud** seed: `meta-data` (`instance-id: kb-fedora-1`,
   `local-hostname: kb-fedora`), an empty `vendor-data`, and `user-data` (`#cloud-config`:
   user `kb`, `/bin/bash`, `sudo: ALL=(ALL) NOPASSWD:ALL`, locked password, the line of
   `~/.ssh/kbool_vmlab.pub`, `ssh_pwauth: false`). The VM's SMBIOS serial number names it:
   `setextradata kb-fedora VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial "ds=nocloud;s=http://10.0.2.2:8099/"`;
   the guest sees the host's `127.0.0.1` as `10.0.2.2`. The host side is
   `timeout -k 5 1800 python -u -m http.server 8099 --bind 127.0.0.1 --directory <seed>`
   (`-u`: the "Serving HTTP" line must not sit in a buffer). Its pid is printed
   and the server is stopped (by that pid, also on any failure or interrupt) as soon
   as the first boot answered ssh and the log shows `GET /meta-data` and `GET /user-data`;
5. `vmlab.sh up` with `VMLAB_BOOT_WAIT=900` (first boot: cloud-init creates `kb`,
   resizes the disk, writes the key), then `provision/dnf.sh` through `sudo -n` (kb has
   NOPASSWD from the seed);
6. `vmlab.sh down`, then the DMI extradata is removed (later boots do not look for a
   seed; `ds-identify` then disables cloud-init: `cloud-init status` says `disabled`)
   and the serial port switched off. The VM is left powered off.

`dnf.sh`: `dnf install` of `bash git-core coreutils sed grep findutils diffutils gawk
procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata
glibc-langpack-en glibc-langpack-de glibc-langpack-ru` (a missing name is fatal), then
one by one `socat nodejs python3` (a missing name would print `dnf.sh: MISSING <pkg>`;
none was missing), `kb ALL=(ALL) NOPASSWD:ALL`, `dnf-makecache.timer` disabled, sshd
key-only (`00-kbool-lab.conf`), login shell of `kb` bash. SELinux stays as shipped.

Things found on VirtualBox 7.1.12 + the Fedora 44 cloud image:

* `clonemedium` converts the qcow2 directly (it also registers the qcow2 as a medium:
  `closemedium disk <qcow2>` without `--delete` unregisters it again).
* The first attempt: cloud-init sat in its network stage for ~40 s, "Getting data from
  DataSourceNoCloudNet failed", **no request reached the host server** (HTTP log empty,
  `Datasource DataSourceNone`), although `showvminfo` already said
  `localhostReachable="1"`. The same VM with `modifyvm --nat-localhostreachable1 on` set
  explicitly fetched the seed at once (`Datasource DataSourceNoCloudNet
  [seed=dmi,http://10.0.2.2:8099/]`), and so did the full script run (it now sets the
  option). The root cause of the first failure was not isolated; the explicit option is
  the only difference found.
* Host proxy variables (`HTTP_PROXY`) apply to `curl` on the host: to test the seed
  server by hand use `curl --noproxy '*'` (a plain `curl http://127.0.0.1:8099/` got a
  502 from the proxy and never reached the server).
* cloud-init asks for `/network-config` (404, retried ten times, ~10 s) before
  `meta-data`/`user-data`; harmless. `vendor-data` is served empty to avoid ten more.
* The image has no guest additions: `down` works through the ACPI power button.

Execution engine, from `C:\var\vbox\kb-lab\kb-fedora\Logs\VBox.log`:

```
HM: HMR3Init: AMD-V w/ nested paging
HM: Using AMD-V implementation 2.0
```

### Versions recorded at creation (2026-10-21)

`cat /etc/fedora-release`: `Fedora release 44 (Forty Four)`; kernel
`6.19.10-300.fc44.x86_64`. `bash --version | head -1`:
`GNU bash, version 5.3.9(1)-release (x86_64-redhat-linux-gnu)`. `getenforce`: `Enforcing`.
`rpm -q` (everything installed; `rpm -q nodejs` alone says "not installed": the package
is `nodejs22`, which provides it):

```
bash 5.3.9-3.fc44            git-core 2.56.0-1.fc44       coreutils 9.10-3.fc44
sed 4.9-7.fc44               grep 3.12-3.fc44             findutils 4.10.0-7.fc44
diffutils 3.12-5.fc44        gawk 5.3.2-3.fc44            procps-ng 4.0.6-1.fc44
util-linux 2.41.3-12.fc44    perl-interpreter 5.42.3-525  perl-POSIX 2.23-525
curl 8.18.0-4.fc44           openssl 3.5.5-1.fc44         nmap-ncat 7.92-11.fc44
netcat 1.237-3.fc44          tzdata 2026a-1.fc44          glibc-langpack-{en,de,ru} 2.43-2.fc44
socat 1.8.1.1-1.fc44         nodejs22 22.23.1-2.fc44 (node v22.23.1)
python3 3.14.3-2.fc44        openssh-server 10.2p1-7.fc44 sudo 1.9.17-7.p2.fc44
```

* `awk` -> `/usr/bin/gawk`.
* `nc`: `/usr/bin/nc -> /etc/alternatives/nc -> /usr/bin/netcat` (the OpenBSD-derived
  `netcat` package; its usage line lists `-C certfile -e name -H hash -I length`);
  `update-alternatives --display nc`: `status is auto`, `netcat` and `ncat` both priority 10.
  Nmap's `ncat` is `/usr/bin/ncat`. `dnf.sh` does not pin the alternative (it is only recorded).
* `locale -a` includes `de_DE.utf8 en_US.utf8 ru_RU.utf8` (the langpacks bring many more).
* `LC_ALL=ru_RU.UTF-8 bash -c 'echo $EPOCHREALTIME'` -> `1792530342,254220` (a comma).
* sshd: `sshd -T` shows `passwordauthentication no`, `kbdinteractiveauthentication no`;
  `dnf-makecache.timer` disabled; `/etc/sudoers.d/kb` is `kb ALL=(ALL) NOPASSWD:ALL`;
  login shell of `kb` is `/bin/bash`; root filesystem 20 GB btrfs, 793 MB used.

## kb-fedora -- manual install

**Fallback only (2026-10-21).** `create/fedora.sh` now builds kb-fedora from the
cloud image (section "kb-fedora" above); this ISO checklist is for a host where that
fails. **The installer route is impossible with VirtualBox 7.1.12.** With the Fedora Server 44 netinst ISO
(`Fedora-Server-netinst-x86_64-44-1.7.iso`) `VBoxManage unattended install`
detects `RedHat_64`, version `44`, and `ConstructMedia()` fails deterministically
(also with `--script-template` and `--post-install-template` given, with and
without `--install-additions`, with `--start-vm=none`):

```
VBoxManage.exe: error: Unknown guest OS major version '44'
VBoxManage.exe: error: Details: code E_FAIL (0x80004005), component UnattendedWrap, interface IUnattended ...
VBoxManage.exe: error: Context: "ConstructMedia()" at line 2574 of file VBoxManageMisc.cpp
```

(its RHEL-family code only knows old major versions; `--dry-run` passes but
builds nothing). Use this checklist until a VirtualBox that knows Fedora 44 exists
or the owner chooses another route.

Where things are: ISO `C:\var\vbox\kb-lab\iso\Fedora-Server-netinst-x86_64-44-1.7.iso`
(sha256 `ae20c06bea746913cadea7d80463e13f4bf55bee4df2918111c921c674b70283`, checked against
`Fedora-Server-44-1.7-x86_64-CHECKSUM` in the same folder); VM folder
`C:\var\vbox\kb-lab\`; ssh key `~/.ssh/kbool_vmlab` (+ `.pub`).

1. VirtualBox: new VM `kb-fedora`, folder `C:\var\vbox\kb-lab`, type Linux / Fedora
   (64-bit), 4096 MB RAM, 4 CPUs, a new 20 GB dynamic VDI on a SATA controller, the
   ISO above in the optical drive. Network adapter 1 = NAT with port forward `ssh`,
   TCP, host `127.0.0.1`:2223 -> guest 22; Audio off; USB off. (CLI equivalent: the
   `createvm`/`modifyvm`/`createmedium`/`storagectl`/`storageattach` lines of
   `create/fedora.sh` with `--ostype Fedora_64`, port 2223; then
   `storageattach kb-fedora --storagectl SATA --port 1 --device 0 --type dvddrive --medium <iso>`
   and `startvm kb-fedora`.)
2. Install Fedora Server 44 with: language English (US), keyboard US, time zone UTC,
   installation destination = the 20 GB disk with automatic partitioning, network
   DHCP, host name `kb-fedora.lab`, installation source = the network default,
   software selection = Fedora Server (minimal is fine), root account: set a password
   (keep it); create user `kb`, **administrator (wheel) = yes**, a password (keep it:
   needed once, below).
3. Reboot into the installed system, log in as `kb` on the console and make sure sshd
   runs: `sudo systemctl enable --now sshd`.
4. Put the lab key in (from the host, Git-bash; the password is asked once):
   `ssh-copy-id -i ~/.ssh/kbool_vmlab.pub -p 2223 kb@127.0.0.1`, then on the VM
   `restorecon -R ~/.ssh` (SELinux), then
   `bash tools/vmlab/vmlab.sh up kb-fedora && bash tools/vmlab/vmlab.sh run kb-fedora -- true` must succeed.
5. Provision (the first sudo asks the password once; later NOPASSWD):
   ```
   bash tools/vmlab/vmlab.sh run kb-fedora -- sh -c 'cat > /tmp/dnf.sh' < tools/vmlab/provision/dnf.sh
   ssh -t -i ~/.ssh/kbool_vmlab -p 2223 kb@127.0.0.1 'sudo bash /tmp/dnf.sh'     # asks the password once
   bash tools/vmlab/vmlab.sh run kb-fedora -- rm -f /tmp/dnf.sh
   ```
   `dnf.sh` installs `bash git-core coreutils sed grep findutils diffutils gawk
   procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat
   tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru` (a missing name is
   fatal), then one by one `socat nodejs python3` (a missing name is printed as
   `dnf.sh: MISSING <pkg>`), sets `kb ALL=(ALL) NOPASSWD:ALL`, disables
   `dnf-makecache.timer`, sets sshd to key-only and makes bash the login shell of `kb`.
6. Record the versions into this README (a section "kb-fedora -- versions"):
   ```
   bash tools/vmlab/vmlab.sh run kb-fedora -- 'cat /etc/fedora-release; bash --version | head -1; rpm -q bash git-core coreutils sed grep findutils diffutils gawk procps-ng util-linux perl-interpreter perl-POSIX curl openssl nmap-ncat netcat tzdata glibc-langpack-en glibc-langpack-de glibc-langpack-ru socat nodejs python3 openssh-server sudo'
   bash tools/vmlab/vmlab.sh run kb-fedora -- 'readlink -f "$(command -v nc)"; nc -h 2>&1 | head -2; locale -a; LC_ALL=ru_RU.UTF-8 bash -c "echo \$EPOCHREALTIME"'
   ```
7. Snapshot: `bash tools/vmlab/vmlab.sh snapshot kb-fedora clean`.
8. Check: `bash tools/vmlab/vmlab.sh status` shows `kb-fedora poweroff ... clean`; `reset` +
   `up` + `run kb-fedora -- 'bash --version | head -1; sudo -n true && echo sudo-ok'` + `down` works;
   `sync kb-fedora` then `run kb-fedora -- 'ls ~/kbool'`.

## kb-freebsd

FreeBSD 15.1-RELEASE lab VM (name `kb-freebsd`, ssh port 2225, user `kb`, bash
`/usr/local/bin/bash`, snapshots `clean` and `clean-gnu`). Created 2026-10-21 by
`create/freebsd.sh` (+ `provision/pkg.sh`) from the official VM image, not from an
installer. VM, image and checksum live in `C:\var\vbox\kb-lab\`
(`img\FreeBSD-15.1-RELEASE-amd64-ufs.vmdk.xz`, its `.vmdk`, and
`img\FreeBSD-15.1-RELEASE-CHECKSUM.SHA256`, all from
`https://download.freebsd.org/releases/VM-IMAGES/15.1-RELEASE/amd64/Latest/`; `15.1` was the
newest `15.x-RELEASE` listed). The VM is not part of the repository.

```
bash tools/vmlab/create/freebsd.sh      # whole recipe, ~12 min; downloads the image if absent;
                                        # takes both snapshots; the VM is left powered OFF
```

The script (refuses with rc 13 if `kb-freebsd` exists):

1. picks the newest `15.x-RELEASE` (or `KB_FB_REL`), downloads image + `CHECKSUM.SHA256` into
   `img\` when absent, compares the `SHA256 (...)` line with `sha256sum`, `xz -dk`;
2. `clonemedium` VMDK -> `kb-freebsd.vdi` (VirtualBox reads the VMDK itself),
   `closemedium` of the VMDK (clonemedium registered it; the file stays), `modifymedium
   --resize 20480`, `createvm --ostype FreeBSD_64`, 4096 MB, 4 CPUs, BIOS, NAT with
   `ssh,tcp,127.0.0.1,2225,,22` and `--nat-localhostreachable1 on`, audio/USB off, VDI on SATA;
3. boots headless, waits 120 s (the login prompt is there after ~60 s), then types on the VGA
   console, one line per `controlvm keyboardputstring` + Enter (`keyboardputscancode 1c 9c`),
   5 s apart: `root` (the image has no root password), `sysrc sshd_enable=YES`,
   `pw useradd kb -m -G wheel -s /bin/sh`, `mkdir -p /home/kb/.ssh`,
   `echo '<the .pub line>' > /home/kb/.ssh/authorized_keys`, the `chown`/`chmod` line,
   `service sshd start`; `vmlab run kb-freebsd -- true` must answer within 90 s;
4. still in the root console, one long line: disable the `FreeBSD-base` repository (below),
   `pkg bootstrap` + `pkg install -y sudo bash git` (up to 4 tries), `kb ALL=(ALL) NOPASSWD: ALL`
   into `/usr/local/etc/sudoers.d/kb`, `pw usermod kb -s /usr/local/bin/bash`, `touch
   /tmp/kb-console.done`; the script polls for that file over ssh (up to 15 min), types `exit`;
5. `provision/pkg.sh` through `sudo -n sh`: sudoers, packages, shell, **`fdesc /dev/fd fdescfs rw 0 0`
   in `/etc/fstab` + `mount /dev/fd`** (process substitution, H14; `bash -c 'cat <(echo ok)'`
   prints `ok` and the script checks it), sshd key-only (`PasswordAuthentication no` and
   `KbdInteractiveAuthentication no` put at the TOP of `/etc/ssh/sshd_config`: first value wins,
   `sshd -T` confirms), `pkg clean -y`; `vmlab snapshot kb-freebsd clean`;
6. `provision/pkg.sh --gnu`: `coreutils gsed gawk findutils gnugrep diffutils netcat curl perl5
   socat`, one `pkg install` each (a missing one prints `pkg.sh: MISSING <pkg>`; none was
   missing); `vmlab snapshot kb-freebsd clean-gnu`.

The console has no serial log (the image has no serial console; a UART log stayed empty). For
debugging: `VBoxManage controlvm kb-freebsd screenshotpng X.png`; on failure the script saves one
as `$KB_SCRATCH/freebsd-fail.png`.

Things found on VirtualBox 7.1.12 + FreeBSD 15.1:

* **The image is a pkgbase install** (531 `FreeBSD-*` packages) and ships
  `/usr/local/etc/pkg/repos/FreeBSD.conf` = `FreeBSD-base: { enabled: yes }`. Every `pkg
  install` then dies with `Unable to update repository FreeBSD-base` (`SSL connect error`
  fetching `.../base_release_1/meta.conf`; `fetch` says `Authentication error`; the same URL
  answers 302 to the host's curl). The card's `pkg install -y ...` therefore failed with rc 3
  until that repository was disabled: `create/freebsd.sh` and `pkg.sh` write
  `FreeBSD-base: { enabled: no }` into that file. Only the ports repositories are used.
* **The pkg mirrors are flaky from this host**: with the SRV mirror selection, `pkg update` /
  `install` fails at random with `SSL connect error` (the very same command worked a minute
  later). The console line and `pkg.sh` retry 4 times, 5 s apart.
* `git` pulls in `perl5` and `python312` (pkg dependencies), so they are in `clean` as well;
  there is no unversioned `python3` (`/usr/local/bin/python3.12` only).
* `$0` of an ssh command is `bash` (login shell `/usr/local/bin/bash`); `kb`'s password field is
  `*` (key login only).
* The image's `growfs` makes the root 18 GB UFS (20 GB disk).
* ACPI power button works: `down` takes a few seconds.

Execution engine, from `C:\var\vbox\kb-lab\kb-freebsd\Logs\VBox.log`:

```
HM: HMR3Init: AMD-V w/ nested paging
```

### Versions recorded at creation (2026-10-21)

`freebsd-version`: `15.1-RELEASE`; `uname -srm`: `FreeBSD 15.1-RELEASE amd64`.
`bash --version | head -1`: `GNU bash, version 5.3.20(0)-release (amd64-portbld-freebsd15.1)`.
`pkg info` (clean): `bash-5.3.20 git-2.56.0 sudo-1.9.17p2_2 curl-8.22.0 perl5-5.42.3
python312-3.12.15`; added by `clean-gnu`:

```
coreutils-9.9   gsed-4.10   gawk-5.4.1_1   findutils-4.11.0   gnugrep-3.12
diffutils-3.12  netcat-1.10_4   socat-1.8.1.3   (curl and perl5 were already there)
```

Binary names in `clean-gnu` (`command -v`):

* coreutils: `g`-prefixed in `/usr/local/bin` (`ghead gtail gdate gsort gseq ...`);
  **GNU stat is `gnustat`**, `gstat` is FreeBSD's GEOM tool `/usr/sbin/gstat`;
* `gsed`, `gawk`, `gfind` (+ `gxargs`, `glocate`), `ggrep` (+ `gegrep gfgrep`), `gdiff gdiff3 gcmp`;
* `sed`, `awk`, `find`, `grep` stay the BSD ones in `/usr/bin`;
* netcat: base `nc` = `/usr/bin/nc` (OpenBSD-derived: `usage: nc [-46DdEFhklNnrStUuvz] ...`);
  the `netcat` package is Hobbit's netcat 1.10 as `/usr/local/bin/netcat`
  (`nc -l -p port` syntax); `socat` is `/usr/local/bin/socat`;
* `curl`, `perl` in `/usr/local/bin`; `openssl` is the base one (`/usr/bin/openssl`).

`LC_ALL=ru_RU.UTF-8 bash -c 'echo $EPOCHREALTIME'` -> `1792543653,485799` (a comma).
`/etc/fstab` has `fdesc /dev/fd fdescfs rw 0 0`; `mount | grep fdescfs` -> `fdescfs on /dev/fd (fdescfs)`.

## kb-alpine

Alpine Linux 3.24.2 lab VM (name `kb-alpine`, ssh port 2224, user `kb`, bash `/bin/bash`,
snapshots `clean` and `clean-gnu`, 2048 MB, 12 GB). Created 2026-10-21 by `create/alpine.sh`
(+ `provision/apk.sh`) from the official **virt** ISO with `setup-alpine -f`. VM and ISO live in
`C:\var\vbox\kb-lab\` (`iso\alpine-virt-3.24.2-x86_64.iso` and its `.sha256` from
`https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/`; the newest `x.y.z`,
release candidates excluded). The VM is not part of the repository.

```
bash tools/vmlab/create/alpine.sh       # whole recipe, ~12 min; downloads the ISO if absent;
                                        # takes both snapshots; the VM is left powered OFF
```

The script (refuses with rc 13 if `kb-alpine` exists):

1. newest ISO (or `KB_ALPINE_VER`), downloaded when absent, `sha256sum -c` on the `.sha256`;
2. `createvm --ostype Linux_64`, 2048 MB, 4 CPUs, BIOS, NAT `ssh,tcp,127.0.0.1,2224,,22` +
   `--nat-localhostreachable1 on`, boot order dvd, disk; a 12 GB VDI and the ISO on SATA;
3. boots headless, waits 60 s, types on the VGA console (2 s per line): `root` (no password),
   the answer file (a here-document into `/tmp/a`, the card's content: `KEYMAPOPTS="us us"`,
   `HOSTNAMEOPTS="-n kb-alpine"`, `INTERFACESOPTS` lo + eth0 dhcp, `DNSOPTS="-d lab 10.0.2.3"`,
   `TIMEZONEOPTS="-z UTC"`, `PROXYOPTS="none"`, `APKREPOSOPTS="-1"`, `USEROPTS="-a -u kb"`,
   `USERSSHKEY="<the .pub line>"`, `SSHDOPTS="-c openssh"`, `NTPOPTS="-c busybox"`,
   `DISKOPTS="-m sys /dev/sda"`), then
   `ERASE_DISKS=/dev/sda setup-alpine -e -f /tmp/a; poweroff` (no prompt came up: the
   erase confirmation is answered by `ERASE_DISKS`). The script waits for `poweroff`, detaches
   the ISO (`storageattach ... --medium emptydrive`), boots from disk and waits up to 150 s for
   ssh; if there is none the whole step is repeated (up to `KB_AL_TRIES` = 4; both full runs
   needed one attempt);
4. root console of the installed system (empty root password, console only): `permit nopass
   :wheel` into `/etc/doas.d/20-wheel.conf`, `exit`; `vmlab run kb-alpine -- 'doas -n true'`;
5. `provision/apk.sh` through `doas -n sh`: `apk add bash git`, kb's login shell
   (`sed -i 's#^\(kb:.*:\)[^:]*$#\1/bin/bash#' /etc/passwd`, checked with `grep '^kb:'` ->
   `kb:x:1000:1000::/home/kb:/bin/bash`), sshd key-only (`sshd_config.d/00-kbool-lab.conf`), the
   ACPI power-button fix below; `vmlab snapshot kb-alpine clean`;
6. `provision/apk.sh --gnu`: `coreutils sed grep findutils diffutils gawk procps-ng util-linux
   perl curl openssl netcat-openbsd tzdata` (a name missing from the index prints `apk.sh:
   MISSING <pkg>`; `procps-ng` would fall back to `procps`, reported; neither happened);
   `vmlab snapshot kb-alpine clean-gnu`.

Things found on VirtualBox 7.1.12 + Alpine 3.24.2:

* **DNS**: the NAT's resolver (10.0.2.3) loses a few percent of the lookups; musl and apk report
  `DNS: transient error (try again later)`. `setup-alpine` cannot retry: in 5 of 5 manual attempts without the pin
  it ended after `Creating file systems...` with `ERROR: <pkg>: DNS: transient error` and no
  system (or with `unable to select packages: syslinux`). `apk update` in the live system failed
  on about half of its runs; with `nameserver 1.1.1.1` 10 of 10 worked, but DHCP rewrites
  `resolv.conf` during `setup-alpine` (and with `/etc/udhcpc/udhcpc.conf` `RESOLV_CONF="no"` and
  1.1.1.1 a package download still lost a lookup), and `--natdnshostresolver1 on` did not help
  either, so none of these is used. What is used (the card's answer file is unchanged): before
  `setup-alpine` the live system gets the four A records of `dl-cdn.alpinelinux.org`
  (`151.101.2.132 151.101.66.132 151.101.130.132 151.101.194.132`, Fastly) in `/etc/hosts` and
  `https://dl-cdn.alpinelinux.org/alpine/v3.24/{main,community}` in `/etc/apk/repositories`;
  `provision/apk.sh` pins the same lines while it runs (removed again at exit, the installed
  `/etc/hosts` is clean) and retries `apk` up to 8 times. `APKREPOSOPTS="-1"` needs
  `mirrors.alpinelinux.org`, which answered `wget: bad address` about half of the time
  (the step then only warns `No mirror found`); when it works it appends
  `http://dl-cdn.alpinelinux.org/alpine/v3.24/main`, so the installed
  `/etc/apk/repositories` has that extra `http` line (harmless).
* `setup-alpine -a` writes `permit persist :wheel` for doas, which asks `kb` for a password it
  does not have (`doas: Authentication required`); hence step 4.
* **ACPI power button**: with VirtualBox's fixed power button the `linux-virt` kernel's `button`
  driver registers no input device (`LNXPWRBN:00` has no driver), so `acpid` never hears the
  press and `vmlab down` fell back to the hard poweroff after 60 s. `apk.sh` loads the
  `tiny-power-button` module instead with `power_signal=12` (SIGUSR2 = busybox `poweroff`; the
  default SIGINT would be "ctrlaltdel" = reboot): `/etc/modprobe.d/kbool-lab.conf`
  (`blacklist button`, `options tiny-power-button power_signal=12`) and `tiny-power-button`
  in `/etc/modules`. `down` now takes about 7 s.
* `nc`: `/usr/bin/nc` is `netcat-openbsd`. Root can log in on the console with an empty
  password (`setup-alpine -e`); sshd does not allow it.
* musl has no `ru_RU` locale: `LC_ALL=ru_RU.UTF-8 bash -c 'echo $EPOCHREALTIME'` prints a dot
  (`1792537375.060807`), unlike the glibc VMs and FreeBSD.

Execution engine, from `C:\var\vbox\kb-lab\kb-alpine\Logs\VBox.log`:

```
HM: HMR3Init: AMD-V w/ nested paging
```

### Versions recorded at creation (2026-10-21)

`cat /etc/alpine-release`: `3.24.2`; kernel `6.18.57-0-virt`. `bash --version | head -1`:
`GNU bash, version 5.3.9(1)-release (x86_64-alpine-linux-musl)`. `clean` has `bash-5.3.9-r1
git-2.54.0-r0` on top of the base system (73 packages, busybox `sed grep awk find`, no
python, no perl); `clean-gnu` adds (129 packages in all):

```
coreutils-9.11-r0   sed-4.9-r2          grep-3.12-r0       findutils-4.10.0-r1
diffutils-3.12-r0   gawk-5.3.2-r2       procps-ng-4.0.6-r0 util-linux-2.42.3-r1
perl-5.42.2-r1      curl-8.22.0-r0      openssl-3.5.9-r0   netcat-openbsd-1.234.1-r0
tzdata-2026e-r0
```

Binary names in `clean-gnu`: GNU tools take the plain names, **there is no `g` prefix**:
`command -v gsed gawk gfind sed awk find` -> `/usr/bin/gawk /bin/sed /usr/bin/awk /usr/bin/find`
(`awk -> gawk`; `/bin/sed` and `/bin/grep` are the GNU ones, the packages replace the busybox
links; `date --version` says `GNU coreutils 9.11`). In `clean` they are busybox.
