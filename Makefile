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
	install -Dpm 0644 20_juno-ubuntu-settings.gschema.override $(DESTDIR)/usr/share/glib-2.0/schemas/20_juno-ubuntu-settings.gschema.override
	install -Dpm 0644 juno-audio-fix.conf $(DESTDIR)/usr/share/junocomp/juno-audio-fix.conf
	install -Dpm 0755 restart-audio $(DESTDIR)/usr/share/junocomp/restart-audio
	install -Dpm 0755 junoppas $(DESTDIR)/usr/bin/junoppas
	install -Dpm 0755 juno-cpufreq.rules $(DESTDIR)/usr/share/nv41/udev/juno-cpufreq.rules
	install -Dpm 755 turbo/turbo-on $(DESTDIR)/usr/bin/turbo-on
	install -Dpm 755 turbo/turbo-off $(DESTDIR)/usr/bin/turbo-off
	install -Dpm 755 turbo/turbo-stat $(DESTDIR)/usr/bin/turbo-stat
	cp -R gaudible/librem5 $(DESTDIR)/usr/share/sounds
	install -Dpm 0755 gaudible/gaudible-deb.py $(DESTDIR)/usr/bin/gaudible-deb
	install -Dpm 0755 gaudible/gaudible-flatpak.py $(DESTDIR)/usr/bin/gaudible-flatpak
	install -Dpm 0644 gaudible/gaudible-deb.desktop $(DESTDIR)/etc/xdg/autostart/gaudible-deb.desktop
	install -Dpm 0644 gaudible/gaudible-flatpak.desktop $(DESTDIR)/etc/xdg/autostart/gaudible-flatpak.desktop
	install -Dpm 0644 power-profiles.rules $(DESTDIR)/etc/udev/rules.d/power-profiles.rules
	install -Dpm 0755 juno-pp $(DESTDIR)/usr/bin/juno-pp
	install -Dpm 0644 juno-pp.service $(DESTDIR)/etc/systemd/system/juno-pp.service
	install -Dpm 0644 disable-cpu-turbo.service $(DESTDIR)/etc/systemd/system/disable-cpu-turbo.service
	install -Dpm 0755 juno-grub $(DESTDIR)/usr/share/junocomp/juno-grub
	install -Dpm 0644 pipewire-pulse.conf $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d/pipewire-pulse.conf

install: install-core

uninstall:
	rm -R $(DESTDIR)/etc/skel/.config/libreoffice
	rm -f $(DESTDIR)/usr/bin/junoppas
	rm -f $(DESTDIR)/etc/tlp.d/juno-tlp.conf
	rm -R $(DESTDIR)/usr/share/junocomp/
	rm -f $(DESTDIR)/lib/systemd/system-sleep/restore-ethernet-connection
	rm -R $(DESTDIR)/usr/share/nv41/
	rm -f $(DESTDIR)/usr/bin/turbo-on
	rm -f $(DESTDIR)/usr/bin/turbo-off
	rm -f $(DESTDIR)/usr/bin/turbo-stat
	rm -R $(DESTDIR)/usr/share/sounds/librem5
	rm -f $(DESTDIR)/etc/xdg/autostart/gaudible-flatpak.desktop
	rm -f $(DESTDIR)/etc/xdg/autostart/gaudible-deb.desktop
	rm -f $(DESTDIR)/usr/bin/gaudible-deb
	rm -f $(DESTDIR)/usr/bin/gaudible-flatpak
	rm -f $(DESTDIR)/etc/udev/rules.d/power-profiles.rules
	rm -f $(DESTDIR)/usr/bin/juno-pp
	rm -f $(DESTDIR)/etc/systemd/system/juno-pp.service
	rm -f $(DESTDIR)/etc/systemd/system/disable-cpu-turbo.service
	rm -f $(DESTDIR)/usr/share/glib-2.0/schemas/20_juno-ubuntu-settings.gschema.override
	rm -f $(DESTDIR)/etc/pipewire/pipewire-pulse.conf.d