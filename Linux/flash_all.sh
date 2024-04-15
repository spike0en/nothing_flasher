#!/bin/bash

echo "#############################################################################"
echo "#                Pacman Fastboot ROM Flasher                                #"
echo "#                   Developed/Tested By                                     #"
echo "#  HELLBOY017, viralbanda, spike0en, PHATwalrus, arter97, AntoninoScordino  #"
echo "#          [Nothing Phone (2a) Telegram Dev Team]                           #"
echo "#############################################################################"

##----------------------------------------------------------##
if [ ! -d platform-tools ]; then
    wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip -O ${PWD}/platform-tools-latest.zip
    unzip ${PWD}/platform-tools-latest.zip
    rm ${PWD}/platform-tools-latest.zip
fi

fastboot=${PWD}/platform-tools/fastboot

if [ ! -f $fastboot ] || [ ! -x $fastboot ]; then
    echo "Fastboot cannot be executed, exiting"
    exit 1
fi

# Partition Variables
boot_partitions="boot dtbo init_boot vendor_boot vendor_dlkm odm_dlkm system_dlkm"
firmware_partitions="apusys audio_dsp ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz lk logo mcf_ota mcupm md1img mvpu_algo pi_img preloader_raw scp spmfw sspm tee vcp"
logical_partitions="odm vendor system_ext system"
vbmeta_partitions="vbmeta_system vbmeta_vendor"

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
            CreateLogicalPartition "${i}_${s}" \ "1"
        done
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
        SLOT="--slot=all"
        ;;
    *)
        SLOT="--slot=a"
        ;;
esac

if [ $SLOT = "--slot=all" ]; then
    for i in $boot_partitions; do
        for s in a b; do
            FlashImage "${i}_${s}" \ "$i.img"
        done
    done
else
    for i in $boot_partitions; do
        FlashImage "$i" \ "$i.img"
    done
fi

echo "##########################"             
echo "# REBOOTING TO FASTBOOTD #"       
echo "##########################"
if ! $fastboot reboot fastboot; then
    echo "Error occured while rebooting to fastbootd. Aborting"
    exit 1
fi

echo "#####################"
echo "# FLASHING FIRMWARE #"
echo "#####################"
for i in $firmware_partitions; do
    FlashImage "$SLOT $i" \ "$i.img"
done

echo "###################"
echo "# FLASHING VBMETA #"
echo "###################"
read -rp "Disable android verified boot?, If unsure, say N. Bootloader won't be lockable if you select Y. (Y/N) " VBMETA_RESP
case $VBMETA_RESP in
    [yY] )
        FlashImage "$SLOT vbmeta --disable-verity --disable-verification" \ "vbmeta.img"
        ;;
    *)
        FlashImage "$SLOT vbmeta" \ "vbmeta.img"
        ;;
esac

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
            for i in $logical_partitions; do
                FlashImage "$i" \ "$i.img"
            done
        else
            FlashImage "super" \ "super.img"
        fi
        ;;
esac

echo "####################################"
echo "# FLASHING OTHER VBMETA PARTITIONS #"
echo "####################################"
for i in $vbmeta_partitions; do
    case $VBMETA_RESP in
        [yY] )
            FlashImage "$i --disable-verity --disable-verification" \ "$i.img"
            ;;
        *)
            FlashImage "$i" \ "$i.img"
            ;;
    esac
done

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
