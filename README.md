# CMF Phone (1) Fastboot ROM Flasher

### Getting Started
- This is a script to make it convenient for the user to return back to the stock rom or unbrick their device under any circumstances where the super partition size has not been changed (If the rom flashed is using the same super partition size as the stock rom then this script will always work, which is supposedly followed by all the custom roms). This script is quite helpful when the custom recoveries fail to flash the stock rom where they usually face errors due to messed up partitioning under the super partition. This script can be modified to flash custom roms as well and can be used on roms shipping the stock firmware.

### Usage
- Make sure you unpack the full stock ota zip and then unpack the `payload.bin` using [payload_dumper_go](https://github.com/ssut/payload-dumper-go) and then place the script suited to your operating system to the directory where the `*.img` files from `payload.bin` have been extracted. Finally reboot your device to the bootloader and then execute the script by double clicking the `flash_all.bat` file on windows or by doing this on a linux operating system in terminal after opening the terminal in the directory where the `*.img` files from `payload.bin` have been extracted :

```bash
chmod +x flash_all.sh && bash flash_all.sh
```

### Notes
- The script flashes the rom on slot A and it destroys the partitions on slot B to create space for the partitions which are being flashed on slot A. This is the reason why we are not including the ability to switch slots as the partitions would get destroyed on the inactive slot which is why the script flashes the partitions on the primary slot which is slot A.\
