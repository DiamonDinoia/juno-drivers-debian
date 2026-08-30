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
  debs=(juno-drivers-diamon)
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
# grub2-common because upstream's juno-grub.prerm calls update-grub with no
# guard, and the swap below removes juno-grub; every Juno machine has GRUB.
apt-get install -y --no-install-recommends curl ca-certificates grub2-common >/dev/null

curl -fsSL https://deb.junocomputers.com/gpg.key -o /etc/apt/keyrings/juno-repo.asc
echo "$JUNO_KEY_SHA  /etc/apt/keyrings/juno-repo.asc" | sha256sum -c - >/dev/null
cat > /etc/apt/sources.list.d/juno-repo.sources <<EOF
Types: deb
URIs: https://deb.junocomputers.com/
Suites: /
Signed-By: /etc/apt/keyrings/juno-repo.asc
EOF

apt-get update -qq -o APT::Update::Error-Mode=any

# The state every Juno machine is in: Juno's own juno-drivers installed. The
# swap must then work on real file ownership, not only on a clean install.
# Upstream's postinst may fail in a container (it predates the guards this
# fork carries); dpkg removal does not care whether configure finished, so the
# swap assertion below stands either way. Two traits of a real Juno machine a
# bare container lacks: apt/dpkg prompts read stdin, which here is this script
# — without a redirect a prompt consumes the rest of it and the run exits
# silent-green instead of failing — and update-grub, which juno-grub's prerm
# calls unconditionally and which cannot run under overlayfs: no shim, no
# removal, no swap. What is under test here is our Conflicts/Replaces, not
# upstream's prerm, so the container gets the stub a real machine does not need.
# dpkg runs maintainer scripts without /usr/local in PATH, so the stub shadows
# the real update-grub in place; the container is discarded afterwards anyway.
apt-get install -y --no-install-recommends grub2-common >/dev/null
printf '#!/bin/sh\nexit 0\n' > /usr/sbin/update-grub
apt-get install -y --no-install-recommends juno-drivers >/dev/null </dev/null ||
    echo "note  upstream juno-drivers packed but not configured here (expected in a container)"
# juno-archive-keyring (a Depends of juno-drivers) just dropped its own
# juno.sources whose Signed-By names /usr/share/keyrings/juno.gpg, so this
# test's source and key now duplicate it and apt refuses to read either.
# Retire the test's copies, exactly what a real machine does once the packaged
# keyring lands.
rm -f /etc/apt/sources.list.d/juno-repo.sources /etc/apt/keyrings/juno-repo.asc
apt-get update -qq
dpkg-query -W -f '${Status}\n' juno-drivers >/dev/null 2>&1 || {
  echo "FAIL  setup: juno's own juno-drivers did not even unpack"; exit 1; }

# Local paths, not the repository's packages of the same name: the bytes under
# test are the ones built above.
apt-get install -y --no-install-recommends /build/*.deb </dev/null </dev/null

rc=0
for old in juno-drivers juno-drivers-local juno-grub; do
  if dpkg-query -W -f '${Status}\n' "$old" 2>/dev/null | grep -F 'install ok installed' >/dev/null; then
    echo "FAIL  swap left $old installed"; rc=1
  fi
done
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
