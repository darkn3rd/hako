# Shared installer for each distro's scripts/install-deps: installs what
# building and testing that distro's boxes needs on this platform, skipping
# what is already there. packer, jq and gh are not here: they come from the
# distro's mise.toml (mise install, which mise run deps runs first).
#
# A distro's scripts/install-deps sources its requirements.sh (DISTRO, BOX,
# SUPPORTED, VIRTUALBOX, EXTRA_TOOLS: see doctor-lib.sh), then this file, and
# calls install_deps_main "$@". PROVIDERS from the environment narrows it as
# for the doctor: PROVIDERS=libvirt skips VirtualBox.
#
#   --dry-run, -n   print the commands instead of running them
#
# Supported: macOS with Homebrew; Debian/Ubuntu (apt), Arch (pacman) and
# Fedora (dnf), with sudo. Other platforms get the doctor's advice instead.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/doctor-lib.sh"

DRY_RUN=0 NOTES=() NO_VAGRANT=0
# The distro's scripts/install-deps, for --help (it cds before calling main).
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
# Print a command, then run it (unless --dry-run). Arguments are one command;
# run_sh takes a shell string for pipelines and redirections.
run()    { printf '  %s$%s %s\n' "$HEADING" "$RESET" "$*"; [ "$DRY_RUN" = 1 ] || "$@"; }
run_sh() { printf '  %s$%s %s\n' "$HEADING" "$RESET" "$1"; [ "$DRY_RUN" = 1 ] || bash -c "$1"; }
later()  { NOTES+=("$1"); }
# Words without repeats, in order: package lists plus EXTRA_TOOLS.
uniq_words() { printf '%s\n' "$@" | awk 'NF && !seen[$0]++' | tr '\n' ' '; }

# Does this distro build a VirtualBox box here? required, optional or none,
# as in the doctor: PROVIDERS overrides, and Linux hosts get none (distro
# VirtualBox packages are often older than 7.1).
virtualbox_need() {
  local need=$VIRTUALBOX
  case " ${PROVIDERS:-} " in
    *" virtualbox "*) [ "$need" = none ] || need=required ;;
    "  ")             ;;
    *)                need=none ;;
  esac
  echo "$need"
}

virtualbox_ok() {
  have VBoxManage && at_least "$(version_of "$(VBoxManage --version 2>/dev/null)")" 7.1
}

deps_macos() {
  local formulae="" vb
  section "Homebrew packages"
  if ! have brew; then
    fail "Homebrew not found"
    NO_VAGRANT=1
    later "install Homebrew (https://brew.sh), then run this again"
    return 1
  fi
  if [ "$HOST_ARCH" = arm64 ]; then have qemu-system-aarch64 || formulae="$formulae qemu"
  else have qemu-system-x86_64 || formulae="$formulae qemu"; fi
  case $formulae in *qemu*) ;; *) have qemu-img || formulae="$formulae qemu" ;; esac
  for t in ${EXTRA_TOOLS:-}; do have "$t" || formulae="$formulae $t"; done
  if [ -n "$formulae" ]; then run brew install $formulae; else ok "QEMU$( [ -n "${EXTRA_TOOLS:-}" ] && echo " and ${EXTRA_TOOLS}") already installed"; fi

  if have vagrant; then ok "vagrant already installed"
  else run brew install --cask hashicorp/tap/hashicorp-vagrant; fi

  vb=$(virtualbox_need)
  if [ "$vb" = none ]; then :
  elif virtualbox_ok; then ok "VirtualBox 7.1+ already installed"
  elif [ "$vb" = required ]; then
    run brew install --cask virtualbox
    later "VirtualBox: allow its system extension if macOS asks (System Settings > Privacy & Security)"
  else
    later "optional: brew install --cask virtualbox   # adds the virtualbox box to make build"
  fi
}

deps_linux() {
  local pkgs q fw vb
  vb=$(virtualbox_need)
  [ "$vb" = none ] || later "VirtualBox is not installed on Linux (distro packages are often older than 7.1); install 7.1+ from https://www.virtualbox.org/wiki/Linux_Downloads for the virtualbox box, or build with PROVIDERS=libvirt"

  section "System packages ($PKG)"
  if ! have sudo && [ "$(id -u)" != 0 ]; then
    fail "sudo not found"; later "install sudo, or run this as root"; return 1
  fi
  local SUDO=sudo; [ "$(id -u)" = 0 ] && SUDO=
  case $PKG in
    apt)
      if [ "$HOST_ARCH" = arm64 ]; then q=qemu-system-arm fw=qemu-efi-aarch64; else q=qemu-system-x86 fw=ovmf; fi
      pkgs="$q qemu-utils $fw xorriso libvirt-daemon-system libvirt-clients libvirt-dev ruby-dev build-essential curl gnupg"
      run $SUDO apt-get update
      run $SUDO apt-get install -y $(uniq_words $pkgs ${EXTRA_TOOLS:-})
      if have vagrant; then ok "vagrant already installed"
      else
        # Vagrant comes from HashiCorp's apt repository (distro packages are old).
        run_sh "curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
        run_sh "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(. /etc/os-release; echo \"\${UBUNTU_CODENAME:-\$VERSION_CODENAME}\") main\" | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null"
        run $SUDO apt-get update
        run $SUDO apt-get install -y vagrant
      fi
      ;;
    pacman)
      if [ "$HOST_ARCH" = arm64 ]; then q=qemu-system-aarch64 fw=edk2-aarch64; else q=qemu-base fw=edk2-ovmf; fi
      pkgs="$q qemu-img $fw libisoburn libvirt dnsmasq base-devel curl"
      run $SUDO pacman -S --needed --noconfirm $(uniq_words $pkgs ${EXTRA_TOOLS:-})
      if have vagrant; then ok "vagrant already installed"
      elif have paru; then run paru -S --needed --noconfirm vagrant
      elif have yay; then run yay -S --needed --noconfirm vagrant
      else
        fail "vagrant is not in Arch's repositories, and no AUR helper (paru, yay) was found"
        NO_VAGRANT=1
        later "install vagrant from the AUR or https://developer.hashicorp.com/vagrant/install, then run this again for its plugin"
      fi
      ;;
    dnf)
      if [ "$HOST_ARCH" = arm64 ]; then q=qemu-system-aarch64 fw=edk2-aarch64; else q=qemu-system-x86 fw=edk2-ovmf; fi
      pkgs="$q qemu-img $fw xorriso libvirt libvirt-devel ruby-devel gcc make curl"
      run $SUDO dnf install -y $(uniq_words $pkgs ${EXTRA_TOOLS:-})
      if have vagrant; then ok "vagrant already installed"
      else
        # Fedora's own vagrant is older than 2.4; use HashiCorp's repository.
        run $SUDO dnf install -y dnf-plugins-core
        if dnf config-manager addrepo --help >/dev/null 2>&1; then
          run $SUDO dnf config-manager addrepo --overwrite --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
        else
          run $SUDO dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
        fi
        run $SUDO dnf install -y vagrant
      fi
      ;;
    *)
      fail "no installer for this Linux distribution"
      NO_VAGRANT=1
      later "install the packages the doctor lists: scripts/doctor"
      return 1 ;;
  esac

  section "libvirt and KVM access"
  run $SUDO systemctl enable --now libvirtd
  local groups="" g
  for g in kvm libvirt; do
    if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then ok "$USER is in the $g group"
    else groups="${groups:+$groups,}$g"; fi
  done
  if [ -n "$groups" ]; then
    run $SUDO usermod -aG "$groups" "$USER"
    later "log out and back in (or reboot) so the new $groups group membership applies"
  fi
}

deps_vagrant() {
  local plugin
  section "Vagrant"
  if [ "$HOST_OS" = macos ]; then plugin=vagrant-qemu; else plugin=vagrant-libvirt; fi
  # (A dry run assumes the steps above installed it, unless one couldn't.)
  if ! have vagrant && { [ "$DRY_RUN" = 0 ] || [ "$NO_VAGRANT" = 1 ]; }; then
    warn "vagrant is not installed, so its plugin and keys are skipped"
    return
  fi
  if have vagrant && vagrant plugin list 2>/dev/null | grep -q "^$plugin "; then
    ok "$plugin plugin already installed"
  else
    run vagrant plugin install "$plugin"
  fi
  # Packer logs into the build VM with Vagrant's insecure key, which Vagrant
  # copies into ~/.vagrant.d the first time it loads.
  if [ -f "${VAGRANT_HOME:-$HOME/.vagrant.d}/insecure_private_keys/vagrant.key.ed25519" ]; then
    ok "Vagrant insecure key in place"
  else
    run_sh "vagrant box list >/dev/null"
  fi
}

install_deps_main() {
  while [ $# -gt 0 ]; do
    case $1 in
      -n|--dry-run) DRY_RUN=1 ;;
      -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$SELF"; return 0 ;;
      *) echo "unknown option: $1" >&2; return 2 ;;
    esac
    shift
  done
  printf 'Installing what %s (%s/) needs on this machine%s\n' "$BOX" "$DISTRO" \
    "$( [ "$DRY_RUN" = 1 ] && echo ' (dry run: printing commands only)')"
  detect_platform
  if ! check_platform || [ "$ERRORS" -gt 0 ]; then
    echo ""; [ ${#FIXES[@]} -eq 0 ] || printf '  %s\n' "${FIXES[@]}"
    return 1
  fi
  have mise || later "packer, jq and gh come from mise.toml: install mise (https://mise.jdx.dev), then mise install"

  case $HOST_OS in
    macos) deps_macos ;;
    linux) deps_linux ;;
  esac
  deps_vagrant

  echo ""
  if [ ${#NOTES[@]} -gt 0 ]; then
    printf '%s=== %s ===%s\n' "$HEADING" "Still to do" "$RESET"
    printf '  %s\n' "${NOTES[@]}"
    echo ""
  fi
  if [ "$ERRORS" -gt 0 ]; then
    echo "$ERRORS step(s) could not be done; see above."
    return 1
  fi
  echo "Done. Check the result with: mise run doctor"
}
