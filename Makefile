# Each distro builds from its own directory (ubuntu/, archlinux/, gentoo/). These
# targets forward to them, e.g.:
#
#   make ubuntu-build PROVIDERS=libvirt   # = make -C ubuntu build PROVIDERS=libvirt
#   make archlinux-test
#   make gentoo-doctor                    # can this machine build gentoo/?
#   make doctor                           # ... each distro, one after another
#
# Catalogs (*.json) stay at the repo root, where GitHub Pages serves them.

DISTROS := ubuntu archlinux gentoo

.PHONY: $(DISTROS) clean doctor

$(foreach d,$(DISTROS),$(d)-%):
	$(MAKE) -C $(firstword $(subst -, ,$@)) $(patsubst $(firstword $(subst -, ,$@))-%,%,$@)

clean: $(addsuffix -clean,$(DISTROS))

# Every distro's check, even after one fails; fails if any failed.
doctor:
	@rc=0; for d in $(DISTROS); do $(MAKE) -s -C $$d doctor || rc=1; echo; done; exit $$rc
