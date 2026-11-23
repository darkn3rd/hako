# What building and testing this distro's boxes needs from the host; read by
# scripts/doctor and scripts/install-deps (see ../../scripts/doctor-lib.sh for
# what each setting means).
DISTRO=almalinux
BOX=hako/almalinux-10
SUPPORTED="macos/arm64 macos/amd64 linux/arm64 linux/amd64"
# As in the Makefile: a Mac builds the virtualbox box by default; Linux only
# when VirtualBox is installed.
if [ "${DOCTOR_UNAME_S:-$(uname -s)}" = Darwin ]; then VIRTUALBOX=required; else VIRTUALBOX=optional; fi
EXTRA_TOOLS="curl"
