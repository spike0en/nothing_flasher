# Nothing Flasher

<img src="./logo.png" width="96" alt="Nothing Flasher Logo">

[![Stars](https://img.shields.io/github/stars/spike0en/nothing_flasher?logo=github&color=D4AF37)](https://github.com/spike0en/nothing_flasher/stargazzers)
[![Contributors](https://img.shields.io/github/contributors/spike0en/nothing_flasher?logo=github&color=9B5DE5)](https://github.com/spike0en/nothing_flasher/graphs/contributors)
[![Forks](https://img.shields.io/github/forks/spike0en/nothing_flasher?logo=github&color=468FAF)](https://github.com/spike0en/nothing_flasher/network/members)

---

## About 📋:

- This collection of fastboot flashing scripts is designed for flashing stock [Nothing OS firmware](https://github.com/spike0en/nothing_archive) on [Nothing](https://nothing.tech) & [CMF](https://cmf.tech) devices, supporting both Windows and bash platforms.
- The script helps users revert to stock ROMs or unbrick devices, especially when the super partition size remains unchanged. It's useful when custom recoveries fail to flash the stock ROM due to partition issues. The script can also be adapted to flash custom ROMs that use the same partition size as the stock firmware.

---

## Download 📥: 

### ⚪ Nothing 
- **Phone (1)**: [Windows](https://github.com/spike0en/nothing_fastboot_flasher/blob/spacewar/Windows/flash_all.bat) | [Bash](https://github.com/spike0en/nothing_fastboot_flasher/blob/spacewar/bash/flash_all.sh)  
- **Phone (2)**: [Windows](https://github.com/spike0en/nothing_fastboot_flasher/blob/pong/Windows/flash_all.bat) | [Bash](https://github.com/spike0en/nothing_fastboot_flasher/blob/pong/bash/flash_all.sh)  
- **Phone (2a) & (2a) Plus**: [Windows](https://github.com/spike0en/nothing_fastboot_flasher/blob/pacman/Windows/flash_all.bat) | [Bash](https://github.com/spike0en/nothing_fastboot_flasher/blob/pacman/bash/flash_all.sh)
- **Phone (3a) & (3a) Pro**: [Windows](https://github.com/spike0en/nothing_fastboot_flasher/blob/asteroids/Windows/flash_all.bat) | [Bash](https://github.com/spike0en/nothing_fastboot_flasher/blob/asteroids/bash/flash_all.sh)

### 🔴 CMF by Nothing  
- **Phone 1**: [Windows](https://github.com/spike0en/nothing_fastboot_flasher/blob/tetris/Windows/flash_all.bat) | [Bash](https://github.com/spike0en/nothing_fastboot_flasher/blob/tetris/bash/flash_all.sh)

---

## Usage ⚙️:

- Refer to [this guide](https://github.com/spike0en/nothing_archive?tab=readme-ov-file#flashing-the-stock-rom-using-fastboot-) for preparing the flashing folder with the respective stock firmware images and run the flashing script for your respective platform.
- Alternatively, users can dump the `payload.bin` using [payload_dumper_go](https://github.com/ssut/payload-dumper-go) by unpacking a full stock firmware zip and then place the script suited to your operating system in the directory where the `*.img` files from `payload.bin` have been extracted. Finally, reboot your device to the bootloader and then run the flashing script.
- The script can be executed by double-clicking the `flash_all.bat` file on Windows or by running the following command in a terminal on a bash-supported operating system (after navigating to the directory where the `*.img` files from `payload.bin` have been extracted):

  ```bash
  chmod +x flash_all.sh
  bash flash_all.sh
  ```

---

## Notes 📝:

- A working internet connection is required to download the latest version of `platform-tools` if it's not already present in the working directory.
- Make sure to download the script that corresponds to your device model's codename and platform (Windows or bash).
- The script flashes the ROM on slot A and erases the partitions on slot B to free up space for the new partitions. Slot switching is not included, as the inactive slot would lose data. The script focuses on flashing partitions to slot A.
- Ensure that you have working [Google USB drivers](https://developer.android.com/studio/run/win-usb) installed before running the script.
- Scripts must be executed in bootloader mode with fastboot access. Also, verify that the `Android Bootloader Interface` is listed in your Windows Device Manager.
- Do not reboot your device into the system before confirming all partitions have been successfully flashed.
- For best results, use the latest Windows installation with functional `curl`, `tar`, and `PowerShell`. Missing binaries in modified installations can cause errors.
- If the `platform-tools` download or unzip process fails, or if `fastboot.exe` is not executable despite following the above steps, manually download the latest version from [here](https://developer.android.com/tools/releases/platform-tools). Unzip it into the same directory as the script, ensuring the following structure:

  ```bash
  ├── platform-tools-latest/
  │   ├── platform-tools/
  │   │   ├── ...binaries
  ├── flashing script (flash_all.bat / flash_all.sh)
  └── Required stock firmware image files
  ```

---

## Acknowledgments 🤝:

- [HELLBOY017](https://github.com/HELLBOY017/Pong_fastboot_flasher)
- [arter97](https://github.com/arter97/Pong_fastboot_flasher)
- [AntoninoScordino](https://github.com/nothing-Pacman/flashtool)
- [Phatwalrus](https://github.com/PHATWalrus)
- [XelXen](https://github.com/XelXen)

---
