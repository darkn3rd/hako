# Each distro builds from its own directory (ubuntu/, archlinux/, gentoo/,
# nixos/). These targets forward to them, e.g.:
#
#   make ubuntu-build PROVIDERS=libvirt   # = make -C ubuntu build PROVIDERS=libvirt
#   make archlinux-test
#
# Catalogs (*.json) stay at the repo root, where GitHub Pages serves them.

DISTROS := ubuntu archlinux gentoo nixos

.PHONY: $(DISTROS) clean

$(foreach d,$(DISTROS),$(d)-%):
	$(MAKE) -C $(firstword $(subst -, ,$@)) $(patsubst $(firstword $(subst -, ,$@))-%,%,$@)

clean: $(addsuffix -clean,$(DISTROS))
