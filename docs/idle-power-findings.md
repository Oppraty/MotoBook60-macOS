# Idle power: what was tried, what was measured

Keep both kexts (NVMeFix, BTIdle) — they load cleanly. But the reason they were
added turned out not to hold. Recording the measurement so nobody re-derives it.

## Where the goal came from

The ThinkPad E16 Gen 3 repo (same CPU, Core 7 240H) reports idle CPU package
going from ~6 W to ~2.5–3 W using NVMeFix, BTIdle, timer coalescing, `ngreenpm`,
EPP tuning, NVMe L1 substates and a patched IntelBluetoothFirmware.

That repo runs NootedGreen on Tahoe 26.7.1. This build runs WhateverXe on Sequoia
15.8.3. The power stacks are not comparable, so its result was never a valid
prediction for this machine. It was treated as one anyway.

## What was actually installed

| Kext | Version | Modified for this build |
|---|---|---|
| NVMeFix | 1.1.3 | No — stock acidanthera RELEASE binary |
| BTIdle | 0.1.1 | No — stock, taken from the E16 repo |

Neither was adapted. Two specific mismatches:

- **BTIdle targets Intel Bluetooth.** Its README says it needs the patched
  IntelBluetoothFirmware power-state support. This build uses **Realtek**
  (`BlueToolFixup` + `-btlfxboardid -btlfxallowanyaddr -btlfxrealtek`). The kext
  loads, and suspending the BT USB controller should be card-agnostic, but
  nothing verified it does anything on Realtek hardware.
- **The NVMe PCI path was wrong at first.** It is
  `PciRoot(0x0)/Pci(0x6,0x2)/Pci(0x0,0x0)` — behind the PEG2 bridge, not on a PCH
  root port. `0x1C,0x0` is the Wi-Fi card and `0x1C,0x5` the card reader. The
  first attempt pointed the L1 substate properties at those. Corrected in commit
  `064c33d`, verified against a Hackintool PCI dump.

Timer coalescing was **not** applied. The script as first taken from the E16 repo
used Linux oid names (`kern.timer.coalescing_bg_scale`) that do not exist on
Darwin 24; they were silently no-ops. `tools/timer-coalesce.sh` now reports and
sets the real macOS oids (`kern.timer_coalesce_bg_scale`,
`kern.timer_coalesce_fp_scale`, `kern.timer_coalesce_kt_scale` and their
`ns_max` pairs) and deliberately **auto-applies nothing** — the sign convention
differs from Linux, so values need measuring rather than importing.

## The measurement

`sudo powermetrics -n 5 -i 5000 --samplers cpu_power`, after `sleep 180` to let
post-boot activity settle, on AC power with `hcpower=4,2` in effect (mode 2).

Samples, W:

| Boot | 1 | 2 | 3 | 4 | 5 | median | mean | spread |
|---|---|---|---|---|---|---|---|---|
| A — kexts off | 7.82 | 9.34 | 5.93 | 5.77 | 6.54 | 6.54 | 7.08 | 3.57 |
| B — kexts on | 6.29 | 6.40 | 6.41 | 6.45 | 7.49 | 6.41 | 6.61 | 1.20 |

**Median difference: 0.13 W, about 2%.** Within-boot spread in A alone was 3.57 W
— roughly 27× the effect. So this is noise, not signal.

One thing that might be real: B is tighter (1.20 W vs 3.57 W). With one boot per
condition that is a hint at most, not a result. It would need several boots each
to confirm.

## Two earlier readings that were wrong

- **24.19 W** recorded in the notes as an idle baseline was a busy machine — per-core
  C7 residency rose while package power rose, which means background work. Not idle.
- **8.55 W** looked like a large win against it. It was a single unsettled sample
  taken seconds after boot. Real idle on this machine is **6–8 W** regardless of
  these kexts.

Deep C-states do engage once settled: sample 4 of A reached package C2 37.29%,
C3 23.70%, C6 3.35%. An earlier note claimed package C-state residency stayed at
0% and that this was a firmware ceiling. That was read from contaminated samples
and is **not** correct. C7 and above still never engage, but C2/C3/C6 do.

## Battery: measured, no benefit either

On battery, HybridCores flips to mode 4 (`hcpower=4,2`, confirmed via
`sysctl debug.hc_stat` showing `mode 4`). With both kexts still enabled:

| 1 | 2 | 3 | 4 | 5 | median | mean | spread |
|---|---|---|---|---|---|---|---|
| 6.47 | 6.37 | 6.31 | 6.33 | 6.28 | **6.33** | 6.35 | 0.19 |

Median **6.33 W**, spread **0.19 W**. Compare AC with the same kexts on: 6.41 W
median, 1.20 W spread.

So HybridCores' battery mode does not lower package idle by itself — 6.33 W against
6.41 W, inside the noise. What it clearly *does* is stabilise it: 0.19 W spread on
battery against 1.20 W on AC, a 6× tighter distribution. That is the one effect in
this whole exercise that looks real rather than noisy.

Still missing: a battery A-run with the kexts off, which would need another boot.
Without it, kext effect on battery is unknown and the 6.33 W is just "battery idle
with everything on."

## Verdict

Two stock kexts, unadapted, on a power stack they were not built for: no
measurable idle benefit on AC, and none demonstrated on battery either. The genuine
outcome of this work is the corrected NVMe path, the repaired timer script, two bad
baselines retired, and one real finding — HybridCores mode 4 makes battery idle far
more consistent than AC, if not lower.