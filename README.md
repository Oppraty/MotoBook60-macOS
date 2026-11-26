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
- Native OLED 2880×1800 at 120 Hz, Metal acceleration, brightness control (display mux and internal panel)
- Wi-Fi (Realtek stack), Bluetooth, USB networking fallback
- Keyboard, touchpad (I2C polling), speakers, brightness keys
- Battery reporting and charging status
- Best recorded Geekbench 7 result: **1517 single / 8026 multi** (clean AC, maximum fan cooling). Windows on the same chassis reaches 2451/12065.

**Known problems — verify before relying on them**
- **Internal digital microphone is broken in this configuration.** The `MacPro7,1` profile fails microphone initialization with `0xe00002d5` (initial PM idle acknowledgement missing). A `MacBookPro16,4` configuration works, at noticeably lower scores. Fixing this on `MacPro7,1` is untested work.
- **Sleep and wake are not safe.** Two vendor wake fixes caused UI freezes on this SKU, and display sleep stays unresolved. Do not close the lid and expect it to recover. Keep sleep disabled.
- **AirDrop is unverified.** No second Apple device was available, so no AirDrop claim can be made either way.
- **CPU throttling is not fully explained.** Every benchmark reads `CPU LIMIT ICCMAX/PL4/OTHER`, a grouped reason rather than a specific register. Write-permission on the usual PL1/PL2/PL4 registers is not the answer here.
- `hw.busfrequency` reports `400000000`; harmless in this build, not investigated further.

**Not tested:** AirDrop continuity, sleep/wake, and the internal camera.

## What is in the repository

| Path | What it is |
| --- | --- |
| `EFI/BOOT/BOOTx64.efi` | From the **official OpenCore 1.0.6 release**. The interior `EFI/OC/OpenCore.efi` is **a custom build matching no release** — unusual, deliberate, and documented. Replace it only if you know what you are doing. |
| `EFI/OC/config.plist` | The tested configuration. SMBIOS fields are placeholders — generate your own serial, MLB, UUID, and ROM before use. |
| `EFI/OC/Kexts/` | 32 kernel extensions: the four custom ones, the stock driver stack, and the two plist-only USB injectors. |
| `EFI/OC/ACPI/`, `Drivers/`, `Resources/` | The tested ACPI tables, EFI drivers, and boot picker assets. |
| `EFI/OC/AuxiliaryKernelExtensions.kc` | A **prebuilt kernelcollection built on one machine** — see the warning below. |
| `install-custom-kexts.sh` | Builds the kernelcollection on *your* machine instead. See below. |
| `tools/publish`, `tools/mic-input-check` | The userspace microphone publisher and capture check tool the mic kext needs. |
| `docs/replication.md` | The full build record, hardware details, and safe changes. |

No backups, `.dSYM`, or `._*` files are committed.

### The prebuilt AuxiliaryKernelExtensions.kc is not machine-neutral

This is the one part of the repo that is genuinely machine-specific, and it should not be used as-is. `OC/AuxiliaryKernelExtensions.kc` was built on the machine this EFI came from, so it carries **that machine's** kernel extensions alongside the five this laptop needs — including third-party HighPoint storage drivers for hardware this laptop does not have. Those are inert but wrong, and shipping them hands readers a collection matched to someone else's PC.

The five kexts this build actually needs live in `/Library/Extensions`, not on the EFI partition:

| Kext | Role |
| --- | --- |
| `IntelSpeedShiftEPP.kext` | HWP EPP handling; treats unknown power source as AC and forces Desired=0 |
| `FanMode.kext` | Fan mode and DYTC via vendor ACPI `VPCW`/`VPCR`/`DYTC` |
| `RazerSSTMicrophone.kext` | Internal digital mic over Intel DSP `8086:51CA` (see the mic caveat above) |
| `RaplDiag.kext` | Read-only RAPL power-limit diagnostics |
| `TccOffset.kext` | `tccoffset=2` thermal offset — **source not included**, binary not in this repo |

Use `install-custom-kexts.sh` to install the four available ones and rebuild the collection on your own machine. Deleting the shipped `.kc` after doing so is the correct outcome, not a problem.

## Install the custom kernel extensions

```bash
sudo ./install-custom-kexts.sh
```

Run it from inside this repository, as root. It:

1. Verifies each of the four kext binaries against a pinned SHA-256 before touching anything.
2. Installs them to `/Library/Extensions` (existing ones are timestamped-backup aside first).
3. Copies `tools/publish` and `tools/mic-input-check` into place.
4. Rebuilds the Auxiliary Kernel Collection with `kmutil`, refusing to install the result if any expected bundle identifier is missing.
5. Arms a **five-minute auto-restore watchdog** as a LaunchDaemon.

The watchdog is the part worth understanding. After you reboot, you have five minutes to say the boot was fine:

```bash
sudo touch /var/db/custom-kexts-pending.ok    # boot was good
sudo rm -f /var/db/custom-kexts-pending /var/db/custom-kexts-pending.ok
```

If you say nothing, the watchdog puts the previous kernelcollection back — so a bad build is less likely to leave you stranded. It was tested against six scenarios: confirmed, silent, idle, cleared mid-wait, missing backup, and already-identical. **It is a safety net, not a guarantee**; it only helps if the machine still boots far enough for the daemon to run.

Note these binaries are unsigned. That is fine under this build's SIP configuration, and is not fine without it.

## Starting point

**If you already have macOS installed.** Mount your ESP, generate your own SMBIOS identifiers, copy `BOOT` and `OC` across, then run `install-custom-kexts.sh`. Full steps and the verification order are in [docs/replication.md](docs/replication.md) §2.

**If you only have Windows, with no Mac and no macOS installed.** This repo ships an EFI, not a macOS installer, so it cannot be your first step. Use [1401](https://github.com/NullMoth/1401) (Windows, free) to build a minimal EFI and a macOS install stick, install macOS, then swap in this EFI. The generated build already has Wi-Fi, Bluetooth, keyboard, and touchpad for this hardware — see [docs/replication.md](docs/replication.md) for the verified device IDs and the full route. It will not have 120 Hz, fan control, or the mic stack; those are what the swap adds.

## Using it

1. **Make recovery possible first.** Back up the disk, and test from a bootable USB before replacing the internal ESP. A second OpenCore folder on the same partition is not a recovery plan. The fallback described above — booting the 1401 stick or a backed-up EFI — is what you use if this one fails.
2. **Generate your own SMBIOS identifiers** and write them into `config.plist` (`PlatformInfo → Generic`). Never reuse another machine's serial, MLB, UUID, or ROM. Leaving the placeholders will not boot properly and will not enable Apple services.
3. **Copy `BOOT` and `OC`** onto the EFI System Partition.
4. **Run `install-custom-kexts.sh`** for the fan mode, thermal offset, and diagnostic kexts, or skip it and accept their absence.
5. **Disable sleep:** `sudo pmset -a sleep 0`. Keep it off until you have verified wake on your own hardware.
6. **Reboot and verify**, in this order, stopping at the first failure: `sw_vers` and CPU counts → display, 120 Hz, brightness keys → keyboard and touchpad → speaker output → network → `kmutil showloaded` → mic.

Windows users should also turn off Fast Startup before multi-booting, since it can leave the filesystem locked.

See [docs/replication.md](docs/replication.md) for the full build record, hardware details, assumptions, safe changes, and the rollback path.

## License

Third-party components retain their own licenses; some custom kernel extensions are derived from upstream projects credited in the guide.