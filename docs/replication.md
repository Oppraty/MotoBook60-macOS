# Replication guide

This repository ships a working, tested EFI alongside this guide. The guide explains what the build is, what it depends on, and how to adapt it — it is not a generic install walkthrough.

This EFI is **not reproducible from stock releases alone**. It contains a custom-built OpenCore bootloader and several custom kernel extensions used in specific combinations. Keep a verified baseline that boots without the optional components before changing anything.

## Starting from Windows only: build a minimal EFI with 1401

This repository ships an EFI, not a macOS installer. If you already have macOS installed, [§2](#2-installing-and-verifying-the-efi) is your path. This section is for someone starting from **Windows only, with no Mac and no macOS installed**.

[1401](https://github.com/NullMoth/1401) runs on Windows, reads your hardware, builds an OpenCore EFI for it, and writes a macOS install stick. It is free and open source (PolyForm Noncommercial) and was designed for exactly this situation.

1. Download `1401-Windows-<version>.zip` from its [releases page](https://github.com/NullMoth/1401/releases) and unzip it, keeping the `1401` folder together.
2. Run `1401.exe` **as administrator**. It needs admin to read ACPI tables and write disks.
3. Click **Check this PC**, read the BIOS steps it shows you, then **Build the Mac setup**, then **Create the macOS stick**. You need an 8 GB+ USB stick that can be erased, and an internet connection — it downloads Apple's recovery image and checks every chunk against Apple's signed chunklist.
4. Apply the BIOS settings it listed, reboot to the stick, pick the macOS installer in the OpenCore menu, and install.

What the generated EFI gives you, and why it is enough to get started:
- **Wi-Fi works.** 1401 builds on [OpCore-Simplify](https://github.com/lzhoang2801/OpCore-Simplify), which knows this laptop's Wi-Fi card (`10EC:8922`) and Bluetooth card (`0BDA:8922`) and selects `AirPort_RTW89` plus the Realtek Bluetooth firmware stack automatically. Both device IDs are in its PCI database, and it is the same driver family this repo ships.
- **Keyboard and touchpad work.** It picks VoodooPS2Controller and VoodooI2C/VoodooI2CHID for I2C devices, plus BrightnessKeys on laptops.
- **Boot logs land on the stick**, so a machine that never reaches macOS can still report why — and 1401 can send that report ID when you ask for help.

What the generated EFI does **not** give you, and this is the important part:
- **120 Hz will not work.** 1401 generates a stock WhateverGreen config. This panel needs the custom WhateverXe 0.8.2 build with the Samsung-specific timing constants, which only exists here.
- **No fan control, no thermal offset, no power profile.** FanMode, `hpmpl1=64`, `hcpower=4,2`, `tccoffset=2`, and HybridPM are absent.
- **No internal mic stack.** RazerSSTMicrophone is absent.
- BlueToolFixup is the stock build, not the Realtek-patched one this laptop needs.

Treat the 1401 output as a **boot-key to get into macOS**, then replace it. It is a means to an install, not the destination.

### Then swap in this EFI

Once macOS is installed and boots from the 1401 stick:

1. Back up the 1401-generated `EFI` folder somewhere you can restore it. This is your recovery path.
2. Fill in your own SMBIOS identifiers in this repo's `config.plist` (see [§1](#1-what-this-build-is-and-what-to-check-first) step 3). 1401 already generated a set for this machine — you can reuse those or generate fresh ones with GenSMBIOS. Do not leave the placeholders.
3. Copy this repo's `BOOT` and `OC` onto the internal ESP, replacing the 1401 output.
4. Decide whether to install `AuxiliaryKernelExtensions.kc` — mic stack, fan control, and `tccoffset=2` depend on it (see [§4](#four-custom-kernel-extensions-plus-one-dependency)).
5. Reboot to the internal EFI and work through the checks in [§2](#2-installing-and-verifying-the-efi) step 4.

If it fails to boot, boot the 1401 stick again.

### Or: build your own from scratch

If you would rather not depend on either this EFI or 1401, the [Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/) is the reference for a hand-built config, and [ProperTree](https://github.com/corpnewt/ProperTree) is the usual plist editor. Two honest warnings if you take this route on this machine:

- **120 Hz cannot be built from stock sources.** It needs a patched WhateverXe and this panel's timing constants. You can match the values in [§3](#the-oled-build) and build your own, but the patch set is not published here.
- **The custom kernel extensions have no public upstream release.** Expect to write or port a FanMode-equivalent, and accept whatever the standard mic situation is.

Start from the OpenCore sample rather than editing someone's config, generate your own SMBIOS, and add drivers one at a time — a stock build you understand beats a copied build you do not.

## 1. What this build is, and what to check first

This EFI is exported from a machine that was already booting. Treat it as a starting point for a similar machine, not a drop-in image.

1. **Record your hardware.** In the OS the machine shipped with, note the CPU, iGPU PCI ID, panel model and native timings, Wi-Fi card PCI ID, and Bluetooth USB ID. The build here targets `83J7` with Core 7 240H, iGPU `8086:A7AB`, Samsung OLED, Wi-Fi `10EC:8922`, Bluetooth `0BDA:D922`. Other `83J7` units ship different wireless cards, and the included Realtek stack will not apply to them.
2. **Make recovery possible before you change anything.** Back up the disk and its existing EFI System Partition, confirm you can still boot your current OS without OpenCore, and test from a bootable USB before touching the internal ESP. A second OpenCore folder on the same partition is not a recovery plan.
3. **Generate your own SMBIOS identifiers.** The committed `config.plist` uses placeholders for `SystemSerialNumber`, `MLB`, `SystemUUID`, and `ROM`. Fill them in with [ProperTree](https://github.com/corpnewt/ProperTree) or your usual tool before the first boot. Never reuse another machine's values.
4. **Sanity-check the config.** Open `config.plist` and confirm `PlatformInfo → Generic → SystemProductName` is what you intend. A passing `ocvalidate` run does not prove the file boots, and a failing one usually means the file is malformed.
5. **Understand what you are enabling.** See [§4](#4-known-limitations-and-that-bootloader) before booting: this build ships a custom bootloader, four unsigned kernel extensions, reduced SIP, and a prebuilt kernelcollection.

## 2. Installing and verifying the EFI

1. Copy both `BOOT` and `OC` onto your EFI System Partition. `BOOT/BOOTx64.efi` comes from the official OpenCore 1.0.6 release.
2. Decide whether to use the bundled `OC/AuxiliaryKernelExtensions.kc`. Installing it on the boot volume restores the microphone stack, fan control, and power diagnostics, but also loads five unsigned kernel extensions. Skipping it means those features are absent.
3. Boot from the firmware boot picker, not by chaining BIOS entries.
4. Verify, in this order, and stop at the first failure:
   - `sw_vers` reports macOS 15.8.3; `sysctl hw.physicalcpu hw.logicalcpu` shows the expected counts
   - Displays: native 2880×1800, 120 Hz available, brightness keys work
   - Input: keyboard, touchpad (with `-vi2c-force-polling`, IORegistry should show `"Interrupt Mode" = "Polling"`)
   - Audio: speaker output, then the microphone — expect the internal mic to fail
   - Network: whichever stack applies to your card
   - `kmutil showloaded` for the kexts you installed
5. **Never run `kmutil unload`** on this setup. Live unloading triggered a kernel panic here and recovery was by boot, not by undo.
6. Keep system sleep disabled (`pmset -a sleep 0`) until you have independently verified wake on your own hardware.

## 3. What is actually in the EFI, and how each piece is used

Every item below is present in `EFI/OC/` unless marked otherwise. Change one area at a time and re-verify from step 4 of [§2](#2-installing-and-verifying-the-efi).

| Area | What ships | Notes and checks |
| --- | --- | --- |
| Bootloader | Custom `OpenCore.efi` (no matching release) + official 1.0.6 `BOOTx64.efi` | See [§4](#4-known-limitations-and-that-bootloader). This is the least auditable part of the build. |
| EFI drivers | `OpenRuntime.efi`, `HfsPlus.efi`, `OpenCanopy.efi`, `ResetNvramEntry.efi`, `OpenLinuxBoot.efi` | The last three are picker, NVRAM reset, and Linux scanning; not required to boot macOS. |
| ACPI | 8 tables: `SSDT-EC`, `SSDT-MCHC`, `SSDT-PLUG-ALT`, `SSDT-RTCAWAC`, `SSDT-USBX`, `SSDT-XOSI`, `SSDT-PNLF`, `SSDT-Disable_Network_RP05` | Paired with the `H_EC _STA to XSTA Rename` and `_OSI to XOSI` ACPI patches. These are not universal — inspect your own ACPI namespace before reusing the renames. |
| Core kexts | Lilu 1.7.3, VirtualSMC 1.3.9, SMCBatteryManager 1.3.9, ReYogaSMC 2.2.1, CpuTscSync 1.1.2, BrightnessKeys 1.0.4 | Dependencies first: Lilu and VirtualSMC load before their plugins. |
| Graphics | Custom [WhateverXe](https://github.com/b00t0x/WhateverXe) 0.8.2 (`org.b00t0x.WhateverXe`), native-only 120/60 Hz | See the OLED note below. `-disablegfxfirmware -igfxdvmt` and the `wex-*` args are tied to this panel. |
| Input | VoodooPS2Controller 2.3.7 (+ VoodooInput, VoodooPS2Keyboard), VoodooI2C 2.9.1 (+ GPIO/services), VoodooI2CHID | `-vi2c-force-polling` keeps touchpad reporting in polling mode. Only one VoodooInput copy. |
| Audio | AppleALC 1.9.8, layout 15 (`0f000000` as Data) on `PciRoot(0x0)/Pci(0x1f,0x3)` | Speakers only. The microphone is a separate, broken stack — see the mic row. |
| USB | USBToolBox 1.2.0, `UTBDefault.kext`, `XHCI-unsupported.kext` | The latter two are plist-only injectors; see [§4](#the-two-plist-only-kexts-are-not-broken). Map ports for your own chassis. |
| Wi-Fi | AirPort_RTW89 0.6.0 (+ `AirPortRTW89Front`), IOSkywalkFamily 1.0, IO80211FamilyLegacy 12.0, AMFIPass 1.4.1 | A matched replacement stack, min kernel `23.0.0`, with the built-in `com.apple.iokit.IOSkywalkFamily` excluded for those kernels. Specific to the Realtek card. |
| Bluetooth | RTL8922AFirmware 0.1.0 (`io.github.gevuz.RTL8922AFirmware`), BlueToolFixup 2.7.3 | **BlueToolFixup is not stock.** It reports the stock `as.acidanthera.BlueToolFixup` identifier, but the binary carries extra Realtek patches. The args `-btlfxboardid -btlfxallowanyaddr -btlfxrealtek` only make sense with that patched binary. |
| Microphone | `RazerSSTMicrophone.kext` via AuxiliaryKernelExtensions.kc | Broken under `MacPro7,1`; see [§4](#the-microphone-does-not-work-in-this-configuration). |
| Performance | HybridPM 1.0.0 (`hpmpl1=64`), IntelHybridCores 0.2.0 (`hcpower=4,2`), IntelSpeedShiftEPP (`EPP=0`, `Desired=0`), FanMode, RaplDiag, TccOffset (AuxKC only) | See the performance note below. HybridPM and IntelHybridCores are Darwin 24 ports, not upstream releases. |
| Disabled in config | CPUFriend, CPUFriendDataProvider, CpuTopologyRebuild | Files are present but `Enabled=false`. Measured worse here. |

### The OLED build

The included WhateverXe binary has SHA-256 `fb2f6bb995f951acb5df501892ae1281c54e5062dffcd0599ad4121496b07546`, and is 0.8.2-derived with native-only modes (`ScaledCount=0`), 120 Hz and 60 Hz, no scaled HiDPI. That fingerprint identifies this one binary; a rebuild will differ. The panel timing came from `kern_display13_panel_timing.hpp` with `VerticalBlanking=80+16+24`, `VerticalSyncOffset=80`, `RefreshRate=120`. Graphics args in the committed config: `-allow3d -disablegfxfirmware -igfxdvmt -wex-tgl-edp-keep -wex-panel-gop -wex-edp-auxbl`. Do not reuse these constants or args on another panel; they were derived from this Samsung panel's EDID and timing. The patch set is not published.

### The performance numbers

The 1517/8026 Geekbench result is one run, on AC, with fan cooling forced to maximum and a custom thermal offset. It is not a target and not reproducible on demand. Run-to-run variance on this machine was large: another identical-config run gave 1234/6501. Several changes that looked like improvements measured worse. Higher PL2 was worse, and CPUFriend with `16,4` vectors was worse. The binding limit reads `ICCMAX/PL4/OTHER`, which is a grouped reason, not a diagnosable register. Do not chase it by writing CPU/VRM registers or raising current limits.

## 4. Known limitations and that bootloader

This section is deliberately blunt because the EFI here is close to the edge of what a public repo should do.

### The bootloader is custom-built

`EFI/OC/OpenCore.efi` matches **no official OpenCore release**. It is 630,784 bytes, while official 1.0.0–1.0.2 builds are 614,400 bytes and 1.0.3 and later are 622,592. Every driver in `EFI/OC/Drivers/` also differs from every release I checked, including `OpenRuntime.efi`.

What is included instead:
- `EFI/BOOT/BOOTx64.efi` and `EFI/OC/BOOTx64.efi` come from the **official OpenCore 1.0.6 RELEASE**, so the mirror entry and the fallback path are verifiable.
- The custom `OpenCore.efi` is shipped as-is and labeled, because replacing it with an official build changes behavior and may not boot.

If you want a fully auditable build, replace `OpenCore.efi` with the 1.0.6 RELEASE binary and retest everything. Do not mix `BOOTx64.efi` from one release with a custom `OpenCore.efi` of unknown provenance — that is the fastest route to a boot failure you cannot diagnose.

### Four custom kernel extensions, plus one dependency

Working microphone, fan control, and the reported performance numbers depend on kernel extensions with no public upstream release, or on local ports that differ from upstream:

| Kext | Role | Source |
| --- | --- | --- |
| `IntelSpeedShiftEPP.kext` | HWP EPP handling; treats unknown power source as AC and forces Desired=0 | Local port of [`xnpty/IntelSpeedShiftEPP`](https://github.com/xnpty/IntelSpeedShiftEPP). **No source published here**; only the built binary ships. If you need the source, rebuild from upstream or contact the maintainer. |
| `FanMode.kext` | Fan mode and DYTC via vendor ACPI `VPCW`/`VPCR`/`DYTC` | Local, no public source. Binary only. |
| `RazerSSTMicrophone.kext` | Internal digital mic over Intel DSP `8086:51CA` | Local port. Binary only. |
| `RaplDiag.kext` | Read-only RAPL power-limit diagnostics | Local. Binary only. |
| `TccOffset.kext` | `tccoffset=2` thermal offset | **Not included.** No source or binary is present in this repository |

These five load from `/Library/Extensions`, not from `/EFI`. They are bundled in `EFI/OC/AuxiliaryKernelExtensions.kc`. If you remove that file, or install the EFI without it, you lose the microphone, fan control, and power diagnostics, and `tccoffset=2` has no effect. `OC/Kexts/` also carries the four whose binaries are available, but those copies are not what loads — the kernelcollection takes precedence.

Copying `Kexts/` to the EFI partition is **not** equivalent to installing them. Do not assume a config plist change or an `UpdateSMBIOS` flag will load them; they live in the boot volume's kernel collection, and the EFI copies are there for reference and rebuilds.

### The microphone does not work in this configuration

The internal mic fails with `0xe00002d5` ("Initial PM idle acknowledgement missing") under `MacPro7,1`. Mic capture worked under `MacBookPro16,4` at lower benchmark scores. If the mic matters to you, expect to redo the SMBIOS and audio tuning work; there is no verified fix shipped here.

### The two plist-only kexts are not broken

`UTBDefault.kext` and `XHCI-unsupported.kext` in `OC/Kexts/` contain only `Info.plist` with no `Contents/MacOS/` binary. This is correct and intentional: they are IOKit injector personalities that publish matching dictionaries and are consumed by their host kext (`com.dhinakg.USBToolBox.kext` and `AppleUSBXHCILPTH` respectively). The official USBToolBox 1.2.0 release ships a byte-identical `UTBDefault` plist with no binary either.

### Sleep and wake

Do not treat sleep as working. Vendor wake fixes caused UI freezes on this SKU, and display-only sleep is unresolved. Keep system sleep disabled (`pmset -a sleep 0`) and expect lid close to blank the panel only.

### Security posture

`Misc → Security` uses `SecureBootModel=Disabled` and `csr-active-config` = `0x0803`, which turns on untrusted kexts, unrestricted filesystem access, and unapproved kexts. `DmgLoading=Signed` remains. Those relaxations support the custom kernel extensions and the Realtek Wi-Fi stack; they are not needed merely to boot macOS. Reduce them if you can accept losing those features.

### Power and fan settings

The reported Geekbench figures came from maximum fan cooling plus a custom thermal offset and specific power limits. They are a recorded result on one machine, not a target. Raising power limits or writing undocumented CPU/VRM registers is not recommended here: the binding limit is not a register that was safely writable, and attempts to raise it made things worse.

## 5. Changing this build safely

- Keep a verified fallback before any change: a second EFI folder you have booted, or a recovery USB. Restoring is by booting that EFI, not by unloading kexts.
- Change one thing per boot. Change one thing, boot, verify the items in [§2](#2-installing-and-verifying-the-efi) step 4, and record expected versus observed before touching the next item.
- Do not copy another machine's `AuxiliaryKernelExtensions.kc` into this build. It is matched to these five kernel extensions and this macOS build.
- Do not reset NVRAM as a first-line diagnostic. It clears the boot picker state you are relying on and hides the real problem.
- The `-wex-*` and `-btlfx*` boot arguments are paired with custom binaries here. Adding them to a stock WhateverXe or stock BlueToolFixup does not reproduce this build and may not do anything.
- Check `kmutil showloaded` rather than `kmutil logs show` dumps when confirming what loaded, and report results with model, OS build, hardware IDs, component versions, and a description of the single change. Redact serials, UUIDs, MAC addresses, Wi-Fi names, usernames, and paths from any logs or configs you share.
