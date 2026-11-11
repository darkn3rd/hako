# hako

Small, fast-booting Vagrant boxes for Apple Silicon Macs, built with Packer
from the distribution's official **cloud image** and published on this
repository's GitHub Releases with a Vagrant box catalog.

| Box                 | Architecture | Providers                                     |
|---------------------|--------------|-----------------------------------------------|
| `hako/ubuntu-26.04` | arm64        | `libvirt` (vagrant-qemu, vagrant-libvirt), `virtualbox` |

Catalog: [`ubuntu-26.04.json`](ubuntu-26.04.json)

## Why

The `bento/ubuntu-26.04` box (202606.01.0) waits two minutes on every boot:
the installer's netplan file renames the NIC by MAC address while bento's own
netplan file configures `eth0`, so `systemd-networkd-wait-online` times out
([chef/bento#1709](https://github.com/chef/bento/issues/1709)).

hako boxes start from Ubuntu's cloud image instead of an installer ISO and
ship with exactly one netplan file that matches any ethernet NIC by name
(`e*`): no MAC address, no `set-name`. A VM boots in a few seconds.

## Using the box

The catalog is not on HashiCorp's registry, so point `box_url` at it:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box     = "hako/ubuntu-26.04"
  config.vm.box_url = "https://raw.githubusercontent.com/darkn3rd/hako/main/ubuntu-26.04.json"
  # config.vm.box_version = "2026.11.10"   # optional pin

  # vagrant-qemu (libvirt box format)
  config.vm.provider "qemu" do |qe|
    qe.memory = "2G"
    qe.smp    = 2
  end

  # VirtualBox 7.1+ on Apple Silicon
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

A catalog on disk works the same way, which is how `make test` runs boxes
before they are published:

```ruby
config.vm.box_url = "file:///path/to/hako/boxes/ubuntu-26.04.local.json"
```

### What is in the box

- Ubuntu 26.04 server cloud image (arm64), packages upgraded at build time.
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
  first boot.
- `apt-daily*` timers and `unattended-upgrades` disabled, so nothing holds
  the dpkg lock while you provision.
- 64 GB sparse disk, already grown.
- VirtualBox box only: Guest Additions (shared folders via `vboxsf`), with
  build tools and kernel headers kept so the modules rebuild on kernel
  upgrades.

## Building

Requirements (macOS on Apple Silicon): Packer 1.9+, QEMU (Homebrew),
VirtualBox 7.1+ for the VirtualBox box, Vagrant, `jq`, and `gh` for
publishing.

```bash
make build                      # both providers, VERSION = today (YYYY.MM.DD)
```

```bash
make build PROVIDERS=libvirt    # only the libvirt box
```

Boxes land in `boxes/`, named `ubuntu-26.04-<version>-<provider>-arm64.box`.

### libvirt

Packer's `qemu` builder boots the cloud image itself as the disk
(`disk_image = true`) with HVF acceleration and UEFI. A NoCloud seed
(`cloud-init/`), attached as a `cidata` CD only during the build, creates
the `vagrant` user. `scripts/base.sh` upgrades packages and installs the
files in `files/`; `scripts/cleanup.sh` runs `cloud-init clean`, empties the
machine-id, removes host keys, logs and caches, and trims free space so
`qemu-img` can compress the image. The `vagrant` post-processor packages the
qcow2 and `metadata.json` as a libvirt box.

### virtualbox

Packer cannot turn a qcow2 into a VirtualBox VM, and two ways were
considered:

1. **Reuse the libvirt image** (chosen). `scripts/make-vbox-ovf.sh`
   converts the finished qcow2 to VMDK and wraps it in an ARM VirtualBox
   OVF (EFI, VirtIO storage and NIC). Packer's `virtualbox-ovf` builder
   imports it, installs the Guest Additions and runs the same cleanup.
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
- checks SSH, passwordless sudo and that exactly one netplan file exists;
- destroys the VM.

## Publishing

```bash
make publish
```

1. Refuses any box of 2 GiB or more (GitHub's release asset limit).
2. Adds the version to `ubuntu-26.04.json` with each provider's release URL
   (`https://github.com/darkn3rd/hako/releases/download/ubuntu-26.04-v<version>/...`)
   and sha256 checksum.
3. Creates the GitHub release `ubuntu-26.04-v<version>` if needed and
   uploads the boxes (`gh release upload --clobber`).

Then commit and push `ubuntu-26.04.json`: Vagrant reads the catalog from the
`main` branch.

To publish a box built on another day, pass its version:
`make publish VERSION=2026.11.10`.

## Layout

```
Makefile               build / test / publish
ubuntu-26.04.json      Vagrant box catalog (committed)
packer/                Packer templates (qemu + virtualbox-ovf sources)
cloud-init/            NoCloud seed used only during the libvirt build
files/                 netplan, cloud-init and systemd files put in the box
scripts/               provisioning, catalog, OVF and test helpers
vagrantfiles/box.rb    Vagrantfile embedded in the boxes
```

## License

Apache-2.0, see [LICENSE](LICENSE).
