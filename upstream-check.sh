#!/bin/bash
# Is upstream ahead of this fork? Juno tags nothing, so the signal is the
# version at the top of debian/changelog, not a tag or a release.
#
# The two sides spell the same upstream release differently: upstream ships
# 0.5.48~debian and this fork rebuilds it as 0.5.48+diamon1 (as +local1 before
# the rename, which base() still strips since old installs carry it). Comparing
# those directly says the fork is ahead, which is true and useless. Both are
# reduced to the upstream release they carry before they are compared.
set -euo pipefail

UPSTREAM=https://gitlab.com/junocomp/juno-drivers-debian/-/raw/main/debian/changelog
GRUB_UPSTREAM=https://gitlab.com/junocomp/juno-grub/-/raw/main/debian/changelog

version() { sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$1"; }
# Blind spot: the fork's 0.5.48.1/.2 reduce to more than upstream's 0.5.48,
# so an upstream 0.5.48.x point release would go unreported. Upstream has
# never shipped a fourth version component.
base()    { sed -E 's/(~debian|\+local[0-9]+|\+diamon[0-9]+)$//' <<<"$1"; }

# tuxedo-drivers tags pre-releases inline ("_rc") instead of using GitHub's
# pre-release flag, and a plain dpkg compare would call "4.23.0_rc" newer
# than a real "4.22.3". Reads `git ls-remote` lines on stdin, so the same
# filter runs offline in the selftest and live against the real remote.
tux_filter() { sed -n 's#.*refs/tags/v##p' | grep -E '^[0-9]+(\.[0-9]+)*$'; }

selftest() {
    local fail=0
    # upstream, fork, expected verdict
    while read -r up mine want; do
        got=no
        dpkg --compare-versions "$(base "$up")" gt "$(base "$mine")" && got=yes
        if [ "$got" = "$want" ]; then
            printf 'ok    %-16s vs %-16s -> %s\n' "$up" "$mine" "$got"
        else
            printf 'FAIL  %-16s vs %-16s -> %s, expected %s\n' "$up" "$mine" "$got" "$want"
            fail=1
        fi
    done <<'CASES'
0.5.48~debian    0.5.48+local1    no
0.5.48~debian    0.5.48~debian    no
0.5.49~debian    0.5.48+local1    yes
0.6.0~debian     0.5.48+local1    yes
0.5.48~debian    0.5.49+local1    no
0.5.48~debian    0.5.9+local1     yes
0.5.48~debian    0.5.48.1+diamon1 no
0.5.49~debian    0.5.48.1+diamon1 yes
0.1.24           0.1.24           no
0.1.25           0.1.24           yes
4.6.2-1          4.6.2-1          no
4.6.2            4.6.2-1          no
4.6.3-1          4.6.2-1          yes
CASES
    # The fifth case is the one that matters: a raw dpkg comparison calls
    # 0.5.48~debian older than 0.5.48+local1 for the right reason and newer
    # than nothing, while the sixth catches a string compare pretending to be
    # a version compare. The seventh and eighth prove base() strips +diamonN
    # the same way it strips +localN. Then the juno-grub watch pair, plain
    # versions with no suffix to strip, and the clevo-keyboard watch rows,
    # including 4.6.2 sorting below 4.6.2-1 the dpkg way.

    # tux tag filter: an _rc pre-release and a bare vX.Y.Z tag are what the
    # real remote actually returns; the _rc must not win the max.
    got=$(printf 'a\trefs/tags/v4.22.3\nb\trefs/tags/v4.23.0_rc\nc\trefs/tags/v4.6.2\n' |
        tux_filter | sort -V | tail -1)
    if [ "$got" = 4.22.3 ]; then
        printf 'ok    tux tag filter drops _rc, picks    -> %s\n' "$got"
    else
        printf 'FAIL  tux tag filter -> %s, expected 4.22.3\n' "$got"
        fail=1
    fi

    # tux/fan version rows: the two the workflow actually branches on.
    while read -r up mine want; do
        got=no
        dpkg --compare-versions "$up" gt "$mine" && got=yes
        if [ "$got" = "$want" ]; then
            printf 'ok    tux %-16s vs %-16s -> %s\n' "$up" "$mine" "$got"
        else
            printf 'FAIL  tux %-16s vs %-16s -> %s, expected %s\n' "$up" "$mine" "$got" "$want"
            fail=1
        fi
    done <<'CASES'
4.23.0           4.6.2            yes
4.6.2            4.6.2            no
CASES

    # fan sha compare: no version syntax to launder, so any mismatch counts.
    while read -r up mine want; do
        got=no
        [ "$up" != "$mine" ] && got=yes
        if [ "$got" = "$want" ]; then
            printf 'ok    fan %-16s vs %-16s -> %s\n' "$up" "$mine" "$got"
        else
            printf 'FAIL  fan %-16s vs %-16s -> %s, expected %s\n' "$up" "$mine" "$got" "$want"
            fail=1
        fi
    done <<'CASES'
f0691d7          f0691d7          no
4e2c1a9          f0691d7          yes
CASES
    return $fail
}

[ "${1-}" != "--selftest" ] || { selftest; exit; }

mine=$(version debian/changelog)
up=$(curl -fsSL "$UPSTREAM" | version /dev/stdin)
[ -n "$up" ] || { echo "could not read upstream changelog" >&2; exit 1; }

printf 'upstream=%s\nmine=%s\n' "$up" "$mine"
if dpkg --compare-versions "$(base "$up")" gt "$(base "$mine")"; then
    echo "newer=yes"
else
    echo "newer=no"
fi

# juno-grub-cmdline is vendored from the separate juno-grub repo; the header
# of the vendored copy names the version it was synced from.
grub_mine=$(sed -n 's/^# Vendored from upstream juno-grub \([0-9.]*\).*/\1/p' juno-grub-cmdline)
grub_up=$(curl -fsSL "$GRUB_UPSTREAM" | version /dev/stdin)
[ -n "$grub_up" ] && [ -n "$grub_mine" ] ||
    { echo "could not read a juno-grub version" >&2; exit 1; }

printf 'grub_upstream=%s\ngrub_mine=%s\n' "$grub_up" "$grub_mine"
if dpkg --compare-versions "$grub_up" gt "$grub_mine"; then
    echo "grub_newer=yes"
else
    echo "grub_newer=no"
fi

# clevo-keyboard-dkms deposes juno's clevo-keyboard; its driver base is
# juno's 4.6.2 line, so anything newer than the 4.6.2-1 juno publishes means
# the replacement went stale. Their repo is flat; the index lists one stanza
# per published deb, so the watch compares the newest of them.
KBD_PACKAGES=https://deb.junocomputers.com/Packages

kbd_mine=4.6.2-1
kbd_list=$(curl -fsSL "$KBD_PACKAGES" |
    awk '/^Package: clevo-keyboard$/{f=1; next} /^Package: /{f=0} f && /^Version: /{print $2}')
[ -n "$kbd_list" ] || { echo "could not read juno's clevo-keyboard version" >&2; exit 1; }
kbd_up=
for v in $kbd_list; do
    { [ -z "$kbd_up" ] || dpkg --compare-versions "$v" gt "$kbd_up"; } && kbd_up=$v
done

printf 'kbd_upstream=%s\nkbd_mine=%s\n' "$kbd_up" "$kbd_mine"
if dpkg --compare-versions "$kbd_up" gt "$kbd_mine"; then
    echo "kbd_newer=yes"
else
    echo "kbd_newer=no"
fi

# tuxedo-drivers is the real upstream of the vendored clevo-keyboard payload
# (the Makefile's CLEVO_VERSION pin), distinct from juno's own clevo-keyboard
# fork above. Upstream publishes tags but no GitHub Releases, and no auth is
# needed to list them.
TUX_URL=https://github.com/tuxedocomputers/tuxedo-drivers.git

tux_mine=$(base "$(sed -n 's/^CLEVO_VERSION := //p' Makefile)")
tux_tags=$(git ls-remote --tags --refs "$TUX_URL" | tux_filter)
[ -n "$tux_tags" ] || { echo "could not read tuxedo-drivers tags" >&2; exit 1; }
tux_up=
for v in $tux_tags; do
    { [ -z "$tux_up" ] || dpkg --compare-versions "$v" gt "$tux_up"; } && tux_up=$v
done

printf 'tux_upstream=%s\ntux_mine=%s\n' "$tux_up" "$tux_mine"
if dpkg --compare-versions "$tux_up" gt "$tux_mine"; then
    echo "tux_newer=yes"
else
    echo "tux_newer=no"
fi

# clevofan is vendored as a separate git checkout, not this repo, so there is
# no version file here to read. Upstream last cut a GitHub release in 2022 and
# otherwise just pushes commits to main, so the live HEAD sha is the signal:
# any new tag needs a commit to sit on, so a sha diff catches both. The pin is
# the merge-base of the vendored fork's main with upstream/main, recorded by
# `git merge-base main upstream/main` in that checkout on 2026-09-09.
FAN_URL=https://github.com/simopil/clevofan.git
fan_mine_sha=f0691d77c3b86867299399c452e4582fa95bca4e

fan_up_sha=$(git ls-remote "$FAN_URL" HEAD | cut -f1)
[ -n "$fan_up_sha" ] || { echo "could not read clevofan upstream HEAD" >&2; exit 1; }

printf 'fan_upstream_sha=%s\nfan_mine_sha=%s\n' "$fan_up_sha" "$fan_mine_sha"
if [ "$fan_up_sha" != "$fan_mine_sha" ]; then
    echo "fan_newer=yes"
else
    echo "fan_newer=no"
fi
