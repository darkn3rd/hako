# What building and testing this distro's boxes needs from the host; read by
# scripts/doctor and scripts/install-deps (see ../../scripts/doctor-lib.sh for
# what each setting means).
DISTRO=archlinux
BOX=hako/archlinux
SUPPORTED="macos/amd64 linux/amd64"
VIRTUALBOX=optional
EXTRA_TOOLS=""
