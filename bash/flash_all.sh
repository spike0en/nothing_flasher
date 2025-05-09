#!/usr/bin/env bash

echo "##################################"
echo "# Asteroids Fastboot ROM Flasher #"
echo "##################################"

##----------------------------------------------------------##
if [ ! -d "$(pwd)/platform-tools" ]; then
    if [[ $OSTYPE == 'darwin'* ]]; then
        fastboot_dl="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
    else
        fastboot_dl="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
    fi
    curl -L "$fastboot_dl" -o "$(pwd)/platform-tools-latest.zip"
    unzip "$(pwd)/platform-tools-latest.zip"
    rm "$(pwd)/platform-tools-latest.zip"
fi

fastboot="$(pwd)/platform-tools/fastboot"

if [ ! -f "$fastboot" ] || [ ! -x "$fastboot" ]; then
    echo "Fastboot cannot be executed, exiting"
    exit 1
fi

# Partition Variables
boot_partitions="boot init_boot vendor_boot dtbo recovery"
firmware_partitions="abl aop aop_config bluetooth cpucp cpucp_dtb devcfg dsp featenabler hyp imagefv keymaster modem multiimgoem pvmfw qupfw shrm tz uefi uefisecapp xbl xbl_config xbl_ramdump"
logical_partitions="system system_ext product vendor system_dlkm vendor_dlkm odm"
junk_logical_partitions="null"
vbmeta_partitions="vbmeta_system vbmeta_vendor"

function SetActiveSlot {
    if ! "$fastboot" --set-active=a; then
        echo "Error occured while switching to slot A. Aborting"
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

function FlashSuper {
    if ! "$fastboot" flash super super.img; then
        RebootFastbootD
        FlashImage "super" \ "super.img"
    else
        RebootFastbootD
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

function RebootBootloader {
    echo "###########################"
    echo "# REBOOTING TO BOOTLOADER #"       
    echo "###########################"
    if ! "$fastboot" reboot bootloader; then
        echo "Error occured while rebooting to bootloader. Aborting"
        exit 1
    fi
}
##----------------------------------------------------------##

echo "#############################"
echo "# CHECKING FASTBOOT DEVICES #"
echo "#############################"
"$fastboot" devices

echo "#############################"
echo "# CHANGING ACTIVE SLOT TO A #"
echo "#############################"
SetActiveSlot

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
read -rp "Flash images on both slots? If unsure, say N. (Y/N) " SLOT_RESP
for i in $boot_partitions; do
    case "$SLOT_RESP" in
        [yY] )
            for s in a b; do
                FlashImage "${i}_${s}" \ "$i.img"
            done
	    ;;
	*)
            FlashImage "${i}_a" \ "$i.img"
	    ;;
    esac
done

echo "###################"
echo "# FLASHING VBMETA #"
echo "###################"
read -rp "Disable android verified boot?, If unsure, say N. Bootloader won't be lockable if you select Y. (Y/N) " VBMETA_RESP
case "$VBMETA_RESP" in
    [yY] )
        if [ "$SLOT_RESP" = "y" ] || [ "$SLOT_RESP" = "Y" ]; then
            for s in a b; do
                FlashImage "vbmeta_${s} --disable-verity --disable-verification" \ "vbmeta.img"
            done
        else
            FlashImage "vbmeta_a --disable-verity --disable-verification" \ "vbmeta.img"
        fi
        ;;
    *)
        if [ "$SLOT_RESP" = "y" ] || [ "$SLOT_RESP" = "Y" ]; then
            for s in a b; do
                FlashImage "vbmeta_${s}" \ "vbmeta.img"
            done
        else
            FlashImage "vbmeta_a" \ "vbmeta.img"
        fi
        ;;
esac

echo "###############################"
echo "# FLASHING LOGICAL PARTITIONS #"
echo "###############################"
if [ ! -f super.img ]; then
    RebootFastbootD
    if [ -f super_empty.img ]; then
        WipeSuperPartition
    else
        ResizeLogicalPartition
    fi
    for i in $logical_partitions; do
        FlashImage "${i}_a" \ "$i.img"
    done
else
    FlashSuper
fi

echo "####################################"
echo "# FLASHING OTHER VBMETA PARTITIONS #"
echo "####################################"
for i in $vbmeta_partitions; do
    case "$VBMETA_RESP" in
        [yY] )
            FlashImage "${i}_a --disable-verity --disable-verification" \ "$i.img"
            ;;
        *)
            FlashImage "${i}_a" \ "$i.img"
            ;;
    esac
done

echo "#####################"
echo "# FLASHING FIRMWARE #"
echo "#####################"
for i in $firmware_partitions; do
    case "$SLOT_RESP" in
        [yY] )
            for s in a b; do
                FlashImage "${i}_${s}" \ "$i.img"
            done
	    ;;
	*)
            FlashImage "${i}_a" \ "$i.img"
	    ;;
    esac
done

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
echo "You may now optionally re-lock the bootloader if you haven't disabled android verified boot."
