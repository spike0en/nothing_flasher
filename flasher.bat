:: SPDX-FileCopyrightText: Hellboy017, spike0en
:: SPDX-License-Identifier: MIT

@echo off
title Nothing Fastboot ROM Flasher (Unified)
setlocal enabledelayedexpansion

:: =========================================
::  ADMIN ELEVATION
:: =========================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Set working directory
set "WORK_DIR=%~dp0"
cd /d "%WORK_DIR%" 2>nul || (
    echo [ERROR] Failed to set working directory: "%WORK_DIR%"
    pause
    exit /b 1
)

:: =========================================
::  LOGGING SETUP
:: =========================================
for /f %%i in ('powershell -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TIMESTAMP=%%i"
set "LOG_FILE=%~dp0log_%TIMESTAMP%.txt"

:: Write session header to log
echo [INFO] Log file: %LOG_FILE%
>> "%LOG_FILE%" echo ========================================================
>> "%LOG_FILE%" echo  Nothing Fastboot ROM Flasher - Session Log
>> "%LOG_FILE%" echo  Timestamp: %TIMESTAMP%
>> "%LOG_FILE%" echo  Working Dir: %CD%
>> "%LOG_FILE%" echo ========================================================

:: =========================================
::  DEVICE SELECTION MENU
:: =========================================
echo.
echo =============================================
echo    Nothing Fastboot ROM Flasher - Unified
echo =============================================
echo.
echo.

:: Scan configs directory
if not exist "configs\*.cfg" (
    echo [ERROR] No device configuration files found in configs\ directory.
    echo Please ensure .cfg files are present.
    pause
    exit /b 1
)

:: Build device list from configs
set "device_count=0"
for %%F in (configs\*.cfg) do (
    set /a device_count+=1
    set "cfg_file_!device_count!=%%F"
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%%F") do (
        if "%%A"=="DEVICE_NAME" set "device_name_!device_count!=%%B"
        if "%%A"=="CODENAME" set "codename_!device_count!=%%B"
    )
)

echo  Select your device:
echo.
for /l %%i in (1,1,%device_count%) do (
    echo   [%%i] !device_name_%%i!  ^(!codename_%%i!^)
)
echo.
set /p "device_choice=  Enter choice (1-%device_count%): "

:: Validate choice
if not defined device_choice goto :InvalidChoice
set /a "valid_choice=device_choice" 2>nul
if !valid_choice! lss 1 goto :InvalidChoice
if !valid_choice! gtr %device_count% goto :InvalidChoice

set "config_file=!cfg_file_%device_choice%!"
echo.
echo [INFO] Loading config: !config_file!
call :Log "[SELECT] User chose device #!device_choice!"
call :Log "[CONFIG] Loading: !config_file!"

:: =========================================
::  LOAD CONFIGURATION
:: =========================================

:: Initialize defaults
set "DEVICE_NAME="
set "CODENAME="
set "FLOW_TYPE="
set "PLATFORM_TOOLS_VERSION=latest"
set "SUPPORTS_AVB_DISABLE=0"
set "SUPPORTS_DUAL_SLOT_PROMPT=0"
set "HAS_PRELOADER=0"
set "HAS_DLKM_SEPARATE=0"
set "BOOT_PARTITIONS="
set "FIRMWARE_PARTITIONS="
set "LOGICAL_PARTITIONS="
set "DLKM_PARTITIONS="
set "VBMETA_PARTITIONS="
set "JUNK_LOGICAL_PARTITIONS="

:: Parse config file
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("!config_file!") do (
    set "%%A=%%B"
)

echo.
echo =============================================
echo  Device  : !DEVICE_NAME!
echo  Code    : !CODENAME!
echo  Flow    : !FLOW_TYPE!
echo  PT Ver  : !PLATFORM_TOOLS_VERSION!
echo =============================================
echo.

call :Log "[CONFIG] Device: !DEVICE_NAME!"
call :Log "[CONFIG] Codename: !CODENAME!"
call :Log "[CONFIG] Flow: !FLOW_TYPE!"
call :Log "[CONFIG] Platform Tools: !PLATFORM_TOOLS_VERSION!"
call :Log "[CONFIG] AVB Disable: !SUPPORTS_AVB_DISABLE!"
call :Log "[CONFIG] Dual Slot Prompt: !SUPPORTS_DUAL_SLOT_PROMPT!"
call :Log "[CONFIG] Preloader: !HAS_PRELOADER!"
call :Log "[CONFIG] DLKM Separate: !HAS_DLKM_SEPARATE!"
call :Log "[CONFIG] Boot: !BOOT_PARTITIONS!"
call :Log "[CONFIG] Firmware: !FIRMWARE_PARTITIONS!"
call :Log "[CONFIG] Logical: !LOGICAL_PARTITIONS!"
call :Log "[CONFIG] DLKM: !DLKM_PARTITIONS!"
call :Log "[CONFIG] VBMeta: !VBMETA_PARTITIONS!"

:: =========================================
::  PRE-REQUIREMENTS CHECK
:: =========================================
echo ############################
echo #  PRE-REQUIREMENTS CHECK  #
echo ############################

choice /m "Is your device bootloader unlocked?"
if !errorlevel! equ 2 (
    echo To use this script, your device bootloader must be unlocked.
    echo Please unlock it before proceeding.
    pause
    exit /b 1
)

choice /m "Are you in bootloader mode?"
if !errorlevel! equ 2 (
    echo Ensure your device is in bootloader mode before proceeding.
    echo You can enter bootloader mode by holding Power + Volume Down and releasing the Power Key when the OEM logo appears or by using:
    echo adb reboot bootloader
    pause
    exit /b 1
)

choice /m "Are your fastboot drivers properly installed? (Can you see 'Android Bootloader Interface' in Device Manager?)"
if !errorlevel! equ 2 (
    echo Please install the proper fastboot drivers before proceeding.
    echo Install the latest Google USB Drivers from https://developer.android.com/studio/run/win-usb
    pause
    exit /b 1
)

echo All pre-requirements met! Proceeding...

:: =========================================
::  FILE INTEGRITY CHECKS [RECOMMENDED]
:: =========================================
call :PreHashVerificationPrompt
if !errorlevel! equ 0 (
    call :VerifyImageHashes
    if !errorlevel! neq 0 (
        echo [ABORTED] Image validation failed or canceled by user.
        pause
        exit /b 1
    )
) else (
    echo [INFO] Skipping hash verification as requested. Proceeding without validation...
)

:: =========================================
::  PLATFORM TOOLS SETUP & VALIDATION
:: =========================================
call :PlatformToolsSetup
call :FastbootValidation

echo #############################
echo # CHECKING FASTBOOT DEVICES #
echo #############################
call :CheckFastbootDevices
if errorlevel 1 exit /b 1

:: =========================================
::  FLOW ROUTER
:: =========================================
call :Log "[FLOW] Routing to flow: !FLOW_TYPE!"
if "!FLOW_TYPE!"=="qualcomm_slotA" goto :FlowQualcommSlotA
if "!FLOW_TYPE!"=="qualcomm_inactive" goto :FlowQualcommInactive
if "!FLOW_TYPE!"=="mediatek" goto :FlowMediaTek

echo [ERROR] Unknown FLOW_TYPE: !FLOW_TYPE!
pause
exit /b 1

:: ###############################################################################
::  FLOW A: QUALCOMM SLOT-A
::
::  SetActiveSlot(a) -> WipeData -> FlashBoot(slot) -> FlashVBMeta(slot,AVB)
::  -> RebootFastbootD -> FlashFirmware(slot) -> FlashLogical
::  -> FlashVBMetaSub(AVB) -> Reboot
:: ###############################################################################
:FlowQualcommSlotA

echo #############################
echo # CHANGING ACTIVE SLOT TO A #
echo #############################
call :SetActiveSlotA

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if !errorlevel! equ 1 (
    echo Please ignore "Did you mean to format this partition?" warnings.
    call :ErasePartition userdata
    call :ErasePartition metadata
) else (
    echo Data wipe canceled.
)

:: Determine slot targeting
set "slot=a"
if "!SUPPORTS_DUAL_SLOT_PROMPT!"=="1" (
    choice /m "Flash images on both slots? If unsure, say N."
    if !errorlevel! equ 1 (
        set "slot=all"
    )
)

echo ############################
echo # FLASHING BOOT PARTITIONS #
echo ############################
if "!slot!"=="all" (
    for %%i in (!BOOT_PARTITIONS!) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s %%i.img
        )
    )
) else (
    for %%i in (!BOOT_PARTITIONS!) do (
        call :FlashImage %%i_!slot! %%i.img
    )
)

echo ###################
echo # FLASHING VBMETA #
echo ###################
set "disable_avb=0"
if "!SUPPORTS_AVB_DISABLE!"=="1" (
    choice /m "Disable android verified boot? If unsure, say N. Bootloader won't be lockable if you select Y."
    if !errorlevel! equ 1 (
        set "disable_avb=1"
    )
)

if "!slot!"=="all" (
    for %%s in (a b) do (
        call :FlashVBMeta vbmeta_%%s vbmeta.img !disable_avb!
    )
) else (
    call :FlashVBMeta vbmeta_!slot! vbmeta.img !disable_avb!
)

echo #####################
echo # FLASHING FIRMWARE #
echo #####################
call :RebootFastbootD
if "!slot!"=="all" (
    for %%i in (!FIRMWARE_PARTITIONS!) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s %%i.img
        )
    )
) else (
    for %%i in (!FIRMWARE_PARTITIONS!) do (
        call :FlashImage %%i_!slot! %%i.img
    )
)

echo ###############################
echo # FLASHING LOGICAL PARTITIONS #
echo ###############################
if not exist super.img (
    if exist super_empty.img (
        call :WipeSuperPartition
    ) else (
        call :ResizeLogicalPartition
    )
    for %%i in (!LOGICAL_PARTITIONS!) do (
        call :FlashImage %%i %%i.img
    )
) else (
    call :FlashSuper
)

echo ####################################
echo # FLASHING OTHER VBMETA PARTITIONS #
echo ####################################
for %%i in (!VBMETA_PARTITIONS!) do (
    call :FlashVBMeta %%i %%i.img !disable_avb!
)

goto :PostFlash

:: ###############################################################################
::  FLOW B: QUALCOMM INACTIVE-SLOT
::
::  Targets inactive slot for kernel 6.6 module compatibility.
::  ShowSlotInfo -> WipeData -> FlashBoot(inactive) -> FlashVBMeta(inactive)
::  -> RebootFastbootD -> FlashDLKM(inactive) -> FlashFirmware(both)
::  -> FlashLogical(inactive) -> SwapSlot -> Reboot
:: ###############################################################################
:FlowQualcommInactive

echo ###############################
echo #     SLOT INFORMATION       #
echo ###############################
call :ShowSlotInfo

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if !errorlevel! equ 1 (
    echo Please ignore "Did you mean to format this partition?" warnings.
    call :ErasePartition userdata
    call :ErasePartition metadata
) else (
    echo Data wipe canceled.
)

echo ############################
echo # FLASHING BOOT PARTITIONS #
echo ############################
for %%i in (!BOOT_PARTITIONS!) do (
    set "target_partition=%%i_!inactive_slot!"
    call :FlashImage !target_partition! %%i.img
)

echo ###################
echo # FLASHING VBMETA #
echo ###################
for %%i in (!VBMETA_PARTITIONS!) do (
    set "target_partition=%%i_!inactive_slot!"
    call :FlashImage !target_partition! %%i.img
)

echo #################
echo # FLASHING DLKM #
echo #################
call :RebootFastbootD
if "!HAS_DLKM_SEPARATE!"=="1" (
    for %%i in (!DLKM_PARTITIONS!) do (
        set "target_partition=%%i_!inactive_slot!"
        %fastboot% delete-logical-partition !target_partition!
        call :CreateLogicalPartition !target_partition! 1
        echo Flashing !target_partition! with %%i.img...
        call :FlashImage !target_partition! %%i.img
    )
)

echo #####################
echo # FLASHING FIRMWARE #
echo #####################
for %%i in (!FIRMWARE_PARTITIONS!) do (
    for %%s in (a b) do (
        call :FlashImage %%i_%%s %%i.img
    )
)

echo ###############################
echo # FLASHING LOGICAL PARTITIONS #
echo ###############################
if not exist super.img (
    if exist super_empty.img (
        call :WipeSuperPartition
    ) else (
        call :ResizeLogicalPartition
    )
    for %%i in (!LOGICAL_PARTITIONS!) do (
        set "target_partition=%%i_!inactive_slot!"
        call :FlashImage !target_partition! %%i.img
    )
) else (
    call :FlashSuper
)

echo ##################
echo # SWITCHING SLOT #
echo ##################
call :SwapSlot

goto :PostFlash

:: ###############################################################################
::  FLOW C: MEDIATEK
::
::  SetActiveSlot(a) -> WipeData -> FlashBoot(slot) -> FlashFirmware(slot)
::  -> FlashVBMeta(AVB) -> FlashPreloader(slot) -> FlashVBMetaSub(AVB)
::  -> RebootFastbootD -> FlashLogical(a) -> SetActiveSlot(a) -> Reboot
:: ###############################################################################
:FlowMediaTek

echo #############################
echo # CHANGING ACTIVE SLOT TO A #
echo #############################
call :SetActiveSlotA

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if !errorlevel! equ 1 (
    echo Please ignore "Did you mean to format this partition?" warnings.
    call :ErasePartition userdata
    call :ErasePartition metadata
) else (
    echo Data wipe canceled.
)

:: Determine slot targeting
set "slot=a"
if "!SUPPORTS_DUAL_SLOT_PROMPT!"=="1" (
    choice /m "Flash images on both slots? If unsure, say N."
    if !errorlevel! equ 1 (
        set "slot=all"
    )
)

echo ############################
echo # FLASHING BOOT PARTITIONS #
echo ############################
if "!slot!"=="all" (
    for %%i in (!BOOT_PARTITIONS!) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s %%i.img
        )
    )
) else (
    for %%i in (!BOOT_PARTITIONS!) do (
        call :FlashImage %%i_!slot! %%i.img
    )
)

echo #####################
echo # FLASHING FIRMWARE #
echo #####################
if "!slot!"=="all" (
    for %%i in (!FIRMWARE_PARTITIONS!) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s %%i.img
        )
    )
) else (
    for %%i in (!FIRMWARE_PARTITIONS!) do (
        call :FlashImage %%i_!slot! %%i.img
    )
)

echo ###################
echo # FLASHING VBMETA #
echo ###################
set "disable_avb=0"
if "!SUPPORTS_AVB_DISABLE!"=="1" (
    choice /m "Disable android verified boot? If unsure, say N. Bootloader won't be lockable if you select Y."
    if !errorlevel! equ 1 (
        set "disable_avb=1"
    )
)
call :FlashVBMeta vbmeta_a vbmeta.img !disable_avb!

:: Flash preloader (MediaTek-specific)
if "!HAS_PRELOADER!"=="1" (
    echo ########################
    echo # FLASHING PRELOADER   #
    echo ########################
    if "!slot!"=="all" (
        for %%s in (a b) do (
            call :FlashImage preloader_%%s preloader_raw.img
        )
    ) else (
        call :FlashImage preloader_!slot! preloader_raw.img
    )
)

echo ####################################
echo # FLASHING OTHER VBMETA PARTITIONS #
echo ####################################
for %%i in (!VBMETA_PARTITIONS!) do (
    call :FlashVBMeta %%i_a %%i.img !disable_avb!
)

echo ###############################
echo # FLASHING LOGICAL PARTITIONS #
echo ###############################
call :RebootFastbootD

if not exist super.img (
    if exist super_empty.img (
        call :WipeSuperPartition
    ) else (
        call :ResizeLogicalPartition
    )
    for %%i in (!LOGICAL_PARTITIONS!) do (
        call :FlashImage %%i_a %%i.img
    )
) else (
    call :FlashImage super super.img
)

echo #############################
echo # CHANGING ACTIVE SLOT TO A #
echo #############################
call :SetActiveSlotA

goto :PostFlash

:: ###############################################################################
::  POST-FLASH (shared ending for all flows)
:: ###############################################################################
:PostFlash

echo #############
echo # REBOOTING #
echo #############
choice /m "Reboot to system? If unsure, say Y."
if !errorlevel! equ 1 (
    %fastboot% reboot
)

echo ########
echo # DONE #
echo ########
echo Stock firmware restored for !DEVICE_NAME! ^(!CODENAME!^).
call :Log "[DONE] Stock firmware restored for !DEVICE_NAME! (!CODENAME!)"
call :Log "[DONE] Session ended at %date% %time%"
call :Log "[DONE] Log saved to: %LOG_FILE%"
echo [INFO] Session log saved to: %LOG_FILE%
if "!SUPPORTS_AVB_DISABLE!"=="1" (
    echo You may now optionally re-lock the bootloader if you haven't disabled android verified boot.
)

pause
exit

:: ###############################################################################
::  SHARED SUBROUTINES
:: ###############################################################################

:InvalidChoice
echo [ERROR] Invalid selection. Please run the script again.
pause
exit /b 1

:: ----------------------------
::  Hash Verification
:: ----------------------------
:PreHashVerificationPrompt
echo.
echo #########################
echo # IMAGE INTEGRITY CHECK #
echo #########################
echo This step verifies file integrity and detects missing or corrupted images before flashing.
echo.
echo Download the provided .sha256 checksum file in release assets
echo From: https://github.com/spike0en/nothing_archive/releases
echo Move the same to: %CD%
echo Example: Pong_V3.2-250708-2227-hash.sha256
echo Filenames can vary based on NOS build and device model
echo.
choice /m "Begin (Y) or skip hash (N) verification"
if !errorlevel! equ 1 (
    exit /b 0
) else (
    exit /b 1
)

:VerifyImageHashes
setlocal enabledelayedexpansion

:CheckForSha
dir /b *.sha256 >nul 2>&1
if errorlevel 1 (
    echo.
    echo =================================================================
    echo [WARNING] No .sha256 checksum files found in the directory!
    echo =================================================================
    choice /m "Do you want to proceed without hash verification?" /c YN

    rem IMPORTANT: In CHOICE, Y = errorlevel 1, N = errorlevel 2
    if errorlevel 2 (
        echo.
        echo [INFO] Please place the required .sha256 checksum files in:
        echo   %CD%
        echo and then press any key to retry...
        pause >nul
        goto :CheckForSha
    )
    if errorlevel 1 (
        echo Proceeding without hash verification...
        endlocal
        exit /b 0
    )
)

set /a total=0
set /a valid=0
set /a invalid=0
set /a missing=0
set "invalidList="
set "missingList="

echo.
echo ===============================
echo Checking Image Hashes...
echo ===============================

for %%F in (*.sha256) do (
    echo Checking: %%F
    echo ------------------------------------------

    for /f "usebackq delims=" %%L in ("%%F") do (
        set "line=%%L"
        if not "!line!"=="" (
            set "hash="
            set "file="
            for /f "tokens=1" %%H in ("!line!") do (
                set "hash=%%H"
            )
            set "file=!line:* *=!"
            set "hash=!hash: =!"
            set "hash=!hash:~0,64!"

            set /a total+=1

            if exist "!file!" (
                set "actual="
                for /f "tokens=1" %%X in ('CertUtil -hashfile "!file!" SHA256 ^| find /i /v "SHA256" ^| find /i /v "CertUtil"') do (
                    set "actual=%%X"
                )
                set "actual=!actual: =!"
                set "actual=!actual:~0,64!"

                if /i "!hash!"=="!actual!" (
                    echo [VALID]     !file!
                    set /a valid+=1
                ) else (
                    echo [INVALID]   !file!
                    set /a invalid+=1
                    set "invalidList=!invalidList!!file!;"
                )
            ) else (
                echo [MISSING]   !file!
                set /a missing+=1
                set "missingList=!missingList!!file!;"
            )
        )
    )
)

echo ------------------------------------------
echo.
echo Final Results
echo ==============================
echo Total .img files    = !total!
echo Valid images        = !valid!
echo Invalid images      = !invalid!
echo Missing images      = !missing!
echo.

if !invalid! GTR 0 (
    echo List of Invalid Images:
    set /a count=0
    for %%I in (!invalidList!) do (
        set /a count+=1
        echo   !count!. %%I
    )
    echo.
)

if !missing! GTR 0 (
    echo List of Missing Images:
    set /a count=0
    for %%M in (!missingList!) do (
        set /a count+=1
        echo   !count!. %%M
    )
    echo.
)

if !invalid! GTR 0 (
    echo [WARNING] One or more image files are invalid.
)
if !missing! GTR 0 (
    echo [WARNING] One or more image files are missing.
)

if !invalid! GTR 0 goto :ConfirmProceed
if !missing! GTR 0 goto :ConfirmProceed

echo All image files validated successfully.
endlocal
exit /b 0

:ConfirmProceed
choice /m "Some files are invalid or missing. Do you want to proceed anyway?"
if !errorlevel! equ 1 (
    rem User chose Yes - continue
    endlocal
    exit /b 0
)

rem User chose No - show retry/exit menu
echo.
echo ====================================================
echo [INFO] Choose an option:
echo   1. Retry validation (after fixing files)
echo   2. Exit flasher
echo ====================================================
set /p choice="Enter 1 or 2: "

if "%choice%"=="1" (
    echo [INFO] Retrying validation...
    endlocal
    goto :VerifyImageHashes
) else (
    echo [ABORTED] Image validation failed or canceled by user.
    endlocal
    exit /b 1
)
exit /b 0

:: ----------------------------
::  Platform Tools
:: ----------------------------
:PlatformToolsSetup
echo #############################
echo # SETTING UP PLATFORM TOOLS #
echo #############################
if not exist "platform-tools\fastboot.exe" (
    echo Platform tools not found. Downloading...

    if "!PLATFORM_TOOLS_VERSION!"=="latest" (
        set "PT_URL=https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    ) else (
        set "PT_URL=https://dl.google.com/android/repository/platform-tools_!PLATFORM_TOOLS_VERSION!-windows.zip"
    )

    curl --ssl-no-revoke -L "!PT_URL!" -o platform-tools-download.zip
    if exist platform-tools-download.zip (
        echo Platform tools downloaded successfully.
        call :UnZipFile "%~dp0platform-tools-download.zip" "%~dp0"
        echo Platform tools extracted successfully.
        del /f /q platform-tools-download.zip
    ) else (
        echo [ERROR] Failed to download platform tools from: !PT_URL!
        exit /b 1
    )
) else (
    echo Platform tools already exist. Skipping download...
)
exit /b

:FastbootValidation
echo ################################
echo # CHECKING FASTBOOT EXECUTABLE #
echo ################################
set "fastboot=.\platform-tools\fastboot.exe"

if not exist "%fastboot%" (
    echo [ERROR] Fastboot executable not found.
    echo Please ensure platform tools are properly downloaded.
    pause
    exit /b 1
)

%fastboot% --version
if !errorlevel! neq 0 (
    echo [ERROR] Fastboot executable is not functioning properly.
    echo Try running "fastboot --version" manually.
    pause
    exit /b 1
)

echo [SUCCESS] Fastboot executable found and verified.
exit /b

:UnZipFile
:: %~1 = zip file path, %~2 = destination path
powershell -Command "Expand-Archive -Path '%~1' -DestinationPath '%~2' -Force"
if !errorlevel! neq 0 (
    echo Extraction using PowerShell has failed, trying with tar...

    tar -xf "%~1" -C "%~2"
    if !errorlevel! neq 0 (
        echo Extraction using tar has failed.
        echo Please download the platform-tools from the link below:
        echo Link: https://developer.android.com/tools/releases/platform-tools
        echo Then, extract it manually so fastboot.exe is at:
        echo .\platform-tools\fastboot.exe (in the same directory as this script)
        exit /b 1
    )
)
exit /b

:: ----------------------------
::  Device Detection
:: ----------------------------
:CheckFastbootDevices
setlocal
set "RETRY_COUNT=1"
set "MAX_RETRIES=3"

:CheckFastbootLoop
set "DEVICE_ID="

for /f "tokens=1" %%A in ('"%fastboot%" devices 2^>nul') do (
    set "DEVICE_ID=%%A"
)

if defined DEVICE_ID (
    echo [SUCCESS] Fastboot device detected: %DEVICE_ID%
    endlocal
    exit /b 0
) else (
    echo [ERROR] No fastboot device detected! Attempt %RETRY_COUNT% of %MAX_RETRIES%
    echo - Ensure your device is in fastboot mode.
    echo - Check USB connection / try a different cable or port.
    echo - Install or update proper fastboot drivers.
    echo.

    if %RETRY_COUNT% lss %MAX_RETRIES% (
        set /a RETRY_COUNT+=1
        pause
        goto :CheckFastbootLoop
    ) else (
        echo [FAILED] No device detected after %MAX_RETRIES% attempts.
        echo Please fix the above issues and re-run the flasher.
        endlocal
        exit /b 1
    )
)

:: ----------------------------
::  Slot Management
:: ----------------------------
:SetActiveSlotA
call :Log "[SLOT] --set-active=a"
%fastboot% --set-active=a
if !errorlevel! neq 0 (
    echo [ERROR] Failed to set active slot to A. Aborting
    call :Log "[FAIL] --set-active=a — FAILED"
    pause
    exit /b 1
)
call :Log "[OK] Active slot set to A"
exit /b

:ShowSlotInfo
set "current_slot="
for /f "tokens=2 delims=: " %%a in ('%fastboot% getvar current-slot 2^>^&1 ^| find "current-slot:"') do (
    set current_slot=%%a
)

:: Normalize slot
set "current_slot=%current_slot:_=%"
set "current_slot=%current_slot: =%"

if /i "%current_slot%"=="a" (
    set "active_slot=a"
    set "inactive_slot=b"
    echo Active slot   : a
    echo Inactive slot : b
    call :Log "[SLOT] Active=a, Inactive=b"
) else if /i "%current_slot%"=="b" (
    set "active_slot=b"
    set "inactive_slot=a"
    echo Active slot   : b
    echo Inactive slot : a
    call :Log "[SLOT] Active=b, Inactive=a"
) else (
    echo [ERROR] Unable to determine active slot.
    call :Log "[FAIL] Unable to determine active slot"
)
exit /b

:SwapSlot
call :Log "[SLOT] --set-active=other (swap)"
%fastboot% --set-active=other
if !errorlevel! neq 0 (
    echo [ERROR] Failed to switch to inactive slot. Aborting
    call :Log "[FAIL] --set-active=other — FAILED"
    pause
    exit /b 1
)
call :Log "[OK] Slot swapped to inactive"
exit /b

:: ----------------------------
::  Flashing Operations
:: ----------------------------
:FlashImage
:: %~1 = partition, %~2 = image file
call :Log "[FLASH] flash %~1 %~2"
%fastboot% flash %~1 %~2
if !errorlevel! neq 0 (
    call :Log "[FAIL] flash %~1 %~2 — FAILED"
    call :Choice "Flashing %~2 failed"
) else (
    call :Log "[OK] flash %~1 %~2 — success"
)
exit /b

:FlashVBMeta
:: %~1 = partition, %~2 = image file, %~3 = disable_avb (0 or 1)
if "%~3"=="1" (
    call :Log "[FLASH] flash %~1 %~2 --disable-verity --disable-verification"
    %fastboot% --disable-verity --disable-verification flash %~1 %~2
) else (
    call :Log "[FLASH] flash %~1 %~2"
    %fastboot% flash %~1 %~2
)
if !errorlevel! neq 0 (
    call :Log "[FAIL] flash vbmeta %~1 %~2 — FAILED"
    call :Choice "Flashing %~2 failed"
) else (
    call :Log "[OK] flash vbmeta %~1 %~2 — success"
)
exit /b

:ErasePartition
echo [INFO] Erasing %~1 partition...
call :Log "[ERASE] erase %~1"
"%fastboot%" erase %~1
if !errorlevel! neq 0 (
    echo [ERROR] Erasing %~1 partition failed
    call :Log "[FAIL] erase %~1 — FAILED"
) else (
    echo [SUCCESS] Erased %~1 partition
    call :Log "[OK] erase %~1 — success"
)
exit /b

:FlashSuper
call :RebootBootloader
%fastboot% flash super super.img
if !errorlevel! neq 0 (
    call :RebootFastbootD
    call :FlashImage super super.img
)
exit /b

:: ----------------------------
::  Reboot Operations
:: ----------------------------
:RebootFastbootD
echo ##########################
echo # REBOOTING TO FASTBOOTD #
echo ##########################
call :Log "[REBOOT] reboot fastboot"
%fastboot% reboot fastboot
if !errorlevel! neq 0 (
    echo [ERROR] Failed to reboot to fastbootd. Aborting
    call :Log "[FAIL] reboot fastboot — FAILED"
    pause
    exit
)
call :Log "[OK] Rebooted to fastbootd"
exit /b

:RebootBootloader
echo ###########################
echo # REBOOTING TO BOOTLOADER #
echo ###########################
call :Log "[REBOOT] reboot bootloader"
%fastboot% reboot bootloader
if !errorlevel! neq 0 (
    echo [ERROR] Failed to reboot to bootloader. Aborting
    call :Log "[FAIL] reboot bootloader — FAILED"
    pause
    exit
)
call :Log "[OK] Rebooted to bootloader"
exit /b

:: ----------------------------
::  Logical Partition Management
:: ----------------------------
:WipeSuperPartition
call :Log "[SUPER] wipe-super super_empty.img"
%fastboot% wipe-super super_empty.img
if !errorlevel! neq 0 (
    echo Wiping super partition failed. Fallback to deleting and creating logical partitions
    call :Log "[FAIL] wipe-super — FAILED, falling back to resize"
    call :ResizeLogicalPartition
) else (
    call :Log "[OK] wipe-super — success"
)
exit /b

:ResizeLogicalPartition
if defined JUNK_LOGICAL_PARTITIONS (
    for %%i in (!JUNK_LOGICAL_PARTITIONS!) do (
        for %%s in (a b) do (
            call :DeleteLogicalPartition %%i_%%s-cow
            call :DeleteLogicalPartition %%i_%%s
        )
    )
)

for %%i in (!LOGICAL_PARTITIONS!) do (
    for %%s in (a b) do (
        call :DeleteLogicalPartition %%i_%%s-cow
        call :DeleteLogicalPartition %%i_%%s
        call :CreateLogicalPartition %%i_%%s 1
    )
)
exit /b

:DeleteLogicalPartition
echo %~1 | find /c "cow" 2>&1
if !errorlevel! equ 0 (
    set partition_is_cow=true
) else (
    set partition_is_cow=false
)
call :Log "[PARTITION] delete-logical-partition %~1"
%fastboot% delete-logical-partition %~1
if !errorlevel! neq 0 (
    if !partition_is_cow! equ false (
        call :Log "[FAIL] delete-logical-partition %~1 — FAILED"
        call :Choice "Deleting %~1 partition failed"
    )
) else (
    call :Log "[OK] delete-logical-partition %~1 — success"
)
exit /b

:CreateLogicalPartition
call :Log "[PARTITION] create-logical-partition %~1 %~2"
%fastboot% create-logical-partition %~1 %~2
if !errorlevel! neq 0 (
    call :Log "[FAIL] create-logical-partition %~1 — FAILED"
    call :Choice "Creating %~1 partition failed"
) else (
    call :Log "[OK] create-logical-partition %~1 — success"
)
exit /b

:: ----------------------------
::  User Prompts
:: ----------------------------
:Choice
choice /m "%~1 continue? If unsure say N"
if !errorlevel! equ 2 (
    call :Log "[ABORT] User chose to abort after: %~1"
    exit
)
call :Log "[CONTINUE] User chose to continue after: %~1"
exit /b

:: ----------------------------
::  Logging
:: ----------------------------
:Log
:: %~1 = message to log (writes to log file only; console output is handled by existing echo statements)
echo %~1 >> "%LOG_FILE%" 2>nul
exit /b
