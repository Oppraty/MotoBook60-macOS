#!/bin/bash
# Install the four custom kernel extensions from this repository into
# /Library/Extensions and rebuild the Auxiliary Kernel Collection on the
# machine you run it on.
#
# Why this exists: these kexts are matched to this build and are meant to be
# installed on the boot volume, not dropped into /EFI. Shipping a prebuilt
# AuxKC built on someone else's machine would carry that machine's kexts. This
# script builds the collection on your machine instead.
#
# Requirements:
#   - macOS already booting from an OpenCore EFI (see docs/replication.md)
#   - the repository's EFI/ folder next to this script
#   - run as root: sudo ./install-custom-kexts.sh
#
# It keeps a timestamped backup of the current AuxKC and arms an auto-restore
# watchdog. If the machine fails to boot after this change, the watchdog puts
# the old kernelcollection back within a few minutes. Say "booted" is done for
# you by the script only after you confirm - see VERIFY below.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
HERE="$(cd "$(dirname "$0")" && pwd)"
KEXTSRC="$HERE/EFI/OC/Kexts"

# Kexts this script installs, with the SHA-256 of the executable that must be
# present. A mismatch means the bundle in the repo was modified or corrupted.
# BundlePath:ExecutablePath:ExpectedSHA256
KEXTS=(
  "IntelSpeedShiftEPP.kext:Contents/MacOS/IntelSpeedShiftEPP:8b769bec675dbd32e815e6eb0dc13e5dffa65923f53b8a061e570ac65a6c06d6"
  "FanMode.kext:Contents/MacOS/FanMode:d261e4a4d386dcc3983dcc026a832a7f36396f2fc250248447df0c30d7678fdf"
  "RazerSSTMicrophone.kext:Contents/MacOS/RazerSSTMicrophone:480418c7671c9371929f1ac168f00137744f476c98dcce043bbff9e9428ef452"
  "RaplDiag.kext:Contents/MacOS/RaplDiag:4bb134f5477d3bde53649ff9b802a5f49c704b24c0c486d418be9199e407b4bc"
)

# Bundle identifiers that must be in the rebuilt collection for it to count as
# a success. These are the four above plus Apple graphics and audio kexts that
# a broken rebuild tends to drop.
REQUIRED_IDS=(
  "local.IntelSpeedShiftEPP"
  "local.markplacer.FanMode"
  "local.markplacer.RaplDiag"
  "local.markplacer.RazerSSTMicrophone"
  "com.apple.iokit.IOAudioFamily"
  "com.apple.iokit.IOGraphicsFamily"
)

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/tmp/custom-kexts-backup
MARK=/var/db/custom-kexts-pending
DAEMON=/Library/LaunchDaemons/local.customkexts.restore.plist
RESTORE=/usr/local/sbin/custom-kexts-restore.sh
LOG=/var/tmp/custom-kexts-$STAMP.log

log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Check privilege before redirecting output, so an unprivileged run does not
# fail partway through with a permissions error on the log file.
[ "$(id -u)" = 0 ] || { echo "FAIL: run as root: sudo $0" >&2; exit 1; }

exec > >(tee -a "$LOG") 2>&1
log "=== install-custom-kexts $STAMP ==="
log "log: $LOG"

[ -d "$KEXTSRC" ] || die "cannot find $KEXTSRC - run this from inside the repository"
[ -f "$KC" ] || die "no AuxKC at $KC - is macOS booting from an OpenCore ESP?"

if [ -e "$MARK" ]; then
  die "a previous run is still pending ($MARK). Boot normally, then run
     'sudo rm -f $MARK' before trying again."
fi

mkdir -p "$BACKUP_DIR"

# --- verify every bundle before touching the system -------------------------
for entry in "${KEXTS[@]}"; do
  IFS=: read -r bundle exec_rel expected <<<"$entry"
  src="$KEXTSRC/$bundle"
  exec_path="$src/$exec_rel"
  [ -d "$src" ] || die "missing $bundle in the repository"
  [ -f "$exec_path" ] || die "missing $exec_path"
  actual=$(shasum -a 256 "$exec_path" | awk '{print $1}')
  [ "$actual" = "$expected" ] || die "$bundle has the wrong hash.
     expected $expected
     actual   $actual"
  id=$(plutil -extract CFBundleIdentifier raw "$src/Contents/Info.plist")
  [ -n "$id" ] || die "$bundle has no CFBundleIdentifier"
  log "verified $bundle ($id)"
done

# --- back up the current AuxKC ---------------------------------------------
BACKUP="$BACKUP_DIR/AuxKC.before-custom-kexts.$STAMP"
cp -p "$KC" "$BACKUP" || die "could not back up the current AuxKC"
log "backed up current AuxKC to $BACKUP"

# --- arm the auto-restore watchdog -----------------------------------------
# It waits five minutes after each boot for you to confirm the boot was fine.
# If you confirm, it cleans up and does nothing. If you do not, it puts the
# original AuxKC back so a bad build is less likely to leave you stranded.
#
# This is a safety net, not a guarantee. It only works if the machine still
# boots far enough for the daemon to run. A machine that will not boot at all
# needs the recovery path in docs/replication.md instead.
mkdir -p /usr/local/sbin
cat > "$RESTORE" <<EOF
#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
MARK="$MARK"; BACKUP="$BACKUP"; KC="$KC"
[ -f "\$MARK" ] || exit 0
/bin/sleep 300
# While we were waiting, the install was either confirmed and cleaned up, or
# cleared by hand. Either way there is nothing to undo, so leave the system as
# the user left it rather than reverting a build they accepted.
if [ ! -f "\$MARK" ]; then
  /bin/rm -f "\$MARK.ok"
  exit 0
fi
if [ -f "\$MARK.ok" ]; then
  /bin/rm -f "\$MARK" "\$MARK.ok"
  exit 0
fi
# No confirmation arrived. Restore, but only if the backup is really there and
# the current collection is not already the backup.
if [ ! -f "\$BACKUP" ]; then
  /bin/echo "auto-restore skipped: no backup at \$BACKUP" >> /var/tmp/custom-kexts-restore.log
  /bin/rm -f "\$MARK" "\$MARK.ok"
  exit 0
fi
if /usr/bin/cmp -s "\$BACKUP" "\$KC"; then
  /bin/rm -f "\$MARK" "\$MARK.ok"
  exit 0
fi
if /bin/cp "\$BACKUP" "\$KC.restore.tmp" && /bin/mv -f "\$KC.restore.tmp" "\$KC"; then
  /bin/rm -f "\$MARK" "\$MARK.ok"
  /bin/echo "auto-restored earlier AuxKC" >> /var/tmp/custom-kexts-restore.log
else
  /bin/rm -f "\$KC.restore.tmp"
  /bin/echo "auto-restore FAILED - restore by hand: cp \$BACKUP \$KC" >> /var/tmp/custom-kexts-restore.log
fi
EOF
chmod 755 "$RESTORE"

cat > "$DAEMON" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD//EN" "http://www.apple.org/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.customkexts.restore</string>
<key>ProgramArguments</key><array><string>$RESTORE</string></array>
<key>RunAtLoad</key><true/>
<key>StandardErrorPath</key><string>/var/tmp/custom-kexts-restore.err</string>
</dict></plist>
EOF
chmod 644 "$DAEMON"
launchctl enable system/local.customkexts.restore 2>/dev/null || true
launchctl bootout system/local.customkexts.restore 2>/dev/null || true
launchctl bootstrap system "$DAEMON" 2>/dev/null || launchctl load -w "$DAEMON" 2>/dev/null || true
log "auto-restore watchdog armed"

# --- install the kexts ------------------------------------------------------
for entry in "${KEXTS[@]}"; do
  IFS=: read -r bundle _ <<<"$entry"
  dst="/Library/Extensions/$bundle"
  if [ -e "$dst" ]; then
    mv "$dst" "$BACKUP_DIR/$bundle.before-custom-kexts.$STAMP"
    log "saved existing $bundle"
  fi
  cp -R "$KEXTSRC/$bundle" "$dst" || die "could not copy $bundle"
  chown -R root:wheel "$dst"
  chmod -R 755 "$dst"
  log "installed $bundle"
done

# The microphone kext needs a one-shot userspace publisher to expose the input
# device. Copy it and its check tool alongside, and note that it is unsigned.
mkdir -p /usr/local/sbin /usr/local/bin
if [ -f "$HERE/tools/publish" ]; then
  install -m 0755 "$HERE/tools/publish" /usr/local/sbin/razermic-publish
  log "installed razermic-publish"
else
  log "WARNING: tools/publish missing - the microphone will not publish"
fi
if [ -f "$HERE/tools/mic-input-check" ]; then
  install -m 0755 "$HERE/tools/mic-input-check" /usr/local/bin/mic-input-check
  log "installed mic-input-check"
fi

# --- rebuild the Auxiliary Kernel Collection -------------------------------
NEWKC=/var/tmp/AuxKC.custom-kexts.$STAMP
log "rebuilding AuxKC (this can take a minute)"
# kmutil's own messages go to the console, which tee already captures into $LOG.
if ! kmutil create -n aux --volume-root / --allow-missing-kdk \
  --kernel /System/Library/Kernels/kernel \
  -B /System/Library/KernelCollections/BootKernelExtensions.kc \
  -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
  --repository /Library/Extensions \
  --repository /System/Library/Extensions \
  --repository /Library/Apple/System/Library/Extensions \
  -A "$NEWKC"; then
  die "kmutil create failed - see the log above. The system AuxKC was not changed."
fi

# Verify by exact bundle identifier, not substring: kmutil inspect prints one
# identifier per line, so a whole-line match cannot be satisfied by a longer
# name that merely contains this one.
INSPECT=$(kmutil inspect -a x86_64 -A "$NEWKC" 2>/dev/null) || die "could not inspect the rebuilt collection"
for id in "${REQUIRED_IDS[@]}"; do
  printf '%s\n' "$INSPECT" | grep -qxF "$id" \
    || die "rebuilt collection is missing $id - refusing to install it."
done
log "rebuilt collection contains all expected kexts"

cp "$NEWKC" "$KC.custom-kexts.tmp" && mv -f "$KC.custom-kexts.tmp" "$KC" \
  || die "could not install the new AuxKC"

rm -f "$NEWKC"
echo "$STAMP" > "$MARK"
log "installed new AuxKC"

log "=== installed. Reboot now. ==="
log ""
log "VERIFY - the watchdog needs to hear from you:"
log "  1. Reboot."
log "  2. If the machine boots, run:  sudo touch $MARK.ok"
log "     That tells the watchdog the boot was fine. Do it within five"
log "     minutes, or it assumes the boot was bad and restores the old"
log "     kernelcollection for you."
log "  3. Then clear the prompt:      sudo rm -f $MARK $MARK.ok"
log ""
log "If you do nothing, the watchdog restores the previous AuxKC about five"
log "minutes after the next boot, so a bad build cannot leave you stranded."
log ""
log "Check what loaded:  kmutil showloaded | grep -E 'FanMode|EPP|RazerSST|RaplDiag'"
log "Check the fan:      sysctl debug.fanmode.mode   (FanMode)"
log "Check the mic:      mic-input-check             (expect non-silent input)"
log ""
log "NOTE: the microphone kext is known to fail on the MacPro7,1 SMBIOS used"
log "by this EFI. Installation succeeding does not mean capture works."
log ""
log "Roll back by hand if needed:"
log "  sudo cp '$BACKUP' '$KC' && sudo reboot"