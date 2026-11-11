# Build, test and publish hako Vagrant boxes.
#
#   make build                      # libvirt + virtualbox boxes into boxes/
#   make build PROVIDERS=libvirt    # just one provider
#   make test                       # vagrant up each box from a local catalog
#   make publish                    # GitHub release + update ubuntu-26.04.json
#
# VERSION defaults to today's date (YYYY.MM.DD). Pass VERSION=... to test or
# publish a box built on another day.

OS         := ubuntu
OS_VERSION := 26.04
ARCH       := arm64
NAME       := $(OS)-$(OS_VERSION)
BOX        := hako/$(NAME)
REPO       := darkn3rd/hako
VERSION    ?= $(shell date +%Y.%m.%d)
PROVIDERS  ?= libvirt virtualbox
MAX_BOOT   ?= 15

CATALOG       := $(NAME).json
LOCAL_CATALOG := boxes/$(NAME).local.json
TAG           := $(NAME)-v$(VERSION)
RELEASE_URL   := https://github.com/$(REPO)/releases/download/$(TAG)
box_file       = boxes/$(NAME)-$(VERSION)-$(1)-$(ARCH).box
LIBVIRT_IMAGE := output-libvirt/hako-$(NAME)-$(ARCH).qcow2
# GitHub release assets must be under 2 GiB.
MAX_ASSET     := 2147483648

PACKER_VARS := -var box_version=$(VERSION) -var os_name=$(OS) \
               -var os_version=$(OS_VERSION) -var arch=$(ARCH)

.PHONY: all init build build-libvirt build-virtualbox test local-catalog catalog check-size publish clean

all: build test

init:
	cd packer && packer init .

build: init $(addprefix build-,$(PROVIDERS))

build-libvirt:
	cd packer && packer build -force -only=hako.qemu.libvirt $(PACKER_VARS) .

# Reuses the finished libvirt image (see README): convert it to a VMDK in a
# VirtualBox OVF, then let Packer add the VirtualBox Guest Additions.
build-virtualbox: $(LIBVIRT_IMAGE)
	scripts/make-vbox-ovf.sh $(LIBVIRT_IMAGE) output-vbox-import
	cd packer && packer build -force -only=hako.virtualbox-ovf.virtualbox $(PACKER_VARS) .

$(LIBVIRT_IMAGE):
	$(MAKE) build-libvirt

# Local catalog with file:// URLs to the boxes in boxes/ (not committed).
local-catalog:
	rm -f $(LOCAL_CATALOG)
	@$(foreach p,$(PROVIDERS),scripts/catalog.sh $(LOCAL_CATALOG) $(BOX) $(VERSION) $(p) $(ARCH) \
	  $(call box_file,$(p)) file://$(CURDIR)/$(call box_file,$(p)) &&) true

test: local-catalog
	@$(foreach p,$(PROVIDERS),MAX_BOOT=$(MAX_BOOT) scripts/test-box.sh $(p) \
	  file://$(CURDIR)/$(LOCAL_CATALOG) $(VERSION) &&) true

# Update the committed catalog with the release download URLs + checksums.
catalog:
	@$(foreach p,$(PROVIDERS),scripts/catalog.sh $(CATALOG) $(BOX) $(VERSION) $(p) $(ARCH) \
	  $(call box_file,$(p)) $(RELEASE_URL)/$(notdir $(call box_file,$(p))) &&) true

# Every box must exist and be under GitHub's release asset limit.
check-size:
	@for f in $(foreach p,$(PROVIDERS),$(call box_file,$(p))); do \
	  size=$$(stat -f %z "$$f") || exit 1; \
	  if [ "$$size" -ge $(MAX_ASSET) ]; then echo "$$f is $$size bytes, over GitHub's 2 GiB limit" >&2; exit 1; fi; \
	  echo "$$f: $$size bytes (limit $(MAX_ASSET))"; \
	done

# Upload the boxes to the GitHub release $(TAG) (created if needed) and
# update $(CATALOG). Commit and push the catalog afterwards.
publish: check-size
	$(MAKE) catalog VERSION=$(VERSION) PROVIDERS="$(PROVIDERS)"
	gh release view $(TAG) --repo $(REPO) >/dev/null 2>&1 || \
	  gh release create $(TAG) --repo $(REPO) --title "$(BOX) $(VERSION)" \
	    --notes "Vagrant box $(BOX) $(VERSION) ($(ARCH): $(PROVIDERS)), built from the Ubuntu $(OS_VERSION) cloud image."
	gh release upload $(TAG) --repo $(REPO) --clobber $(foreach p,$(PROVIDERS),$(call box_file,$(p)))
	@echo "Now commit and push $(CATALOG)."

clean:
	rm -rf output-libvirt output-virtualbox output-vbox-import boxes
	rm -f packer-*.log build-*.out
