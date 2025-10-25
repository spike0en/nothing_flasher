#!/usr/bin/env bash

echo "##################################"
echo "# Asteroids Fastboot ROM Flasher #"
echo "##################################"

##----------------------------------------------------------##
if [ ! -d "$(pwd)/platform-tools-r33.0.0" ]; then
    if [[ $OSTYPE == 'darwin'* ]]; then
        fastboot_dl="https://dl.google.com/android/repository/platform-tools_r33.0.0-darwin.zip"
    else
        fastboot_dl="https://dl.google.com/android/repository/platform-tools_r33.0.0-linux.zip"
    fi
    curl -L "$fastboot_dl" -o "$(pwd)/platform-tools-r33.0.0.zip"
    unzip "$(pwd)/platform-tools-r33.0.0.zip"
    rm "$(pwd)/platform-tools-r33.0.0.zip"

    if [ -d "$(pwd)/platform-tools" ]; then
        mv "$(pwd)/platform-tools" "$(pwd)/platform-tools-r33.0.0"
    fi
fi

fastboot="$(pwd)/platform-tools-r33.0.0/fastboot"

if [ ! -f "$fastboot" ] || [ ! -x "$fastboot" ]; then
    echo "Fastboot cannot be executed, exiting"
    exit 1
fi

# Partition Variables
boot_partitions="boot init_boot vendor_boot dtbo recovery"
vbmeta_partitions="vbmeta vbmeta_system vbmeta_vendor"
firmware_partitions="abl aop aop_config bluetooth cpucp cpucp_dtb devcfg dsp featenabler hyp imagefv keymaster modem multiimgoem pvmfw qupfw shrm tz uefi uefisecapp xbl xbl_config xbl_ramdump"
logical_partitions="system system_ext product vendor odm"
dlkm_partitions="system_dlkm vendor_dlkm"
junk_logical_partitions="null"

function RebootBootloader {
    echo "###########################"
    echo "# REBOOTING TO BOOTLOADER #"       
    echo "###########################"
    if ! "$fastboot" reboot bootloader; then
        echo "Error occured while rebooting to bootloader. Aborting"
        exit 1
    fi
}

function SetActiveSlot {
    if ! "$fastboot" --set-active=${1}; then
        echo "Error occured while switching to slot ${1}. Aborting"
        exit 1
    fi
}

function SwapSlot {
    if ! "$fastboot" --set-active=other; then
        echo "Error occured while switching to inactive slot. Aborting"
        exit 1
    fi
}

function handle_fastboot_error { 
    case "$FASTBOOT_ERROR" in
        [nN] )
            exit 1
	    ;;
    esac
}

function ErasePartition {
    if ! "$fastboot" erase $1; then
        read -rp "Erasing $1 partition failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function RebootFastbootD {
    echo "##########################"             
    echo "# REBOOTING TO FASTBOOTD #"       
    echo "##########################"
    if ! "$fastboot" reboot fastboot; then
        echo "Error occured while rebooting to fastbootd. Aborting"
        exit 1
    fi
}

function FlashImage {
    if ! "$fastboot" flash $1 $2; then
        read -rp "Flashing$2 failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function FlashImageToOther {
    if ! "$fastboot" flash $1 $2 --slot=${INACTIVE_SLOT}; then
        read -rp "Flashing$2 failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function FlashSuper {
    RebootBootloader
    if ! "$fastboot" flash super super.img; then
        RebootFastbootD
        FlashImage "super" \ "super.img"
    fi
}

function DeleteLogicalPartition {
    if ! "$fastboot" delete-logical-partition $1; then
        if ! echo $1 | grep -q "cow"; then
            read -rp "Deleting $1 partition failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
            handle_fastboot_error
        fi
    fi
}

function CreateLogicalPartition {
    if ! "$fastboot" create-logical-partition $1 $2; then
        read -rp "Creating $1 partition failed, Continue? If unsure say N, Pressing Enter key without any input will continue the script. (Y/N)" FASTBOOT_ERROR
        handle_fastboot_error
    fi
}

function ResizeLogicalPartition {
    if [ $junk_logical_partitions != "null" ]; then
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
            CreateLogicalPartition "${i}_${s}" \ "1"
        done
    done
}

function WipeSuperPartition {
    if ! "$fastboot" wipe-super super_empty.img; then 
        echo "Wiping super partition failed. Fallback to deleting and creating logical partitions"
        ResizeLogicalPartition
    fi
}

function isFastbootD {
    fastboot getvar is-userspace 2>&1 | grep -q "yes"
}

function GetSlot {
    ACTIVE_SLOT=$("$fastboot" getvar current-slot 2>&1 | head -n1 | rev | cut -c1)
    if [ -z "$ACTIVE_SLOT" ]; then 
        echo active slot not set! Aborting...
    fi
    if [ "$ACTIVE_SLOT" = "a" ]; then 
        INACTIVE_SLOT="b"
    else 
        INACTIVE_SLOT="a"
    fi
}

##----------------------------------------------------------##

echo "#############################"
echo "# CHECKING FASTBOOT DEVICES #"
echo "#############################"
"$fastboot" devices
GetSlot
if ! isFastbootD; then
    RebootFastbootD
fi

echo "###################"
echo "# FORMATTING DATA #"
echo "###################"
read -rp "Wipe Data? (Y/N) " DATA_RESP
case "$DATA_RESP" in
    [yY] )
        echo 'Please ignore "Did you mean to format this partition?" warnings.'
        ErasePartition userdata
        ErasePartition metadata
        ;;
esac

echo "############################"
echo "# FLASHING BOOT PARTITIONS #"
echo "############################"
for i in $boot_partitions; do
    FlashImageToOther "${i}" \ "$i.img"
done

echo "###################"
echo "# FLASHING VBMETA #"
echo "###################"
for i in $vbmeta_partitions; do
    FlashImageToOther "${i}" \ "$i.img"
done

echo "################"
echo "# FLASHING DLKM #"
echo "################"
for i in $dlkm_partitions; do
    FlashImage "${i}_${INACTIVE_SLOT}" \ "$i.img"
done

echo "#####################"
echo "# FLASHING FIRMWARE #"
echo "#####################"
if ! isFastbootD; then 
    RebootFastbootD
fi
for i in $firmware_partitions; do
        FlashImageToOther "${i}" \ "$i.img"
done

echo "###############################"
echo "# FLASHING LOGICAL PARTITIONS #"
echo "###############################"
if [ ! -f super.img ]; then
    if [ -f super_empty.img ]; then
        WipeSuperPartition
    else
        ResizeLogicalPartition
    fi
    for i in $logical_partitions; do
        FlashImageToOther "${i}" \ "$i.img"
    done
else
    FlashSuper
fi

echo "#################################"
echo "# CHANGING ACTIVE SLOT TO ${INACTIVE_SLOT} #"
echo "#################################"
SwapSlot

echo "#############"
echo "# REBOOTING #"
echo "#############"
read -rp "Reboot to system? If unsure, say Y. (Y/N) " REBOOT_RESP
case "$REBOOT_RESP" in
    [yY] )
        "$fastboot" reboot
        ;;
esac

echo "########"
echo "# DONE #"
echo "########"
echo "Stock firmware restored."
