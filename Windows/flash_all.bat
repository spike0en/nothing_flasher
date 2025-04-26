:: SPDX-FileCopyrightText: Hellboy017, spike0en
:: SPDX-License-Identifier: MIT

@echo off
title Nothing Phone 3a Series Fastboot ROM Flasher

:: Ensure the script runs as administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    :: Relaunch the script as administrator using PowerShell
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ##################################
echo # Asteroids Fastboot ROM Flasher #
echo ##################################

:: Set partition variables
set boot_partitions=boot init_boot vendor_boot dtbo recovery
set firmware_partitions=abl aop aop_config bluetooth cpucp cpucp_dtb devcfg dsp featenabler hyp imagefv keymaster modem multiimgoem pvmfw qupfw shrm tz uefi uefisecapp xbl xbl_config xbl_ramdump
set logical_partitions=system system_ext product vendor system_dlkm vendor_dlkm odm
set junk_logical_partitions=null
set vbmeta_partitions=vbmeta_system vbmeta_vendor

:: Set working directory
set "WORK_DIR=%~dp0"
echo [INFO] Setting working directory to: "%WORK_DIR%"
cd /d "%WORK_DIR%" 2>nul || (
    echo [ERROR] Failed to set working directory: "%WORK_DIR%"
    pause
    exit /b 1
)
echo [SUCCESS] Working directory set to: "%CD%"

echo ############################
echo #  PRE-REQUIREMENTS CHECK  #
echo ############################

:: Check 1: Is bootloader unlocked?
choice /m "Is your device bootloader unlocked?"
if %errorlevel% equ 2 (
    echo To use this script, your device bootloader must be unlocked.
    echo Please unlock it before proceeding.
    pause
    exit /b 1
)

:: Check 2: Is the device in bootloader mode?
choice /m "Are you in bootloader mode?"
if %errorlevel% equ 2 (
    echo Ensure your device is in bootloader mode before proceeding.
    echo You can enter bootloader mode by holding Power + Volume Down and releasing the Power Key when the OEM logo appears or by using:
    echo adb reboot bootloader
    pause
    exit /b 1
)

:: Check 3: Are fastboot drivers installed?
choice /m "Are your fastboot drivers properly installed? (Can you see 'Android Bootloader Interface' in Device Manager?)"
if %errorlevel% equ 2 (
    echo Please install the proper fastboot drivers before proceeding.
    echo Install the latest Google USB Drivers from https://developer.android.com/studio/run/win-usb
    pause
    exit /b 1
)

echo All pre-requirements met! Proceeding...

:: ----------------------------------
::  PLATFORM TOOLS SETUP & VALIDATION
:: ----------------------------------

:: Setup platform-tools
call :PlatformToolsSetup

:: Validate fastboot existence
call :FastbootValidation

echo #############################
echo # CHECKING FASTBOOT DEVICES #
echo #############################
call :CheckFastbootDevices

echo #############################
echo # CHANGING ACTIVE SLOT TO A #
echo #############################
call :SetActiveSlot

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if %errorlevel% equ 1 (
    echo Please ignore "Did you mean to format this partition?" warnings.
    call :ErasePartition userdata
    call :ErasePartition metadata
) else (
    echo Data wipe canceled.
    exit /b
)

echo ############################
echo # FLASHING BOOT PARTITIONS #
echo ############################
set slot=a
choice /m "Flash images on both slots? If unsure, say N."
if %errorlevel% equ 1 (
    set slot=all
)

if %slot% equ all (
    for %%i in (%boot_partitions%) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s, %%i.img
        )
    ) 
) else (
    for %%i in (%boot_partitions%) do (
        call :FlashImage %%i_%slot%, %%i.img
    )
)

echo ###################
echo # FLASHING VBMETA #
echo ###################
set disable_avb=0
choice /m "Disable android verified boot?, If unsure, say N. Bootloader won't be lockable if you select Y."
if %errorlevel% equ 1 (
    set disable_avb=1
    if %slot% equ all (
        for %%s in (a b) do (
            call :FlashImage "vbmeta_%%s --disable-verity --disable-verification", vbmeta.img
        )
    ) else (
        call :FlashImage "vbmeta_a --disable-verity --disable-verification", vbmeta.img
    )
) else (
    if %slot% equ all (
        for %%s in (a b) do (
            call :FlashImage "vbmeta_%%s", vbmeta.img
        )
    ) else (
        call :FlashImage "vbmeta_a", vbmeta.img
    )
)

call :RebootFastbootD

echo ###############################
echo # FLASHING LOGICAL PARTITIONS #
echo ###############################
if not exist super.img (
    if exist super_empty.img (
        call :WipeSuperPartition
    ) else (
        call :ResizeLogicalPartition
    )
    for %%i in (%logical_partitions%) do (
        call :FlashImage %%i, %%i.img
    )
) else (
    call :FlashImage super, super.img
)

echo ####################################
echo # FLASHING OTHER VBMETA PARTITIONS #
echo ####################################
for %%i in (%vbmeta_partitions%) do (
    if %disable_avb% equ 1 (
        call :FlashImage "%%i --disable-verity --disable-verification", %%i.img
    ) else (
        call :FlashImage %%i, %%i.img
    )
)

echo #####################
echo # FLASHING FIRMWARE #
echo #####################
if %slot% equ all (
    for %%i in (%firmware_partitions%) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s, %%i.img
        )
    ) 
) else (
    for %%i in (%firmware_partitions%) do (
        call :FlashImage %%i_%slot%, %%i.img
    )
)

echo #############
echo # REBOOTING #
echo #############
choice /m "Reboot to system? If unsure, say Y."
if %errorlevel% equ 1 (
    %fastboot% reboot
)

echo ########
echo # DONE #
echo ########
echo Stock firmware restored.
echo You may now optionally re-lock the bootloader if you haven't disabled android verified boot.

pause
exit

:PlatformToolsSetup
echo #############################
echo # SETTING UP PLATFORM TOOLS #
echo #############################
if not exist platform-tools-latest (
    echo Platform tools not found. Downloading...
    curl --ssl-no-revoke -L https://dl.google.com/android/repository/platform-tools-latest-windows.zip -o platform-tools-latest.zip
    if exist platform-tools-latest.zip (
        echo Platform tools downloaded successfully.
        call :UnZipFile "%~dp0platform-tools-latest.zip" "%~dp0platform-tools-latest"
        echo Platform tools extracted successfully.
        del /f /q platform-tools-latest.zip
    ) else (
        echo Error: Failed to download platform tools.
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
set "fastboot=.\platform-tools-latest\platform-tools\fastboot.exe"

:: Ensure fastboot.exe exists
if not exist "%fastboot%" (
    echo [ERROR] Fastboot executable not found.
    echo Please ensure platform tools are properly downloaded.
    pause
    exit /b 1
)

:: Ensure fastboot is executable and prints version
%fastboot% --version
if %errorlevel% neq 0 (
    echo [ERROR] Fastboot executable is not functioning properly.
    echo Try running "fastboot --version" manually.
    pause
    exit /b 1
)

echo [SUCCESS] Fastboot executable found and verified.
exit /b

:UnZipFile
:: Try to extract using PowerShell
powershell -Command "Expand-Archive -Path '%~1' -DestinationPath '%~2' -Force"
if %errorlevel% neq 0 (
    :: If PowerShell fails, display message and prepare to use tar
    echo Extraction using PowerShell has failed, trying with tar...

    :: Try to extract using tar
    if exist "%~2" (
        echo Directory "%~2" exists, removing it...
        rmdir /s /q "%~2"
    )
    mkdir "%~2"
    tar -xf "%~1" -C "%~2"
    if %errorlevel% neq 0 (
        :: In rare cases, if tar also fails, guide the user to do it manually
        echo Extraction using tar has failed.
        echo Please download the platform-tools from the link below:
        echo Link: https://developer.android.com/tools/releases/platform-tools
        echo Then, extract it manually to the following directory structure:
        echo .\platform-tools-latest\platform-tools\ (in the same directory as this script)
        echo
        exit /b 1
    )
)
exit /b

:CheckFastbootDevices
:: Clear any previous DEVICE_ID
set "DEVICE_ID="

:: Run fastboot devices and capture output
for /f "tokens=1" %%A in ('%fastboot% devices 2^>nul') do (
    set "DEVICE_ID=%%A"
)

:: Check if fastboot executed successfully
if %errorlevel% neq 0 (
    echo [ERROR] Fastboot command failed to execute.
    echo - Ensure fastboot.exe is available and your environment is set up correctly.
    pause
    exit /b 1
)

:: Check if a device was detected
if not defined DEVICE_ID (
    echo [ERROR] No fastboot device detected!
    echo - Ensure your device is in fastboot mode.
    echo - Check USB connection and try a different port.
    echo - Install proper drivers if not already installed.
    echo - Run "fastboot devices" manually to verify.
    pause
    exit /b 1
)

echo [SUCCESS] Fastboot device detected: %DEVICE_ID%
exit /b

:SetActiveSlot
%fastboot% --set-active=a
if %errorlevel% neq 0 (
    echo Error occured while switching to slot A. Aborting
    pause
    exit
)
exit /b

:ErasePartition
echo [INFO] Erasing %~1 partition...
"%fastboot%" erase %~1
if %errorlevel% neq 0 (
    echo [ERROR] Erasing %~1 partition failed
) else (
    echo [SUCCESS] Erased %~1 partition
)
exit /b

:FlashImage
%fastboot% flash %~1 %~2
if %errorlevel% neq 0 (
    call :Choice "Flashing %~2 failed"
)
exit /b

:RebootFastbootD
echo ##########################             
echo # REBOOTING TO FASTBOOTD #       
echo ##########################
%fastboot% reboot fastboot
if %errorlevel% neq 0 (
    echo Error occured while rebooting to fastbootd. Aborting
    pause
    exit
)
exit /b

:WipeSuperPartition
%fastboot% wipe-super super_empty.img
if %errorlevel% neq 0 (
    echo Wiping super partition failed. Fallback to deleting and creating logical partitions
    call :ResizeLogicalPartition
)
exit /b

:ResizeLogicalPartition
if %junk_logical_partitions% neq null (
    for %%i in (%junk_logical_partitions%) do (
        for %%s in (a b) do (
            call :DeleteLogicalPartition %%i_%%s-cow
            call :DeleteLogicalPartition %%i_%%s
        )
    )
)

for %%i in (%logical_partitions%) do (
    for %%s in (a b) do (
        call :DeleteLogicalPartition %%i_%%s-cow
        call :DeleteLogicalPartition %%i_%%s
        call :CreateLogicalPartition %%i_%%s, 1
    )
)
exit /b

:DeleteLogicalPartition
echo %~1 | find /c "cow" 2>&1
if %errorlevel% equ 0 (
    set partition_is_cow=true
) else (
    set partition_is_cow=false
)
%fastboot% delete-logical-partition %~1
if %errorlevel% neq 0 (
    if %partition_is_cow% equ false (
        call :Choice "Deleting %~1 partition failed"
    )
)
exit /b

:CreateLogicalPartition
%fastboot% create-logical-partition %~1 %~2
if %errorlevel% neq 0 (
    call :Choice "Creating %~1 partition failed"
)
exit /b

:RebootBootloader
echo ###########################             
echo # REBOOTING TO BOOTLOADER #       
echo ###########################
%fastboot% reboot bootloader
if %errorlevel% neq 0 (
    echo Error occured while rebooting to bootloader. Aborting
    pause
    exit
)
exit /b

:Choice
choice /m "%~1 continue? If unsure say N"
if %errorlevel% equ 2 (
    exit
)
exit /b