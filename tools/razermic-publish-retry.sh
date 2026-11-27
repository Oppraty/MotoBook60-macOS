#!/bin/bash
# Root publisher for RazerSSTMicrophone.
#
# Two earlier versions of this failed for different reasons, both worth
# recording:
#
# 1. The original ran publish exactly once ~70 s after boot with
#    KeepAlive=false, so an early failure was never retried.
# 2. An intermediate version gated on FirmwareReady before attempting. That
#    was wrong: FirmwareReady is only set *after* publication is requested and
#    the DSP firmware downloads, so it is a downstream effect of publishing,
#    not a precondition. The script waited for something it had to cause, and
#    logged "dsp not FirmwareReady yet, waiting" forever.
#
# Now: wait only for the kext to be loaded, then attempt publication and retry.
# No gating on a condition that publication itself is what produces.
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

# Wait for the kext itself, before publishing.
for _ in $(seq 1 60); do
    state | grep -q '"Phase"' && break
    sleep 2
done
state | grep -q '"Phase"' || { echo "$(date) $SVC never appeared; giving up" >> "$LOG"; exit 1; }

while true; do
    if is_published; then
        [ "$ATTEMPT" -gt 0 ] && echo "$(date) published after $ATTEMPT attempt(s)" >> "$LOG"
        exit 0
    fi

    ATTEMPT=$((ATTEMPT + 1))
    "$PUB" >/dev/null 2>&1
    RC=$?
    sleep 3

    if is_published; then
        echo "$(date) published rc=$RC after $ATTEMPT attempt(s)" >> "$LOG"
        exit 0
    fi

    # Report the phase alongside the failure - that is what localises a stall.
    PH=$(state | grep -oE '"Phase" = "[^"]*"' | head -1 | sed 's/.*= "//;s/"//')
    FAIL=$(state | grep -oE '"Failure" = "[^"]*"' | head -1 | sed 's/.*= "//;s/"//')
    echo "$(date) attempt $ATTEMPT failed rc=$RC phase=${PH:-unknown} failure=${FAIL:-none}" >> "$LOG"

    # Fast retries for the first ~10 min after boot, then a slower steady-state
    # poll so a late-arriving handshake is eventually caught.
    if [ "$ATTEMPT" -lt 20 ]; then
        sleep 28
    else
        sleep 120
    fi
done