# Known issues

Open problems on this build, with what has been ruled out. Written so the next
attempt does not repeat the failed theories.

## Internal mic works, but goes dormant

**Status: intermittent. A reboot restores it.**

The mic does work. On 2026-11-27 the kext log showed three real captures:

    2026-11-27 15:03  coreaudiod takes power assertion
                     RazerSSTMicrophone:8086-51CA:17AA-387E:PDM1-16K
    2026-11-27 15:04  3x, each ~4s

and `mic-input-check` had earlier reported 3/3 cycles PASS with RMS 0.19 and 53
clipped samples at input volume 10.

The behaviour: the kext publishes, captures, then clears `PublishesAudioInput`
and goes dormant. Further `publish` calls return `0xe00002d5` without re-arming
it. The kext log simply stops after `WaitingForInitialPMIdle` — no failure line,
no phase advance.

Not yet known: what the kext does between `WaitingForInitialPMIdle` and
dormancy. `log show --predicate 'senderImagePath CONTAINS "RazerSST"'` shows
nothing in that gap. That silence is the thing to investigate if this recurs.

Recovery is a reboot. It worked at 14:46 and 14:59 on 2026-11-27.

### Theories that did not survive

Recorded because they cost real time:

- **"MacPro7,1 has no battery service."** Invented. `AppleSmartBatteryManager`
  and `IOPMPowerSource` are present on this boot, 7 matches. Never repeat this.
- **"`PMActualState` truthiness is the whole cause."** The check
  `if(!self->getProperty("PMActualState"))` was genuinely wrong — state 0 is
  valid and this machine parks there. Fixing it did unblock the gate once and
  the mic did publish and capture. But the same binary failed on the next boot,
  so it was one trigger, not the cause.
- **"`0xe00002d5` means already armed / busy."** Readable from
  `OSCompareAndSwap(0,1,&armed_)` in `setProperties`, but unproven, and polling
  showed the device never re-arms.
- **"The Failure property is stale."** Half right — the log goes silent rather
  than recording new failures — but it did not explain the stall.

### Input gain

Default is now 10 dB, not 30. At 30 the kext applied a x31.6 multiplier to a
signal already near full scale: about 9,250 of 64,000 frames clipped, RMS 0.54.
At 10: 53 frames clipped, RMS 0.19. Note volume 0 does not attenuate, it
silences the engine.

`tools/razermic-publish-retry.sh` publishes once per boot and exits. Earlier
versions retried in a loop, which was actively harmful: 18 attempts logged on
2026-11-27, none of which changed anything.

## Tap-to-click silently off (resolved)

Symptom: single-finger tap does nothing; physical click works.

Cause: `com.apple.AppleMultitouchTrackpad` `Clicking = 0`.

**The trap: setting it fails silently with the wrong type flag.**

    defaults write com.apple.AppleMultitouchTrackpad Clicking -int 1     # FAILS
    defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true  # WORKS

The domain stores `Clicking` as a Boolean. An `-int` write to a Boolean key
does not error, it just does nothing. Worse, the two verification commands
disagree after the correct write — this is what made it look like a driver
problem:

    defaults read com.apple.AppleMultitouchTrackpad Clicking   # reports 0
    plutil -extract Clicking raw ~/Library/Preferences/com.apple.AppleMultitouchTrackpad.plist
                                                                 # reports true

`plutil` reads the file, `defaults read` reported a stale or coerced value.
Cross-check with `plutil` when a `defaults write` appears not to take.

Note the asymmetry inside the same domain: integer-valued keys such as
`TrackpadThreeFingerTapGesture` read back correctly immediately. Only the
Boolean key behaves this way.

Also disabled while in that pane: `TrackpadThreeFingerTapGesture -int 0`
(look up & data detectors, enabled by default at 2).

### Theories that were wrong

Recorded because each cost real time:

- **VoodooI2CHID can't do tap-to-click.** False. The kext exposes a tip switch
  at `ElementCookie=42`, `ReportID=0`, `UsagePage=13`, `Usage=0x22`. macOS
  reads it and drives it correctly.
- **Vorssaint's pointer feature swallowed the tap.** False. Quitting the app
  restored tap, but disabling every pointer feature inside it did not. The
  correlation was real, the causation was not — the app was quit at the same
  time the setting was fixed.

## Cursor jitter while using the keyboard

**Status: pre-existing, unresolved. Not a regression.**

Confirmed present before 2026-11-27, so the session's work (AuxKC rebuilds, the
FAT repair, kext installs) is not implicated.

Recorded from GOAL-source.md, 2026-11-25:

    mouse/keyboard choppiness UNRESOLVED (persists across EPP removal,
    CPUFriend/topology removal, 60 Hz test, Reduce Transparency/Motion,
    key-repeat tuning)
    WindowServer ~80-100% CPU; OpenCode app ~80-100% CPU;
    likely host-side compositor/CPU saturation

Symptom is specific: cursor is smooth with trackpad movement alone, jittery when
the keyboard is also in use. Minecraft framerate stays 80+, so general CPU
saturation is ruled out.

**Already ruled out on 2026-11-27:**
- CPU contention (80+ fps in Minecraft)
- PS2 double-reporting (`VoodooPS2Trackpad` is not enabled and not loaded)
- duplicate I2C devices (one `VoodooI2CDeviceNub`, one `VoodooI2CHIDDevice`;
  the extra `Magic Trackpad 2` entries carry Voodoo's own vendor ID 1452, not
  the hardware's 1267)

**Not yet tried:** System Settings → Accessibility → Pointer Control →
"Ignore built-in trackpad when mouse or wireless trackpad is present", which is
currently off. macOS is merging the I2C trackpad with Voodoo's PS2 `Mouse`. This
matches the symptom and is the cheapest remaining test.

**To measure rather than guess:**
`cursor-watch` equivalent is `event-gaps.c` in the November evidence folder. It
needs Accessibility permission for the terminal. Baseline to compare against is
`median 8.83ms, max 26.59ms, 0 gaps over 50ms`.

Your own note names the likely suspect: WindowServer at 80-100% CPU. If that
checks out during play, the lever is composition load, not input:

    sudo powermetrics -n 3 -i 2000 --samplers tasks | grep -A2 WindowServer

## FAT corruption on the ESP

Occurred twice, both from hard power-off during writes. It creates duplicate
directory entries named `FSCK0000.000` inside kext `PlugIns/` folders, which
breaks VoodooI2C's plugin discovery and takes the trackpad with it.

Prevention: unmount before rebooting.

    sudo diskutil unmount /Volumes/EFI

Repair:

    sudo diskutil unmount force /Volumes/EFI && sudo fsck_msdos -y /dev/disk0s1

Quarantined duplicates are kept in `/Volumes/EFI/EFI/OC/_fsck-quarantine/`.
`tools/build_efi.py` strips these directories when building.

## Boot entries and the WEX recovery tree

There is one EFI System Partition (`disk0s1`), not two. `/Volumes/EFI` is the
mount point and `/Volumes/EFI/EFI/OC` the OpenCore tree inside it.

Alongside the live tree the partition root also carries `WEX-RECOVERY/` (a
`config.plist`, `WhateverXe` copy and `fix.sh`), plus `System` and `mach_kernel`
leftovers. Worth checking whether a recovery daemon is still armed and what its
pins point at — an armed restore mechanism can silently revert binaries after
verification, which is documented as having happened once already.