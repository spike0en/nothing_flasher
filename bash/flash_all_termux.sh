#!/bin/bash
# SPDX-FileCopyrightText: Hellboy017, spike0en
# SPDX-License-Identifier: MIT
#
# Modified by: devvsid (sid_imp)

BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' 
PROG_BG='\033[1;30;42m'

FASTBOOT_CMD="termux-fastboot"
REBOOT_WAIT_TIME=16
TERMUX_ADB_REPO="https://github.com/nohajc/termux-adb.git"
LOG_FILE="flash_debug.log"

core_partitions="boot dtbo init_boot vendor_boot apusys ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz lk logo mcf_ota mcupm modem pi_img scp spmfw sspm tee vcp"
vbmeta_partitions="vbmeta vbmeta_system vbmeta_vendor"
logical_partitions="odm_dlkm odm vendor_dlkm product vendor system_dlkm system_ext system"

TOTAL_STEPS=0
for _ in $core_partitions $vbmeta_partitions $logical_partitions "preloader"; do ((TOTAL_STEPS++)); done
CURRENT_STEP=0

echo "--- Flashing Log Start ---" > "$LOG_FILE"

SetupEnvironment() {
    echo -e "${BLUE}Checking Termux environment...${NC}"
    if [ ! -d "$HOME/storage" ]; then
        echo -e "${RED}[WARNING] Termux storage not set up.${NC}"
        termux-setup-storage
        echo -e "${GREEN}Once granted, please re-run this script!${NC}"
        exit 0
    fi

    if ! command -v "$FASTBOOT_CMD" &> /dev/null; then
        echo -e "${RED}[WARNING] $FASTBOOT_CMD not detected. Auto-installing...${NC}"
        pkg update -y && pkg upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
        pkg install git -y
        if [ -d "$HOME/termux-adb" ]; then rm -rf "$HOME/termux-adb"; fi
        cd "$HOME" || exit 1
        git clone "$TERMUX_ADB_REPO"
        if [ -d "termux-adb" ]; then
            cd termux-adb || exit 1
            chmod +x install.sh
            yes | ./install.sh
            echo -e "${BLUE}[SETUP COMPLETE] Please restart Termux, then re-run this script.${NC}"
            exit 0
        else
            echo -e "${RED}[ERROR] Failed to clone termux-adb.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[SUCCESS] termux-fastboot is ready.${NC}"
    fi
}

UpdateProgressMath() {
    _progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local _done=$((_progress * 40 / 100))
    local _left=$((40 - _done))
    
    _fill=""
    _empty=""
    for (( c=1; c<=_done; c++ )); do _fill="${_fill}█"; done
    for (( c=1; c<=_left; c++ )); do _empty="${_empty} "; done
    _prog_text=$(printf "%3s" "$_progress")
    
    PROG_STRING="${PROG_BG}Progress: [ ${_prog_text}%]${NC} [${_fill}${_empty}]"
}

FlashImageSilent() {
    local partition_name="$1"
    local image_file="$2"
    
    ((CURRENT_STEP++))
    UpdateProgressMath
    
    echo -ne "\r\033[2K"
    echo -e "${GREEN}Flashing $partition_name with $image_file...${NC}"
    echo -ne "$PROG_STRING"
    
    "$FASTBOOT_CMD" flash "$partition_name" "$image_file" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo -ne "\r\033[2K"
        echo -e "${RED}[ERROR] Flash failed for $partition_name. Check $LOG_FILE. Stopping.${NC}"
        exit 1
    fi
}

FlashImageVerbose() {
    local partition_name="$1"
    local image_file="$2"
    
    ((CURRENT_STEP++))
    UpdateProgressMath
    
    echo -ne "\r\033[2K"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${BLUE}Flashing $partition_name with $image_file...${NC}"
    echo -ne "$PROG_STRING"
    
    "$FASTBOOT_CMD" flash "$partition_name" "$image_file" 2>&1 | while IFS= read -r line; do
        clean_line="${line//$'\r'/}"
        if [[ -n "${clean_line// /}" ]]; then
            echo -ne "\r\033[2K"
            echo -e "${GREEN}$clean_line${NC}"
            echo -ne "$PROG_STRING"
        fi
    done
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -ne "\r\033[2K"
        echo -e "${RED}[ERROR] Flash failed for $partition_name. Stopping.${NC}"
        exit 1
    fi
}

CheckDevice() {
    local stage="$1"
    local attempts=0
    local max_attempts=8
    
    echo -ne "\r\033[2K"
    echo -e "${GREEN}Checking for device in $stage mode...${NC}"
    
    while [ $attempts -lt $max_attempts ]; do
        if "$FASTBOOT_CMD" devices 2>&1 | grep -q fastboot; then
            echo -ne "\r\033[2K"
            echo -e "${GREEN}[SUCCESS] Device detected.${NC}"
            return 0
        fi
        sleep 5
        ((attempts++))
    done
    echo -ne "\r\033[2K"
    echo -e "${RED}[CRITICAL ERROR] Device not found in $stage mode.${NC}"
    exit 1
}

RebootFastbootD() {
    echo -ne "\r\033[2K"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${GREEN}Initiating reboot to Fastbootd (Wait: ${REBOOT_WAIT_TIME}s)...${NC}"
    echo -ne "$PROG_STRING"
    
    "$FASTBOOT_CMD" reboot fastboot >> "$LOG_FILE" 2>&1 &
    sleep "$REBOOT_WAIT_TIME"
    CheckDevice "Fastbootd"
    
    echo -ne "\r\033[2K"
    echo -e "${BLUE}--------------------------------------------------${NC}"
}

SetupEnvironment

echo -e "${BLUE}\c"
cat << 'EOF'
#################################
##      CMF Phone 1 / 2 Pro    ##
##     Nothing Phone 3a Lite   ##
##        Termux Flasher       ##
#################################
EOF
echo -e "${NC}"


echo -e "${BLUE}STARTING FULL TERMUX FLASH SEQUENCE (SLOT A)${NC}"
echo -e "${BLUE}==================================================${NC}"

if ! CheckDevice "Fastboot"; then exit 1; fi

"$FASTBOOT_CMD" --set-active=a >> "$LOG_FILE" 2>&1

echo ""
echo -e "${YELLOW}==================================================${NC}"
echo -e "${YELLOW}           ⚠️  ACTION REQUIRED ⚠️               ${NC}"
echo -e "${YELLOW} Do you want to wipe data (userdata & metadata)?  ${NC}"
echo -e "${YELLOW}==================================================${NC}"
echo -ne "${YELLOW} Choose (y/n): ${NC}"
read format_data

if [[ "$format_data" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Wiping User Data...${NC}"
    "$FASTBOOT_CMD" erase userdata >> "$LOG_FILE" 2>&1
    "$FASTBOOT_CMD" erase metadata >> "$LOG_FILE" 2>&1
else
    echo -e "${GREEN}Skipping data format.${NC}"
fi

UpdateProgressMath

echo -e "${BLUE}--------------------------------------------------${NC}"
echo -e "${BLUE}FLASHING CORE AND FIRMWARE PARTITIONS...${NC}"
for i in $core_partitions; do FlashImageSilent "${i}_a" "${i}.img"; done
FlashImageSilent "preloader_a" "preloader_raw.img"

echo -ne "\r\033[2K"
echo -e "${BLUE}FLASHING VBMETA PARTITIONS...${NC}"
for i in $vbmeta_partitions; do FlashImageSilent "${i}_a" "${i}.img"; done

RebootFastbootD

if [ -f "super_empty.img" ]; then
    echo -e "${GREEN}Wiping super partition...${NC}"
    echo -ne "$PROG_STRING"
    "$FASTBOOT_CMD" wipe-super super_empty.img >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo -ne "\r\033[2K"
        echo -e "${RED}[ERROR] wipe-super failed. Cannot flash logical partitions.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW} super_empty.img not found. ${NC}"
    echo -e "${YELLOW} Skipping wipe-super. ${NC}"
    echo -e "${YELLOW}[NOTE] super_empty.img only required when you flashing Nothing OS.${NC}"

    echo -ne "$PROG_STRING"
fi

echo -ne "\r\033[2K"
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}FLASHING LOGICAL PARTITIONS...${NC}"
for i in $logical_partitions; do FlashImageVerbose "${i}_a" "${i}.img"; done

echo -ne "\r\033[2K"
echo -e "${PROG_BG}Progress: [100%]${NC} [████████████████████████████████████████]"
echo -e "${BLUE}FINALIZING AND REBOOTING...${NC}"
"$FASTBOOT_CMD" --set-active=a >> "$LOG_FILE" 2>&1
"$FASTBOOT_CMD" reboot >> "$LOG_FILE" 2>&1
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}[=] FLASHING COMPLETE. The device should now be rebooting.${NC}"