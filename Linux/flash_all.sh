#!/usr/bin/env bash

echo "#############################################################################"
echo "#                       Tetris Fastboot ROM Flasher                         #"
echo "#                           Developed/Tested By                             #"
echo "#  HELLBOY017, viralbanda, spike0en, PHATwalrus, arter97, AntoninoScordino  #"
echo "#                    [CMF Phone (1) Telegram Dev Team]                      #"
echo "#############################################################################"

##----------------------------------------------------------##
if ! command -v wget && ! command -v unzip; then
    echo "Required utilities not found."
    if command -v apt; then
        sudo apt install -y wget unzip
    elif command -v pacman; then
        sudo pacman -S --noconfirm wget unzip
    elif command -v dnf; then
        sudo dnf install -y wget unzip
    else
        echo "Please, install 'wget' and 'unzip' before executing this script."
        exit 0
    fi
fi

if [ ! -d platform-tools ]; then
    wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip -O "${PWD}"/platform-tools-latest.zip
    unzip "${PWD}"/platform-tools-latest.zip
    rm "${PWD}"/platform-tools-latest.zip
fi

fastboot=${PWD}/platform-tools/fastboot

if [ ! -f "$fastboot" ] || [ ! -x "$fastboot" ]; then
    echo "Fastboot cannot be executed, exiting"
    exit 1
fi

# Partition Variables
boot_partitions="boot dtbo init_boot vendor_boot"
firmware_partitions="apusys ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz lk logo mcf_ota mcupm modem pi_img scp spmfw sspm tee vcp"
logical_partitions="odm odm_dlkm product vendor vendor_dlkm system_ext system system_dlkm"
vbmeta_partitions="vbmeta vbmeta_system vbmeta_vendor"

function SetActiveSlot {
    if ! $fastboot --set-active=a; then
        echo "Error occured while switching to slot A. Aborting"
        exit 1
    fi
}

function handle_fastboot_error {
    if [ ! "$FASTBOOT_ERROR" = "n" ] || [ ! "$FASTBOOT_ERROR" = "N" ] || [ ! "$FASTBOOT_ERROR" = "" ]; then
       exit 1
    fi  
}

function ErasePartition {
    if ! $fastboot erase "$1"; then
        read -rp "Erasing $1 partition failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function FlashImage {
    if ! $fastboot flash "$1" "$2"; then
        read -rp "Flashing$2 failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function DeleteLogicalPartition {
    if ! $fastboot delete-logical-partition "$1"; then
        read -rp "Deleting $1 partition failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function CreateLogicalPartition {
    if ! $fastboot create-logical-partition "$1" "$2"; then
        read -rp "Creating $1 partition failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function ResizeLogicalPartition {
    for i in $logical_partitions; do
        for s in a b; do 
            DeleteLogicalPartition "${i}_${s}-cow"
            DeleteLogicalPartition "${i}_${s}"
        done
    CreateLogicalPartition "${i}_${curSlot}" \ "1"
    done
}

function WipeSuperPartition {
    if ! $fastboot wipe-super super_empty.img; then 
        echo "Wiping super partition failed. Fallback to deleting and creating logical partitions"
        ResizeLogicalPartition
    fi
}
##----------------------------------------------------------##

echo "#############################"
echo "# CHECKING FASTBOOT DEVICES #"
echo "#############################"
$fastboot devices

ACTIVE_SLOT=$($fastboot getvar current-slot 2>&1 | awk 'NR==1{print $2}')
if [ ! "$ACTIVE_SLOT" = "waiting" ] && [ ! "$ACTIVE_SLOT" = "a" ]; then
    echo "#############################"
    echo "# CHANGING ACTIVE SLOT TO A #"
    echo "#############################"
    SetActiveSlot
fi
curSlot="a"

echo "###################"
echo "# FORMATTING DATA #"
echo "###################"
read -rp "Wipe Data? (Y/N) " DATA_RESP
case $DATA_RESP in
    [yY] )
        echo 'Please ignore "Did you mean to format this partition?" warnings.'
        ErasePartition userdata
        ErasePartition metadata
        ;;
esac

echo "############################"
echo "# FLASHING BOOT PARTITIONS #"
echo "############################"
read -rp "Flash images on both slots? If unsure, say N. (Y/N) " SLOT_RESP
case $SLOT_RESP in
    [yY] )
        SLOT="all"
        ;;
    *)
        SLOT="a"
        ;;
esac

if [ $SLOT = "all" ]; then
    for i in $boot_partitions; do
        for s in a b; do
            FlashImage "${i}_${s}" \ "$i.img"
        done
    done
else
    for i in $boot_partitions; do
        FlashImage "${i}_${SLOT}" \ "$i.img"
    done
fi

echo "#####################"
echo "# FLASHING FIRMWARE #"
echo "#####################"
if [ $SLOT = "all" ]; then
    for i in $firmware_partitions; do
        for s in a b; do
            FlashImage "${i}_${s}" \ "$i.img"
        done
    done
else
    for i in $firmware_partitions; do
        FlashImage "${i}_${SLOT}" \ "$i.img"
    done
fi

# 'preloader_raw.img' must be flashed at a different partition name
if [ $SLOT = "--slot=all" ]; then
    for s in a b; do
        FlashImage "preloader_${s}" \ "preloader_raw.img"
    done
else
    FlashImage "preloader_${SLOT}" \ "preloader_raw.img"
fi

echo "###################"
echo "# FLASHING VBMETA #"
echo "###################"
read -rp "Disable android verified boot?, If unsure, say N. Bootloader won't be lockable if you select Y. (Y/N) " VBMETA_RESP
case $VBMETA_RESP in
    [yY] )
        if [ $SLOT = "all" ]; then
            for i in $vbmeta_partitions; do
                    for s in a b; do
                        FlashImage "${i}_${s} --disable-verity --disable-verification" \ "$i.img"
                    done
                done
        else
            for i in $vbmeta_partitions; do
                FlashImage "${i}_${SLOT} --disable-verity --disable-verification" \ "$i.img"
            done
        fi
        ;;
    *)
        avb_enabled=1
        if [ $SLOT = "all" ]; then
            for i in $vbmeta_partitions; do
                for s in a b; do
                    FlashImage "${i}_${s}" \ "$i.img"
                done
            done
        else
            for i in $vbmeta_partitions; do
                FlashImage "${i}_${SLOT}" \ "$i.img"
            done
        fi
        ;;
esac

echo "##########################"             
echo "# REBOOTING TO FASTBOOTD #"       
echo "##########################"
if ! $fastboot reboot fastboot; then
    echo "Error occured while rebooting to fastbootd. Aborting"
    exit 1
fi

echo "###############################"
echo "# FLASHING LOGICAL PARTITIONS #"
echo "###############################"
echo "Flash logical partition images?"
echo "If you're about to install a custom ROM that distributes its own logical partitions, say N."
read -rp "If unsure, say Y. (Y/N) " LOGICAL_RESP
case $LOGICAL_RESP in
    [yY] )
        if [ ! -f super.img ]; then
            if [ -f super_empty.img ]; then
                WipeSuperPartition
            else
                ResizeLogicalPartition
            fi
            for s in a b; do
                FlashImage "${i}_${curSlot}" \ "$i.img"
            done
        else
            FlashImage "super" \ "super.img"
        fi
        ;;
esac

echo "##########################"
echo "# LOCKING THE BOOTLOADER #"
echo "##########################"
if [ "${avb_enabled}" -eq 1 ]; then
    read -rp "Lock the bootloader? If unsure, say N (Y/N) " LOCK_RESP
    case $LOCK_RESP in
        [yY] )
            if ! $fastboot reboot bootloader; then
                echo "Error occured while rebooting to bootloader. Aborting"
                exit 1
            else
                $fastboot flashing lock
            fi
            ;;
    esac
fi

echo "#############"
echo "# REBOOTING #"
echo "#############"
read -rp "Reboot to system? If unsure, say Y. (Y/N) " REBOOT_RESP
case $REBOOT_RESP in
    [yY] )
        $fastboot reboot
        ;;
esac

echo "########"
echo "# DONE #"
echo "########"
echo "Stock firmware restored."
echo "You may now optionally re-lock the bootloader if you haven't disabled android verified boot."
