# hako

Small, fast-booting Vagrant boxes for Macs (Apple Silicon and Intel), built
with Packer from the distribution's official **cloud image** and published on
this repository's GitHub Releases with a Vagrant box catalog.

| Box                 | Architecture | Providers                                     |
|---------------------|--------------|-----------------------------------------------|
| `hako/ubuntu-26.04` | arm64        | `libvirt` (vagrant-qemu, vagrant-libvirt), `virtualbox` |
| `hako/ubuntu-26.04` | amd64 (Intel x86) | `libvirt` (vagrant-qemu, vagrant-libvirt), `virtualbox` |

Both architectures share one box name; Vagrant picks the one matching the
host. Each is built natively on a host of its own architecture (never
emulated), so arm64 boxes come from an Apple Silicon Mac and amd64 boxes from
an Intel one.

Catalog: [`ubuntu-26.04.json`](ubuntu-26.04.json)

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

## Building

Requirements (macOS, Apple Silicon or Intel): Packer 1.9+ (`brew install
hashicorp/tap/packer`), QEMU (Homebrew), VirtualBox 7.1+ for the VirtualBox
box, Vagrant 2.4+, `jq`, and `gh` for publishing.

```bash
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
- destroys the VM.

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

## Layout

```
Makefile               build / test / publish
ubuntu-26.04.json      Vagrant box catalog (committed)
packer/                Packer templates (qemu + virtualbox-ovf sources)
cloud-init/            NoCloud seed used only during the libvirt build
files/                 netplan, cloud-init and systemd files put in the box
scripts/               provisioning, catalog, OVF, release notes and test helpers
vagrantfiles/box.rb    Vagrantfile embedded in the boxes
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

## License

Apache-2.0, see [LICENSE](LICENSE).
