# CMF Phone (1), Phone (2) Pro & Nothing (3a) Lite Fastboot ROM Flasher

## Getting Started

This script makes it convenient for users to return to the stock ROM or unbrick their device under circumstances where the super partition size has not been modified.

If the ROM being flashed uses the same super partition size as the stock ROM (which most custom ROMs follow), this script should work properly.

This script is especially useful when custom recoveries fail to flash stock ROMs due to partition issues inside the super partition.

It can also be modified to:
- Flash custom ROMs
- Flash ROMs shipping stock firmware

---

## Usage

### Windows / Linux / macOS / Bash Shell


Refer to [this guide](https://spike0en.github.io/nothing_archive/docs/guides#flashing-stock-rom-unbrick--downgrade) from the [Nothing Archive](https://github.com/spike0en).

---

# Flashing with Termux (No PC)

## Requirements

### Host Device
An Android device with:
- Termux installed
- OTG support or Type-C to Type-C cable

### Required Apps

Install the following apps on the host device:

- [Termux](https://play.google.com/store/apps/details?id=com.termux)
  - Used for executing the script

- [Termux:API](https://github.com/termux/termux-api/releases/download/v0.53.0/termux-api-app_v0.53.0+github.debug.apk)
  - Used for calling ADB/Fastboot commands

- [Payload Dumper Android](https://github.com/rajmani7584/Payload-Dumper-Android/releases/download/v4.1/PayloadDumperAndroid-4.1-stable.apk)
  - Used for extracting `payload.bin`

---

## Steps

1. Put the target device into **Fastboot Mode**.

2. Extract `payload.bin` into a new folder.

3. Copy `flash_all_termux.sh` into the same folder where the extracted `.img` files are located.

4. Open Termux and grant storage permission:

```bash
termux-setup-storage
```

5. Navigate to shared storage:

```bash
cd storage/shared
```

6. List folders:

```bash
ls
```

7. Open your extracted ROM folder:

```bash
cd your_folder_name
```

8. Run the flashing script:

```bash
bash flash_all_termux.sh
```

9. Follow the on-screen instructions.

## Acknowledgments

- [sid_imp](https://github.com/devvsid) for adapting the original bash script for termux.
- [rx6500M](https://github.com/rx6500M) for initial testing on other host devices.

---

## Notes

- The `.bat` script supports Windows 10 and above.
- The script flashes the ROM to **Slot A**.
- Partitions on **Slot B** are wiped to create space for flashing.
- Slot switching is intentionally disabled because inactive slot partitions are destroyed during the process.
- The script always flashes to the primary slot (`Slot A`).

---