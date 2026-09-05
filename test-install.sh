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
# dkms payload version tracked by the swap test: pinned in the Makefile, never hardcode
ckver=$(sed -n 's/^CLEVO_VERSION := //p' "$root/Makefile")
engine=$(command -v podman || command -v docker) || {
  echo "FAIL  no podman or docker; this check cannot run"; exit 1; }

juno_key_sha=06347ea57cf8ce6c96cf673f32a34cd6a520c0a0b5aef5db393702072f598901

if [ $# -eq 0 ]; then
  (cd "$root" && dpkg-buildpackage -b -uc -us >/dev/null)
  debs=(juno-drivers-diamon clevo-keyboard-dkms)
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

# Juno's clevo-keyboard, the package clevo-keyboard-dkms deposes, has to be
# fetched now: the juno-drivers install below drags in juno-archive-keyring,
# whose own juno.sources carries a different Signed-By, and apt then refuses
# to read either source until the rm below retires this test's copy. When
# juno's repo ever stops publishing the deb, the test simulates juno's side
# and asserts the deposition from package metadata instead.
swap_mode=real
junokbd=$(mktemp -d)
(cd "$junokbd" && apt-get download clevo-keyboard >/dev/null 2>&1) || {
  swap_mode=simulated
  echo "note  juno's repo no longer publishes clevo-keyboard; simulating its side of the swap"
}

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

# The other half of a stock Juno machine: juno's own clevo-keyboard, the
# package the new clevo-keyboard-dkms deposes. Its postinst fails without
# kernel headers (same KDIR pattern as juno-drivers); dpkg removal does not
# care, and that removal is what the swap asserts below exercise.
if [ "$swap_mode" = real ]; then
  apt-get install -y --no-install-recommends "$junokbd"/clevo-keyboard_*.deb >/dev/null </dev/null ||
    echo "note  upstream clevo-keyboard unpacked but not configured here (expected in a container)"
  rm -rf "$junokbd"
  # A real machine ends up with clevo-keyboard/4.6.2 registered: juno's
  # postinst gets that far before KDIR stops it. If the container stopped
  # earlier, finish only the registration — juno's prerm removes only what
  # dkms shows it, and the swap must exercise that real removal.
  if ! dkms status -m clevo-keyboard -v 4.6.2 2>/dev/null | grep -q .; then
    [ -d /usr/src/clevo-keyboard-4.6.2 ] ||
      cp -a /usr/share/clevo-keyboard/4.6.2 /usr/src/clevo-keyboard-4.6.2
    dkms add -m clevo-keyboard -v 4.6.2 >/dev/null
  fi
  # The stock world must exist or the swap asserts below prove nothing.
  dpkg-query -W -f '${db:Status-Abbrev}\n' clevo-keyboard 2>/dev/null | grep -q '^i' ||
    { echo "FAIL  setup: juno's clevo-keyboard was never unpacked"; exit 1; }
  [ -L /var/lib/dkms/clevo-keyboard/4.6.2/source ] ||
    { echo "FAIL  setup: no 4.6.2 dkms registration; the swap test would be vacuous"; exit 1; }
  echo "setup juno world: clevo-keyboard ($(dpkg-query -W -f '${db:Status-Abbrev}' clevo-keyboard | tr -d ' ')), unowned /usr/src/clevo-keyboard-4.6.2, dkms registration 4.6.2"
else
  # Simulate the wreckage a stock machine carries, then emulate juno's prerm;
  # dpkg's real removal mechanics are covered by the metadata asserts.
  mkdir -p /usr/src/clevo-keyboard-4.6.2 /var/lib/dkms/clevo-keyboard/4.6.2
  echo junk > /usr/src/clevo-keyboard-4.6.2/clevo_keyboard.c
  ln -s /usr/src/clevo-keyboard-4.6.2 /var/lib/dkms/clevo-keyboard/4.6.2/source
  rm -rf /usr/src/clevo-keyboard-4.6.2 /var/lib/dkms/clevo-keyboard
fi

# Local paths, not the repository's packages of the same name: the bytes under
# test are the ones built above.
apt-get install -y --no-install-recommends /build/*.deb </dev/null

rc=0
for old in juno-drivers juno-drivers-local juno-grub; do
  if dpkg-query -W -f '${Status}\n' "$old" 2>/dev/null | grep -F 'install ok installed' >/dev/null; then
    echo "FAIL  swap left $old installed"; rc=1
  fi
done

# --- clevo-keyboard swap: juno's package deposed by clevo-keyboard-dkms ---
echo "swap-mode=$swap_mode"
# The relationships that make dpkg depose juno's package, checked on the
# bytes under test (this is the whole check in simulated mode).
for rel in Conflicts Replaces Provides; do
  dpkg-deb -f /build/clevo-keyboard-dkms_*.deb "$rel" 2>/dev/null | tr -d ' ' | tr ',' '\n' |
    grep -Fxq clevo-keyboard ||
    { echo "FAIL  $rel of clevo-keyboard-dkms misses clevo-keyboard"; rc=1; }
done
# (i) juno's clevo-keyboard must not be installed (any i* state) post-swap.
st=$(dpkg-query -W -f '${db:Status-Abbrev}' clevo-keyboard 2>/dev/null || true)
case "$st" in
  i*) echo "FAIL  swap left clevo-keyboard in dpkg state '$st'"; rc=1 ;;
  *)  echo "ok    clevo-keyboard not installed post-swap (state '${st:-not present}')" ;;
esac
# (ii) /usr/src/clevo-keyboard-* resolves solely to clevo-keyboard-dkms.
owners=$(dpkg-query -S '/usr/src/clevo-keyboard-*' 2>/dev/null | cut -d: -f1 | sort -u || true)
if [ -z "$owners" ]; then
  echo "FAIL  nothing owns /usr/src/clevo-keyboard-*"; rc=1
elif [ "$owners" != clevo-keyboard-dkms ]; then
  echo "FAIL  dpkg-query -S /usr/src/clevo-keyboard-* resolves to: $owners"; rc=1
else
  echo "ok    dpkg-query -S /usr/src/clevo-keyboard-* resolves solely to clevo-keyboard-dkms"
fi
d=$(ls -d /usr/src/clevo-keyboard-*/dkms.conf 2>/dev/null || true)
[ -n "$d" ] || { echo "FAIL  no /usr/src/clevo-keyboard-*/dkms.conf payload"; rc=1; }
[ -z "$d" ] || [ "clevo-keyboard-$(sed -n 's/^PACKAGE_VERSION=//p' "$d")" = "$(basename "$(dirname "$d")")" ] ||
  { echo "FAIL  dkms.conf version and the /usr/src dir name disagree"; rc=1; }
# (iii) no dkms tree for juno's 4.6.2 and no phantom links under /var/lib/dkms.
if [ -e /var/lib/dkms/clevo-keyboard/4.6.2 ]; then
  echo "FAIL  juno's clevo-keyboard/4.6.2 dkms tree survived the swap"; rc=1
else
  echo "ok    no clevo-keyboard/4.6.2 left in /var/lib/dkms"
fi
phantoms=$(find /var/lib/dkms -xtype l -print 2>/dev/null || true)
[ -z "$phantoms" ] || { echo "FAIL  phantom symlinks in /var/lib/dkms: $phantoms"; rc=1; }
status=$(dkms status clevo-keyboard 2>/dev/null || true)
echo "ok    dkms status: ${status:-<empty>}"
printf '%s\n' "$status" | grep -Fq "clevo-keyboard/$ckver" ||
  { echo "FAIL  dkms does not track clevo-keyboard/$ckver"; rc=1; }
other=$(printf '%s\n' "$status" | grep -Fvc "clevo-keyboard/$ckver" || true)
[ "$other" = 0 ] ||
  { echo "FAIL  dkms tracks clevo-keyboard in states other than ours"; rc=1; }
# (iv) reconfigure must be idempotent: dkms state byte-identical afterwards.
dkms_snap() {
  find /var/lib/dkms -printf '%y %m %p -> %l\n' 2>/dev/null | LC_ALL=C sort
  find /var/lib/dkms -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort
}
s0=$(dkms_snap | sha256sum)
dpkg-reconfigure clevo-keyboard-dkms >/dev/null
s1=$(dkms_snap | sha256sum)
dpkg-reconfigure clevo-keyboard-dkms >/dev/null
s2=$(dkms_snap | sha256sum)
if [ "$s0" = "$s1" ] && [ "$s1" = "$s2" ]; then
  echo "ok    dpkg-reconfigure twice leaves the dkms state byte-identical"
else
  echo "FAIL  dpkg-reconfigure mutated the dkms state"; rc=1
fi
# (v) the historical modprobe conffile, taken over from juno, still reads the same.
if grep -qx 'options clevo-keyboard kbd_backlight_mode=0' /etc/modprobe.d/clevo_keyboard.conf 2>/dev/null; then
  echo "ok    /etc/modprobe.d/clevo_keyboard.conf carries the historical option"
else
  echo "FAIL  /etc/modprobe.d/clevo_keyboard.conf missing or changed"; rc=1
fi
confowner=$(dpkg-query -S /etc/modprobe.d/clevo_keyboard.conf 2>/dev/null | cut -d: -f1 | sort -u || true)
[ "$confowner" = clevo-keyboard-dkms ] ||
  { echo "FAIL  clevo_keyboard.conf owned by: $confowner"; rc=1; }

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
# set -e; grub_env simulates exactly that. The negative control at the end
# proves the check fires on the pre-fix line in both directions.
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

# Negative control: the grub check above must fire on the pre-fix line, or it
# proves nothing. With the helper gone (purged above) the old assignment form
# has to kill a set -e sourcing shell; with a helper present it has to
# overwrite the admin value.
mkdir -p /etc/default/grub.d
echo 'GRUB_CMDLINE_LINUX="$(/usr/share/junocomp/juno-grub-cmdline)"' \
  > /etc/default/grub.d/11-juno-drivers.cfg
if grub_env >/dev/null 2>&1; then
  echo "FAIL  negative control: pre-fix line sourced cleanly without the helper"; rc=1
fi
mkdir -p /usr/share/junocomp
printf '#!/bin/sh\necho stubparam\n' > /usr/share/junocomp/juno-grub-cmdline
chmod +x /usr/share/junocomp/juno-grub-cmdline
cmdline=$(grub_env) || { echo "FAIL  negative control: stubbed sourcing broke"; rc=1; }
case " $cmdline " in
  *" adminparam=1 "*)
    echo "FAIL  negative control: pre-fix line kept the admin value"; rc=1 ;;
esac

# Purging the new package must leave no /usr/src payload, no dkms
# registration and no conffile: the full round trip of the bug it fixes.
apt-get purge -y clevo-keyboard-dkms >/dev/null </dev/null
[ ! -e "/usr/src/clevo-keyboard-$ckver" ] ||
  { echo "FAIL  /usr/src payload survived purge"; rc=1; }
[ -z "$(dkms status clevo-keyboard 2>/dev/null || true)" ] ||
  { echo "FAIL  dkms still tracks clevo-keyboard after purge"; rc=1; }
[ ! -e /etc/modprobe.d/clevo_keyboard.conf ] ||
  { echo "FAIL  clevo_keyboard.conf survived purge"; rc=1; }

echo "ok    $DEBS at $VERSION, $(ls /build | wc -l) debs"
exit $rc
SCRIPT
