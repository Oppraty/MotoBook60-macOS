#!/bin/bash
# Root publisher for RazerSSTMicrophone.
#
# Replaces a one-shot version that failed intermittently. The old script ran
# publish exactly once ~70 s after boot; when the DSP had not finished its
# power-management idle handshake yet, publish returned 0 but
# PublishesAudioInput never flipped to Yes, and nothing retried until reboot.
# That produced the alternating 'published' / 'publish failed' log on 2026-11-26.
#
# Now: retry on a fixed cadence for a bounded window after boot, and keep
# trying at a slower cadence forever, because the failure is a timing race.
export PATH=/usr/sbin:/usr/bin:/bin

# Where the built publisher lives. Resolves relative to this script first, then
# falls back to paths that do not embed a username, so the script keeps working
# after the repo moves and does not publish a home directory in its source.
SELF="$(cd "$(dirname "$0")" && pwd)"
PUB=""
for c in \
  "$SELF/publish" \
  "/Library/Application Support/moto60/publish" \
  "/usr/local/libexec/moto60/publish" \
  "$SELF/../sources/dmic-port/RazerSSTMicrophone/build/publish"; do
  [ -x "$c" ] && { PUB="$c"; break; }
done
[ -n "$PUB" ] || { echo "$(date) no publish binary found" >> /var/log/razermic-publish.log; exit 1; }

SVC=RazerSSTMicrophone
LOG=/var/log/razermic-publish.log
ATTEMPT=0

state() { ioreg -r -c "$SVC" -l -w0 2>/dev/null; }
is_published() { state | grep -q '"PublishesAudioInput" = Yes'; }
is_ready()     { state | grep -q '"FirmwareReady" = Yes'; }

while true; do
    if is_published; then
        [ "$ATTEMPT" -gt 0 ] && echo "$(date) published after $ATTEMPT attempt(s)" >> "$LOG"
        exit 0
    fi

    # DSP not ready yet is the expected early-boot condition; not an error.
    if ! is_ready; then
        echo "$(date) dsp not FirmwareReady yet, waiting" >> "$LOG"
        sleep 10
        continue
    fi

    ATTEMPT=$((ATTEMPT + 1))
    "$PUB" >/dev/null 2>&1
    RC=$?
    sleep 3

    if is_published; then
        echo "$(date) published rc=$RC after $ATTEMPT attempt(s)" >> "$LOG"
        exit 0
    fi

    echo "$(date) attempt $ATTEMPT failed rc=$RC (dsp ready, publish did not stick)" >> "$LOG"

    # Fast retries for the first ~10 min after boot, then a slow steady-state
    # poll, so a late-arriving handshake is eventually caught without burning
    # cycles forever.
    if [ "$ATTEMPT" -lt 20 ]; then
        sleep 28
    else
        sleep 120
    fi
done