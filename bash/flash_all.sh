#!/usr/bin/env bash
# SPDX-FileCopyrightText: Hellboy017, spike0en
# SPDX-License-Identifier: MIT

read_choice() {
    local prompt_msg="$1"
    local choice_var
    while true; do
        read -p "$prompt_msg [Y/n]: " choice_var
        case "$choice_var" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            "" ) return 0;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

Choice() {
    local message="$1"
    if ! read_choice "$message Continue?"; then
        echo "Operation aborted by user."
        exit 1
    fi
}

PlatformToolsSetup() {
    echo "#############################"
    echo "# SETTING UP PLATFORM TOOLS #"
    echo "#############################"
    if [[ ! -d "platform-tools-latest" ]]; then
        echo "Platform tools not found. Downloading..."
        if curl --fail --location https://dl.google.com/android/repository/platform-tools-latest-linux.zip -o platform-tools-latest.zip; then
            echo "Platform tools downloaded successfully."
            UnZipFile "platform-tools-latest.zip" "platform-tools-latest"
            echo "Platform tools extracted successfully."
            rm -f platform-tools-latest.zip
        else
            echo "[ERROR] Failed to download platform tools. Check internet connection and permissions."
            exit 1
        fi
    else
        echo "Platform tools already exist. Skipping download..."
    fi
}

FastbootValidation() {
    echo "###############################"
    echo "# CHECKING FASTBOOT EXECUTABLE #"
    echo "###############################"
    fastboot="./platform-tools-latest/platform-tools/fastboot"

    if [[ ! -f "$fastboot" ]]; then
        echo "[ERROR] Fastboot executable not found at '$fastboot'."
        echo "Please ensure platform tools are properly downloaded and extracted."
        read -p "Press Enter to exit..."
        exit 1
    fi
    if [[ ! -x "$fastboot" ]]; then
        echo "[ERROR] Fastboot executable at '$fastboot' is not executable."
        echo "Attempting to set executable permission..."
        chmod +x "$fastboot"
        if [[ ! -x "$fastboot" ]]; then
             echo "[ERROR] Failed to set executable permission. Please check file permissions."
             read -p "Press Enter to exit..."
             exit 1
        fi
        echo "[INFO] Executable permission set."
    fi

    if ! "$fastboot" --version > /dev/null; then
        echo "[ERROR] Fastboot executable is not functioning properly."
        echo "Try running \"$fastboot --version\" manually."
        read -p "Press Enter to exit..."
        exit 1
    fi

    echo "[SUCCESS] Fastboot executable found and verified."
}

UnZipFile() {
    local zip_file="$1"
    local dest_dir="$2"

    # Try unzip first, fallback to tar
    if command -v unzip > /dev/null; then
        unzip -o "$zip_file" -d "$dest_dir"
        if [[ $? -ne 0 ]]; then
            echo "Extraction using unzip failed. Trying with tar..."
            if [[ -d "$dest_dir" ]]; then
                echo "Directory \"$dest_dir\" exists, removing it..."
                rm -rf "$dest_dir"
            fi
            mkdir -p "$dest_dir"
            tar -xf "$zip_file" -C "$dest_dir"
            if [[ $? -ne 0 ]]; then
                echo "[ERROR] Extraction using tar also failed."
                echo "Please download the platform-tools manually from:"
                echo "Link: https://developer.android.com/tools/releases/platform-tools"
                echo "Then, extract it manually to ./platform-tools-latest/platform-tools/"
                exit 1
            fi
        fi
    else
        echo "unzip command not found. Trying with tar..."
        if [[ -d "$dest_dir" ]]; then
            echo "Directory \"$dest_dir\" exists, removing it..."
            rm -rf "$dest_dir"
        fi
        mkdir -p "$dest_dir"
        tar -xf "$zip_file" -C "$dest_dir"
        if [[ $? -ne 0 ]]; then
            echo "[ERROR] Extraction using tar failed."
            echo "Please install 'unzip' or ensure 'tar' can handle zip files."
            echo "Alternatively, download the platform-tools manually from:"
            echo "Link: https://developer.android.com/tools/releases/platform-tools"
            echo "Then, extract it manually to ./platform-tools-latest/platform-tools/"
            exit 1
        fi
    fi
}

CheckFastbootDevices() {
    local device_id
    if ! output=$("$fastboot" devices 2>&1); then
        echo "[ERROR] Fastboot command failed to execute."
        echo "Output: $output"
        echo "- Ensure fastboot is available and your environment is set up correctly."
        read -p "Press Enter to exit..."
        exit 1
    fi

    device_id=$(echo "$output" | awk 'NR==1{print $1}')

    if [[ -z "$device_id" ]]; then
        echo "[ERROR] No fastboot device detected!"
        echo "- Ensure your device is in fastboot mode."
        echo "- Check USB connection and try a different port/cable."
        echo "- Ensure you have correct udev rules set up for your device."
        echo "- Run \"sudo $fastboot devices\" manually to verify (permissions might be needed)."
        read -p "Press Enter to exit..."
        exit 1
    fi

    echo "[SUCCESS] Fastboot device detected: $device_id"
}

SetActiveSlot() {
    echo "[INFO] Setting active slot to A..."
    if ! "$fastboot" --set-active=a; then
        echo "[ERROR] Error occurred while switching to slot A. Aborting."
        read -p "Press Enter to exit..."
        exit 1
    fi
    echo "[SUCCESS] Active slot set to A."
}

WipeData() {
    echo "[INFO] Wiping userdata..."
    if ! "$fastboot" erase userdata; then
        echo "[ERROR] Erasing userdata failed"
    else
        echo "[SUCCESS] Erased userdata"
    fi

    echo "[INFO] Wiping metadata..."
    if ! "$fastboot" erase metadata; then
        echo "[ERROR] Erasing metadata failed"
    else
        echo "[SUCCESS] Erased metadata"
    fi
}

FlashImage() {
    local partition_opts="$1"
    local image_file="$2"

    if [[ ! -f "$image_file" ]]; then
        Choice "[WARNING] Image file '$image_file' not found for partition '$partition_opts'."
        return
    fi

    echo "[INFO] Flashing $image_file to $partition_opts..."
    if ! "$fastboot" flash $partition_opts "$image_file"; then
        Choice "[ERROR] Flashing $image_file to $partition_opts failed."
    fi
}

RebootFastbootD() {
    echo "##########################"
    echo "# REBOOTING TO FASTBOOTD #"
    echo "##########################"
    if ! "$fastboot" reboot fastboot; then
        echo "[ERROR] Error occurred while rebooting to fastbootd. Aborting."
        read -p "Press Enter to exit..."
        exit 1
    fi
    echo "[INFO] Waiting for device to enter fastbootd..."
    sleep 5
    CheckFastbootDevices
}

WipeSuperPartition() {
    local super_empty="super_empty.img"
    if [[ ! -f "$super_empty" ]]; then
         echo "[WARNING] '$super_empty' not found. Falling back to deleting/creating logical partitions."
         ResizeLogicalPartition
         return
    fi

    echo "[INFO] Wiping super partition using $super_empty..."
    if ! "$fastboot" wipe-super "$super_empty"; then
        echo "[WARNING] Wiping super partition failed. Falling back to deleting and creating logical partitions."
        ResizeLogicalPartition
    else
        echo "[SUCCESS] Super partition wiped."
    fi
}

ResizeLogicalPartition() {
    echo "[INFO] Resizing logical partitions (delete/create)..."
    if [[ "$junk_logical_partitions" != "null" ]]; then
        for i in $junk_logical_partitions; do
            for s in a b; do
                DeleteLogicalPartition "${i}_${s}-cow"
                DeleteLogicalPartition "${i}_${s}"
            done
        done
    fi

    for i in $logical_partitions; do
        for s in a b; do
            DeleteLogicalPartition "${i}_${s}-cow"
            DeleteLogicalPartition "${i}_${s}"
            CreateLogicalPartition "${i}_${s}" 1
        done
    done
    echo "[INFO] Finished resizing logical partitions."
}

DeleteLogicalPartition() {
    local partition_name="$1"
    local partition_is_cow=false

    if echo "$partition_name" | grep -q -- "-cow"; then
        partition_is_cow=true
    fi

    echo "[INFO] Deleting logical partition: $partition_name"
    if ! "$fastboot" delete-logical-partition "$partition_name"; then
        if [[ "$partition_is_cow" == "false" ]]; then
            Choice "[ERROR] Deleting partition $partition_name failed."
        else
             echo "[DEBUG] Ignoring potential error deleting COW partition: $partition_name"
        fi
    fi
}

CreateLogicalPartition() {
    local partition_name="$1"
    local partition_size="$2"
    echo "[INFO] Creating logical partition: $partition_name with size $partition_size"
    if ! "$fastboot" create-logical-partition "$partition_name" "$partition_size"; then
        Choice "[ERROR] Creating partition $partition_name failed."
    fi
}

echo "###############################"
echo "# Pacman Fastboot ROM Flasher #"
echo "###############################"
echo

# Check root privileges
if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] This script requires root privileges to run potentially."
  echo "Attempting to relaunch with sudo..."
  sudo bash "$0" "$@"
  exit $?
fi
echo "[INFO] Running with root privileges."
echo

# Define partitions
boot_partitions="boot dtbo init_boot vendor_boot"
main_partitions="odm_dlkm product system_dlkm vendor_dlkm"
firmware_partitions="apusys audio_dsp ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz lk logo mcf_ota mcupm md1img mvpu_algo pi_img scp spmfw sspm tee vcp"
logical_partitions="odm_dlkm odm vendor_dlkm product vendor system_dlkm system_ext system"
junk_logical_partitions="null"
vbmeta_partitions="vbmeta vbmeta_system vbmeta_vendor"

# Set working directory
WORK_DIR=$(dirname "$(realpath "$0")")
echo "[INFO] Setting working directory to: \"$WORK_DIR\""
if ! cd "$WORK_DIR"; then
    echo "[ERROR] Failed to set working directory: \"$WORK_DIR\""
    read -p "Press Enter to exit..."
    exit 1
fi
echo "[SUCCESS] Working directory set to: \"$(pwd)\""
echo

echo "############################"
echo "#  PRE-REQUIREMENTS CHECK  #"
echo "############################"

if ! read_choice "Is your device bootloader unlocked?"; then
    echo "To use this script, your device bootloader must be unlocked."
    echo "Please unlock it before proceeding."
    read -p "Press Enter to exit..."
    exit 1
fi

if ! read_choice "Are you in bootloader mode (fastboot)?"; then
    echo "Ensure your device is in bootloader mode before proceeding."
    echo "You can enter bootloader mode by holding Power + Volume Down or using:"
    echo "adb reboot bootloader"
    read -p "Press Enter to exit..."
    exit 1
fi

if ! read_choice "Are fastboot drivers/udev rules properly installed/configured?"; then
    echo "Please install/configure the proper fastboot drivers/rules before proceeding."
    echo "For Linux, ensure you have appropriate udev rules set up."
    echo "See: https://developer.android.com/studio/run/device#setting-up-udev"
    read -p "Press Enter to exit..."
    exit 1
fi

echo "All pre-requirements met! Proceeding..."
echo

# ----------------------------------
#  PLATFORM TOOLS SETUP & VALIDATION
# ----------------------------------
PlatformToolsSetup
FastbootValidation
echo

echo "#############################"
echo "# CHECKING FASTBOOT DEVICES #"
echo "#############################"
CheckFastbootDevices
echo

echo "#############################"
echo "# CHANGING ACTIVE SLOT TO A #"
echo "#############################"
SetActiveSlot
echo

echo "###################"
echo "# FORMATTING DATA #"
echo "###################"
if read_choice "Wipe Data (userdata and metadata)?"; then
    WipeData
else
    echo "Data wipe canceled."
fi
echo

echo "############################"
echo "# FLASHING BOOT PARTITIONS #"
echo "############################"
slot="a"
if read_choice "Flash images on both slots (A and B)? If unsure, say N."; then
    slot="all"
fi

if [[ "$slot" == "all" ]]; then
    for i in $boot_partitions; do
        for s in a b; do
            FlashImage "${i}_${s}" "${i}.img"
        done
    done
else
    for i in $boot_partitions; do
        FlashImage "${i}_${slot}" "${i}.img"
    done
fi
echo

echo "#####################"
echo "# FLASHING FIRMWARE #"
echo "#####################"
if [[ "$slot" == "all" ]]; then
    for i in $firmware_partitions; do
        for s in a b; do
            FlashImage "${i}_${s}" "${i}.img"
        done
    done
else
    for i in $firmware_partitions; do
        FlashImage "${i}_${slot}" "${i}.img"
    done
fi
echo

echo "[INFO] Flashing Preloader..."
if [[ "$slot" == "all" ]]; then
    for s in a b; do
        FlashImage "preloader_${s}" "preloader_raw.img"
    done
else
    FlashImage "preloader_${slot}" "preloader_raw.img"
fi
echo

echo "###################"
echo "# FLASHING VBMETA #"
echo "###################"
disable_avb=0
if read_choice "Disable android verified boot (AVB)? If unsure, say N. Bootloader won't be lockable if you select Y."; then
    disable_avb=1
    echo "[WARNING] Android Verified Boot will be disabled."
fi

for s in a b; do
    if [[ "$disable_avb" -eq 1 ]]; then
        FlashImage "vbmeta_${s} --disable-verity --disable-verification" "vbmeta.img"
    else
        FlashImage "vbmeta_${s}" "vbmeta.img"
    fi
done
echo

echo "####################################"
echo "# FLASHING OTHER VBMETA PARTITIONS #"
echo "####################################"
for i in $vbmeta_partitions; do
    if [[ "$i" == "vbmeta" ]]; then
        continue
    fi
    for s in a b; do
        if [[ "$disable_avb" -eq 1 ]]; then
            FlashImage "${i}_${s} --disable-verity --disable-verification" "${i}.img"
        else
            FlashImage "${i}_${s}" "${i}.img"
        fi
    done
done
echo

echo "###############################"
echo "# FLASHING LOGICAL PARTITIONS #"
echo "###############################"
RebootFastbootD

if [[ ! -f "super.img" ]]; then
    echo "[INFO] super.img not found. Flashing logical partitions individually."
    if [[ -f "super_empty.img" ]]; then
        WipeSuperPartition
    else
        echo "[INFO] super_empty.img not found. Resizing logical partitions manually."
        ResizeLogicalPartition
    fi

    echo "[INFO] Flashing logical partitions to slot A..."
    for i in $logical_partitions; do
        FlashImage "${i}_a" "${i}.img"
    done

else
    echo "[INFO] super.img found. Flashing super partition directly..."
    FlashImage "super" "super.img"
fi
echo

echo "#############"
echo "# REBOOTING #"
echo "#############"
SetActiveSlot

if read_choice "Reboot to system now? If unsure, say Y."; then
    echo "[INFO] Rebooting device to system..."
    "$fastboot" reboot
else
    echo "[INFO] Reboot canceled. Device remains in fastbootd/fastboot mode."
fi
echo

echo "########"
echo "# DONE #"
echo "########"
echo "Stock firmware flashing process completed."
if [[ "$disable_avb" -eq 0 ]]; then
    echo "You may now optionally re-lock the bootloader."
else
    echo "NOTE: Bootloader cannot be locked because AVB was disabled."
fi
echo

read -p "Press Enter to exit..."
exit 0