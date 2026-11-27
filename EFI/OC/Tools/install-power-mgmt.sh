#!/bin/bash
# Power-management post-install for this machine.
#
# Deliberately NOT included:
#   * timer-coalesce LaunchDaemon. The original version wrote Linux oid
#     names that do not exist on Darwin 24. tools/timer-coalesce.sh now
#     reports and applies the real macOS oids, but only one at a time and
#     only when asked - it does not auto-apply anything at boot.
#   * Reduce transparency / Reduce motion. Those are a user preference and
#     were set off deliberately.
#
# Only applies changes that are verifiable and reversible.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
KEXTS="$DIR/../Kexts"
UID_NUM="$(id -u)"

echo "== NVMeFix"
if [ -x "$KEXTS/NVMeFix.kext/Contents/MacOS/NVMeFix" ]; then
  echo "  NVMeFix present in EFI (loads at boot from /EFI)"
else
  echo "  WARNING: NVMeFix.kext missing from $KEXTS" >&2
fi
echo "  DeviceProperties must carry pci-l1ss-enable + pci-max-latency for"
echo "  the NVMe controller and its root port - already in config.plist."

echo "== BTIdle"
if [ -x "$KEXTS/BTIdle.kext/Contents/MacOS/BTIdle" ]; then
  echo "  BTIdle present in EFI (loads at boot from /EFI)"
else
  echo "  WARNING: BTIdle.kext missing from $KEXTS" >&2
fi

if [ "$UID_NUM" -ne 0 ]; then
  echo
  echo "pmset changes need root. Re-run as:"
  echo "  sudo \"$0\""
  exit 0
fi

echo "== sleep policy"
pmset -a proximitywake 0
pmset -a hibernatemode 3
pmset -a sleep 0
pmset -a powernap 0
pmset -a standby 0
pmset -a autopoweroff 0
pmset -a displaysleep 3
pmset -b displaysleep 3
pmset -c displaysleep 10
pmset -a disksleep 10

echo "== background photo analysis (already disabled; idempotent)"
launchctl disable "gui/$UID_NUM/com.apple.photoanalysisd" 2>/dev/null || true
launchctl disable "gui/$UID_NUM/com.apple.mediaanalysisd" 2>/dev/null || true

echo "== done"
echo "No reboot required for the pmset changes. NVMeFix and BTIdle only"
echo "load at next boot, and only if they are in the live ESP's config.plist."
echo
echo "To inspect timer coalescing without changing anything:"
echo "  $DIR/timer-coalesce.sh status"