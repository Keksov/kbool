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

## kb-fedora -- manual install

**Status (2026-10-20): the unattended install is impossible with VirtualBox
7.1.12.** `create/fedora.sh` and `provision/dnf.sh` are written but were never run
past this point (untested). With the Fedora Server 44 netinst ISO
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
