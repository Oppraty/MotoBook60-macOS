#!/bin/bash
# Build a RazerSSTMicrophone variant with a different SOF firmware blob.
#
# Why this exists: tools/build.py hardcodes sof-adl.ri (Alder Lake) in both the
# copy step and the .incbin directive, and rejects command-line arguments. This
# wrapper reproduces the real build's compile flags exactly and only changes the
# firmware blob, leaving build.py untouched.
#
# Confirmed from this machine's own Fedora dmesg:
#   sof-audio-pci-intel-tgl 0000:00:1f.3: Firmware paths/files for ipc type 0:
#   sof-audio-pci-intel-tgl 0000:00:1f.3:  Firmware file: intel/sof/sof-rpl.ri
#   sof-audio-pci-intel-tgl 0000:00:1f.3:  Topology file: intel/sof-tplg/sof-hda-generic-2ch.tplg
#
# ipc type 0 = IPC3, the generation this kext and the reference Raptor Lake port
# both support. The kernel loads the RPL blob on this hardware; the shipped blob
# is Alder Lake.
#
# Also confirmed on this machine (alsa-info):
#   0 [sofhdadsp]: sof-hda-dsp
#   device 6: DMIC, device 7: DMIC16kHz, cfg-dmics:2
#   Components: HDA:8086281f ... HDA:14f11f87,17aa3830 cfg-dmics:2
#
# Usage:
#   tools/build-variant.sh /path/to/sof-rpl.ri
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FW="${1:-}"
[ -n "$FW" ] || { echo "usage: $0 /path/to/sof-rpl.ri" >&2; exit 2; }
[ -f "$FW" ] || { echo "firmware not found: $FW" >&2; exit 2; }

FWNAME="$(basename "$FW")"
case "$FWNAME" in
  *.ri) TAG="$(printf '%s' "$FWNAME" | sed 's/\.ri$//')" ;;
  *) echo "expected a .ri firmware blob, got: $FWNAME" >&2; exit 2 ;;
esac
OUT="build-$TAG"

echo "== firmware: $FWNAME ($(wc -c < "$FW") bytes, sha256 $(shasum -a 256 "$FW" | cut -c1-16))"

# Fedora ships sof-rpl-s.ri.xz for the IPC4 path. An IPC3 machine loads
# intel/sof/<name>.ri uncompressed, so refuse the wrong generation outright.
if head -c 6 "$FW" | grep -q $'\xfd7zXZ\x00'; then
  echo "ERROR: $FWNAME is xz-compressed — that is the IPC4 blob." >&2
  echo "       IPC3 uses intel/sof/<name>.ri, uncompressed." >&2
  exit 1
fi

SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
clang="$(/usr/bin/xcrun --find clang)"
cc="$(/usr/bin/xcrun --find clang)"

# Same flags as tools/build.py lines 33-38, verbatim.
target=(-target x86_64-apple-macos10.9)
kernel=(-O2 -mkernel -DKERNEL -DKERNEL_PRIVATE -fno-exceptions -fno-rtti
        -fno-stack-protector -nostdinc -isystem "$SDK/Headers")

mkdir -p "$OUT"
cp "$FW" "$OUT/$FWNAME"
/usr/bin/env python3 tools/generate-dai.py "$OUT/DAIConfig.bin"

# Same symbol names as the original Firmware.s; only .incbin differs.
cat > "$OUT/Firmware.s" <<EOF
.section __TEXT,__const
.p2align 4
.globl _razer_sof_fw
_razer_sof_fw:
.incbin "$FWNAME"
.globl _razer_sof_fw_end
_razer_sof_fw_end:
.p2align 4
.globl _razer_dmic_dai
_razer_dmic_dai:
.incbin "DAIConfig.bin"
EOF

echo "== compiling (build.py flags)"
"$clang" "${target[@]}" "${kernel[@]}" -std=c++14 -Wall -Wextra -DDRIVER_PRIVATE \
  -DAPPLE_KEXT_VTABLE_PADDING -fno-common -fno-builtin \
  -isystem "$SDK/Headers/libkern" \
  -c src/RazerSSTMicrophone.cpp -o "$OUT/RazerSSTMicrophone.o"
"$clang" "${target[@]}" "${kernel[@]}" -std=c++14 \
  -c src/ModuleInfo.cpp -o "$OUT/ModuleInfo.o"
"$clang" "${target[@]}" -c "$OUT/Firmware.s" -o "$OUT/Firmware.o"

BUNDLE="$OUT/RazerSSTMicrophone.kext"
mkdir -p "$BUNDLE/Contents/MacOS"
"$clang" "${target[@]}" -nostdlib -Wl,-kext -Wl,-undefined,dynamic_lookup \
  "$OUT/RazerSSTMicrophone.o" "$OUT/ModuleInfo.o" "$OUT/Firmware.o" \
  "$SDK/Library/x86_64/libkmod.a" -o "$BUNDLE/Contents/MacOS/RazerSSTMicrophone"

cp src/Info.plist "$BUNDLE/Contents/Info.plist"
RES="$BUNDLE/Contents/Resources/Licenses"
mkdir -p "$RES"
for p in LICENSE NOTICE licenses/*; do
  [ -f "$p" ] && cp "$p" "$RES/$(basename "$p")" || true
done

# Ad-hoc signing. Without this the kext is rejected on Sequoia.
/usr/bin/plutil -lint "$BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$BUNDLE"
/usr/bin/codesign --verify --strict --verbose=2 "$BUNDLE"

# Userspace tools, same flags build.py uses for them.
HOST_SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
for name in publish mic-input-check; do
  case "$name" in
    publish)         fw=(-framework IOKit -framework CoreFoundation) ;;
    mic-input-check) fw=(-framework CoreAudio -framework CoreFoundation) ;;
  esac
  "$cc" -isysroot "$HOST_SDK" -arch x86_64 -O2 -Wall -Wextra \
    "tools/$name.c" "${fw[@]}" -o "$OUT/$name" || echo "  (userspace $name not built)"
done

echo "== variant built: $BUNDLE"
shasum -a 256 "$BUNDLE/Contents/MacOS/RazerSSTMicrophone" | sed 's/^/   /'