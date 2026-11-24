# hako

Small, fast-booting Vagrant boxes for Macs (Apple Silicon and Intel), built
with Packer from the distribution's official **cloud image** and published on
this repository's GitHub Releases with a Vagrant box catalog.

| Box                 | Architecture | Providers                                     |
|---------------------|--------------|-----------------------------------------------|
| `hako/ubuntu-26.04` | arm64        | `libvirt` (vagrant-qemu, vagrant-libvirt), `virtualbox` |
| `hako/ubuntu-26.04` | amd64 (Intel x86) | `libvirt` (vagrant-qemu, vagrant-libvirt), `virtualbox` |
| `hako/archlinux`    | amd64 (Intel x86) | `libvirt` (vagrant-qemu, vagrant-libvirt), `virtualbox` (new, not yet published) |
| `hako/gentoo`       | arm64, amd64 (Intel x86) | `libvirt` (vagrant-qemu, vagrant-libvirt) (new, not yet published; amd64 not yet built) |

Both architectures share one box name; Vagrant picks the one matching the
host. Each is built natively on a host of its own architecture (never
emulated), so arm64 boxes come from an Apple Silicon Mac and amd64 boxes from
an Intel one.

Catalogs: [`ubuntu-26.04.json`](ubuntu-26.04.json), `archlinux.json` and
`gentoo.json` (each written by that distro's first `make publish`)

Each distribution builds from its own directory, [`ubuntu/`](ubuntu) and
[`archlinux/`](archlinux) and [`gentoo/`](gentoo). The rest of this README
describes the Ubuntu box; see [Arch Linux](#arch-linux) and [Gentoo](#gentoo)
for how those differ.

## Why

The `bento/ubuntu-26.04` box (202606.01.0) waits two minutes on every boot:
the installer's netplan file renames the NIC by MAC address while bento's own
netplan file configures `eth0`, so `systemd-networkd-wait-online` times out
([chef/bento#1709](https://github.com/chef/bento/issues/1709)).

hako boxes start from Ubuntu's cloud image instead of an installer ISO and
ship with exactly one netplan file that matches any ethernet NIC by name
(`e*`): no MAC address, no `set-name`. Measured with `systemd-analyze`:

| Host                       | Provider      | Boot  | `vagrant up` |
|----------------------------|---------------|-------|--------------|
| Apple Silicon (arm64)      | both          | ~5 s  | 20-30 s      |
| Intel Mac (amd64)          | vagrant-qemu  | ~11 s | ~28 s        |
| Intel Mac (amd64)          | VirtualBox    | ~14 s | ~50 s        |

## Using the box

The catalog is not on HashiCorp's registry, so point `box_url` at it. It's
served by GitHub Pages, from this repository's `main` branch:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box     = "hako/ubuntu-26.04"
  config.vm.box_url = "https://darkn3rd.github.io/hako/ubuntu-26.04.json"
  # config.vm.box_version = "2026.11.10"   # optional pin

  # vagrant-qemu (libvirt box format)
  config.vm.provider "qemu" do |qe|
    qe.memory = "2G"
    qe.smp    = 2
  end

  # VirtualBox 7.1+ (Apple Silicon or Intel)
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus   = 2
  end
end
```

```bash
vagrant up --provider=qemu
```

```bash
vagrant up --provider=virtualbox
```

Because the catalog has a `versions` list, `vagrant box outdated` and
`vagrant box update` work as with any registry box.

### Architecture

Use Vagrant 2.4 or newer. It reads the `architecture` of each catalog entry
and, by default (`config.vm.box_architecture = :auto`), downloads the box for
the host: arm64 on Apple Silicon, amd64 on Intel. Nothing needs to be set.
Older Vagrant ignores the architecture and can download the wrong one.

To choose an architecture yourself, for example for a remote host:

```ruby
config.vm.box_architecture = "amd64"
```

When a version has both architectures, the catalog marks amd64 as
`default_architecture`. Vagrant only falls back to it when the host's
architecture isn't in the catalog.

A catalog on disk works the same way, which is how `make test` runs boxes
before they are published:

```ruby
config.vm.box_url = "file:///path/to/hako/boxes/ubuntu-26.04.local.json"
```

### What is in the box

- Ubuntu 26.04 server cloud image (arm64 or amd64), packages upgraded at build time.
- User `vagrant` (password `vagrant`), passwordless sudo, Vagrant's insecure
  public keys (RSA and ed25519); Vagrant swaps in a per-VM key on first `up`.
- One netplan file, `/etc/netplan/01-hako-netcfg.yaml`: DHCP on every NIC
  named `e*`. Its id sorts last, so per-interface configs added later (a
  Vagrant `private_network`, a cloud-init seed) win for their NIC.
- cloud-init stays installed but only reacts to a NoCloud/ConfigDrive seed.
  With no seed (a plain `vagrant up`) it is disabled for that boot and costs
  nothing; `config.vm.cloud_init` and vagrant-qemu's private networks still
  work.
- Empty `/etc/machine-id` and no SSH host keys: each VM gets its own on
  first boot (`hako-ssh-hostkeys.service` runs `ssh-keygen -A` before
  `ssh.socket` starts).
- Only the running kernel; no kernel headers (except in the VirtualBox box).
- `apt-daily*` timers and `unattended-upgrades` disabled, so nothing holds
  the dpkg lock while you provision.
- 64 GB sparse disk, already grown. Box files are about 0.7 GB (libvirt)
  and 0.8 GB (virtualbox).
- VirtualBox box only: Guest Additions (shared folders via `vboxsf`), with
  build tools and kernel headers kept so the modules rebuild on kernel
  upgrades.
- Ready for Docker: the kernel and its installed modules have everything
  Docker needs (checked by every `make test`, see Testing). Docker itself is
  not preinstalled; `sudo apt-get install docker.io` (or Docker's own
  packages) works as-is.

## Building

Requirements (macOS, Apple Silicon or Intel): Packer 1.9+ (`brew install
hashicorp/tap/packer`), QEMU (Homebrew), VirtualBox 7.1+ for the VirtualBox
box, Vagrant 2.4+ with the `vagrant-qemu` plugin, `jq`, and `gh` for publishing.
`mise run deps` installs them (see below).

### Setting up with mise

Each distro directory has its own `mise.toml` (there is none at the repo
root). It pins the command-line tools (`packer`, `jq`, `gh`) and has tasks
for setting up and checking the machine. Building, testing and publishing
stay in the Makefile; the matching mise tasks just call it:

```bash
cd ubuntu
mise trust
mise run deps                   # packer/jq/gh, then QEMU, Vagrant, plugins, ... for this platform
mise run doctor                 # check everything, with the commands that fix what's missing
mise run build                  # = make build; extra arguments pass on: mise run build PROVIDERS=libvirt
```

| Task | What it runs |
|---|---|
| `mise run deps` | `mise install packer jq gh`, then `scripts/install-deps` (`--dry-run` prints the commands instead) |
| `mise run doctor` | `scripts/doctor` |
| `mise run build`, `test`, `all`, `publish`, `clean` | the `make` target of the same name |

`scripts/install-deps` installs only what's missing, with the platform's
package manager:

- **macOS:** Homebrew installs QEMU (with its UEFI firmware), Vagrant, and
  VirtualBox where the distro builds that box.
- **Debian/Ubuntu, Arch, Fedora:** the package manager (with sudo) installs
  QEMU for the host's architecture, OVMF/AAVMF firmware, `xorriso`, libvirt
  and the headers `vagrant-libvirt` builds against. It then enables
  `libvirtd` and adds you to the `kvm` and `libvirt` groups (log in again
  afterwards).
- **Vagrant on Linux:** on Debian/Ubuntu and Fedora it comes from
  HashiCorp's repository, since distro packages are older than 2.4. On Arch
  it comes from the AUR through `paru` or `yay`, if one is installed.
- **Then, everywhere:** the Vagrant plugin `make test` uses (`vagrant-qemu`
  on macOS, `vagrant-libvirt` on Linux), and Vagrant's insecure key, which
  the build logs in with.

VirtualBox isn't installed on Linux (distro packages are often older than
7.1); the script says where to get it.

`scripts/doctor` is read-only. It checks:

- that the distro builds on this host (Ubuntu: macOS only; Arch Linux: amd64
  only; Gentoo: macOS or Linux, arm64 or amd64), and that the shell isn't
  running under Rosetta on Apple Silicon;
- hardware virtualization (HVF on macOS, a usable `/dev/kvm` on Linux);
- mise (optional), Packer 1.9+ and the plugins the templates need, QEMU for
  the host's architecture, `qemu-img`, the UEFI firmware, an ISO tool for
  the build's cloud-init seed and `jq`;
- Vagrant 2.4+, its insecure key, and the plugin `make test` uses:
  `vagrant-qemu` on macOS, or `vagrant-libvirt` plus access to libvirt and
  its `default` storage pool on Linux;
- VirtualBox 7.1+ where the distro builds a VirtualBox box
  (`PROVIDERS=libvirt mise run doctor` skips it);
- `gh` signed in (a warning only: just `make publish` needs it), and free
  disk space.

When something fails, the fixes start with `mise run deps`, followed by the
individual commands for this platform (Homebrew, apt, pacman or dnf). Native
Windows is detected and pointed at WSL2 with nested virtualization, which
counts as a Linux host. Exit status is 1 if any check fails; warnings don't
fail it.

Both scripts work without mise too (`scripts/doctor`,
`scripts/install-deps`). What a distro needs is in its
`scripts/requirements.sh`; the shared code is in `scripts/doctor-lib.sh` and
`scripts/install-deps-lib.sh` at the repo root.

Commands and paths in Building, Testing and Publishing are relative to
`ubuntu/`. From the repo root, prefix the target with the distro instead:
`make ubuntu-build`, `make ubuntu-test`, `make ubuntu-publish`.

```bash
cd ubuntu
make build                      # both providers, VERSION = today (YYYY.MM.DD)
```

```bash
make build PROVIDERS=libvirt    # only the libvirt box
```

The same commands build on both kinds of Mac; the Makefile picks the
architecture from `uname -m`:

| Mac | `ARCH` | Builds |
| --- | --- | --- |
| Apple Silicon | `arm64` | arm64 boxes, with `qemu-system-aarch64` and an Arm VirtualBox VM |
| Intel | `amd64` | amd64 boxes, with `qemu-system-x86_64` and an x86 VirtualBox VM |

Each Mac builds only its own architecture, natively under Apple's Hypervisor
framework; the build never emulates the other one. So `ARCH` has to match the
Mac, and setting `ARCH=amd64` on Apple Silicon fails rather than cross-building.

On Apple Silicon, run `make` from a native (arm64) shell. A terminal running
under Rosetta reports `x86_64`, so the Makefile stops with an error there
instead of starting an amd64 build. `arch -arm64 make build` runs it natively.

The Makefile looks up QEMU's firmware directory once with `brew --prefix`
(`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel). Override it with
`QEMU_SHARE=...` if QEMU is installed elsewhere. The cloud image, QEMU binary,
machine type, EFI firmware and VirtualBox platform are all chosen from `ARCH`
(see `locals` in `packer/variables.pkr.hcl` and `scripts/make-vbox-ovf.sh`).

Boxes land in `boxes/`, named
`ubuntu-26.04-<version>-<provider>-<arch>.box`.

### libvirt

Packer's `qemu` builder boots the cloud image itself as the disk
(`disk_image = true`) with HVF acceleration and UEFI (`virt` machine on
arm64, `q35` on amd64). A NoCloud seed
(`cloud-init/`), attached as a `cidata` CD only during the build, creates
the `vagrant` user. `scripts/base.sh` upgrades packages and installs the
files in `files/`. The VM then reboots into the upgraded kernel and
`scripts/kernel.sh` purges the old kernel and the headers. `scripts/cleanup.sh`
runs `cloud-init clean`, empties the machine-id, removes host keys, logs and
caches, and trims free space so `qemu-img` can compress the image. The
`vagrant` post-processor packages the qcow2 and `metadata.json` as a libvirt
box. Packer prepends a `libvirt.driver = "qemu"` block to the box's
Vagrantfile; vagrant-qemu ignores it.

### virtualbox

Packer cannot turn a qcow2 into a VirtualBox VM, and two ways were
considered:

1. **Reuse the libvirt image** (chosen). `scripts/make-vbox-ovf.sh`
   converts the finished qcow2 to VMDK and wraps it in a VirtualBox OVF
   for the same architecture (EFI and a VirtIO NIC; VirtIO storage on arm64,
   SATA on amd64). Packer's `virtualbox-ovf` builder
   imports it, installs the Guest Additions and runs the same cleanup, which
   zero-fills free space here (VirtualBox ignores TRIM on VMDK disks).
2. An autoinstall ISO build (bento-style). It would need its own installer
   config and care to avoid the stale installer netplan file that causes
   the bento delay, and the result would differ from the cloud-image base
   used everywhere else.

Option 1 keeps a single base: both boxes are the same configured cloud
image, the VirtualBox build is short, and no installer runs at all.

## Testing

```bash
make test
```

For each provider this writes a local catalog (`boxes/ubuntu-26.04.local.json`
with `file://` URLs), removes any cached copy of that box version, runs
`vagrant up` in a scratch directory (`--provider=qemu` for the libvirt box),
and then:

- fails if `systemd-analyze time` reports a boot over `MAX_BOOT` seconds
  (default 15);
- checks SSH, passwordless sudo, exactly one netplan file and
  `systemctl is-system-running` = `running`;
- VirtualBox only: mounts the project as a `vboxsf` shared folder;
- reboots with `vagrant reload` and checks SSH again;
- runs Moby's [`check-config.sh`](third_party/moby/check-config.sh) in the
  VM and fails if a feature Docker requires is missing (optional ones such as
  ZFS are only reported);
- loads the kernel modules Docker uses (`overlay`, `br_netfilter`, `veth`,
  netfilter/NAT), since `check-config.sh` only reads the kernel config and
  would not notice a module file missing from the box;
- unless `DOCKER_TEST=0`: installs Docker in the test VM (not the box), runs
  a container with outbound HTTP and serves a page on a published port;
- destroys the VM.

`make test DOCKER_TEST=0` skips the Docker install, for example without
Docker Hub access; the kernel and module checks still run.

The cached box is removed with `vagrant box remove --provider ...` but
without `--architecture`: Vagrant 2.4.9 then wrongly reports that the
architecture is not installed (seen on arm64 and amd64), which would leave an
old build in the cache. All Vagrant commands run from a scratch directory,
because Vagrant loads the first Vagrantfile it finds walking up from the
current directory, and an unrelated one in a parent of the repository would
break the run.

## Publishing

```bash
make publish
```

1. Refuses any box of 2 GiB or more (GitHub's release asset limit).
2. Stops if `origin/main` has changes to `ubuntu-26.04.json` that this
   checkout doesn't have, so a stale catalog can't drop entries that another
   Mac published.
3. Adds this Mac's architecture to the version in `ubuntu-26.04.json`, with
   each provider's release URL
   (`https://github.com/darkn3rd/hako/releases/download/ubuntu-26.04-v<version>/...`)
   and sha256 checksum. Entries for the other architecture are kept.
4. Creates the GitHub release `ubuntu-26.04-v<version>` if needed and
   uploads the boxes (`gh release upload --clobber`).
5. Rewrites the release notes with `scripts/release-notes.sh`, listing every
   architecture and provider now in the release.

Then commit and push `ubuntu-26.04.json`: GitHub Pages serves it from the
`main` branch at `https://darkn3rd.github.io/hako/ubuntu-26.04.json`.
Vagrant only reads a remote catalog served as `application/json`, so use the
Pages URL, not `raw.githubusercontent.com` (served as `text/plain`) or a
release asset (served as `application/octet-stream`); with those, Vagrant
tries to unpack the JSON as a box. Release tags are per box (`ubuntu-26.04-v<version>`) so other
distributions can share this repository.

A rebuild changes the checksums, so publish the boxes you tested: `make
publish` rewrites the catalog entries from the files in `boxes/`.

To publish a box built on another day, pass its version:
`make publish VERSION=2026.11.10`.

### Publishing both architectures

arm64 and amd64 boxes come from two Macs but go into one version, one release
and one catalog. Use the same `VERSION` on both, since it otherwise defaults
to the day each Mac builds:

1. On the Apple Silicon Mac:

   ```bash
   make build test VERSION=2026.11.21
   make publish VERSION=2026.11.21
   git commit -am "Publish hako/ubuntu-26.04 2026.11.21 (arm64)" && git push
   ```

2. On the Intel Mac, pull the catalog first, then do the same:

   ```bash
   git pull
   make build test VERSION=2026.11.21
   make publish VERSION=2026.11.21
   git commit -am "Publish hako/ubuntu-26.04 2026.11.21 (amd64)" && git push
   ```

Either Mac can go first. Each one tests only its own architecture, and
`make publish` refuses to run on a checkout that's missing the other Mac's
catalog changes.

## Arch Linux

`archlinux/` builds `hako/archlinux` the same way, from the official
[arch-boxes](https://gitlab.archlinux.org/archlinux/arch-boxes) cloud image
(`Arch-Linux-x86_64-cloudimg.qcow2`, which ships cloud-init like Ubuntu's).
The differences:

- **amd64 only.** Arch Linux publishes no arm64 cloud image (Arch Linux ARM
  is a separate project), so the Makefile stops on an arm64 host. Build on an
  Intel Mac (HVF) or an x86 Linux host (KVM; `ACCEL` is picked from `uname -s`).
- **No OS version.** Arch is a rolling release: the box is `hako/archlinux`,
  the date version is the package snapshot, and release tags are
  `archlinux-v<version>`.
- **Networking** is one systemd-networkd file,
  `/etc/systemd/network/99-hako-ethernet.network` (DHCP on any `e*` NIC),
  instead of netplan. It sorts last, so per-NIC files from Vagrant or a
  cloud-init seed win for their NIC.
- **No kernel cleanup.** pacman replaces the kernel in place; the build still
  reboots once so the box is checked to boot the upgraded kernel.
- **VirtualBox** support comes from `virtualbox-guest-utils-nox`: the Arch
  kernel already has `vboxguest`/`vboxsf`, so there are no build tools or
  headers in the box and nothing to rebuild on kernel upgrades.
- **Docker** is tested the same way; the test VM installs it with
  `pacman -S docker`.
- **pacman keyring** keeps only the public packager keys at cleanup; each
  VM's first boot, in `hako-pacman-init.service`, creates its own master key
  and signs the trusted keys with it, so VMs don't share a master key. The
  keys are imported at build time because importing them is the slow part of
  first boot. (The
  image's own `pacman-init.service` needs a systemd "first boot", which hako
  boxes don't have: they ship an empty `/etc/machine-id`, as the Ubuntu box
  does.)
- **initramfs without autodetect**, as arch-boxes builds it, so a kernel
  upgrade during the build doesn't drop the SATA drivers the VirtualBox box
  boots from.

```bash
cd archlinux && make                    # build, then test (or from the root: make archlinux-all)
make archlinux-publish
```

On an x86 Linux host the build uses KVM and the distro's OVMF firmware
(found automatically; override with `EFI_CODE=... EFI_VARS=...`), and
`make test` boots the libvirt box with vagrant-libvirt instead of
vagrant-qemu. You need `xorriso` (for the build's cloud-init CD), `ovmf`,
access to `/dev/kvm` and to libvirt (the `kvm` and `libvirt` groups; log in
again after adding them). The VirtualBox box is built only when
`VBoxManage` is installed, so on a host without it `make` builds and tests
just the libvirt box:

```bash
sudo apt-get install xorriso ovmf        # Debian/Ubuntu
cd archlinux && make
```

`make build` runs a quick preflight check first and lists anything missing.
`mise run deps` installs these on Debian/Ubuntu, Arch and Fedora, and
`mise run doctor` checks more (Vagrant, libvirt access, plugins); see
[Setting up with mise](#setting-up-with-mise).

## Gentoo

`gentoo/` builds `hako/gentoo` from Gentoo's official cloud-init disk image
(`di-<arch>-cloudinit-<timestamp>.qcow2`, rebuilt weekly by release
engineering: systemd profile, dist-kernel, XFS root, GRUB, cloud-init). The
differences from the Ubuntu box:

- **arm64 and amd64**, one box name, as for Ubuntu. Each is built natively;
  the Makefile picks the architecture from `uname -m`.
- **No OS version.** Gentoo is a rolling release: the box is `hako/gentoo`,
  the date version is the snapshot, and release tags are `gentoo-v<version>`.
  The image's file name carries its build timestamp, so `make build` looks up
  the latest one (`scripts/cloud-image.sh`, from
  `latest-di-<arch>-cloudinit.txt` and the image's `.sha256`). Pin one with
  `CLOUD_IMAGE_URL=... CLOUD_IMAGE_CHECKSUM=sha256:...`. The box records the
  image it came from in `/etc/hako-release`.
- **Packages are not upgraded at build time.** The image is at most a week
  old, and an `@world` update would compile from source, the kernel included,
  turning a two-minute build into hours.
- **Binary packages by default.** The image already lists Gentoo's binhost
  (signatures verified); the box adds `FEATURES="getbinpkg"` to `make.conf`,
  so `emerge` installs prebuilt packages where they match instead of
  compiling.
- **No ebuild repository in the box** (the image ships none either). Fetch
  one before the first `emerge`:

  ```bash
  sudo emerge-webrsync
  ```

- **No linux-firmware.** A VM loads no hardware firmware, and the package is
  about 640 MB; removing it takes the box from 1.1 GB to 0.8 GB. It is also
  removed from `@world`, so updates don't bring it back.
- **Networking** is one systemd-networkd file, as in the Arch box.
- **cloud-init stays off without a seed.** Gentoo's cloud-init enables itself
  when no datasource is found, then fails four units and writes a network
  file on every plain `vagrant up`. `/etc/cloud/ds-identify.cfg` sets
  `notfound=disabled`; a VM with a NoCloud seed still runs cloud-init.
- **sshd** is enabled as a unit (the image only starts it from cloud-init),
  and the GRUB menu timeout is 0.
- **Boots with BIOS or UEFI (amd64).** Gentoo's image is UEFI-only, but
  vagrant-libvirt and vagrant-qemu start x86_64 VMs with BIOS (SeaBIOS) by
  default. The build adds a 1 MiB GRUB BIOS boot partition in the gap before
  the ESP and installs GRUB for BIOS next to the image's UEFI GRUB; both read
  the same `/boot/grub/grub.cfg`. The box boots with no provider settings,
  and with UEFI when the provider is configured for it (see
  [Booting the Gentoo box with UEFI](#booting-the-gentoo-box-with-uefi)).
  The arm64 box is UEFI only, as every arm64 VM is.
- **Named CPU model on an Intel Mac (amd64).** Under HVF, `-cpu host` passes
  the CPU's AVX-512 feature bits to the guest without enabling the AVX-512
  register state, so Gentoo's kernel panics at boot with an invalid opcode
  (in `chacha_8block_xor_avx512vl`). The build uses `Skylake-Client` there
  (`packer/variables.pkr.hcl`), and the box's Vagrantfile sets the same model
  for vagrant-qemu on an Intel Mac (`vagrantfiles/box.rb`). Linux with KVM
  keeps `host`.
- **libvirt only.** Neither architecture's dist-kernel has the
  `vboxguest`/`vboxsf` modules, and the image has no kernel build tree to
  compile the Guest Additions against, so there is no VirtualBox box yet.
- **Docker** is tested the same way; the test VM runs `emerge-webrsync` and
  installs `app-containers/docker` from the binhost (nothing is compiled).

Measured on Apple Silicon (arm64, vagrant-qemu): boot ~8 s, `vagrant up`
~20 s, box 0.8 GB. On an x86 Linux host (amd64, vagrant-libvirt, BIOS):
boot ~8 s, `vagrant up` ~36 s.

```bash
cd gentoo && make                       # build, then test (or from the root: make gentoo-all)
make gentoo-publish
```

On a Linux host the build uses KVM and the distro's firmware (OVMF for
amd64, AAVMF/edk2-aarch64 for arm64; override with `EFI_CODE=... EFI_VARS=...`)
and `make test` uses vagrant-libvirt, as for Arch Linux.

## Layout

```
Makefile               forwards <distro>-<target> to the distro directory
ubuntu-26.04.json      Ubuntu box catalog (committed, served by GitHub Pages)
archlinux.json         Arch Linux box catalog (created by the first publish)
gentoo.json            Gentoo box catalog (created by the first publish)
ubuntu/                Ubuntu 26.04 box
archlinux/             Arch Linux box (same layout as ubuntu/)
gentoo/                Gentoo box (same layout, libvirt only)
scripts/               doctor-lib.sh and install-deps-lib.sh, shared by every
                       distro's scripts/doctor and scripts/install-deps
third_party/moby/      Moby's check-config.sh, run by every test script

Inside each distro directory:
  Makefile             build / test / publish
  mise.toml            tools (packer, jq, gh) and tasks: deps, doctor, and
                       build/test/publish calling make
  packer/              Packer templates (qemu + virtualbox-ovf sources)
  cloud-init/          NoCloud seed used only during the libvirt build
  files/               network, cloud-init and systemd files put in the box
  scripts/             provisioning, catalog, OVF, release notes, test helpers;
                       doctor, install-deps and requirements.sh (mise tasks)
  vagrantfiles/box.rb  Vagrantfile embedded in the boxes
  fixtures/            Gentoo only: generated example Vagrantfiles per provider
                       and boot mode (scripts/fixtures; not committed)
```

## Roadmap

Planned, not implemented yet. amd64 builds on an Intel Mac, with `libvirt`
and `virtualbox`, are done and tested, and both architectures publish into
one version (see [Publishing both architectures](#publishing-both-architectures)).

A hako box file is about 700 MB (bento's are 2.6-3.7 GB), which is why GitHub
Releases, with its 2 GiB-per-asset limit, works as the download host.

1. **amd64 on x86 Linux hosts with KVM, or GitHub Actions Ubuntu
   runners.** The `ARCH` plumbing (cloud image, QEMU binary and machine
   type, EDK2 firmware, VirtualBox platform) exists; what is left is the
   `kvm` accelerator (`-var accelerator=kvm`) and Linux firmware paths.
   Never emulate: each architecture is built on a host of its own.
2. **A `qemu` catalog entry** pointing at the same libvirt box file, as bento
   does, so vagrant-qemu users get a direct provider match.
3. **Hyper-V (amd64)**, which bento's 26.04 box does not offer:
   - add `linux-cloud-tools` to the base image (`hv_kvp_daemon`, which
     Vagrant needs to learn the VM's IP) and check that the initramfs has
     `hv_vmbus`, `hv_netvsc` and `hv_storvsc`;
   - convert the amd64 image with
     `qemu-img convert -O vhdx -o subformat=dynamic` and package it as a
     `hyperv` box (`Virtual Hard Disks/`, VM config if needed, and
     `metadata.json` with `provider: hyperv`), for a Generation 2 VM with
     Secure Boot off or the "Microsoft UEFI Certificate Authority" template;
   - test on a Windows host (`vagrant up --provider hyperv` as
     administrator) with the same boot-time and SSH checks;
   - Hyper-V on Windows on ARM (arm64) is a later option.
4. **Optional: register `hako/ubuntu-26.04` on the HCP Vagrant Registry**
   (free for public boxes), with provider URLs pointing at the GitHub
   release assets, so `config.vm.box = "hako/ubuntu-26.04"` works without
   `box_url`.
5. **Later providers:** `parallels`, `vmware_desktop`, `utm`.

## Booting the Gentoo box with UEFI

The amd64 `hako/gentoo` box is hybrid: its disk has both an EFI system
partition (with the removable-media loader `EFI/BOOT/BOOTX64.EFI`, so it boots
from empty firmware variables) and a GRUB BIOS boot partition. By default
vagrant-libvirt and vagrant-qemu boot it with BIOS, which needs no settings.
To boot it with UEFI instead:

**vagrant-libvirt** (Linux):

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hako/gentoo"

  config.vm.provider :libvirt do |libvirt|
    libvirt.machine_type = "q35"
    libvirt.loader = "/usr/share/OVMF/OVMF_CODE_4M.fd"
    libvirt.nvram  = "/var/lib/libvirt/qemu/nvram/hako-gentoo_VARS.fd"
  end
end
```

- `loader` is the read-only firmware code (Debian/Ubuntu path; Arch:
  `/usr/share/edk2/x64/OVMF_CODE.4m.fd`, Fedora:
  `/usr/share/edk2/ovmf/OVMF_CODE.fd`).
- `nvram` is this VM's own writable copy of the UEFI variables, not the
  template in `/usr/share/OVMF`: pointing it at the template either fails
  (QEMU can't write it) or makes every VM share one variable store. Use one
  path per VM. When the file doesn't exist, libvirt creates it from the
  template that matches `loader` (from the firmware descriptors in
  `/usr/share/qemu/firmware`). vagrant-libvirt keeps the file on
  `vagrant destroy`.
- The CODE and VARS files must come from the same set (both `_4M`, or both
  without).

**vagrant-qemu** (Intel Mac or Linux): the plugin attaches UEFI firmware only
for arm64 guests, and has no firmware setting for x86_64, so it boots them
with QEMU's SeaBIOS. Its `extra_qemu_args` (appended after the plugin's own
arguments) can attach the firmware instead; give the VM its own copy of the
variables file:

```ruby
require "fileutils"

# Intel Mac (Homebrew QEMU):
code = "/usr/local/share/qemu/edk2-x86_64-code.fd"
vars = "/usr/local/share/qemu/edk2-i386-vars.fd"
# Linux (Debian/Ubuntu):
# code = "/usr/share/OVMF/OVMF_CODE_4M.fd"
# vars = "/usr/share/OVMF/OVMF_VARS_4M.fd"

vm_vars = File.join(__dir__, ".vagrant", "uefi-vars.fd")
unless File.exist?(vm_vars)
  FileUtils.mkdir_p(File.dirname(vm_vars))
  FileUtils.cp(vars, vm_vars)
end

Vagrant.configure("2") do |config|
  config.vm.box = "hako/gentoo"

  config.vm.provider "qemu" do |qe|
    qe.extra_qemu_args = [
      "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=#{code}",
      "-drive", "if=pflash,format=raw,unit=1,file=#{vm_vars}",
    ]
  end
end
```

The default machine type for x86_64 is already `q35`, which UEFI needs; if
you set `qe.machine` yourself, keep the accelerator (`"q35,accel=hvf"` on a
Mac, `"q35,accel=kvm"` on Linux).

`make test` boots the box with BIOS (vagrant-libvirt's default). The
Vagrantfiles above are generated, and booted in each mode, by
`make fixtures-test` (next section).

## Testing example Vagrantfiles (Gentoo)

`make test` checks the box itself. `make fixtures-test` is a separate set of
integration tests of how a user runs it: it writes an example Vagrantfile for
each provider and boot mode, boots each one this machine can run, and checks
that the guest came up in the mode the name claims (`/sys/firmware/efi` is
there for UEFI and absent for BIOS), that sudo works and the system is
healthy, and that it comes up again after `vagrant reload`. The Vagrantfiles
are test fixtures: generated into `gentoo/fixtures/` and not committed.

| Fixture        | Provider        | Boot mode | Needs                                  |
|----------------|-----------------|-----------|----------------------------------------|
| `qemu-bios`    | vagrant-qemu    | BIOS      | QEMU, the `vagrant-qemu` plugin        |
| `qemu-uefi`    | vagrant-qemu    | UEFI      | the above, plus edk2 firmware          |
| `libvirt-bios` | vagrant-libvirt | BIOS      | Linux, libvirt, `vagrant-libvirt`      |
| `libvirt-uefi` | vagrant-libvirt | UEFI      | the above, plus OVMF firmware          |

```bash
cd gentoo
make fixtures-list          # which fixtures this machine can run, and why not
make fixtures               # write fixtures/<provider>-<mode>/Vagrantfile, run nothing
make fixtures-test          # boot, check, reload, check and destroy each
make fixtures-test FIXTURES="qemu-uefi"      # only some
```

- A fixture this machine can't run is skipped with the reason (no plugin, no
  Linux, no firmware), not failed. The run fails if any fixture fails, or if
  nothing could run.
- Each fixture has its own directory, because Vagrant keeps its state beside
  the Vagrantfile. To bring one up yourself:
  `cd fixtures/qemu-uefi && vagrant up --provider qemu`. Naming a fixture
  (`scripts/fixtures gen libvirt-uefi`) generates it even if this machine
  can't run it.
- The fixtures use the box in `boxes/` (through the local catalog that
  `make test` also builds), so build first.
- UEFI firmware comes from the same place as the build: Homebrew's QEMU on a
  Mac, the distro's OVMF on Linux; set `EFI_CODE=` and `EFI_VARS=` to
  override. The arm64 box is UEFI only, so it has just `qemu-uefi`, where
  vagrant-qemu attaches the firmware itself.
- There are no VirtualBox fixtures: the Gentoo box is libvirt only.

Status: on an Intel Mac, `qemu-bios` and `qemu-uefi` pass. The two libvirt
fixtures need a Linux host with vagrant-libvirt and have not been run yet; the
arm64 fixture has not been run.

## License

Apache-2.0, see [LICENSE](LICENSE).
