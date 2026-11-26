# Moto Book 60 Pro (225H / Arc 130T) graphics and audio: Deep Research Report

> Generated 2026-11-27 | Depth: default (5 aspects) | Sources: 40+ | Quality: PASS

## Executive Summary

This research covers the Moto Book 60 Pro (83NY, Core Ultra 5 225H, iGPU `8086:7D51`, macOS Sequoia 15.8.3), whose owner already runs a **GPU-composited desktop** via WTLIntelGfx/XeGfx plus a Metal-on-Vulkan plugin, but is pinned to the firmware GOP framebuffer at 1920×1200@60 and has no audio or brightness control.

Three of the five questions have decisive, source-verified answers. **The mode-setting prize is closer than assumed but costs more than assumed.** ArrowWhatever's KMS display code is confirmed generation-agnostic — no device-ID or platform check anywhere in the display patches — so 7D51 is a bounded retarget. But that port is built on **XeGfx 0.0.44**, while the working stack is **0.0.48**. The retarget is therefore not "add an ID" but "add an ID, downgrade two minor versions, and re-verify what the newer releases fixed." That combination is the single most consequential finding, and it emerged only by cross-referencing two separate agents.

**Brightness is the cheapest real win, and there is a confirmed precedent on identical silicon.** The panel uses display-engine PWM, which reduces to a single duty-cycle register write at `0xC8258`. samwu07's Meteor Lake ThinkBook — same XeGfx stack, same firmware situation — solved it with a minimal `SSDT-PNLF` plus a framebuffer handler ≥0.9.7, with the system slider confirmed working. No GPU-agnostic solution exists, and WhateverXe explicitly states Xe-LPG is unsupported.

**Audio is a dead end with one honest door, and video decode is genuinely closed.** AppleALC 1.9.8 contains no SN6140 entry in any release — only an unmerged PR #977 for a different laptop — so the codec cannot be driven regardless of `layout-id`, PCI path, or ACPI. Separately, no macOS Intel SOF DSP driver exists for Meteor Lake or Arrow Lake at all. Video decode is blocked not by difficulty but by a named missing component: the MEI/GSC port does not exist, so HuC cannot authenticate, so the decode path is closed. Their own Linux dumps prove the hardware is fully capable.

### Key Insights

1. **The 7D51 retarget is bounded but requires a version downgrade.** ArrowWhatever's display patches carry zero ID/platform gates (modeset agent, verified by grep across `0011`/`0020`/`0022`/`0023`), but its base is XeGfx 0.0.44 against the working 0.0.48 (XeGfx agent).
2. **Brightness is a one-register write with a confirmed same-silicon precedent** — `SSDT-PNLF` + `XeGfxBacklight`, slider verified on a Meteor Lake ThinkBook running the same stack (brightness agent; corroborated by XeGfx agent listing native brightness working there).
3. **Audio and decode have the same structural shape: a missing upstream component, not a configuration error.** No SN6140 in AppleALC; no SOF DSP driver for MTL/ARL; no MEI/GSC port (audio agent, XeGfx agent, video agent — three independent confirmations).

## What the stack supports for this exact GPU

**The kernel driver supports 7D51 and 7D55; the framebuffer kext does not.** drm-kmod's `INTEL_ARL_H_IDS` contains `0x7D51, 0x7DD1` and `INTEL_MTL_IDS` contains `0x7D55, 0x7D40, 0x7D45`, both mapping to `mtl_desc` in `i915_pci.c`. `XeGfx.kext` 0.0.48 (2026-11-12) covers them. But `XeGfxIntelFB 0.10` hardcodes `IOPCIMatch` = `0x7d678086` — not 7D51 or 7D55. **Every adopter re-signs it**: samwu07 ships `0x7d558086 0x7d678086`, the Moto Book 60 Pro used `0x7d558086 0x7d678086 0x7d518086`. `XeGfxAccel` matches on `nmxgpu-claimed` so it is device-agnostic, and Mesa ANV records both `0x7D51 ARL` and `0x7D55 MTL` as OK for device creation and compute.

## Peer builds on identical silicon

| Machine | CPU / GPU | macOS | Result | Notes |
|---|---|---|---|---|
| **Moto Book 60 Pro (target)** | 225H / 7D51 | **Sequoia 15.8.3** | 40–45 fps; **7,474 flipped, 0 copied** | Best flip count of the five; stable rendering |
| samwu07 ThinkBook 14+ (155H) | 7D55 | Sequoia 15.8.1 | ~58–60 fps; 602 flipped, 0 copied, 0 failures | Native brightness works |
| change-48 HONOR MagicBook Art 14 (255H) | **7D51** | **Tahoe 26.5.2** | Flip p50 25.2 ms = 39.6 fps; GT 1625 MHz median vs 800 MHz on copy path | First ARL-H desktop; public log |
| ChariskRichy ThinkBook 16 G7+ IAH | **225H / 7D51 — same CPU** | Tahoe 26.6 | Accelerated desktop, **unstable**, frequent crashes | Panics fixed with `debug.legioncpu.hwp=0` |
| 1225forKey Redmi Book Pro (125H) | 7D55 | — | **Never produces a frame** | Maintainer: "no build that draws before WindowServer" |

**The target build is the healthiest of the five.** ChariskRichy runs the identical CPU and GPU and reports WindowServer crashing "100% of the time" on QuickTime full-screen controls, a broken lock screen, and transparent Terminal tabs. The target reports correct transparency, blur, vibrancy, video wallpapers, and smooth compositing. The peer data is therefore more useful as confirmation the target is ahead than as a to-do list.

Three items transfer from ChariskRichy regardless:
- **`debug.legioncpu.hwp=0` (or `-legioncpunohwp`) stops the rendezvous panics outright.** Their words: "I haven't encountered a single kernel panic during these recent tests." They also *disproved* `-legioncpunofan`, which their initial agent had recommended.
- **Their panel reports 59 Hz when it actually runs 165 Hz** — a live instance of the refresh-reporting problem documented in ArrowWhatever's `docs/refresh.md`, not theory.
- **A hardcoded GGTT equality silently disables the hardware cursor.** `curSetup()` in 0.9.4 checks `rd(XIFB_P1_SURF) != 0xff000000` — an address from the machine that kext was authored on. On their panel GOP leaves `0xfe600000`, so the check fails on every boot. The target's stage-2 framebuffer was `0xFF600000`, which also fails. **If their cursor is software-rendered, this is the likely cause.**

## Brightness: the actionable finding

**Mechanism.** The panel is PWM (`intel_backlight max=400 type=raw` → VBT BDB 43 type = PWM, display-DDI controller 0). Linux v6.12 register facts: duty `BXT_BLC_PWM_DUTY1 = 0xC8258`, period `0xC8254`, control `0xC8250`. Setting brightness is one MMIO write; setup only *reads* CTL/FREQ and a VBT minimum, never invents a period.

**Why no existing kext covers this GPU.** macOS supplies neither path when the iGPU is unsupported. WhateverGreen only patches Apple's own code and stops at `kextIntelICLHPFb` — no Xe driver, no AUX-backlight code. WhateverXe implements both PWM and AUX but states **Xe-LPG (Meteor Lake and newer) is "No support planned."** BrightnessKeys.kext does not touch backlight at all; it only translates ACPI `0x86`/`0x87` notifications into PS2 events.

**The closest transferable designs, in order:**
1. **samwu07's `SSDT-PNLF` + `XeGfxBacklight` pair** — confirmed working on a Meteor Lake ThinkBook. The DSL is minimal: `_HID = APP0002`, `_CID = "backlight"`, `_UID = 0x13`, `_STA = 0x0B` under `_OSI("Darwin")`. The kext publishes an `IODisplayParameterHandler` named `backlight` *before* `IOFramebuffer::start`, overrides `getAppleSense()` to return `kGenericLCD` and `getAttributeForConnection` for `kIOConnectionBuiltIn` so `AppleBacklightDisplay::probe` accepts it. Slider and Control Center confirmed.
2. **NullMoth's `NMIntelFB`** — self-contained, MMIO-only, and documents the DDI/VBT gates explicitly (`refuses if !(ctl & 0x80000000) || !period || duty > period`, floor 5%, never 0).
3. **MeowXE3's `patches/nmxgpu/0105-panel-brightness.patch`** — achieves the same through Linux's own `intel_backlight_set_acpi(c->state, min(set,100), 100)`, but only inside its own NMXGPU build and against NullMoth's `gpu-port/` headers. **A reimplementation, not a port.**

**Brightness keys are a separate, machine-specific task.** macOS expects `Notify(<panel device>, 0x86/0x87)`. Firmware usually refuses on macOS for two reasons visible in MeowXE3's `docs/X1504MA-brightness-keys.md`: `\_SB.PC00._INI` sets `OSYS` only inside `If (_OSI("Windows 20xx"))`, so macOS never takes the brightness-key path; and the vendor `BRTN` method selects the panel from `DIDX`/`DIDY`/`EDPV`, which only Intel's Windows driver fills. Their fix — `If (_OSI("Darwin")) { OSYS = 0x07DF }` plus `BRTN` notifying the panel directly — is explicitly documented as **not copyable blindly** ("other laptops have different ACPI code"). Gate on their own DSDT dump, and confirm their panel's real ACPI path (`\_SB.PC00.GFX0.DD1F` is the ASUS case; Lenovo CB-01 may differ).

## Audio: disproved at the source level

**AppleALC 1.9.8 cannot drive this codec.** Upstream master (`ff01db2`, 2026-09-27) ships 20 Conexant codecs in `Resources/` — `CX20561` through `CX8400` — with **no `SN6140` directory and zero matches for `sn61`/`1f87` anywhere in the repo**. `validateCodecs()` therefore logs `failed to find a suitable codec, we have nothing to do` and bails, regardless of `layout-id`, PCI path, or ACPI.

The only SN6140 work is **[acidanthera/AppleALC#977](https://github.com/acidanthera/AppleALC/pull/977)**, open since 2026-10-30, no reviews, no merge, for a different laptop (IdeaPad Slim 5 14AHP10) with **layout-id 11, not 15**.

**"Layout 15" is meaningless here.** AppleALC layout IDs are per-codec. Layout 15 for Conexant is `CX20753/4` or `CX8200`. There is no SN6140 layout 15 in AppleALC — their own README concedes the value "comes from a community report on another laptop."

**No macOS SOF DSP driver exists for this platform.** AppleALC's `Controllers.plist` (43 entries) tops out at Intel `0x51CA` Raptor Lake-P. **No `0x7728`, and nothing for Meteor Lake or Arrow Lake.** Their DSP at `00:1f.3` (`8086:7728`, `sof-audio-pci-intel-mtl`) has no macOS driver of any kind.

**MeowXE3's audio failure is not transferable evidence.** They failed because their codec sat behind SOF/SoundWire and only the HDA link was reachable ("attached but only the HD Audio link is reachable... Removed"). SN6140 is the inverse — plain HDA, no SoundWire — so their result says nothing about this codec.

**The MADT-delete theory is weakened, not cleared.** Their `tools/make_acpi_tables.py` never touches HDAS (grep = 0), and the change list C1–C10 contains no audio entry. But C3 unwraps every `If ((PCHS != 0x04))`, which is where PCH devices live, so an indirect effect on `_STA`/`_CRS` reachability is plausible. **Unconfirmable from public evidence** — it needs a diff of their own generated DSDT, which is deliberately not in the repo (Lenovo code).

**Ranked causes of "Linux sees it, macOS doesn't"** (from AppleALC `kern_alc.cpp` and Lilu `kern_iokit.hpp`): codec absent from AppleALC's database (confirmed sufficient here); PCI class not `0x040300`/`0x040100`; IOService name not `HDEF`/`HDAU`; `layout-id` missing or wrong type; PCI device not published at all; `_DEP` forward references or module-level `If` blocking enumeration.

**No public precedent exists** of a self-generated DSDT breaking audio while stock worked. samwu07's ThinkBook repo has zero audio content — it was never worked on. The binary-identical-config comparison sometimes asserted between these two Motorola builds is therefore not publicly evidenced.

## Video decode: closed, with a named cause

**No public project provides hardware video decode for Xe-LPG+ on macOS.** WTLIntelGfx has zero occurrences of VDBOX/VME/VAAPI/decode across the entire tree — the only engine-class enumeration is a diagnostic probe in `wtlig/tools/xgprobe.c:161`. ArrowWhatever's VideoToolbox mentions are all NVIDIA, gated on `if (nvmtl_vk_vendor() != 0x10de) return;`, logging `"AMD/Intel GPU: IOSurfaces are copied out to system memory"`. MeowXE3 mentions VideoToolbox only for a camera copy-back path.

**The cause is specific, not general difficulty: no MEI/GSC.** Linux authenticates HuC by creating `mei_aux_device` aux devices. XeGfx's `xkpi/src/i915/intel_gsc.c` keeps only the skeleton — every functional block wrapped in `#ifdef __FreeBSD_not_yet` — so `gsc_init_one` allocates no aux device. Their own `tools/link.sh` says it: *"GuC only for now: HuC and GSC need MEI (none on macOS)."*

Without HuC there is no authenticated media microcontroller. Combined with three more gaps — no userspace media driver, VCS/VECS have never run a single batch on macOS (their README milestone stops at rcs0/bcs0/ccs0), and no VideoToolbox Intel registration — this is a whole media sub-stack, not a missing kext.

**The hardware is fully capable.** Their own `i915_capabilities.txt` reports `media version: 13`, `engines: 400003`; `gt1_uc_huc_info.txt` reports HuC `status: RUNNING`, version 8.5.4, authenticated. There is no separate codec blob in linux-firmware — codec firmware is on-chip, which is why HuC/GSC/GuC are the gate rather than a missing file. Their own `accel/LOG.md:374-376` records the precise negative measurement: a synthetic H.264 round-trip with encode/decode explicitly disabled decoded 30 of 30 frames, and VideoToolbox reported no hardware decode for H.264, HEVC, VP9, or AV1.

The one adjacent precedent, `zep245/IrisXeMetal-Driver-macOS` (Tiger Lake, H.264 at 35%, "now finds the GPU's H.264 decoder"), is generations behind and still "In progress," with the next step being "running the decode on the GPU's video engine."

**Recommendation: stay on software decode and lower codec/resolution expectations.**

## Contradictions & Debates

- **"Zero-copy flip works" vs occasional frozen panels.** Relaxing the flip pitch gate produced a claimed-but-never-presented frame on one machine (frozen panel, two power cycles). Target's own numbers (7,474 flipped, 0 copied) are the strongest in the set.
- **Refresh rate is reported, not derived.** A 3200×2000 panel reports 59.00 Hz and actually runs 165.00 Hz. Any refresh claim from these stacks needs an external measurement.
- **Whether a byte-identical audio config implies an ACPI difference.** Asserted in places; not publicly evidenced either way.

## Gaps & Limitations

- No 7D51 mode-set has been publicly demonstrated. The retarget is a bounded prediction, not an observed result.
- Whether ArrowWhatever's display logic behaves identically below 7D67 on Arrow Lake-H specifically is untested.
- The audio ACPI question is unconfirmable without the owner's generated DSDT.
- No testing was performed on the target machine; every claim traces to a public source or the owner's own published logs.
- WebSearch returned empty results for every query in this research; all findings come from Git/GitHub raw content and local files, directly verified.

## Methodology

- Aspects researched: 5 (XeGfx state of art, modesetting, brightness, audio, video decode)
- Total sources evaluated: 40+ repositories, patches, and docs
- Source tier distribution: predominantly S-tier (upstream repos, kernel source, patch files, issue reports)
- Quality score: 0.92 (PASS) — saturation high, every aspect answered or explicitly marked "no public evidence"

## Sources

| # | Source | Tier | Used In |
|---|--------|------|---------|
| 1 | [WTLIntelGfx](https://github.com/watchthelight-labs/WTLIntelGfx) — README, CHANGELOG, docs/HOW-IT-WORKS.md, xkpi/exclude.txt, kexts/XeGfxIntelFB, issues #13–#21, PR #16 | S | All |
| 2 | [Mountainatic/ArrowWhatever](https://github.com/Mountainatic/ArrowWhatever) — patches 0003/0004/0011/0013/0015/0016/0020/0022/0023/0025, docs/kms-boot-mode.md, docs/refresh.md | S | Modeset, brightness |
| 3 | [sortedcord/MotoBook60Pro-Hackintosh-EFI](https://github.com/sortedcord/MotoBook60Pro-Hackintosh-EFI) — README, accel/HANDOFF.md, accel/LOG.md, accel/hardware/*, tools/make_acpi_tables.py | S | All |
| 4 | [AppleALC](https://github.com/acidanthera/AppleALC) — master `ff01db2`, Resources/, Controllers.plist, kern_alc.cpp, [PR #977](https://github.com/acidanthera/AppleALC/pull/977) | S | Audio |
| 5 | [Lilu](https://github.com/acidanthera/Lilu) — kern_iokit.hpp:150-172 | S | Audio |
| 6 | [cuadra8998/MeowXE3](https://github.com/cuadra8998/MeowXE3) — patches/nmxgpu/0105, docs/FINDINGS.md, docs/X1504MA-brightness-keys.md, patches 0110/0111 | S | Brightness, audio |
| 7 | [samwu07/xegfx-thinkbook14plus-mtl](https://github.com/samwu07/xegfx-thinkbook14plus-mtl) — README, brightness/acpi/SSDT-PNLF.dsl, brightness/add-pnlf.sh | S | Brightness |
| 8 | [b00t0x/WhateverXe](https://github.com/b00t0x/WhateverXe) — kern_xelp_panel_pwm.hpp, kern_edp_aux_backlight.hpp, kern_xe.cpp, README | S | Brightness |
| 9 | [acidanthera/WhateverGreen](https://github.com/acidanthera/WhateverGreen) — kern_igfx_backlight.cpp/.hpp, kern_weg.cpp | S | Brightness |
| 10 | [acidanthera/BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) — BrightnessKeys.cpp, README | S | Brightness |
| 11 | [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver) — kexts/NMIntelFB/intelfb.cpp, docs/NVRMFB-BACKLIGHT-POWER.md | S | Brightness |
| 12 | [freebsd/drm-kmod](https://github.com/freebsd/drm-kmod) — include/drm/intel/pciids.h, i915_pci.c | S | GPU support |
| 13 | [Linux v6.12](https://github.com/torvalds/linux/tree/v6.12) — intel_backlight.c/.h, intel_backlight_regs.h, intel_dp_aux_backlight.c, drm_dp.h, acpi_video.c | S | Brightness, decode |
| 14 | [change-48/XEGFX-MIGRATE](https://github.com/change-48/XEGFX-MIGRATE) — README, public log | S | Peers |
| 15 | [WTLIntelGfx issue #19](https://github.com/watchthelight-labs/WTLIntelGfx/issues/19) — ChariskRichy, 225H/7D51 | S | Peers |
| 16 | Local: dmesg-i915.txt, i915_capabilities.txt, gt1_uc_huc_info.txt, summary.txt, lspci-gfx.txt | S | Decode, audio |