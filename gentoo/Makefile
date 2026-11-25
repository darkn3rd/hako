# Build, test and publish the hako Gentoo Vagrant box. Run from gentoo/
# (or from the repo root: make gentoo-build, make gentoo-test, ...).
#
#   make                            # build, then test (from gentoo/)
#   make build                      # libvirt box into boxes/
#   make test                       # vagrant up the box from a local catalog
#   make fixtures                   # example Vagrantfiles per provider and boot mode
#   make fixtures-test              # boot each one that this machine can run
#   make publish                    # GitHub release + update ../gentoo.json
#
# Gentoo is a rolling release, so the box has no OS version: the box version
# (today's date, YYYY.MM.DD) is the snapshot. Pass VERSION=... to test or
# publish a box built on another day.
#
# arm64 and amd64, each built natively (never emulated) from Gentoo's weekly
# cloud-init disk image for that architecture. libvirt only: the images'
# kernels have no vboxguest/vboxsf modules and no build tree to compile the
# Guest Additions against (see README.md, "VirtualBox (planned)").

OS         := gentoo
NAME       := $(OS)
BOX        := hako/$(NAME)
REPO       := darkn3rd/hako
PROVIDERS  ?= libvirt
MAX_BOOT   ?= 15
# 0 skips installing Docker and running containers in make test.
DOCKER_TEST ?= 1

# Each lookup below runs once (see ../ubuntu/Makefile for why).
ifndef ARCH
ARCH := $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,amd64)
endif
ifndef VERSION
VERSION := $(shell date +%Y.%m.%d)
endif
HOST_OS := $(shell uname -s)

ifneq ($(filter-out arm64 amd64,$(ARCH)),)
$(error unsupported ARCH $(ARCH); use arm64 or amd64)
endif
ifneq ($(filter-out libvirt,$(PROVIDERS)),)
$(error Gentoo boxes are libvirt only (no VirtualBox guest modules in the image kernel))
endif

QEMU_BINARY := $(if $(filter arm64,$(ARCH)),qemu-system-aarch64,qemu-system-x86_64)

# QEMU accelerator, and the Vagrant provider that boots the libvirt box in
# make test: hvf + vagrant-qemu on a Mac, kvm + vagrant-libvirt on Linux.
ifeq ($(HOST_OS),Darwin)
ACCEL           ?= hvf
LIBVIRT_VAGRANT ?= qemu
else
ACCEL           ?= kvm
LIBVIRT_VAGRANT ?= libvirt
endif

# UEFI firmware. Homebrew's QEMU ships edk2-*.fd in QEMU_SHARE; Linux distros
# package it separately, so on Linux pick the first pair found for the
# architecture: Debian/Ubuntu, Arch, Fedora. Override with EFI_CODE= EFI_VARS=
ifeq ($(HOST_OS),Darwin)
ifndef QEMU_SHARE
QEMU_SHARE := $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)/share/qemu
endif
else
QEMU_SHARE ?= /usr/share/qemu
ifeq ($(ARCH),arm64)
efi_pairs := /usr/share/AAVMF/AAVMF_CODE.fd:/usr/share/AAVMF/AAVMF_VARS.fd \
             /usr/share/edk2/aarch64/QEMU_CODE.fd:/usr/share/edk2/aarch64/QEMU_VARS.fd \
             /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw:/usr/share/edk2/aarch64/vars-template-pflash.raw
else
efi_pairs := /usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
             /usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd \
             /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd
endif
efi_pair  := $(firstword $(foreach p,$(efi_pairs),$(if $(wildcard $(subst :, ,$(p))),$(p))))
EFI_CODE  ?= $(word 1,$(subst :, ,$(efi_pair)))
EFI_VARS  ?= $(word 2,$(subst :, ,$(efi_pair)))
endif

# The image file name carries its build timestamp, so the URL and checksum
# are looked up at build time (scripts/cloud-image.sh). Set both to pin one.
CLOUD_IMAGE_URL      ?=
CLOUD_IMAGE_CHECKSUM ?=

CATALOG       := ../$(NAME).json
LOCAL_CATALOG := boxes/$(NAME).local.json
TAG           := $(NAME)-v$(VERSION)
RELEASE_URL   := https://github.com/$(REPO)/releases/download/$(TAG)
box_file       = boxes/$(NAME)-$(VERSION)-$(1)-$(ARCH).box
# GitHub release assets must be under 2 GiB.
MAX_ASSET     := 2147483648

PACKER_VARS := -var box_version=$(VERSION) -var arch=$(ARCH) \
               -var accelerator=$(ACCEL) -var qemu_share_dir=$(QEMU_SHARE) \
               $(if $(EFI_CODE),-var efi_code=$(EFI_CODE)) $(if $(EFI_VARS),-var efi_vars=$(EFI_VARS))

.PHONY: all preflight init build build-libvirt test local-catalog catalog check-size publish clean \
        fixtures fixtures-test fixtures-list fixtures-env

all: build test

# Fail early, naming every missing tool, instead of minutes into a build.
# Packer needs an ISO tool for the cloud-init seed CD.
preflight:
	@missing=; \
	for c in packer $(QEMU_BINARY) qemu-img jq curl; do \
	  command -v $$c >/dev/null || missing="$$missing $$c"; done; \
	command -v xorriso >/dev/null || command -v mkisofs >/dev/null || \
	  command -v hdiutil >/dev/null || missing="$$missing xorriso"; \
	if [ -n "$$missing" ]; then echo "missing:$$missing" >&2; exit 1; fi
	@if [ "$(HOST_OS)" != Darwin ]; then \
	  [ -n "$(EFI_CODE)" ] && [ -f "$(EFI_CODE)" ] && [ -f "$(EFI_VARS)" ] || \
	    { echo "no UEFI firmware found for $(ARCH); install ovmf/qemu-efi-aarch64 (Debian/Ubuntu), edk2-ovmf/edk2-aarch64 (Arch/Fedora) or pass EFI_CODE= EFI_VARS=" >&2; exit 1; }; \
	  [ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "no access to /dev/kvm (add yourself to the kvm group)" >&2; exit 1; }; \
	fi

init: preflight
	cd packer && packer init .

build: init $(addprefix build-,$(PROVIDERS))

build-libvirt:
	@if [ -n "$(CLOUD_IMAGE_URL)" ]; then set -- "$(CLOUD_IMAGE_URL)" "$(CLOUD_IMAGE_CHECKSUM)"; \
	else set -- $$(scripts/cloud-image.sh $(ARCH)) || exit 1; fi; \
	echo "cloud image: $$1"; \
	cd packer && packer build -force -only=hako.qemu.libvirt $(PACKER_VARS) \
	  -var cloud_image_url="$$1" -var cloud_image_checksum="$$2" .

# Local catalog with file:// URLs to the boxes in boxes/ (not committed).
local-catalog:
	rm -f $(LOCAL_CATALOG)
	@$(foreach p,$(PROVIDERS),scripts/catalog.sh $(LOCAL_CATALOG) $(BOX) $(VERSION) $(p) $(ARCH) \
	  $(call box_file,$(p)) file://$(CURDIR)/$(call box_file,$(p)) &&) true

test: local-catalog
	@$(foreach p,$(PROVIDERS),MAX_BOOT=$(MAX_BOOT) DOCKER_TEST=$(DOCKER_TEST) \
	  LIBVIRT_VAGRANT=$(LIBVIRT_VAGRANT) scripts/test-box.sh $(p) \
	  file://$(CURDIR)/$(LOCAL_CATALOG) $(VERSION) &&) true

# Integration tests, separate from make test (which checks the box itself):
# generated example Vagrantfiles in fixtures/<provider>-<mode>/, one per way
# a user runs the box. Name some to act on those only, e.g.
#   make fixtures-test FIXTURES="qemu-bios qemu-uefi"
# See scripts/fixtures.
FIXTURES ?=

# Generate the Vagrantfiles this machine can run, and run nothing.
fixtures: local-catalog
	scripts/fixtures gen $(FIXTURES)

# Generate, boot, check, reload, check and destroy each of them.
fixtures-test: local-catalog
	scripts/fixtures test $(FIXTURES)

fixtures-list:
	@scripts/fixtures list

# The settings scripts/fixtures reads (it must not recompute them).
fixtures-env:
	@printf "%s='%s'\n" \
	  ARCH "$(ARCH)" VERSION "$(VERSION)" BOX "$(BOX)" HOST_OS "$(HOST_OS)" \
	  QEMU_BINARY "$(QEMU_BINARY)" QEMU_SHARE "$(QEMU_SHARE)" \
	  EFI_CODE "$(EFI_CODE)" EFI_VARS "$(EFI_VARS)" LOCAL_CATALOG "$(LOCAL_CATALOG)"

# Update the committed catalog with the release download URLs + checksums.
catalog:
	@$(foreach p,$(PROVIDERS),scripts/catalog.sh $(CATALOG) $(BOX) $(VERSION) $(p) $(ARCH) \
	  $(call box_file,$(p)) $(RELEASE_URL)/$(notdir $(call box_file,$(p))) &&) true

# Every box must exist and be under GitHub's release asset limit.
# (stat -f is BSD/macOS, stat -c is GNU/Linux.)
check-size:
	@for f in $(foreach p,$(PROVIDERS),$(call box_file,$(p))); do \
	  size=$$(stat -f %z "$$f" 2>/dev/null || stat -c %s "$$f") || exit 1; \
	  if [ "$$size" -ge $(MAX_ASSET) ]; then echo "$$f is $$size bytes, over GitHub's 2 GiB limit" >&2; exit 1; fi; \
	  echo "$$f: $$size bytes (limit $(MAX_ASSET))"; \
	done

# Upload the boxes to the GitHub release $(TAG) (created if needed) and
# update $(CATALOG). Commit and push the catalog afterwards.
publish: check-size
	@git fetch -q origin main
	@if [ -n "$$(git rev-list HEAD..origin/main -- $(CATALOG))" ]; then \
	  echo "origin/main has $(CATALOG) changes this checkout lacks; pull first." >&2; exit 1; \
	fi
	$(MAKE) catalog VERSION=$(VERSION) PROVIDERS="$(PROVIDERS)"
	gh release view $(TAG) --repo $(REPO) >/dev/null 2>&1 || \
	  gh release create $(TAG) --repo $(REPO) --title "$(BOX) $(VERSION)" --notes ""
	gh release upload $(TAG) --repo $(REPO) --clobber $(foreach p,$(PROVIDERS),$(call box_file,$(p)))
	scripts/release-notes.sh $(REPO) $(TAG) $(BOX) $(VERSION) | \
	  gh release edit $(TAG) --repo $(REPO) --notes-file -
	@echo "Now commit and push $(CATALOG)."

clean:
	rm -rf output-libvirt boxes fixtures
	rm -f packer-*.log build-*.out
