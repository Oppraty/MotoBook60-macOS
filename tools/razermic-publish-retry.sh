#!/bin/bash
# Root publisher for RazerSSTMicrophone. One attempt per boot, then stop.
#
# Three earlier versions, each wrong in a different way:
#
# 1. The original ran publish once ~70 s after boot with KeepAlive=false, so an
#    early failure was never retried.
# 2. A version gated on FirmwareReady. Wrong: that property is only set *after*
#    publication triggers the DSP download, so the script waited for something
#    it had to cause and logged "dsp not FirmwareReady yet, waiting" forever.
# 3. A retry loop that kept calling publish forever. Also wrong. Observed on
#    2026-11-27: the kext publishes, captures, then goes dormant and clears
#    PublishesAudioInput; further publish calls return 0xe00002d5 without
#    re-arming it. The loop read that as failure and hammered it - 18 attempts,
#    none of which changed anything.
#
# So: bounded waiting, then ONE publish call, then exit either way. If the
# device later goes dormant on its own, that is a kext behaviour, not something
# a daemon can fix by calling publish again.
export PATH=/usr/sbin:/usr/bin:/bin

# Where the built publisher lives. First existing executable wins. Step 2 is the
# one that matters when this runs as /usr/local/sbin/razermic-publish.sh, since
# SELF is then /usr/local/sbin and nothing beside it resolves.
SELF="$(cd "$(dirname "$0")" && pwd)"
PUB=""
for c in \
  "$SELF/publish" \
  "/usr/local/libexec/moto60/publish" \
  "/Library/Application Support/moto60/publish" \
  "/usr/local/share/moto60/publish" \
  "$SELF/../sources/dmic-port/RazerSSTMicrophone/build/publish"; do
  [ -x "$c" ] && { PUB="$c"; break; }
done
if [ -z "$PUB" ]; then
  echo "$(date) no publish binary found (searched \$SELF/publish, /usr/local/libexec/moto60/publish, /Library/Application Support/moto60/publish, /usr/local/share/moto60/publish)" >> /var/log/razermic-publish.log
  exit 1
fi

SVC=RazerSSTMicrophone
LOG=/var/log/razermic-publish.log

state() { ioreg -r -c "$SVC" -l -w0 2>/dev/null; }
is_published() { state | grep -q '"PublishesAudioInput" = Yes'; }

# Wait for the kext to be loaded. No other precondition: everything the kext
# needs to get to publication is produced by publication itself.
WAITED=0
while [ "$WAITED" -lt 120 ]; do
    state | grep -q '"Phase"' && break
    sleep 2
    WAITED=$((WAITED + 1))
done
if ! state | grep -q '"Phase"'; then
  echo "$(date) $SVC never appeared after $((WAITED*2))s; not publishing" >> "$LOG"
  exit 1
fi

# Already published - a previous run or the kext's own state. Nothing to do.
if is_published; then
  echo "$(date) already published; nothing to do" >> "$LOG"
  exit 0
fi

"$PUB" >/dev/null 2>&1
RC=$?
sleep 3

if is_published; then
  echo "$(date) published rc=$RC" >> "$LOG"
  exit 0
fi

PH=$(state | grep -oE '"Phase" = "[^"]*"' | head -1 | sed 's/.*= "//;s/"//')
FAIL=$(state | grep -oE '"Failure" = "[^"]*"' | head -1 | sed 's/.*= "//;s/"//')
echo "$(date) publish rc=$RC did not stick; phase=${PH:-unknown} failure=${FAIL:-none}. Reboot to retry." >> "$LOG"
exit 1