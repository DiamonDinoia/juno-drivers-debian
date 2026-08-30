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

version() { sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$1"; }
base()    { sed -E 's/(~debian|\+local[0-9]+|\+diamon[0-9]+)$//' <<<"$1"; }

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
CASES
    # The fifth case is the one that matters: a raw dpkg comparison calls
    # 0.5.48~debian older than 0.5.48+local1 for the right reason and newer
    # than nothing, while the sixth catches a string compare pretending to be
    # a version compare.
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
