#!/bin/bash
# Timer coalescing for macOS Sequoia (Darwin 24).
#
# The values in the original ThinkPad-fedora note were Linux kernel names
# (kern.timer.coalescing_bg_scale). macOS uses different oids, and the
# defaults here differ from Linux's, so do not copy Linux numbers across.
#
# Real macOS oids and their current defaults on this machine:
#   kern.timer_coalesce_bg_scale   -5
#   kern.timer_coalesce_bg_ns_max  100000000   (100 ms)
#   kern.timer_coalesce_fp_scale   3
#   kern.timer_coalesce_fp_ns_max  1000000     (1 ms)
#   kern.timer_coalesce_kt_scale   3
#   kern.timer_coalesce_kt_ns_max  1000000     (1 ms)
#
# Sign convention is NOT the same as Linux. -5 is already the widest
# background window here; a positive value is not automatically "more
# coalescing". Verify empirically with idle-power measurement, one oid at a
# time, and watch for timer latency in audio/video and interactive work.
set -euo pipefail

show() {
  printf '%-38s %s\n' "$1" "$(sysctl -n "$1" 2>/dev/null || echo absent)"
}

case "${1:-status}" in
  status)
    for k in kern.timer_coalesce_bg_scale kern.timer_coalesce_bg_ns_max \
             kern.timer_coalesce_fp_scale kern.timer_coalesce_fp_ns_max \
             kern.timer_coalesce_kt_scale kern.timer_coalesce_kt_ns_max \
             kern.timer.coalescing_enabled; do show "$k"; done
    ;;
  set)
    # apply only what is passed, so a bad value is attributable
    shift
    while [ $# -ge 2 ]; do
      oid="$1"; value="$2"; shift 2
      if sysctl -n "$oid" >/dev/null 2>&1; then
        sysctl -w "$oid=$value" && printf 'set %s = %s\n' "$oid" "$value"
      else
        printf 'SKIP: %s does not exist on this macOS build\n' "$oid" >&2
      fi
    done
    ;;
  *)
    printf 'usage: %s [status|set oid value ...]\n' "$0" >&2; exit 2 ;;
esac