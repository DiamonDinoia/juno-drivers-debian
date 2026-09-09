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
