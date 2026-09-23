#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

check_postinst()
{
	postinst=$1

	grep -Fq 'if [ -e /run/udev/control ]; then' "$postinst" || return 1
	grep -Fq 'udevadm control --reload' "$postinst" || return 1
}

check_postinst "$root/debian/clevo-keyboard-dkms.postinst"

tmp=$(mktemp -d /tmp/clevo-keyboard-postinst-check.XXXXXX)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp "$root/debian/clevo-keyboard-dkms.postinst" "$tmp/postinst"
sed -i '/udevadm control --reload/d' "$tmp/postinst"
if check_postinst "$tmp/postinst"; then
	echo 'missing udev reload mutation passed' >&2
	exit 1
fi

echo 'clevo-keyboard postinst checks passed'

# /etc/modprobe.d/juno-audio-fix.conf is admin-editable config, not a dpkg
# conffile: the PE60RNE_RND_RNC branch must seed it once, never reinstall
# over a local edit on every postinst run (upgrade, reconfigure).
check_audio_fix_guard()
{
	postinst=$1

	awk '/PE60RNE_RND_RNC/{f=1} f && /juno-audio-fix.conf/{print; c++} f && /;;/{exit} END{exit !(c && found)}
	     f && /\[ -e \/etc\/modprobe\.d\/juno-audio-fix\.conf \]/{found=1}' "$postinst" >/dev/null
}

check_audio_fix_guard "$root/debian/juno-drivers-diamon.postinst" ||
	{ echo 'juno-audio-fix.conf guard missing' >&2; exit 1; }

cp "$root/debian/juno-drivers-diamon.postinst" "$tmp/postinst"
sed -i '/\[ -e \/etc\/modprobe\.d\/juno-audio-fix\.conf \]/,+1c\
\t\tcp /usr/share/junocomp/juno-audio-fix.conf /etc/modprobe.d/juno-audio-fix.conf' "$tmp/postinst"
if check_audio_fix_guard "$tmp/postinst"; then
	echo 'unconditional juno-audio-fix.conf clobber mutation passed' >&2
	exit 1
fi

echo 'juno-drivers-diamon postinst checks passed'

