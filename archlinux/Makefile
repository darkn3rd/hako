# Build, test and publish the hako Arch Linux Vagrant box. Run from archlinux/
# (or from the repo root: make archlinux-build, make archlinux-test, ...).
#
#   make build                      # libvirt + virtualbox boxes into boxes/
#   make build PROVIDERS=libvirt    # just one provider
#   make test                       # vagrant up each box from a local catalog
#   make publish                    # GitHub release + update ../archlinux.json
#
# Arch Linux is a rolling release, so the box has no OS version: the box
# version (today's date, YYYY.MM.DD) is the snapshot. Pass VERSION=... to test
# or publish a box built on another day.
#
# amd64 only: Arch Linux publishes no official arm64 cloud image (Arch Linux
# ARM is a separate project), and boxes are built natively, never emulated.

OS         := archlinux
NAME       := $(OS)
BOX        := hako/$(NAME)
REPO       := darkn3rd/hako
PROVIDERS  ?= libvirt virtualbox
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
ifndef QEMU_SHARE
QEMU_SHARE := $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)/share/qemu
endif
# hvf on an Intel Mac; kvm on an x86 Linux host.
ifndef ACCEL
ACCEL := $(if $(filter Darwin,$(shell uname -s)),hvf,kvm)
endif

ifneq ($(ARCH),amd64)
$(error Arch Linux boxes are amd64 only (no official arm64 cloud image); this host is $(ARCH))
endif

CATALOG       := ../$(NAME).json
LOCAL_CATALOG := boxes/$(NAME).local.json
TAG           := $(NAME)-v$(VERSION)
RELEASE_URL   := https://github.com/$(REPO)/releases/download/$(TAG)
box_file       = boxes/$(NAME)-$(VERSION)-$(1)-$(ARCH).box
LIBVIRT_IMAGE := output-libvirt/hako-$(NAME)-$(ARCH).qcow2
# GitHub release assets must be under 2 GiB.
MAX_ASSET     := 2147483648

PACKER_VARS := -var box_version=$(VERSION) -var arch=$(ARCH) \
               -var accelerator=$(ACCEL) -var qemu_share_dir=$(QEMU_SHARE)

.PHONY: all init build build-libvirt build-virtualbox test local-catalog catalog check-size publish clean

all: build test

init:
	cd packer && packer init .

build: init $(addprefix build-,$(PROVIDERS))

build-libvirt:
	cd packer && packer build -force -only=hako.qemu.libvirt $(PACKER_VARS) .

# Reuses the finished libvirt image: convert it to a VMDK in a VirtualBox
# OVF, then let Packer add the VirtualBox guest utilities.
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
	@$(foreach p,$(PROVIDERS),MAX_BOOT=$(MAX_BOOT) DOCKER_TEST=$(DOCKER_TEST) scripts/test-box.sh $(p) \
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
	rm -rf output-libvirt output-virtualbox output-vbox-import boxes
	rm -f packer-*.log build-*.out
