# Build, test and publish the hako NixOS Vagrant boxes. Run from nixos/
# (or from the repo root: make nixos-build, make nixos-test, ...).
#
#   make                            # build, then test (from nixos/)     
#   make build                      # boxes into boxes/: libvirt and virtualbox
#   make build PROVIDERS=libvirt    # just one provider
#   make test                       # vagrant up each box from a local catalog
#   make publish                    # GitHub release + update ../nixos-26.05.json
#
# VERSION defaults to today's date (YYYY.MM.DD). Pass VERSION=... to test or
# publish a box built on another day.
#
# arm64 and amd64, each built natively (never emulated). NixOS has no
# official cloud image, so a helper VM booted from Debian's generic cloud
# image installs NixOS onto a second disk with the official installer tools
# (build-installer), and that disk, booted on its own, becomes the box.

OS         := nixos
OS_VERSION := 26.05
CHANNEL    := https://channels.nixos.org/nixos-$(OS_VERSION)
NAME       := $(OS)-$(OS_VERSION)
BOX        := hako/$(NAME)
REPO       := darkn3rd/hako
# Both providers on a Mac; on Linux, virtualbox only when VirtualBox is
# installed (KVM is the usual hypervisor there).
ifeq ($(shell uname -s),Darwin)
PROVIDERS  ?= libvirt virtualbox
else
PROVIDERS  ?= libvirt$(if $(shell command -v VBoxManage 2>/dev/null), virtualbox)
endif
MAX_BOOT   ?= 15

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
ifneq ($(filter-out libvirt virtualbox,$(PROVIDERS)),)
$(error unknown PROVIDERS $(filter-out libvirt virtualbox,$(PROVIDERS)); use libvirt and/or virtualbox)
endif

# Under Rosetta, an Apple Silicon Mac reports itself as x86_64, so the build
# would pick amd64 and fail, since boxes are never emulated. Stop early.
ifeq ($(shell sysctl -n sysctl.proc_translated 2>/dev/null),1)
$(error make is running under Rosetta (x86_64) on Apple Silicon; run it from a native arm64 shell, for example: arch -arm64 make $(MAKECMDGOALS))
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

# The helper VM's image (Debian 13's newest dated generic cloud image) is
# looked up at build time (scripts/helper-image.sh). Set both to pin one.
HELPER_IMAGE_URL      ?=
HELPER_IMAGE_CHECKSUM ?=

CATALOG       := ../$(NAME).json
LOCAL_CATALOG := boxes/$(NAME).local.json
TAG           := $(NAME)-v$(VERSION)
RELEASE_URL   := https://github.com/$(REPO)/releases/download/$(TAG)
box_file       = boxes/$(NAME)-$(VERSION)-$(1)-$(ARCH).box
LIBVIRT_IMAGE := output-libvirt/hako-$(NAME)-$(ARCH).qcow2
# The installer VM's second disk, where NixOS is installed.
INSTALLED_IMAGE := output-installer/hako-$(NAME)-$(ARCH)-installer.qcow2-1
# GitHub release assets must be under 2 GiB.
MAX_ASSET     := 2147483648

PACKER_VARS := -var box_version=$(VERSION) -var os_version=$(OS_VERSION) -var nixos_channel=$(CHANNEL) -var arch=$(ARCH) \
               -var accelerator=$(ACCEL) -var qemu_share_dir=$(QEMU_SHARE) \
               $(if $(EFI_CODE),-var efi_code=$(EFI_CODE)) $(if $(EFI_VARS),-var efi_vars=$(EFI_VARS))

.PHONY: all preflight init build build-installer build-libvirt build-virtualbox test local-catalog catalog check-size publish clean

all: build test

# Fail early, naming every missing tool, instead of minutes into a build.
# Packer needs an ISO tool for the cloud-init seed CD.
preflight:
	@missing=; \
	for c in packer $(QEMU_BINARY) qemu-img jq curl; do \
	  command -v $$c >/dev/null || missing="$$missing $$c"; done; \
	command -v xorriso >/dev/null || command -v mkisofs >/dev/null || \
	  command -v hdiutil >/dev/null || missing="$$missing xorriso"; \
	case " $(PROVIDERS) " in *" virtualbox "*) \
	  command -v VBoxManage >/dev/null || missing="$$missing VBoxManage";; esac; \
	if [ -n "$$missing" ]; then echo "missing:$$missing" >&2; exit 1; fi
	@if [ "$(HOST_OS)" != Darwin ]; then \
	  [ -n "$(EFI_CODE)" ] && [ -f "$(EFI_CODE)" ] && [ -f "$(EFI_VARS)" ] || \
	    { echo "no UEFI firmware found for $(ARCH); install ovmf/qemu-efi-aarch64 (Debian/Ubuntu), edk2-ovmf/edk2-aarch64 (Arch/Fedora) or pass EFI_CODE= EFI_VARS=" >&2; exit 1; }; \
	  [ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "no access to /dev/kvm (add yourself to the kvm group)" >&2; exit 1; }; \
	fi

init: preflight
	cd packer && packer init .

build: init $(addprefix build-,$(PROVIDERS))

# Step 1: install NixOS onto the helper VM's second disk.
build-installer:
	@if [ -n "$(HELPER_IMAGE_URL)" ]; then set -- "$(HELPER_IMAGE_URL)" "$(HELPER_IMAGE_CHECKSUM)"; \
	else set -- $$(scripts/helper-image.sh 13 $(ARCH)) || exit 1; fi; \
	echo "helper image: $$1"; \
	cd packer && packer build -force -only=install.qemu.installer $(PACKER_VARS) \
	  -var helper_image_url="$$1" -var helper_image_checksum="$$2" .

# Step 2: boot the installed disk, check and clean it up: the libvirt box.
build-libvirt: build-installer
	cd packer && packer build -force -only=hako.qemu.libvirt $(PACKER_VARS) \
	  -var installed_image=$(CURDIR)/$(INSTALLED_IMAGE) .

# Reuses the finished libvirt image: convert it to a VMDK in a VirtualBox
# OVF, then let Packer add VirtualBox guest support.
build-virtualbox: $(LIBVIRT_IMAGE)
	scripts/make-vbox-ovf.sh $(LIBVIRT_IMAGE) output-vbox-import $(ARCH)
	cd packer && packer build -force -only=hako.virtualbox-ovf.virtualbox $(PACKER_VARS) .

$(LIBVIRT_IMAGE):
	$(MAKE) build-libvirt

# Local catalog with file:// URLs to the boxes in boxes/ (not committed).
local-catalog:
	rm -f $(LOCAL_CATALOG)
	@$(foreach p,$(PROVIDERS),scripts/catalog.sh $(LOCAL_CATALOG) $(BOX) $(VERSION) $(p) $(ARCH) \
	  $(call box_file,$(p)) file://$(CURDIR)/$(call box_file,$(p)) &&) true

test: local-catalog
	@$(foreach p,$(PROVIDERS),MAX_BOOT=$(MAX_BOOT) \
	  LIBVIRT_VAGRANT=$(LIBVIRT_VAGRANT) scripts/test-box.sh $(p) \
	  file://$(CURDIR)/$(LOCAL_CATALOG) $(VERSION) &&) true

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
	rm -rf output-installer output-libvirt output-virtualbox output-vbox-import boxes
	rm -f packer-*.log build-*.out
