# Vagrant and libvirt helpers shared by test-box.sh and fixtures. Source it:
#
#   . "$(dirname "$0")/vagrant-lib.sh"

libvirt_uri=${LIBVIRT_DEFAULT_URI:-qemu:///system}

# vagrant-libvirt talks to the system libvirtd: can this user reach it?
libvirt_reachable() {
  virsh -c "$libvirt_uri" uri >/dev/null 2>&1
}

# libvirt_unreachable_hint COMMAND: the fix, for a failed libvirt_reachable.
libvirt_unreachable_hint() {
  echo "cannot connect to libvirt ($libvirt_uri). Join the libvirt group and"
  echo "      log in again (or run: sg libvirt -c '$1')."
}

# drop_cached_box BOX VERSION PROVIDER: a rebuilt box keeps its version
# number, so remove any cached copy before adding it again.
# (No --architecture: Vagrant 2.4.9 then claims the architecture is not
# installed, on arm64 and on amd64 alike.)
drop_cached_box() {
  local box=$1 version=$2 provider=$3
  if vagrant box list | grep -q "^$box *($provider, $version"; then
    vagrant box remove "$box" --box-version "$version" \
      --provider "$provider" --force
  fi
}

# drop_stale_libvirt_volumes BOX VERSION: vagrant-libvirt copies the box disk
# into a libvirt storage pool and reuses that copy for as long as it exists;
# vagrant box remove leaves it behind. A rebuilt box keeps its version, so
# delete the copy or the old build is tested.
drop_stale_libvirt_volumes() {
  local box=$1 version=$2 vol_prefix vol
  vol_prefix="${box//\//-VAGRANTSLASH-}_vagrant_box_image_${version}_"
  # (virsh 8.0 vol-list has no --name; take the first column of the table.)
  { virsh -c "$libvirt_uri" vol-list default | awk 'NR > 2 && NF { print $1 }' |
      grep -F "$vol_prefix" || true; } |
    while read -r vol; do
      echo "Deleting stale libvirt volume $vol"
      virsh -c "$libvirt_uri" vol-delete "$vol" --pool default
    done
}
