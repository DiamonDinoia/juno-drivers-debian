SHELL := /bin/bash
# Install Juno-Drivers

DESTDIR=debian/juno-drivers

install-core:
	install -dm755 $(DESTDIR)/lib/systemd/system-sleep/
	install -dm755 $(DESTDIR)/etc/skel/.config
	install -dm755 $(DESTDIR)/etc/tlp.d/
	install -dm755 $(DESTDIR)/etc/skel/.local/share/applications
	install -dm755 $(DESTDIR)/usr/share/juno-tlp
	install -dm755 $(DESTDIR)/usr/share/nv41/udev/
	install -dm755 $(DESTDIR)/usr/share/junocomp
	install -dm755 $(DESTDIR)/usr/share/glib-2.0/schemas/
	install -dm755 $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d/
	install -dm755 install -dm755 $(DESTDIR)/etc/initramfs-tools/
	install -dm755 $(DESTDIR)/etc/libinput/
	install -Dpm 0644 20_juno-ubuntu-settings.gschema.override $(DESTDIR)/usr/share/glib-2.0/schemas/20_juno-ubuntu-settings.gschema.override
	install -Dpm 0644 juno-audio-fix.conf $(DESTDIR)/usr/share/junocomp/juno-audio-fix.conf
	install -Dpm 0755 restart-audio $(DESTDIR)/usr/share/junocomp/restart-audio
	install -Dpm 0755 juno-cpufreq.rules $(DESTDIR)/usr/share/nv41/udev/juno-cpufreq.rules
	install -Dpm 755 turbo/turbo-on $(DESTDIR)/usr/bin/turbo-on
	install -Dpm 755 turbo/turbo-off $(DESTDIR)/usr/bin/turbo-off
	install -Dpm 755 turbo/turbo-stat $(DESTDIR)/usr/bin/turbo-stat
	install -Dpm 0644 disable-cpu-turbo.service $(DESTDIR)/etc/systemd/system/disable-cpu-turbo.service
	install -Dpm 0644 pipewire-pulse.conf $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d/pipewire-pulse.conf
	install -Dpm 0644 resume $(DESTDIR)/etc/initramfs-tools/resume
	install -Dpm 0644 60-nj70au-touchpad.conf $(DESTDIR)/usr/share/junocomp/60-nj70au-touchpad.conf
	install -Dpm 0644 60-system-clevo.quirks $(DESTDIR)/etc/libinput/60-system-clevo.quirks

install: install-core

uninstall:
	rm -R $(DESTDIR)/etc/skel/.config/libreoffice
	rm -R $(DESTDIR)/usr/share/junocomp/
	rm -f $(DESTDIR)/lib/systemd/system-sleep/restore-ethernet-connection
	rm -R $(DESTDIR)/usr/share/nv41/
	rm -f $(DESTDIR)/usr/bin/turbo-on
	rm -f $(DESTDIR)/usr/bin/turbo-off
	rm -f $(DESTDIR)/usr/bin/turbo-stat
	rm -f $(DESTDIR)/etc/systemd/system/disable-cpu-turbo.service
	rm -f $(DESTDIR)/usr/share/glib-2.0/schemas/20_juno-ubuntu-settings.gschema.override
	rm -R $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d
	rm -f $(DESTDIR)/etc/initramfs-tools/resume
	rm -f $(DESTDIR)/etc/libinput/60-system-clevo.quirks
