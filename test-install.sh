#!/bin/bash
# Installs the debs this fork just built in a clean debian:sid container, the
# way a Juno machine would. The check is not vacuous: juno-drivers has to come
# out configured, the files the Makefile installs have to be on disk, and the
# version has to match debian/changelog.
#
# Juno's own repository is configured only because juno-drivers Depends on
# juno-info, which Juno alone publishes. The key is pinned by SHA-256, the same
# discipline the apt repository applies: a replaced key fails here at build
# time, not on a user's machine.
#
# Needs podman or docker. With no argument it builds first; versioned debs can
# also be passed and the build is skipped.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
engine=$(command -v podman || command -v docker) || {
  echo "FAIL  no podman or docker; this check cannot run"; exit 1; }

juno_key_sha=06347ea57cf8ce6c96cf673f32a34cd6a520c0a0b5aef5db393702072f598901

if [ $# -eq 0 ]; then
  (cd "$root" && dpkg-buildpackage -b -uc -us >/dev/null)
  debs=(juno-drivers juno-drivers-local)
else
  debs=("$@")
fi
version=$(dpkg-parsechangelog -l "$root/debian/changelog" -SVersion)

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
for deb in "${debs[@]}"; do
  f=$root/../${deb}_${version}_amd64.deb
  [ -f "$f" ] || { echo "FAIL  no built .deb at $f"; exit 1; }
  cp "$f" "$build/"
done

"$engine" run --rm -i -v "$build:/build:ro" -e "VERSION=$version" \
    -e "JUNO_KEY_SHA=$juno_key_sha" -e "DEBS=${debs[*]}" \
    debian:sid bash -eo pipefail <<'SCRIPT'
# flatpak, the microcode packages and friends sit outside main.
sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' \
    /etc/apt/sources.list.d/debian.sources

apt-get update -qq
apt-get install -y --no-install-recommends curl ca-certificates >/dev/null

curl -fsSL https://deb.junocomputers.com/gpg.key -o /etc/apt/keyrings/juno.asc
echo "$JUNO_KEY_SHA  /etc/apt/keyrings/juno.asc" | sha256sum -c - >/dev/null
cat > /etc/apt/sources.list.d/juno.sources <<EOF
Types: deb
URIs: https://deb.junocomputers.com/
Suites: /
Signed-By: /etc/apt/keyrings/juno.asc
EOF

apt-get update -qq -o APT::Update::Error-Mode=any

# Local paths, not the repository's packages of the same name: the bytes under
# test are the ones built above.
apt-get install -y --no-install-recommends /build/*.deb

rc=0
for deb in $DEBS; do
  dpkg-query -W -f '${Status}\n' "$deb" | grep -F 'install ok installed' >/dev/null ||
    { echo "FAIL  $deb not configured"; rc=1; }
  got=$(dpkg-query -W -f '${Version}' "$deb")
  [ "$got" = "$VERSION" ] ||
    { echo "FAIL  $deb installed as $got, changelog says $VERSION"; rc=1; }
done
for f in /usr/bin/juno-cpu-policy /usr/bin/turbo-on /usr/bin/turbo-off \
         /usr/bin/turbo-stat /etc/default/grub.d/11-juno-drivers.cfg \
         /usr/share/junocomp/restart-audio /usr/share/junocomp/juno-grub-cmdline \
         /usr/share/glib-2.0/schemas/20_juno-ubuntu-settings.gschema.override; do
  [ -e "$f" ] || { echo "FAIL  $f absent"; rc=1; }
done
echo "ok    $DEBS at $VERSION, $(ls /build | wc -l) debs"
exit $rc
SCRIPT
