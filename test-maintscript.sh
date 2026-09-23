#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

check_postinst()
{
	postinst=$1

	# Anchored, not a substring match: a mutation that comments the guard
	# out (keeping the words on disk) must not still "find" them.
	grep -Eq '^if \[ -e /run/udev/control \]; then$' "$postinst" || return 1
	grep -Eq '^	udevadm control --reload$' "$postinst" || return 1
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

# A substring grep would still "see" these words inside a comment; the
# anchored check above must not.
cp "$root/debian/clevo-keyboard-dkms.postinst" "$tmp/postinst"
sed -i \
	-e 's/^if \[ -e \/run\/udev\/control \]; then$/# if [ -e \/run\/udev\/control ]; then/' \
	-e 's/^\tudevadm control --reload$/\t# udevadm control --reload/' \
	"$tmp/postinst"
if check_postinst "$tmp/postinst"; then
	echo 'commented-out udev reload mutation passed' >&2
	exit 1
fi

echo 'clevo-keyboard postinst checks passed'

# /etc/modprobe.d/juno-audio-fix.conf is admin-editable config, not a dpkg
# conffile: the PE60RNE_RND_RNC branch must seed it once, never reinstall
# over a local edit on every postinst run (upgrade, reconfigure). A text
# check cannot tell "[ -e X ] || cp" from the inverted, backwards
# "[ -e X ] && cp" (both mention the same test), so run the real function
# and compare bytes: kept when the file exists, installed when it doesn't.
check_audio_fix_guard()
{
	postinst=$1
	src="$tmp/audio-fix.src"
	dest="$tmp/audio-fix.dest"

	fn=$(sed -n '/^seed_if_absent() {/,/^}/p' "$postinst")
	[ -n "$fn" ] || { echo 'seed_if_absent() not found in postinst' >&2; return 1; }

	printf 'template\n' > "$src"

	rm -f "$dest"
	(eval "$fn"; seed_if_absent "$src" "$dest")
	[ "$(cat "$dest")" = template ] ||
		{ echo 'absent case: file not seeded from the template' >&2; return 1; }

	printf 'user-edit\n' > "$dest"
	(eval "$fn"; seed_if_absent "$src" "$dest")
	[ "$(cat "$dest")" = user-edit ] ||
		{ echo 'present case: local edit was reinstalled over' >&2; return 1; }
}

check_audio_fix_guard "$root/debian/juno-drivers-diamon.postinst" ||
	{ echo 'juno-audio-fix.conf guard failed' >&2; exit 1; }

cp "$root/debian/juno-drivers-diamon.postinst" "$tmp/postinst"
sed -i 's/\[ -e "\$dest" \] || cp "\$src" "\$dest"/[ -e "$dest" ] \&\& cp "$src" "$dest"/' "$tmp/postinst"
grep -q '&& cp "\$src" "\$dest"' "$tmp/postinst" ||
	{ echo 'inverted-guard mutation did not take (test setup is stale)' >&2; exit 1; }
if check_audio_fix_guard "$tmp/postinst" 2>/dev/null; then
	echo 'inverted juno-audio-fix.conf guard mutation passed' >&2
	exit 1
fi

echo 'juno-drivers-diamon postinst checks passed'

# CI actions pinned to a commit, not a movable tag (supply-chain: a tag can be
# retargeted after review; a 40-char sha cannot).
for wf in "$root"/.github/workflows/*.yml; do
	unpinned=$(grep -Eo 'uses: [^ ]+@[^ #]+' "$wf" | grep -Ev '@[0-9a-f]{40}$' || true)
	[ -z "$unpinned" ] || { echo "unpinned action in $wf: $unpinned" >&2; exit 1; }
done
echo 'CI action pins checked'
