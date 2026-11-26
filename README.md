# macOS Sequoia on the Motorola Moto Book 60

This project documents an OpenCore setup tested on one Motorola Moto Book 60 (machine type `83J7`) with an Intel Core 7 240H. It is a build guide and test record, not a downloadable EFI or an official macOS configuration. Start with the [replication guide](docs/replication.md).

| Component | Tested configuration |
| --- | --- |
| OS | macOS Sequoia 15.8.3 (`24H241`, Darwin 24) |
| CPU | Core 7 240H, 6 P-cores + 4 E-cores, 16 threads with Hyper-Threading enabled |
| Graphics | Intel iGPU `8086:A7AB`, Samsung OLED, 2880×1800 at 120 Hz with a custom WhateverXe build |
| Wireless | Realtek RTL8922AE Wi-Fi (`10EC:8922`) and RTL8922A Bluetooth (`0BDA:D922`); other units may ship with different cards |

## What worked and what didn't

- The internal OLED ran at native 120 Hz with acceleration and brightness control. The tested build also offered native 60 Hz; scaled HiDPI modes were removed after glitches.
- Realtek Wi-Fi and Bluetooth worked with the matched driver stack. AirDrop was **not verified** with an Apple peer; Android Quick Share is not a substitute for that test.
- The touchpad worked more smoothly with VoodooI2C polling. Sleep/wake caused freezes and a panic during testing; do not rely on lid-close sleep.
- The internal digital mic worked with the custom driver and publisher on a laptop SMBIOS. In the saved `MacPro7,1` profile it failed to publish. Use a laptop-SMBIOS design if internal mic support matters, and test capture before depending on it.
- Best recorded Geekbench 7 result: **1517 single-core / 8026 multi-core**, on AC with maximum fan cooling and several custom power-management changes. This is a single-machine result, not a baseline or a target.

**Before trying this:** Make a verified backup and keep a separate bootable recovery USB. Test on USB before changing the internal EFI. Match your panel, wireless hardware, and macOS build; a Moto Book 60 model name alone is not sufficient.

## What is included

Only the guide and reference settings. There is no macOS installer, prebuilt EFI, kernel collection, driver binary, raw log, or machine-specific SMBIOS data. Build or obtain compatible components from their upstream projects. Some local ports in the tested setup do not have matching builds in this repository; where a stock release cannot reproduce the result, the guide calls that out explicitly.
