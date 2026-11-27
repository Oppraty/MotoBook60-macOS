#!/bin/bash
# Timer coalescing - reduces CPU wake-ups at idle
# Based on ThinkPad E16 Gen 3 implementation
# Sysctls: tier0 scale 1 / ns_max 10000000, tier1 scale 2 / ns_max 20000000

/usr/sbin/sysctl -w kern.timer.coalescing_enabled=1
/usr/sbin/sysctl -w kern.timer.coalescing_bg_scale=1
/usr/sbin/sysctl -w kern.timer.coalescing_bg_ns_max=10000000
/usr/sbin/sysctl -w kern.timer.coalescing_fg_scale=2
/usr/sbin/sysctl -w kern.timer.coalescing_fg_ns_max=20000000
