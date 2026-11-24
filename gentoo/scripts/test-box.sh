#!/usr/bin/env bash
# Boot a hako box with Vagrant from a catalog and check it:
#   - boot (systemd-analyze) must finish within MAX_BOOT seconds
#   - SSH works, sudo is passwordless, exactly one networkd file, no failed
#     units, and the VM comes back after a reboot
#   - the kernel passes Moby's check-config.sh, Docker's modules load, and
#     (unless DOCKER_TEST=0) Docker runs containers with networking
# then destroy the VM.
#
#   scripts/test-box.sh PROVIDER(libvirt) CATALOG_URL VERSION
set -euo pipefail

box=hako/gentoo

provider=$1 catalog_url=$2 version=$3
# Vendored from moby/moby (see third_party/moby/README.md).
check_config=$(cd "$(dirname "$0")/../../third_party/moby" && pwd)/check-config.sh
# Runs as root in the guest, only for the Docker test. The box ships no
# ebuild repository, so fetch one first; the packages come prebuilt from the
# binhost (getbinpkg is on in the box).
docker_install='emerge-webrsync -q && emerge --quiet --noreplace app-containers/docker app-containers/docker-cli'
max_boot=${MAX_BOOT:-15}

case $provider in
  # vagrant-qemu on macOS, vagrant-libvirt on Linux (set by the Makefile).
  libvirt)    vagrant_provider=${LIBVIRT_VAGRANT:-qemu} ;;
  *) echo "unknown provider $provider" >&2; exit 2 ;;
esac

. "$(dirname "$0")/vagrant-lib.sh"

# vagrant-libvirt talks to the system libvirtd: check access up front.
if [[ $vagrant_provider == libvirt ]] && ! libvirt_reachable; then
  echo "FAIL: $(libvirt_unreachable_hint 'make test ...')" >&2
  exit 1
fi

workdir=$(mktemp -d "${TMPDIR:-/tmp}/hako-test.XXXXXX")
trap 'cd "$workdir" && vagrant destroy -f >/dev/null 2>&1 || true; rm -rf "$workdir"' EXIT

# Run every Vagrant command from the scratch dir: Vagrant loads the first
# Vagrantfile it finds walking up from the current directory, so running from
# the repo can pick up an unrelated one in a parent directory.
cd "$workdir"

drop_cached_box "$box" "$version" "$provider"
if [[ $vagrant_provider == libvirt ]]; then
  drop_stale_libvirt_volumes "$box" "$version"
fi

cat > "$workdir/Vagrantfile" <<VF
Vagrant.configure("2") do |config|
  config.vm.box         = "$box"
  config.vm.box_url     = "$catalog_url"
  config.vm.box_version = "$version"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider "qemu" do |qe|
    qe.ssh_auto_correct = true
  end
  # vagrant-libvirt defaults to 512 MB, too little for the Docker test.
  config.vm.provider "libvirt" do |lv|
    lv.memory = 2048
    lv.cpus   = 2
  end
end
VF

start=$(date +%s)
vagrant up --provider "$vagrant_provider"
echo "vagrant up took $(( $(date +%s) - start ))s"

# Wait until systemd reports the boot as finished.
for _ in $(seq 1 30); do
  if out=$(vagrant ssh -c 'systemd-analyze time' 2>/dev/null); then break; fi
  sleep 2
done
echo "$out"
total=$(printf '%s\n' "$out" | sed -n 's/.*= \(.*\)$/\1/p' | head -1)
# LC_ALL=C: gawk 5.4.0 with no locale set never matches /s$/, which made this
# parse silently return 0.0.
seconds=$(printf '%s\n' "$total" | LC_ALL=C awk '{
  s = 0
  for (i = 1; i <= NF; i++) {
    v = $i
    if (v ~ /ms$/)       { sub(/ms$/, "", v); s += v / 1000 }
    else if (v ~ /min$/) { sub(/min$/, "", v); s += v * 60 }
    else if (v ~ /s$/)   { sub(/s$/, "", v); s += v }
  }
  printf "%.1f", s }')
if [[ -z $total || $seconds == 0.0 ]]; then
  echo "FAIL: could not read the boot time from systemd-analyze" >&2
  exit 1
fi
echo "boot time: ${seconds}s (limit ${max_boot}s)"

vagrant ssh -c 'set -e
  echo "hostname: $(uname -n)  kernel: $(uname -r)"
  sudo -n true && echo "passwordless sudo: ok"
  ls /etc/systemd/network; test "$(ls /etc/systemd/network/*.network | wc -l)" -eq 1
  cat /etc/hako-release
  state=$(systemctl is-system-running --wait || true)
  echo "system state: $state"
  if [ "$state" != running ]; then systemctl --failed --no-pager; exit 1; fi
  systemd-analyze blame | head -5'

# A second boot must work too (no first-boot-only luck).
vagrant reload
vagrant ssh -c 'systemctl is-system-running --wait && uptime'

# Docker: every kernel feature Docker requires must be configured (Moby's
# check-config.sh exits non-zero otherwise), the modules must really be on
# disk (check-config only reads the kernel config), and a container must run
# with outbound networking and a published port.
vagrant upload "$check_config" /tmp/check-config.sh
vagrant ssh -c 'sudo NO_COLOR=1 sh /tmp/check-config.sh'
vagrant ssh -c 'set -e
  for m in overlay veth bridge br_netfilter nf_nat nf_conntrack nf_tables nft_compat \
           xt_conntrack xt_addrtype xt_MASQUERADE xt_mark ip_tables iptable_filter \
           iptable_nat ip6_tables ip6table_filter ip6table_nat; do
    sudo modprobe "$m" || { echo "FAIL: cannot load kernel module $m" >&2; exit 1; }
  done
  echo "docker kernel modules: ok"'

# Install Docker in the throwaway test VM (not in the box) and run
# containers. DOCKER_TEST=0 skips this, e.g. without Docker Hub access.
if [[ ${DOCKER_TEST:-1} == 1 ]]; then
  {
    printf '#!/usr/bin/env bash\nset -euxo pipefail\n%s\n' "$docker_install"
    cat <<'SH'
systemctl enable --now docker
docker info --format 'storage driver: {{.Driver}}, cgroup: {{.CgroupVersion}}'
docker run --rm busybox wget -q --spider http://example.com
echo "container egress: ok"
docker run -d --name hako-web -p 8080:80 busybox \
  sh -c 'mkdir -p /www && echo hako > /www/index.html && exec httpd -f -p 80 -h /www'
ok=
for _ in $(seq 1 15); do
  if [ "$(curl -fsS http://127.0.0.1:8080/ 2>/dev/null)" = hako ]; then ok=1; break; fi
  sleep 1
done
docker rm -f hako-web
[ -n "$ok" ] || { echo "FAIL: no reply on published port 8080" >&2; exit 1; }
echo "published port: ok"
SH
  } > "$workdir/docker-test.sh"
  vagrant upload "$workdir/docker-test.sh" /tmp/docker-test.sh
  vagrant ssh -c 'sudo bash /tmp/docker-test.sh'
fi

if awk -v s="$seconds" -v m="$max_boot" 'BEGIN { exit !(s > m) }'; then
  echo "FAIL: boot took ${seconds}s, over ${max_boot}s" >&2
  exit 1
fi
echo "PASS: $box $version ($provider)"
