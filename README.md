# Nothing Flasher

<img src="./assets/logo.png" width="96" alt="Nothing Flasher Logo">

[![Hits](https://hitscounter.dev/api/hit?url=https%3A%2F%2Fgithub.com%2Fspike0en%2Fnothing_flasher&label=Hits&icon=github&color=%23b02a37&labelColor=2E2E3F)](https://github.com/spike0en/nothing_flasher)
[![Stars](https://img.shields.io/github/stars/spike0en/nothing_flasher?logo=github&color=D4AF37)](https://github.com/spike0en/nothing_flasher/stargazzers)
[![Forks](https://img.shields.io/github/forks/spike0en/nothing_flasher?logo=github&color=468FAF)](https://github.com/spike0en/nothing_flasher/network/members)

## Overview

- This collection of fastboot flashing scripts is designed for flashing stock [Nothing OS firmware](https://github.com/spike0en/nothing_archive) on [Nothing](https://nothing.tech) & [CMF](https://cmf.tech) devices, supporting Windows.
- The script helps users revert to stock ROMs or unbrick devices, especially when the super partition size remains unchanged. It's useful when custom recoveries fail to flash the stock ROM due to partition issues. The script can also be adapted to flash custom ROMs that use the same partition size as the stock firmware.

## Supported Devices

| # | Device | Codename | SoC | Flow Type |
|---|--------|----------|-----|-----------|
| 1 | Nothing Phone (1) | Spacewar | Snapdragon 778G+ | Qualcomm Slot-A |
| 2 | Nothing Phone (2) | Pong | Snapdragon 8+ Gen 1 | Qualcomm Slot-A |
| 3 | Nothing Phone (2a) | Pacman | Dimensity 7200 Pro | MediaTek |
| 4 | CMF Phone 1 / Phone 2 Pro | Galaga-Tetris | Dimensity 7300 | MediaTek |
| 5 | Nothing Phone (3a) Series | Asteroids | Snapdragon 7s Gen 3 | Qualcomm Inactive-Slot |
| 6 | Nothing Phone (4a) | Frogger | Snapdragon 7s Gen 3 | Qualcomm Inactive-Slot |
| 7 | Nothing Phone (3) | Metroid | Snapdragon 8 Elite | Qualcomm Slot-A |

## Prerequisites

- **Unlocked bootloader** on your Nothing/CMF device
- **Device in fastboot mode** (hold Power + Volume Down, release Power when logo appears — or run `adb reboot bootloader`)
- **Fastboot drivers installed** — [Google USB Drivers](https://developer.android.com/studio/run/win-usb) (should show as *Android Bootloader Interface* in Device Manager)
- **Firmware images** extracted in the same directory as `flasher.bat`
- **Windows OS** (the script auto-elevates to Administrator)

## Usage

### Quick Start

1. Download and extract the firmware images for your device into the same folder as `flasher.bat`
2. Double-click `flasher.bat` (or right-click → Run as Administrator)
3. Select your device from the numbered menu
4. Follow the on-screen prompts

### Step-by-Step Flow

```
┌─────────────────────────────────┐
│  1. Select Device Model         │
│  2. Pre-requirements Check      │
│  3. Image Integrity Verification│ ← Optional (SHA-256 checksums)
│  4. Platform Tools Auto-Setup   │ ← Downloads fastboot if needed
│  5. Device Detection            │ ← With retry (3 attempts)
│  6. Flashing Flow               │ ← Auto-selected per device
│  7. Reboot                      │
└─────────────────────────────────┘
```

### Hash Verification (Optional)

Before flashing, the tool can verify image integrity using SHA-256 checksums:

1. Download the `.sha256` checksum file from [Nothing Archive Releases](https://github.com/spike0en/nothing_archive/releases)
2. Place it in the same directory as the firmware images
3. When prompted, select **Y** to begin verification

### Platform Tools

The flasher automatically downloads Google's platform-tools (containing `fastboot.exe`) if not already present. The version is configurable per device in the config file:

- **Pinned version** (e.g., `r33.0.0`) — downloads that specific release
- **Latest** — downloads the most recent platform-tools

---

## Architecture

### Design Philosophy

Instead of maintaining separate scripts for each device (which leads to ~85% duplicated code), Nothing Flasher uses a **config-driven architecture**:

```
flasher.bat              ← Single script with all shared logic + 3 flow engines  
configs/
  ├── spacewar.cfg       ← Device-specific partition layout + flags
  ├── pong.cfg
  ├── pacman.cfg
  ├── galaga-tetris.cfg
  ├── asteroids.cfg
  ├── frogger.cfg
  └── metroid.cfg
```

The device menu is **auto-generated** by scanning `configs\*.cfg` — no hardcoded device lists.

### Config File Format

Each `.cfg` file defines a device's complete flashing profile:

```ini
# Nothing Phone (2) — Pong
# Qualcomm SM8475 (Snapdragon 8+ Gen 1)

DEVICE_NAME=Nothing Phone (2)
CODENAME=pong
FLOW_TYPE=qualcomm_slotA
PLATFORM_TOOLS_VERSION=r33.0.0

# Feature Flags
SUPPORTS_AVB_DISABLE=1
SUPPORTS_DUAL_SLOT_PROMPT=1
HAS_PRELOADER=0
HAS_DLKM_SEPARATE=0

# Partition Layout
BOOT_PARTITIONS=boot vendor_boot dtbo recovery
FIRMWARE_PARTITIONS=abl aop bluetooth cpucp devcfg dsp ...
LOGICAL_PARTITIONS=system system_ext product vendor vendor_dlkm odm
VBMETA_PARTITIONS=vbmeta_system vbmeta_vendor
```

| Config Key | Description |
|-----------|-------------|
| `DEVICE_NAME` | Human-readable name shown in menu |
| `CODENAME` | Internal device codename |
| `FLOW_TYPE` | Flashing flow engine (`qualcomm_slotA`, `qualcomm_inactive`, `mediatek`) |
| `PLATFORM_TOOLS_VERSION` | `latest` or a pinned version like `r33.0.0` |
| `SUPPORTS_AVB_DISABLE` | `1` to offer AVB disable prompt, `0` to skip |
| `SUPPORTS_DUAL_SLOT_PROMPT` | `1` to offer "flash both slots?" prompt |
| `HAS_PRELOADER` | `1` if device has a MediaTek preloader partition |
| `HAS_DLKM_SEPARATE` | `1` if DLKM partitions need separate handling (delete → create → flash) |
| `BOOT_PARTITIONS` | Space-separated list of boot partition names |
| `FIRMWARE_PARTITIONS` | Space-separated list of firmware partition names |
| `LOGICAL_PARTITIONS` | Space-separated list of logical (super) partition names |
| `DLKM_PARTITIONS` | Space-separated list of DLKM partition names (if `HAS_DLKM_SEPARATE=1`) |
| `VBMETA_PARTITIONS` | Space-separated list of secondary vbmeta partition names |

### Flashing Flows

The flasher implements three distinct flashing engines, selected automatically based on the device's `FLOW_TYPE`:

#### Flow 1: `qualcomm_slotA`
**Devices:** Phone (1), Phone (2), Phone (3)

```
Set Active Slot → A
Wipe Data? → [optional]
Flash Both Slots? → [optional]
Flash Boot Partitions → slot(s)
Flash VBMeta → slot(s) [with optional AVB disable]
Reboot → FastbootD
Flash Firmware → slot(s)
Flash Logical Partitions → generic names
Flash Sub-VBMeta Partitions → [with optional AVB disable]
Reboot → System
```

Standard Qualcomm flow. Forces active slot to A, flashes everything to slot A (or both if selected), and reboots.

#### Flow 2: `qualcomm_inactive`
**Devices:** Phone (3a) Series, Phone (4a)

```
Detect Active Slot → determine inactive slot
Wipe Data? → [optional]
Flash Boot Partitions → inactive slot only
Flash VBMeta → inactive slot only
Reboot → FastbootD
Flash DLKM → inactive slot only (delete → create → flash)
Flash Firmware → BOTH slots unconditionally
Flash Logical Partitions → inactive slot only
Swap → to inactive slot
Reboot → System
```

> **Why inactive-slot targeting?** This ensures compatibility for custom ROMs using kernel version **6.6**, avoiding issues caused by incompatible kernel modules from the older 6.1 version used by OEM firmware. Boot, vbmeta, DLKM, and logical partitions are flashed only to the inactive slot; firmware is flashed to both slots (slot-agnostic binaries). The slot is then swapped so the device boots into the freshly flashed firmware.

#### Flow 3: `mediatek`
**Devices:** Phone (2a), CMF Phone 1 / Phone 2 Pro

```
Set Active Slot → A
Wipe Data? → [optional]
Flash Both Slots? → [optional]
Flash Boot Partitions → slot(s)
Flash Firmware → slot(s)
Flash VBMeta → slot A [with optional AVB disable]
Flash Preloader → slot(s)
Flash Sub-VBMeta Partitions → slot A [with optional AVB disable]
Reboot → FastbootD
Flash Logical Partitions → slot A
Set Active Slot → A
Reboot → System
```

MediaTek flow includes preloader flashing (unique to MTK devices) and sets the active slot at both the start and end of the process.

---

## Adding Support for a New Device

Adding a new device requires **zero code changes** — just create a config file.

### Step 1: Identify the Device Profile

Determine the following for your device:
- **Codename** (e.g., `breakout`)
- **SoC platform** → determines which `FLOW_TYPE` to use
- **Partition layout** → list all boot, firmware, logical, vbmeta, and DLKM partitions
- **Platform tools version** requirement
- **Feature flags** (AVB disable support, preloader, dual-slot prompt, separate DLKM)

### Step 2: Create the Config File

Create `configs\<codename>.cfg`:

```ini
# Nothing Phone (X) — Breakout
# Qualcomm SM#### (Snapdragon XXX)

DEVICE_NAME=Nothing Phone (X)
CODENAME=breakout
FLOW_TYPE=qualcomm_slotA
PLATFORM_TOOLS_VERSION=latest

SUPPORTS_AVB_DISABLE=1
SUPPORTS_DUAL_SLOT_PROMPT=1
HAS_PRELOADER=0
HAS_DLKM_SEPARATE=0

BOOT_PARTITIONS=boot init_boot vendor_boot dtbo recovery
FIRMWARE_PARTITIONS=abl aop aop_config bluetooth ...
LOGICAL_PARTITIONS=system system_ext product vendor odm
VBMETA_PARTITIONS=vbmeta_system vbmeta_vendor
```

### Step 3: Done

Run `flasher.bat` — your new device will automatically appear in the selection menu.

### Adding a New SoC Family

If a future device uses a completely new SoC family (e.g., Exynos, Tensor) that requires a different flashing flow:

1. Add a new `FLOW_TYPE` value (e.g., `exynos`)
2. Add a `:FlowExynos` subroutine to `flasher.bat` with the device-specific flashing sequence
3. Add the flow type to the flow router section
4. Create device configs with `FLOW_TYPE=exynos`

---

## Project Structure

```
.
├── flasher.bat                 # Unified flasher script
├── configs/                    # Device configuration files
│   ├── spacewar.cfg            #   Phone (1)
│   ├── pong.cfg                #   Phone (2)
│   ├── pacman.cfg              #   Phone (2a)
│   ├── galaga-tetris.cfg       #   CMF Phone 1 / Phone 2 Pro
│   ├── asteroids.cfg           #   Phone (3a) Series
│   ├── frogger.cfg             #   Phone (4a)
│   └── metroid.cfg             #   Phone (3)
├── platform-tools/             # Auto-downloaded (fastboot.exe lives here)
└── *.img                       # Firmware images (user-provided)
```

## License

MIT — see source file headers for attribution.

## Credits

- [Hellboy017](https://github.com/Hellboy017)
- [arter97](https://github.com/arter97)
- [AntoninoScordino](https://github.com/nothing-Pacman/flashtool)
- [PHATWalrus](https://github.com/PHATWalrus)