SHELL := /bin/bash
# Install Juno-Drivers

.PHONY: install

DESTDIR ?= debian/juno-drivers-diamon

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
