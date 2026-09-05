SHELL := /bin/bash
# Install Juno-Drivers

.PHONY: install bundle-source

DESTDIR ?= debian/juno-drivers-diamon

# Pinned tree behind the clevo-keyboard-dkms payload: the sibling
# tuxedo-keyboard checkout, archived at build time, never vendored here. The
# sha is also named in the matching debian/changelog entry; keep them in sync.
CLEVO_REPO ?= ../tuxedo-keyboard
CLEVO_SHA := 8d62d129a65d116f5be4508fc55952f48945e1d1
CLEVO_VERSION := 4.6.2+diamon1

install:
	install -dm755 $(DESTDIR)/usr/share/junocomp
	install -dm755 $(DESTDIR)/usr/share/nv41/udev
	install -dm755 $(DESTDIR)/usr/share/glib-2.0/schemas/
	install -dm755 $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d/
	install -dm755 $(DESTDIR)/etc/libinput/
	install -dm755 $(DESTDIR)/etc/default/grub.d
	install -dm755 $(DESTDIR)/usr/bin
	install -Dpm 0644 20_juno-ubuntu-settings.gschema.override $(DESTDIR)/usr/share/glib-2.0/schemas/20_juno-ubuntu-settings.gschema.override
	install -Dpm 0644 juno-audio-fix.conf $(DESTDIR)/usr/share/junocomp/juno-audio-fix.conf
	install -Dpm 0644 pipewire-pulse.conf $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d/pipewire-pulse.conf
	install -Dpm 0644 60-nj70au-touchpad.conf $(DESTDIR)/usr/share/junocomp/60-nj70au-touchpad.conf
	install -Dpm 0644 60-system-clevo.quirks $(DESTDIR)/etc/libinput/60-system-clevo.quirks
	install -Dpm 0755 restore-i2c-hid $(DESTDIR)/usr/share/junocomp/restore-i2c-hid
	install -Dpm 0755 juno-grub-cmdline $(DESTDIR)/usr/share/junocomp/juno-grub-cmdline
	install -Dpm 0644 juno-cpufreq.rules $(DESTDIR)/usr/share/nv41/udev/juno-cpufreq.rules
	install -Dpm 0755 turbo/juno-cpu-policy $(DESTDIR)/usr/bin/juno-cpu-policy
	install -Dpm 0755 turbo/turbo-on $(DESTDIR)/usr/bin/turbo-on
	install -Dpm 0755 turbo/turbo-off $(DESTDIR)/usr/bin/turbo-off
	install -Dpm 0755 turbo/turbo-stat $(DESTDIR)/usr/bin/turbo-stat
	install -Dpm 0644 11-juno-drivers.cfg $(DESTDIR)/etc/default/grub.d/11-juno-drivers.cfg

# Stage the dpkg-owned DKMS source tree, and hand dh_dkms the pinned dkms.conf:
# debian/clevo-keyboard-dkms.dkms (generated, git-ignored) points at the copy
# dh_dkms installs itself, so no maintainer script ever copies a payload.
# Fails loudly when the pin is absent from the sibling checkout or the pinned
# dkms.conf drifts from the names the packaging stages.
bundle-source:
	@git -C "$(CLEVO_REPO)" cat-file -e "$(CLEVO_SHA)^{commit}" 2>/dev/null || { \
		echo "FATAL  pinned tuxedo-keyboard sha $(CLEVO_SHA) not in $(CLEVO_REPO);" >&2; \
		echo "       fetch that checkout (team/integration) before building" >&2; exit 1; }
	install -dm755 "$(DESTDIR)/usr/src/clevo-keyboard-$(CLEVO_VERSION)"
	git -C "$(CLEVO_REPO)" archive "$(CLEVO_SHA)" Makefile src | \
		tar -x -C "$(DESTDIR)/usr/src/clevo-keyboard-$(CLEVO_VERSION)"
	git -C "$(CLEVO_REPO)" show "$(CLEVO_SHA):dkms.conf" > debian/clevo-keyboard-dkms.dkms.conf
	@s=debian/clevo-keyboard-dkms.dkms.conf; \
		grep -qx 'PACKAGE_NAME=clevo-keyboard' "$$s" && \
		grep -qx 'PACKAGE_VERSION=$(CLEVO_VERSION)' "$$s" || { \
		echo "FATAL  dkms.conf at $(CLEVO_SHA) disagrees with clevo-keyboard-$(CLEVO_VERSION)" >&2; \
		exit 1; }
	printf '%s\n' 'debian/clevo-keyboard-dkms.dkms.conf' > debian/clevo-keyboard-dkms.dkms
