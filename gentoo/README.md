# hako/gentoo

`hako/gentoo` is a Vagrant box built from Gentoo's official cloud-init disk
image (`di-<arch>-cloudinit-<timestamp>.qcow2`, rebuilt weekly by Gentoo
release engineering: systemd profile, dist-kernel, XFS root, GRUB,
cloud-init). Build, test and publish it from this directory; see the
[root README](../README.md) for what all hako boxes share.

| Host | Arch | Provider | Boot modes | Status |
|---|---|---|---|---|
| Linux (x86) | amd64 | vagrant-libvirt | BIOS (default), UEFI | `make test` and both libvirt fixtures pass |
| Linux (x86) | amd64 | vagrant-qemu | BIOS (default), UEFI | both qemu fixtures pass |
| macOS, Intel | amd64 | vagrant-qemu | BIOS (default), UEFI | both qemu fixtures passed, before the GRUB text-terminal change (not rerun since) |
| macOS, Apple Silicon | arm64 | vagrant-qemu | UEFI | `make test` passes; `qemu-uefi` fixture not run yet |
| Linux (Arm) | arm64 | vagrant-libvirt | UEFI | not tested |

The box is not published yet: `gentoo.json` is written by the first
`make publish`. Until then, use the local catalog that `make test` writes
(`boxes/gentoo.local.json`, see [Using the box](#using-the-box)).

## Boot modes: BIOS and UEFI

**The amd64 box is hybrid.** It boots with BIOS or UEFI, whichever the
provider gives it:

- Gentoo's image is UEFI only: a GPT disk with an EFI system partition
  (mounted at `/boot`) and GRUB for UEFI, including the removable-media
  loader `EFI/BOOT/BOOTX64.EFI`, so it boots from empty firmware variables.
- The build adds a 1 MiB GRUB BIOS boot partition in the free gap before the
  ESP, and installs GRUB for BIOS (`i386-pc`) there and in the disk's first
  sector.
- Both GRUBs read the same `/boot/grub/grub.cfg`, so the menu, kernel and
  initramfs are identical in either mode.

**What each provider boots by default:**

| Guest | vagrant-libvirt | vagrant-qemu |
|---|---|---|
| amd64 (Intel/AMD host) | BIOS (SeaBIOS): no firmware is set unless you set `loader` | BIOS (SeaBIOS): the plugin has no firmware setting for x86_64 |
| arm64 (Arm host) | UEFI is the only mode, but you have to set `loader` yourself (see [Linux, arm64](#linux-arm64)) | UEFI: the plugin attaches the edk2 firmware itself |

So on amd64 the box needs no settings at all and boots with BIOS; to boot
with UEFI, configure the provider as shown below. arm64 has no BIOS; every
arm64 VM boots with UEFI.

To see which mode a VM booted in:

```bash
vagrant ssh -c 'test -d /sys/firmware/efi && echo uefi || echo bios'
```

## Using the box

Once the box is published:

```ruby
config.vm.box     = "hako/gentoo"
config.vm.box_url = "https://darkn3rd.github.io/hako/gentoo.json"
```

Until then, build it (`make`) and point at the local catalog instead:

```ruby
config.vm.box     = "hako/gentoo"
config.vm.box_url = "file:///path/to/hako/gentoo/boxes/gentoo.local.json"
```

Vagrant picks the box for the host's architecture (see
[Architecture](../README.md#architecture)). Each example below is a whole
Vagrantfile minus those two lines. `make fixtures` writes them for this
machine, and `make fixtures-test` boots each one (see
[Testing example Vagrantfiles](../README.md#testing-example-vagrantfiles)).

### Linux, amd64

**vagrant-libvirt, BIOS** (the default; nothing to set):

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hako/gentoo"

  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = 2048
    libvirt.cpus   = 2
  end
end
```

```bash
vagrant up --provider libvirt
```

**vagrant-libvirt, UEFI:**

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hako/gentoo"

  config.vm.provider :libvirt do |libvirt|
    libvirt.memory       = 2048
    libvirt.cpus         = 2
    libvirt.machine_type = "q35"
    libvirt.loader       = "/usr/share/OVMF/OVMF_CODE_4M.fd"
    libvirt.nvram        = "/var/lib/libvirt/qemu/nvram/hako-gentoo_VARS.fd"
  end
end
```

- `loader` is the read-only firmware code. That path is Debian/Ubuntu's
  (`apt install ovmf`); on Arch it is `/usr/share/edk2/x64/OVMF_CODE.4m.fd`,
  on Fedora `/usr/share/edk2/ovmf/OVMF_CODE.fd`.
- `nvram` is this VM's own writable copy of the UEFI variables, **not** the
  template in `/usr/share/OVMF`. Pointing it at the template either fails
  (QEMU can't write it) or makes every VM share one variable store. Use one
  path per VM. When the file doesn't exist, libvirt creates it from the
  template that matches `loader` (found through the firmware descriptors in
  `/usr/share/qemu/firmware`). vagrant-libvirt keeps the file on
  `vagrant destroy`.
- The CODE and VARS files must come from the same set (both `_4M`, or both
  without).

**vagrant-qemu** works on Linux too (`vagrant plugin install vagrant-qemu`),
with the same Vagrantfiles as on an Intel Mac below and the Linux firmware
paths.

### macOS, Intel

vagrant-qemu (`vagrant plugin install vagrant-qemu`), with QEMU from
Homebrew.

**vagrant-qemu, BIOS** (the default; nothing to set):

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hako/gentoo"
  config.vm.provider "qemu" do |qe|
    qe.ssh_auto_correct = true
  end
end
```

```bash
vagrant up --provider qemu
```

**vagrant-qemu, UEFI:** the plugin has no firmware setting for x86_64
guests, but `extra_qemu_args` (added after the plugin's own arguments) can
attach the UEFI firmware. Give each VM its own copy of the variables file:

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
    qe.ssh_auto_correct = true
    qe.extra_qemu_args = [
      "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=#{code}",
      "-drive", "if=pflash,format=raw,unit=1,file=#{vm_vars}",
    ]
  end
end
```

- The default x86_64 machine type is already `q35`, which UEFI needs. If you
  set `qe.machine` yourself, keep the accelerator: `"q35,accel=hvf"` on a
  Mac, `"q35,accel=kvm"` on Linux.
- **CPU model.** Under HVF, vagrant-qemu's default `-cpu host` passes the
  CPU's AVX-512 feature bits to the guest without enabling the AVX-512
  register state, and Gentoo's kernel panics at boot with an invalid opcode
  (in `chacha_8block_xor_avx512vl`). The box's own Vagrantfile
  (`vagrantfiles/box.rb`) sets `qe.cpu = "Skylake-Client"` on an Intel Mac,
  so nothing is needed in yours; if you set `qe.cpu`, choose a model without
  AVX-512. Linux with KVM handles `host` correctly.

### macOS, Apple Silicon

vagrant-qemu, with QEMU from Homebrew. The arm64 box boots with UEFI, and
vagrant-qemu attaches the firmware (`edk2-aarch64-code.fd`) itself, so there
is nothing to configure:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "hako/gentoo"
  config.vm.provider "qemu" do |qe|
    qe.ssh_auto_correct = true
  end
end
```

```bash
vagrant up --provider qemu
```

### Linux, arm64

Not tested yet, and `make fixtures` has no arm64 libvirt fixture. arm64 VMs
need UEFI firmware, and vagrant-libvirt only adds it when `loader` is set, so
point it at the distro's AAVMF/edk2 files (Debian/Ubuntu shown; the
`machine_type` default on arm64 is `virt`):

```ruby
config.vm.provider :libvirt do |libvirt|
  libvirt.loader = "/usr/share/AAVMF/AAVMF_CODE.fd"
  libvirt.nvram  = "/var/lib/libvirt/qemu/nvram/hako-gentoo_VARS.fd"
end
```

## What is different in this box

Compared with the Ubuntu box:

- **arm64 and amd64**, one box name. Each is built natively (never
  emulated); the Makefile picks the architecture from `uname -m`.
- **No OS version.** Gentoo is a rolling release: the box is `hako/gentoo`,
  the date version is the snapshot, and release tags are `gentoo-v<version>`.
  The image's file name carries its build timestamp, so `make build` looks up
  the latest one (`scripts/cloud-image.sh`, from
  `latest-di-<arch>-cloudinit.txt` and the image's `.sha256`). Pin one with
  `CLOUD_IMAGE_URL=... CLOUD_IMAGE_CHECKSUM=sha256:...`. The box records the
  image it came from in `/etc/hako-release`.
- **Packages are not upgraded at build time.** The image is at most a week
  old, and an `@world` update would compile from source, the kernel included,
  turning a minutes-long build into hours.
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
  removed from `@world`, so updates don't bring it back. `grub.cfg` is
  written after it is gone (the package's `/boot/amd-uc.img` would otherwise
  be listed as an initrd and, once deleted, stop the initramfs from loading).
- **GRUB:** no menu wait (timeout 0) and text terminals only (serial and the
  firmware console, no `gfxterm`). The image's graphical terminal sends a
  BIOS boot with no video device, as vagrant-qemu runs QEMU (`-vga none`),
  into a reboot loop right after "Loading Linux".
- **Networking** is one systemd-networkd file,
  `/etc/systemd/network/99-hako-ethernet.network` (DHCP on any `e*` NIC), as
  in the Arch Linux box.
- **cloud-init stays off without a seed.** Gentoo's cloud-init enables itself
  when no datasource is found, then fails four units and writes a network
  file on every plain `vagrant up`. `/etc/cloud/ds-identify.cfg` sets
  `notfound=disabled`; a VM with a NoCloud seed still runs cloud-init.
- **sshd** is enabled as a unit (the image only starts it from cloud-init).
- **Docker-ready**, as every hako box: `make test` checks the kernel and
  modules, then installs `app-containers/docker` in the test VM from the
  binhost (nothing is compiled) and runs containers.

Measured: Apple Silicon (arm64, vagrant-qemu) boot ~8 s, `vagrant up` ~20 s;
x86 Linux (amd64, vagrant-libvirt, BIOS) boot ~8 s, `vagrant up` ~31 s. The
box is about 0.8 GB.

## VirtualBox (planned)

There is no VirtualBox box yet, and `make` refuses `PROVIDERS=virtualbox`.
It is planned soon. What is missing:

- Gentoo's dist-kernel, on both architectures, is built without the
  `vboxguest` and `vboxsf` modules, so there are no shared folders and no
  guest services (unlike Arch Linux, whose kernel has them).
- The image has no kernel build tree to compile the Guest Additions modules
  against, and adding one means a source kernel or `emerge` of the matching
  sources at build time, which is slow and has to be redone on every kernel
  update.

The likely route is the Arch Linux one: convert the finished libvirt image
to a VirtualBox OVF (the disk already boots with BIOS or UEFI) and add the
guest modules from a package, once one that fits the dist-kernel is chosen.

## Building

Host requirements that differ from the other boxes (`scripts/requirements.sh`):

- **Every host platform:** macOS (Apple Silicon or Intel) and Linux (arm64 or
  amd64). Ubuntu builds on macOS only, Arch Linux on amd64 only.
- **No VirtualBox**, on any host (`VIRTUALBOX=none`).
- **`curl`**, which `scripts/cloud-image.sh` uses to find the latest image.
- **Linux, arm64:** AAVMF/edk2-aarch64 firmware instead of OVMF.
- **The fixtures** additionally use the `vagrant-qemu` plugin on Linux, if
  you want the two qemu fixtures there; `make test` on Linux uses only
  vagrant-libvirt.

Everything else is as for the other boxes: Packer, QEMU, `qemu-img`, `jq`, an
ISO tool (`xorriso` on Linux), Vagrant 2.4+ with vagrant-qemu (macOS) or
vagrant-libvirt (Linux), and access to `/dev/kvm` and libvirt on Linux.
`mise run deps` installs them and `mise run doctor` checks them (see
[Setting up with mise](../README.md#setting-up-with-mise)).

```bash
cd gentoo
make                    # build, then test (from the repo root: make gentoo-all)
make build              # only build, into boxes/
make test               # boot the box in boxes/ and check it
make publish            # GitHub release + ../gentoo.json
```

On Linux the build uses KVM and the distro's UEFI firmware (OVMF on amd64,
AAVMF/edk2-aarch64 on arm64; override with `EFI_CODE=... EFI_VARS=...`), and
`make test` uses vagrant-libvirt. On a Mac it uses HVF, Homebrew's firmware
and vagrant-qemu.

On Linux, libvirt needs the `libvirt` group in your session; if you just
joined it, log in again or run `newgrp libvirt` (or
`sg libvirt -c 'make'`).

## Testing

- `make test` checks the box itself, as for every hako box (see
  [Testing](../README.md#testing)): boot time, SSH, one network file, a
  second boot, Docker. It boots with each provider's default mode, so BIOS
  on amd64.
- `make fixtures-test` boots the example Vagrantfiles above, in each boot
  mode, and checks that the guest booted in the mode its name claims (see
  [Testing example Vagrantfiles](../README.md#testing-example-vagrantfiles)).
  Gentoo is the first box with fixtures.
