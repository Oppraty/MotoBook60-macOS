# Internal mic: what is established, and what is not

The mic worked once on this machine and does not now. This records what is
verified so the next attempt does not start from zero.

## Confirmed working before

`RazerSSTMicrophone.kext` 0.3.3, `local.markplacer`, controller `8086:51CA`.
`mic-input-check` recorded 3/3 PASS cycles: status 0, 65536 + 63488 + 63488
frames, non-silent stereo (RMS 0.067–0.094, peak 0.29–0.43, 0 clipped),
`CaptureSessions=3`, `IPCSetupEntriesSent=20`, `ReplayEntriesSent=21`, every IPC
step Error=0 including teardown.

So the whole approach works on this hardware. The question is what broke.

## What broke it

SMBIOS was changed to `MacPro7,1` for CPU performance. The publisher now fails:

    0xe00002d5  "Initial PM idle acknowledgement missing"

`PublishesAudioInput=No`. A desktop SMBIOS has no battery service, so the power
management idle handshake the DSP kext waits for never arrives. This is the most
likely cause and it is a **SMBIOS** problem, not a kext problem.

Confirming yourself:

    sysctl -n machdep.cpu.brand_string    # whatever
    nvram -p | grep -i 'PublishesAudioInput'
    log show --last boot --predicate 'process == "RazerSSTMicrophone"' | grep -i 'e00002d5'

## Hardware is capable — verified from your own Fedora data

From `alsa-info` and the audio dmesg capture on this machine's Fedora 45:

| Fact | Value |
| --- | --- |
| Sound card | `sof-hda-dsp` |
| Capture devices | `device 6: DMIC`, `device 7: DMIC16kHz` |
| DMIC count | `cfg-dmics:2` |
| Codec | `14f11f87`, subsystem `17aa3830` — Conexant SN6140 |
| Controller | `8086281f` — Raptor Lake-P cAVS |
| Kernel driver | `sof-audio-pci-intel-tgl` |
| IPC generation | **`ipc type 0` = IPC3** |
| Firmware the kernel loads | `intel/sof/sof-rpl.ri` |
| Topology | `intel/sof-tplg/sof-hda-generic-2ch.tplg` |

Two of these matter:

1. **IPC3.** The reference Raptor Lake port and this kext are both IPC3. If the
   machine had been IPC4 (`intel/sof-ipc4/`), neither would work at all. It is not.
2. **`sof-rpl.ri`, not `sof-adl.ri`.** The shipped blob is Alder Lake. The kernel
   loads the Raptor Lake one. Intel signs SOF firmware per platform.

## Independent corroboration

A Raptor Lake-P DMIC bring-up was published on r/hackintosh (ThinkPad T14 Gen 4,
`8086:51CA`): <https://www.reddit.com/r/hackintosh/comments/1y5ocbc/>
Repo: <https://github.com/chxnathanaels/RaptorLake_IntelDSP_Hackintosh>

Their port differs from this one — `LatSOF-Audio` (pokipoi / jalavoui) rather than
`RazerSSTMicrophone` — and their repo ships only the write-up, no kext source.
But their prerequisites all confirm this build was already correct:

| Their requirement | This machine |
| --- | --- |
| `sof-hda-dsp` with a DMIC that records | present, `cfg-dmics:2` |
| IPC3, not IPC4 | IPC3 confirmed from own dmesg |
| `DisableIoMapper = true` | already `True` |
| Must load from `/Library/Extensions`, not OpenCore | already correct |
| AppleALC working for the codec | speakers confirmed working |
| SIP allows third-party kexts | `csr-active-config` = `0x0803` |

Their write-up never mentions `0xe00002d5`. That is weak evidence for the SMBIOS
theory rather than proof — their report does not say which SMBIOS they used.

Their port also exists *because* `sof-tgl.ri` did not work on Raptor Lake, which
is the strongest reason to try `sof-rpl.ri` here. It is a variable to test, not a
confirmed bug: **the mic worked with `sof-adl.ri`.**

## Where `sof-rpl.ri` is not yet available

Not present on this Mac, and no public mirror carries the plain path:

- `linux-firmware` GitHub / kernel.org — both 404 for `intel/sof/sof-rpl.ri`
- Fedora `alsa-sof-firmware-2025.12.2-1.fc43.noarch.rpm` — contains
  `intel/sof-ipc4/rpl-s/...sof-rpl-s.ri.xz`, the **IPC4** blob. Wrong generation.
  Do not use it.

Get the right one from this machine's own Fedora install, where the exact file the
kernel loaded lives:

    cp /lib/firmware/intel/sof/sof-rpl.ri /path/to/usb/

Then build the variant:

    tools/build-variant.sh /path/to/sof-rpl.ri

`tools/build-variant.sh` reproduces `tools/build.py`'s compile flags exactly and
changes only the `.incbin` target, so `build.py` stays untouched. It refuses an
xz-compressed blob so the IPC4 file cannot be embedded by accident.

## Where it stands now (2026-11-27)

Confirmed symptom, cause unknown.

Under `MacPro7,1`:

- kext loads — `local.markplacer.RazerSSTMicrophone (0.3.3)`, version
  `0.3.3-DMIC16K-RPL`
- `FirmwareReady` **never** becomes `Yes` (sampled repeatedly, stable)
- `PublishesAudioInput` stays `No`
- `mic-input-check` returns `{"device_found":false,"audio_saved":false}`
- CoreAudio lists a generic "Built-in Input / Internal Microphone" — that is the
  generic Apple device, **not** the RazerSST one. A listed input device is not
  evidence the mic works.

Under `MacBookPro16,4` (recorded earlier in GOAL-source.md):

- `PublishesAudioInput=Yes`, `FirmwareReady=Yes`, IPC setup 20/21 Error=0
- user confirmed working

So the SMBIOS correlation is real, but **the mechanism is not established.** An
earlier version of this file said a desktop SMBIOS has no battery service and
that is what breaks the PM idle handshake. That was a guess and it is wrong here:
`AppleSmartBatteryManager` / `IOPMPowerSource` **are present** on this `MacPro7,1`
boot (SMCBatteryManager is loaded). Something else about the desktop SMBIOS
prevents the DSP from reporting ready. Do not repeat the battery-service
explanation.

## Why the old one-shot publisher was misleading

`/usr/local/sbin/razermic-publish.sh` as installed ran `publish` exactly once
about 70 s after boot, and the LaunchDaemon has `KeepAlive=false`. It did **not**
check `FirmwareReady` first, so it invoked `publish` against a DSP that was never
ready. Its log therefore read `published rc=0` on some boots and
`publish failed rc=0` on others, which looked like intermittency.

It was not intermittent. The retry replacement waits for `FirmwareReady` before
attempting and logs `dsp not FirmwareReady yet, waiting` forever — so the
"publish failed" entries were the publisher being called prematurely, and the
"published rc=0` entries came from boots where the SMBIOS was different.

**Lesson:** treat `publish`'s exit code as meaningless unless `FirmwareReady` is
`Yes` first. `tools/razermic-publish-retry.sh` does that.

## Order to try

1. **`MacBookPro16,4`.** The confirmed-working configuration, already saved as
   config `5183eac0` in `evidence/pl1-65-20261126/`. Its CPU cost is **not
   measured** — GOAL-source.md records "Geekbench A/B vs 954/5777 pending".
   Ethernet is already absent on `MacPro7,1` (Wi-Fi holds `en0`), so switching
   gives up nothing there.
2. **Find what the DSP is actually waiting on.** Now that `FirmwareReady` is known
   to be the gate, read the kext's own log for what precedes it — the PM idle
   ack is the named suspect but unproven. `log show --predicate` against
   `RazerSSTMicrophone` during a boot is the place to look.
3. `sof-rpl.ri` firmware swap — **not relevant to this failure.** The loaded kext
   already reports `0.3.3-DMIC16K-RPL`, and `FirmwareReady` failing is upstream of
   anything firmware-generation would affect. Do not spend time on it first.

## Priorities, corrected

This section previously listed `sof-rpl.ri` first. The `FirmwareReady` finding
demotes it: the RPL version string is already present, and a firmware-generation
mismatch would not stop the DSP from reporting ready. The firmware angle only
matters if `FirmwareReady` is `Yes` and *capture* still fails.

Keep the `sof-rpl.ri` material — it is correct and still untested — but as step 3,
not step 1.

## Assets preserved

Kext, `publish`, and `mic-input-check` are all intact and shipped in the repo.
Nothing was lost during the power-management detour.