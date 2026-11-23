# Shared checks for each distro's scripts/doctor: can this machine build and
# test that distro's boxes? Read-only: it reports problems and prints the
# commands that fix them, for the platform it runs on (macOS on Apple
# Silicon or Intel, Debian/Ubuntu, Arch, Fedora; native Windows and WSL are
# recognised and told what is and isn't supported).
#
# A distro's scripts/doctor sets these, then sources this file and calls
# doctor_main:
#
#   DISTRO      directory name, e.g. gentoo
#   BOX         box name, e.g. hako/gentoo
#   SUPPORTED   host platforms the distro builds on: macos/arm64 macos/amd64
#               linux/arm64 linux/amd64
#   VIRTUALBOX  required (the default PROVIDERS builds it), optional (built
#               only when VBoxManage is installed) or none (libvirt only)
#   EXTRA_TOOLS more commands the build needs, e.g. curl
#
# PROVIDERS from the environment (as make passes it) overrides what is
# checked: PROVIDERS=libvirt skips VirtualBox.
#
# Exit status is 1 if any check fails; warnings do not fail it.
#
# For trying the advice for another platform, DOCTOR_UNAME_S, DOCTOR_UNAME_M
# and DOCTOR_OS_RELEASE (a file in /etc/os-release format) stand in for
# uname -s, uname -m and /etc/os-release. Only the platform and the advice
# change; the tool checks still look at this machine.

set -u -o pipefail

# Colour the marks and section headings only on a terminal, and never when
# NO_COLOR is set. Warnings are orange where the terminal has 256 colours,
# else yellow.
GREEN="" RED="" ORANGE="" HEADING="" RESET=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  GREEN=$'\033[32m' RED=$'\033[31m' HEADING=$'\033[1;36m' RESET=$'\033[0m'
  if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]; then
    ORANGE=$'\033[38;5;214m'
  else
    ORANGE=$'\033[33m'
  fi
fi

ERRORS=0 WARNINGS=0 FIXES=()
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$ORANGE" "$RESET" "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"; ERRORS=$((ERRORS + 1)); }
note() { printf '    %s\n' "$1"; }
fix()  { FIXES+=("$1"); }
section() { printf '\n%s=== %s ===%s\n' "$HEADING" "$1" "$RESET"; }
have() { command -v "$1" >/dev/null 2>&1; }
# sysctl -n, also when /usr/sbin is not on PATH (macOS).
sysctl_n() { { command -v sysctl >/dev/null && sysctl -n "$1" || /usr/sbin/sysctl -n "$1"; } 2>/dev/null; }
# First dotted version number in a string: "Packer v1.16.2" -> 1.16.2
version_of() { printf '%s\n' "$1" | grep -Eo '[0-9]+(\.[0-9]+)+' | head -1; }
# True when dotted version $1 is at least $2 (no sort -V: macOS bash/BSD).
at_least() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, ".")
    for (i = 1; i <= (n > m ? n : m); i++) {
      if (x[i] + 0 > y[i] + 0) exit 0
      if (x[i] + 0 < y[i] + 0) exit 1
    }
    exit 0 }'
}

# --- platform ---------------------------------------------------------------

# Sets HOST_OS (macos|linux|windows|other), HOST_ARCH (arm64|amd64|<uname -m>),
# PKG (brew|apt|pacman|dnf|zypper|unknown), IS_WSL (0|1), ROSETTA (0|1) and
# PLATFORM (a readable label).
detect_platform() {
  local s m os_release id like
  s=${DOCTOR_UNAME_S:-$(uname -s)}
  m=${DOCTOR_UNAME_M:-$(uname -m)}
  IS_WSL=0 ROSETTA=0 PKG=unknown
  case $m in
    arm64|aarch64) HOST_ARCH=arm64 ;;
    x86_64|amd64)  HOST_ARCH=amd64 ;;
    *)             HOST_ARCH=$m ;;
  esac
  case $s in
    Darwin)
      HOST_OS=macos PKG=brew
      # An x86_64 shell on Apple Silicon runs under Rosetta and reports x86_64.
      if [ -z "${DOCTOR_UNAME_M:-}" ] && [ "$(sysctl_n sysctl.proc_translated)" = 1 ]; then
        ROSETTA=1 HOST_ARCH=arm64
      fi
      if [ "$HOST_ARCH" = arm64 ]; then PLATFORM="macOS, Apple Silicon (arm64)"
      else PLATFORM="macOS, Intel (amd64)"; fi
      ;;
    Linux)
      HOST_OS=linux
      os_release=${DOCTOR_OS_RELEASE:-/etc/os-release}
      id=$( (. "$os_release" 2>/dev/null; echo "${ID:-}") )
      like=$( (. "$os_release" 2>/dev/null; echo "${ID_LIKE:-}") )
      case " $id $like " in
        *" debian "*|*" ubuntu "*)          PKG=apt ;;
        *" arch "*)                         PKG=pacman ;;
        *" fedora "*|*" rhel "*|*" centos "*) PKG=dnf ;;
        *" suse "*|*" opensuse "*)          PKG=zypper ;;
      esac
      PLATFORM="Linux, $( (. "$os_release" 2>/dev/null; echo "${PRETTY_NAME:-$id}") ) ($HOST_ARCH)"
      if [ -z "${DOCTOR_UNAME_S:-}" ] && grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=1 PLATFORM="$PLATFORM under WSL2"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      HOST_OS=windows PLATFORM="Windows ($s, $HOST_ARCH)" ;;
    *)
      HOST_OS=other PLATFORM="$s ($HOST_ARCH)" ;;
  esac
}

# The install command for one requirement on this platform.
install_hint() {
  local q_sys q_apt q_dnf fw_apt fw_pac fw_dnf
  if [ "$HOST_ARCH" = arm64 ]; then
    q_sys=qemu-system-aarch64 q_apt=qemu-system-arm q_dnf=qemu-system-aarch64
    fw_apt=qemu-efi-aarch64 fw_pac=edk2-aarch64 fw_dnf=edk2-aarch64
  else
    q_sys=qemu-base q_apt=qemu-system-x86 q_dnf=qemu-system-x86
    fw_apt=ovmf fw_pac=edk2-ovmf fw_dnf=edk2-ovmf
  fi
  case "$PKG:$1" in
    brew:packer)     echo "brew install hashicorp/tap/packer" ;;
    brew:qemu|brew:qemu-img|brew:firmware) echo "brew install qemu" ;;
    brew:vagrant)    echo "brew install --cask hashicorp/tap/hashicorp-vagrant" ;;
    brew:virtualbox) echo "brew install --cask virtualbox   # 7.1 or later" ;;
    brew:gh)         echo "brew install gh" ;;
    brew:*)          echo "brew install $1" ;;

    apt:packer|apt:vagrant)
      echo "sudo apt-get install $1   # from HashiCorp's apt repository: https://developer.hashicorp.com/$1/install" ;;
    apt:qemu)        echo "sudo apt-get install $q_apt" ;;
    apt:qemu-img)    echo "sudo apt-get install qemu-utils" ;;
    apt:firmware)    echo "sudo apt-get install $fw_apt" ;;
    apt:iso)         echo "sudo apt-get install xorriso" ;;
    apt:libvirt)     echo "sudo apt-get install libvirt-daemon-system libvirt-clients" ;;
    apt:libvirt-dev) echo "sudo apt-get install libvirt-dev ruby-dev build-essential" ;;
    apt:virtualbox)  echo "sudo apt-get install virtualbox   # or 7.1+ from https://www.virtualbox.org/wiki/Linux_Downloads" ;;
    apt:*)           echo "sudo apt-get install $1" ;;

    pacman:vagrant)  echo "install vagrant from the AUR (it is not in Arch's repositories) or https://developer.hashicorp.com/vagrant/install" ;;
    pacman:qemu)     echo "sudo pacman -S $q_sys" ;;
    pacman:qemu-img) echo "sudo pacman -S qemu-img" ;;
    pacman:firmware) echo "sudo pacman -S $fw_pac" ;;
    pacman:iso)      echo "sudo pacman -S libisoburn" ;;
    pacman:libvirt)  echo "sudo pacman -S libvirt && sudo systemctl enable --now libvirtd" ;;
    pacman:libvirt-dev) echo "sudo pacman -S --needed base-devel libvirt" ;;
    pacman:gh)       echo "sudo pacman -S github-cli" ;;
    pacman:*)        echo "sudo pacman -S $1" ;;

    dnf:packer|dnf:vagrant)
      echo "sudo dnf install $1   # from HashiCorp's repository: https://developer.hashicorp.com/$1/install" ;;
    dnf:qemu)        echo "sudo dnf install $q_dnf" ;;
    dnf:qemu-img)    echo "sudo dnf install qemu-img" ;;
    dnf:firmware)    echo "sudo dnf install $fw_dnf" ;;
    dnf:iso)         echo "sudo dnf install xorriso" ;;
    dnf:libvirt)     echo "sudo dnf install libvirt && sudo systemctl enable --now libvirtd" ;;
    dnf:libvirt-dev) echo "sudo dnf install libvirt-devel ruby-devel gcc make" ;;
    dnf:virtualbox)  echo "install VirtualBox 7.1+ from https://www.virtualbox.org/wiki/Linux_Downloads" ;;
    dnf:*)           echo "sudo dnf install $1" ;;

    zypper:qemu)     echo "sudo zypper install qemu" ;;
    zypper:iso)      echo "sudo zypper install xorriso" ;;
    zypper:*)        echo "sudo zypper install $1   # or see its download page" ;;

    *:iso)           echo "install xorriso with your package manager" ;;
    *:firmware)      echo "install your distro's UEFI firmware for $HOST_ARCH (OVMF/AAVMF, edk2)" ;;
    *:libvirt-dev)   echo "install libvirt's development files, Ruby headers and a C compiler (vagrant-libvirt builds against them)" ;;
    *)               echo "install $1 with your package manager" ;;
  esac
}

check_platform() {
  section "Platform"
  ok "$PLATFORM"
  case $HOST_OS in
    windows)
      fail "native Windows is not a supported build host (the builds use HVF on macOS or KVM on Linux; Hyper-V is on the roadmap)"
      fix "build inside WSL2 on Windows 11 with nested virtualization (/dev/kvm), then run this check there"
      return 1 ;;
    other)
      fail "$PLATFORM is not a supported build host (macOS or Linux only)"
      return 1 ;;
  esac
  if [ "$ROSETTA" = 1 ]; then
    fail "this shell runs under Rosetta (x86_64) on Apple Silicon; boxes are built natively, never emulated"
    fix "arch -arm64 /bin/bash -l   # then run make from that native shell"
  fi
  if [ "$IS_WSL" = 1 ]; then
    note "WSL2 counts as a Linux host if it has /dev/kvm (nested virtualization, Windows 11)."
  fi
  if [ "$HOST_OS" = linux ] && [ "$PKG" = unknown ]; then
    warn "unrecognised Linux distribution: install hints below are generic"
  fi
  local p="$HOST_OS/$HOST_ARCH"
  case " $SUPPORTED " in
    *" $p "*) ok "$BOX builds on $p" ;;
    *)
      fail "$BOX does not build on $p (supported: $SUPPORTED)"
      case "$DISTRO:$p" in
        archlinux:*/arm64) note "Arch Linux publishes no arm64 cloud image; build on an Intel Mac or an x86 Linux host." ;;
        ubuntu:linux/*)    note "Linux hosts are on the roadmap for the Ubuntu box; build on a Mac for now." ;;
      esac
      return 1 ;;
  esac
}

check_virtualization() {
  section "Hardware virtualization"
  if [ "$HOST_OS" = macos ]; then
    if [ "$(sysctl_n kern.hv_support)" = 1 ]; then
      ok "Hypervisor.framework (HVF) available"
    else
      fail "Hypervisor.framework is not available (kern.hv_support is not 1)"
      fix "run on a Mac with virtualization support, not inside a VM without nested virtualization"
    fi
    return
  fi
  if [ ! -e /dev/kvm ]; then
    fail "/dev/kvm does not exist"
    if [ "$IS_WSL" = 1 ]; then
      fix "enable nested virtualization for WSL2: nestedVirtualization=true under [wsl2] in %UserProfile%\\.wslconfig, then wsl --shutdown"
    elif [ "$HOST_ARCH" = arm64 ]; then
      fix "use an arm64 host whose kernel has KVM (bare metal, or a VM with nested virtualization), then: sudo modprobe kvm"
    else
      fix "enable VT-x/AMD-V in the firmware settings, then: sudo modprobe kvm_intel   # or kvm_amd"
    fi
  elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ok "/dev/kvm is usable"
  else
    fail "no read/write access to /dev/kvm"
    fix "sudo usermod -aG kvm \$USER   # then log out and back in"
  fi
}

check_build_tools() {
  section "Build tools"
  local v q fw_code fw_vars share

  if have packer; then
    v=$(version_of "$(packer --version 2>/dev/null)")
    if at_least "$v" 1.9; then ok "packer $v"
    else fail "packer $v (need 1.9 or later)"; fix "$(install_hint packer)"; fi
    # The plugins this distro's templates require (packer/plugins.pkr.hcl).
    local installed wanted missing="" p
    installed=$(packer plugins installed 2>/dev/null)
    wanted=$(sed -n 's|.*source *= *"github.com/hashicorp/\([a-z0-9-]*\)".*|\1|p' packer/plugins.pkr.hcl 2>/dev/null)
    for p in $wanted; do
      printf '%s\n' "$installed" | grep -q "/packer-plugin-${p}_" || missing="$missing $p"
    done
    if [ -z "$missing" ]; then
      ok "packer plugins: $(echo $wanted)"
    else
      warn "packer plugins not installed yet:$missing (make build installs them)"
      fix "make init"
    fi
  else
    fail "packer not found"; fix "$(install_hint packer)"
  fi

  if [ "$HOST_ARCH" = arm64 ]; then q=qemu-system-aarch64; else q=qemu-system-x86_64; fi
  if have "$q"; then
    ok "$q $(version_of "$("$q" --version 2>/dev/null | head -1)")"
  else
    fail "$q not found"; fix "$(install_hint qemu)"
  fi
  have qemu-img && ok "qemu-img" || { fail "qemu-img not found"; fix "$(install_hint qemu-img)"; }

  # UEFI firmware, where the Makefiles look for it.
  if [ "$HOST_OS" = macos ]; then
    share=$(brew --prefix 2>/dev/null || echo /opt/homebrew)/share/qemu
    if [ "$HOST_ARCH" = arm64 ]; then fw_code=$share/edk2-aarch64-code.fd fw_vars=$share/edk2-arm-vars.fd
    else fw_code=$share/edk2-x86_64-code.fd fw_vars=$share/edk2-i386-vars.fd; fi
  else
    local pairs p
    if [ "$HOST_ARCH" = arm64 ]; then
      pairs="/usr/share/AAVMF/AAVMF_CODE.fd:/usr/share/AAVMF/AAVMF_VARS.fd
/usr/share/edk2/aarch64/QEMU_CODE.fd:/usr/share/edk2/aarch64/QEMU_VARS.fd
/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw:/usr/share/edk2/aarch64/vars-template-pflash.raw"
    else
      pairs="/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd
/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd
/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd"
    fi
    fw_code=${EFI_CODE:-} fw_vars=${EFI_VARS:-}
    if [ -z "$fw_code" ]; then
      for p in $pairs; do
        if [ -f "${p%%:*}" ] && [ -f "${p#*:}" ]; then fw_code=${p%%:*} fw_vars=${p#*:}; break; fi
      done
    fi
  fi
  if [ -n "$fw_code" ] && [ -f "$fw_code" ] && [ -f "$fw_vars" ]; then
    ok "UEFI firmware: $fw_code"
  else
    fail "no UEFI firmware for $HOST_ARCH${fw_code:+ (looked for $fw_code)}"
    fix "$(install_hint firmware)"
  fi

  # Packer writes the build's cloud-init seed CD with one of these.
  if have xorriso || have mkisofs || have hdiutil; then
    ok "ISO tool: $(basename "$(command -v xorriso || command -v mkisofs || command -v hdiutil)")"
  else
    fail "no ISO tool (xorriso, mkisofs or hdiutil) for the cloud-init seed CD"
    fix "$(install_hint iso)"
  fi

  for v in jq ${EXTRA_TOOLS:-}; do
    have "$v" && ok "$v" || { fail "$v not found"; fix "$(install_hint "$v")"; }
  done
  have make && ok "make" || {
    fail "make not found"
    if [ "$HOST_OS" = macos ]; then fix "xcode-select --install"; else fix "$(install_hint make)"; fi
  }
}

check_vagrant() {
  section "Vagrant (make test)"
  local v plugins key
  if ! have vagrant; then
    fail "vagrant not found"; fix "$(install_hint vagrant)"
  else
    v=$(version_of "$(vagrant --version 2>/dev/null)")
    if at_least "$v" 2.4; then ok "vagrant $v"
    else fail "vagrant $v (need 2.4 or later, which reads the catalog's architecture)"; fix "$(install_hint vagrant)"; fi
    plugins=$(vagrant plugin list 2>/dev/null)
  fi

  # Packer logs into the build VM with Vagrant's insecure key; Vagrant copies
  # its keys into ~/.vagrant.d the first time it loads.
  key=${VAGRANT_HOME:-$HOME/.vagrant.d}/insecure_private_keys/vagrant.key.ed25519
  if [ -f "$key" ]; then
    ok "Vagrant insecure key (the build logs in with it)"
  else
    fail "missing $key (the build logs in with it)"
    fix "vagrant box list   # any vagrant command copies Vagrant's insecure keys into ~/.vagrant.d"
  fi

  if [ "$HOST_OS" = macos ]; then
    if printf '%s\n' "${plugins:-}" | grep -q '^vagrant-qemu '; then
      ok "vagrant-qemu plugin $(version_of "$(printf '%s\n' "$plugins" | grep '^vagrant-qemu ')")"
    else
      fail "vagrant-qemu plugin not installed (make test boots the libvirt box with it)"
      fix "vagrant plugin install vagrant-qemu"
    fi
  else
    local uri=${LIBVIRT_DEFAULT_URI:-qemu:///system}
    if ! have virsh; then
      fail "virsh not found (libvirt)"; fix "$(install_hint libvirt)"
    elif virsh -c "$uri" uri >/dev/null 2>&1; then
      ok "libvirt reachable ($uri)"
      if virsh -c "$uri" pool-info default >/dev/null 2>&1; then
        ok "libvirt storage pool \"default\""
      else
        warn "no libvirt storage pool named \"default\" (vagrant-libvirt uses it)"
        fix "virsh -c $uri pool-define-as default dir --target /var/lib/libvirt/images && virsh -c $uri pool-autostart default && virsh -c $uri pool-start default"
      fi
    else
      fail "cannot connect to libvirt ($uri)"
      fix "sudo systemctl enable --now libvirtd && sudo usermod -aG libvirt \$USER   # then log out and back in"
    fi
    if printf '%s\n' "${plugins:-}" | grep -q '^vagrant-libvirt '; then
      ok "vagrant-libvirt plugin $(version_of "$(printf '%s\n' "$plugins" | grep '^vagrant-libvirt ')")"
    else
      fail "vagrant-libvirt plugin not installed (make test boots the libvirt box with it)"
      fix "$(install_hint libvirt-dev)"
      fix "vagrant plugin install vagrant-libvirt"
    fi
  fi
}

check_virtualbox() {
  local need=$VIRTUALBOX v
  case " ${PROVIDERS:-} " in
    *" virtualbox "*) [ "$need" = none ] || need=required ;;
    "  ")             ;;
    *)                need=none ;;
  esac
  [ "$need" = none ] && return
  section "VirtualBox"
  if have VBoxManage; then
    v=$(version_of "$(VBoxManage --version 2>/dev/null)")
    if at_least "$v" 7.1; then ok "VirtualBox $v"
    else
      # 7.1 is the first with Apple Silicon support and createvm --platform-architecture.
      fail "VirtualBox $v (need 7.1 or later)"
      fix "$(install_hint virtualbox)"
    fi
  elif [ "$need" = required ]; then
    fail "VBoxManage not found (the default build includes the virtualbox box)"
    fix "$(install_hint virtualbox)"
    fix "or build without it: make build PROVIDERS=libvirt"
  else
    warn "VBoxManage not found: only the libvirt box will be built"
    fix "$(install_hint virtualbox)   # optional, for the virtualbox box"
  fi
}

check_publish() {
  section "Publishing (make publish)"
  if ! have gh; then
    warn "gh not found (only needed to publish)"; fix "$(install_hint gh)"
  elif gh auth status >/dev/null 2>&1; then
    ok "gh $(version_of "$(gh --version 2>/dev/null | head -1)"), signed in"
  else
    warn "gh is not signed in (only needed to publish)"; fix "gh auth login"
  fi
}

check_disk() {
  section "Disk space"
  # A build holds the cloud image, the output image and the compressed box.
  local avail_kb need_gb=15
  avail_kb=$(df -Pk . 2>/dev/null | awk 'NR == 2 { print $4 }')
  if [ -z "$avail_kb" ]; then
    warn "could not read free disk space"
  elif [ "$avail_kb" -ge $((need_gb * 1024 * 1024)) ]; then
    ok "$((avail_kb / 1024 / 1024)) GB free"
  else
    warn "only $((avail_kb / 1024 / 1024)) GB free (a build needs about $need_gb GB)"
    fix "free some space, or remove old builds: make clean"
  fi
}

doctor_main() {
  printf 'Checking this machine for building and testing %s (%s/)\n' "$BOX" "$DISTRO"
  detect_platform
  if check_platform; then
    check_virtualization
    check_build_tools
    check_vagrant
    check_virtualbox
    check_publish
    check_disk
  fi
  echo ""
  if [ ${#FIXES[@]} -gt 0 ]; then
    printf '%s=== %s ===%s\n' "$HEADING" "To fix" "$RESET"
    printf '  %s\n' "${FIXES[@]}" | awk '!seen[$0]++'
    echo ""
  fi
  echo "$ERRORS error(s), $WARNINGS warning(s)"
  [ "$ERRORS" -eq 0 ]
}
