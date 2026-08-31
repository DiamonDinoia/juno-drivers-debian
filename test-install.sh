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

# postinst must not touch the network: configure has to work offline.
if grep -q 'https://' "$root/debian/juno-drivers-diamon.postinst"; then
  echo "FAIL  postinst references a URL; configure must work offline"; exit 1
fi

# Every file the Makefile installs, read from the Makefile so the two lists
# cannot drift apart. An empty parse means the pattern rotted, not a clean bill.
payload=$(sed -n 's/.*install -Dpm [0-9]* [^ ]* \$(DESTDIR)//p' "$root/Makefile")
[ -n "$payload" ] || { echo "FAIL  parsed no payload paths from the Makefile"; exit 1; }

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
for deb in "${debs[@]}"; do
  f=$root/../${deb}_${version}_amd64.deb
  [ -f "$f" ] || { echo "FAIL  no built .deb at $f"; exit 1; }
  cp "$f" "$build/"
done

"$engine" run --rm -i -v "$build:/build:ro" -e "VERSION=$version" \
    -e "JUNO_KEY_SHA=$juno_key_sha" -e "DEBS=${debs[*]}" -e "PAYLOAD=$payload" \
    debian:sid bash -eo pipefail <<'SCRIPT'
# The microcode packages, rar and friends sit outside main.
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
for f in $PAYLOAD; do
  [ -e "$f" ] || { echo "FAIL  $f absent"; rc=1; }
done
# The GRUB drop-in must append to the admin's GRUB_CMDLINE_LINUX, never
# overwrite it, and must keep sourcing cleanly after `apt remove` deletes
# /usr/share/junocomp/juno-grub-cmdline while the conffile stays behind.
# grub-mkconfig sources /etc/default/grub and every grub.d drop-in under
# set -e; grub_env simulates exactly that. Both negatives are proven: the
# pre-fix line loses adminparam and, with the helper gone, kills the shell.
echo 'GRUB_CMDLINE_LINUX="adminparam=1"' > /etc/default/grub
grub_env() {
  bash -ec 'source /etc/default/grub
            for f in /etc/default/grub.d/*.cfg; do source "$f"; done
            printf "%s" "$GRUB_CMDLINE_LINUX"'
}
cmdline=$(grub_env) || { echo "FAIL  sourcing the grub.d drop-in failed"; rc=1; }
case " $cmdline " in
  *" adminparam=1 "*) ;;
  *) echo "FAIL  drop-in overwrote the admin cmdline: '$cmdline'"; rc=1 ;;
esac

# postrm has to clean the model-gated files postinst drops outside the
# package's file list, and purge has to delete the pulse line. This
# container's DMI matches none of the gated models, so fake the droppings.
mkdir -p /etc/modprobe.d /usr/lib/systemd/system-sleep \
         /usr/share/X11/xorg.conf.d /etc/pulse
droppings="/etc/modprobe.d/juno-audio-fix.conf
/usr/lib/systemd/system-sleep/restore-i2c-hid
/usr/share/X11/xorg.conf.d/60-nj70au-touchpad.conf"
echo "$droppings" | xargs touch
echo 'load-module module-alsa-sink device=hw:0,0' >> /etc/pulse/default.pa

apt-get remove -y juno-drivers-diamon >/dev/null </dev/null
cmdline=$(grub_env) || { echo "FAIL  grub.d sourcing broke after remove"; rc=1; }
case " $cmdline " in
  *" adminparam=1 "*) ;;
  *) echo "FAIL  admin cmdline lost after remove: '$cmdline'"; rc=1 ;;
esac
for f in $droppings; do
  [ ! -e "$f" ] || { echo "FAIL  $f survived remove"; rc=1; }
done

apt-get purge -y juno-drivers-diamon >/dev/null </dev/null
! grep -q 'load-module module-alsa-sink device=hw:0,0' /etc/pulse/default.pa ||
  { echo "FAIL  pulse line survived purge"; rc=1; }

echo "ok    $DEBS at $VERSION, $(ls /build | wc -l) debs"
exit $rc
SCRIPT
