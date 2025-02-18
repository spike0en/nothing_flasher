# Nothing Phone (1) Fastboot ROM Flasher

### Getting Started
- This script is designed to make it convenient for users to return to the stock ROM or unbrick their device in situations where the super partition size has not been changed. If the ROM being flashed uses the same super partition size as the stock ROM, this script will always work, which is typically the case with all custom ROMs. 
- It is particularly helpful when custom recoveries fail to flash the stock ROM, often encountering errors due to issues with partitioning under the super partition. 
- Additionally, this script can be modified to flash custom ROMs and can be used with ROMs that include the stock firmware.

### Usage
- Before proceeding, ensure that the script is tailored to your operating system. Place the script in the directory where the required stock partition `*.img` files have been extracted. Finally, reboot your device into the bootloader and execute the script by double-clicking the `flash_all.bat` file on Windows, or by running the following command in a terminal on a Linux operating system after navigating to the directory where the `*.img` files from `payload.bin` have been extracted:

    ```bash
    chmod +x flash_all.sh && bash flash_all.sh
    ```

### Notes
- Windows 10+ supported.
- For a bash-supporting operating system, the `curl` and `unzip` utilities should be installed on your system.
- The script flashes the ROM on slot A and destroys the partitions on slot B to create space for the partitions being flashed on slot A. This is why we do not include the ability to switch slots; the partitions on the inactive slot would be destroyed. Therefore, the script only flashes the partitions on the primary slot, which is slot A.

### Thanks to
- [HELLBOY017](https://github.com/HELLBOY017) and all the contributors for their efforts in refining the script.