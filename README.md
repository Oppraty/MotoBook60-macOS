# macOS Sequoia on the Motorola Moto Book 60

A working OpenCore EFI for the Motorola Moto Book 60 (machine type `83J7`), Intel Core 7 240H, on macOS Sequoia 15.8.3 (`24H241`). Built from a real booting configuration rather than a template, and documented as-is — including what does not work.

**Read [docs/replication.md](docs/replication.md) before using the EFI.** It explains what this build is, what it depends on, and how to adapt it.

| Component | This build |
| --- | --- |
| CPU | Intel Core 7 240H (6 P + 4 E cores, 16 threads) |
| Graphics | Intel iGPU `8086:A7AB`, custom WhateverXe 0.8.2, native-only 2880×1800 @120 Hz |
| Panel | Samsung OLED, 240 Hz capable; 120 Hz used |
| Wireless | Realtek RTL8922AE Wi-Fi (`10EC:8922`) + RTL8922A Bluetooth (`0BDA:D922`) |
| SMBIOS | `MacPro7,1` |
| OS | macOS 15.8.3 (`24H241`), Darwin 24 |

**Your hardware may differ.** Other `83J7` units ship with different Wi-Fi/Bluetooth cards, so verify your PCI and USB IDs before assuming the included driver stack applies.

## Status: what works, what does not

**Working**
- Native OLED 2880×1800 at 120 Hz, Metal acceleration, and brightness control (display mux and internal panel)
- Wi-Fi (Realtek stack), Bluetooth, and USB networking fallback
- Keyboard, touchpad (I2C polling), speakers, brightness keys
- Battery reporting and charging status
- Best recorded Geekbench 7 result: **1517 single / 8026 multi**, best-case, clean AC and maximum fan cooling

**Known problems — verify before relying on them**
- **Internal digital microphone is broken in this configuration.** The saved best-performance build (`MacPro7,1`) fails microphone initialization with `0xe00002d5` (initial PM idle acknowledgement missing). The equivalent `MacBookPro16,4` configuration works, at noticeably lower scores. Fixing this on `MacPro7,1` is untested work.
- **Sleep and wake are not safe.** Two vendor wake fixes caused UI freezes on this SKU, and display sleep remains unresolved. Do not close the lid and expect it to recover. Keep sleep disabled.
- **AirDrop is unverified.** No second Apple device was available, so no AirDrop test can be claimed either way.
- **CPU throttling is not fully explained.** Every benchmark reads `CPU LIMIT ICCMAX/PL4/OTHER`, which is a grouped reason, not a specific register. Windows on the same chassis scores higher.
- **`hw.busfrequency` reports 400000000**; harmless in this build, not investigated further.
- **OC loading depends on untested local extensions.** Four custom kernel extensions — IntelSpeedShiftEPP, FanMode, RazerSSTMicrophone, RaplDiag — and `TccOffset` load only from `/Library/Extensions` through the prebuilt `AuxiliaryKernelExtensions.kc` included here; see [heavily custom build details](docs/replication.md#known-limitations-and-that-bootloader).

**Not tested:** AirDrop continuity, sleep/wake, and the internal camera.

## What is in `EFI/`

- `BOOT/BOOTx64.efi` — from an official OpenCore 1.0.6 release, and **not from your snapshot's bootloader**. If you substitute your own bootloader, know which build you are substituting.
- `OC/` — the tested configuration:
  - `OpenCore.efi` — **a custom build matching no official release.** This is unusual and deliberate, and its behavior is documented in the replication guide. Replace it only if you know what you are doing.
  - `config.plist` — SMBIOS fields are placeholders. Generate your own serial, MLB, UUID, and ROM before use.
  - `Kexts/` — 32 kernel extensions, including the four custom ones plus their matching upstream injectors.
  - `ACPI/`, `Drivers/`, `Resources/` — the tested tables and boot picker assets.
  - `AuxiliaryKernelExtensions.kc` — a prebuilt kernelcollection that carries the five `/Library/Extensions` kexts, needed for fan mode and fan hotkey, microphone, and read-only power diagnostics to work. It is machine-neutral; your serial, MLB, UUID, and MAC do not appear in it.
- No backups, `.dSYM`, or `._*` files are committed.

## Starting point

**If you already have macOS installed**, this EFI is your path — see [docs/replication.md](docs/replication.md) §2.

**If you only have Windows**, do not start here. This repo ships an EFI, not a macOS installer. Use [1401](https://github.com/NullMoth/1401) (Windows, free) to build a minimal EFI and a macOS install stick, install macOS, then swap in this EFI to get 120 Hz, fan control, and the rest. The full route, including why the 1401 output is a boot-key rather than a destination, is in [docs/replication.md](docs/replication.md).

## Using it

1. Make a verified backup of your disk and existing EFI first, and test from a bootable USB before replacing the internal ESP.
2. Generate your own SMBIOS identifiers and write them into `config.plist` (`PlatformInfo → Generic`).
3. Copy `BOOT` and `OC` onto your EFI System Partition.
4. Install the `/Library/Extensions` kexts (or use the provided AuxiliaryKernelExtensions.kc) to get full functionality.
5. Disable sleep, as described in the safety section.
6. Boot, then check the relevant items: display and 120 Hz, brightness, input, audio, USB, network, mic.

See [docs/replication.md](docs/replication.md) for the full build record, assumptions, and safe changes.

## License

Third-party components retain their own licenses; some custom kernel extensions are derived from upstream projects credited in the guide.