# What building and testing this distro's boxes needs from the host; read by
# scripts/doctor and scripts/install-deps (see ../../scripts/doctor-lib.sh for
# what each setting means).
DISTRO=ubuntu
BOX=hako/ubuntu-26.04
SUPPORTED="macos/arm64 macos/amd64"
VIRTUALBOX=required
EXTRA_TOOLS=""
