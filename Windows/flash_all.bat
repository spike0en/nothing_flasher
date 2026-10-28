:: SPDX-FileCopyrightText: Hellboy017, spike0en
:: SPDX-License-Identifier: MIT

@echo off
title Nothing Phone 3 Fastboot ROM Flasher

echo ################################
echo # Metroid Fastboot ROM Flasher #
echo ################################

cd %~dp0

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

:: -------------------------------------
::  FILE INTEGRITY CHECKS [RECOMMENDED]
:: -------------------------------------
call :PreHashVerificationPrompt
if %errorlevel% equ 0 (
    call :VerifyImageHashes
    if %errorlevel% neq 0 (
        echo [ABORTED] Image validation failed or canceled by user.
        pause
        exit /b 1
    )
) else (
    echo [INFO] Skipping hash verification as requested. Proceeding without validation...
)

:: ----------------------------------
::  PLATFORM TOOLS SETUP & VALIDATION
:: ----------------------------------

:: Setup platform-tools
call :PlatformToolsSetup

:: Validate fastboot existence
call :FastbootValidation

set boot_partitions=boot init_boot vendor_boot dtbo recovery
set firmware_partitions=abl aop aop_config bluetooth cpucp cpucp_dtb devcfg dsp featenabler hyp imagefv keymaster modem multiimgoem multiimgqti pvmfw qupfw shrm soccp_dcd soccp_debug tz uefi uefisecapp xbl xbl_config xbl_ramdump
set logical_partitions=system system_dlkm system_ext product vendor vendor_dlkm odm
set junk_logical_partitions=null

set super_exists=false
if exist super.img (
    set super_exists=true
)

echo #############################
echo # CHECKING FASTBOOT DEVICES #
echo #############################
%fastboot% devices

echo #########################
echo # CHECKING CURRENT SLOT #
echo #########################
for /f "tokens=2 delims=: " %%i in ('%fastboot% getvar current-slot 2^>^&1 ^| findstr /b /c:"current-slot:"') do set "current_slot=%%i"
if %current_slot% == a (
    set slot=b
) else if %current_slot% == b (
    set slot=a
) else (
    echo Error: Could not determine current slot.
    exit /b 1
)
echo Current slot: %current_slot%
if %super_exists% equ true (
    set slot=a
)
echo Target slot: %slot%

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if %errorlevel% equ 1 (
    call :WipeData
)

echo ###################
echo # FLASHING VBMETA #
echo ###################
choice /m "Disable android verified boot?, If unsure, say N. Bootloader won't be lockable if you select Y."
set disable_avb=%errorlevel%
if %disable_avb% equ 1 (
    call :FlashImage "vbmeta_%slot% --disable-verity --disable-verification", vbmeta.img
) else (
    call :FlashImage "vbmeta_%slot%", vbmeta.img
)

echo ############################
echo # FLASHING BOOT PARTITIONS #
echo ############################
for %%i in (%boot_partitions%) do (
    call :FlashImage "%%i_%slot%", %%i.img
)

echo ###############################
echo # FLASHING LOGICAL PARTITIONS #
echo ###############################
if %super_exists% neq true (
    call :RebootFastbootD
    if exist super_empty.img (
        call :WipeSuperPartition
    ) else (
        call :ResizeLogicalPartition
    )
    for %%i in (%logical_partitions%) do (
        call :FlashImage "%%i_%slot%", %%i.img
    )
) else (
    call :FlashSuper
)

echo ########################################
echo # FLASHING VBMETA_SYSTEM/VBMETA_VENDOR #
echo ########################################
for %%i in (vbmeta_system vbmeta_vendor) do (
    if %disable_avb% equ 1 (
        call :FlashImage "%%i_%slot% --disable-verity --disable-verification", %%i.img
    ) else (
        call :FlashImage "%%i_%slot%", %%i.img
    )
)

echo ########################
echo # CHANGING ACTIVE SLOT #
echo ########################
call :SetActiveSlot

echo #####################
echo # FLASHING FIRMWARE #
echo #####################
if %super_exists% equ true (
    call :RebootFastbootD
)
choice /m "Flash firmware on both slots? If unsure, say N."
set both_slots=%errorlevel%
if %both_slots% equ 1 (
    for %%i in (%firmware_partitions%) do (
        for %%s in (a b) do (
            call :FlashImage %%i_%%s, %%i.img
        )
    ) 
) else (
    for %%i in (%firmware_partitions%) do (
        call :FlashImage "%%i", %%i.img
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

pause
exit

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
if %errorlevel% equ 1 (
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
if %errorlevel% equ 1 (
    rem User chose Yes → continue
    endlocal
    exit /b 0
)

rem User chose No → show retry/exit menu
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

:PlatformToolsSetup
echo #############################
echo # SETTING UP PLATFORM TOOLS #
echo #############################
if not exist platform-tools (
    echo Platform tools not found. Downloading...
    curl --ssl-no-revoke -L https://dl.google.com/android/repository/platform-tools-latest-windows.zip -o platform-tools-latest-windows.zip
    if exist platform-tools-latest-windows.zip (
        echo Platform tools downloaded successfully.
        call :UnZipFile "%~dp0platform-tools-latest-windows.zip" "%~dp0"
        echo Platform tools extracted successfully.
        del /f /q platform-tools-latest-windows.zip
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
set "fastboot=.\platform-tools\fastboot.exe"

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
    tar -xf "%~1" -C "%~2"
    if %errorlevel% neq 0 (
        :: In rare cases, if tar also fails, guide the user to do it manually
        echo Extraction using tar has failed.
        echo Please download the platform-tools from the link below:
        echo Link: https://developer.android.com/tools/releases/platform-tools
        echo Then, extract it manually to the following directory structure:
        echo .\platform-tools\ (in the same directory as this script)
        echo.
        exit /b 1
    )
)
exit /b

:SetActiveSlot
%fastboot% set_active %slot%
if %errorlevel% neq 0 (
    echo Error occured while changing slot. Aborting
    pause
    exit
)
exit /b

:WipeData
%fastboot% -w
if %errorlevel% neq 0 (
    call :Choice "Wiping data failed"
)
exit /b

:FlashImage
%fastboot% flash %~1 %~2
if %errorlevel% neq 0 (
    call :Choice "Flashing %~2 failed"
)
exit /b

:FlashSuper
call :RebootBootloader
%fastboot% flash super super.img
if %errorlevel% neq 0 (
    call :RebootFastbootD
    call :FlashImage super, super.img
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
set partition_is_cow=%errorlevel%
%fastboot% delete-logical-partition %~1
if %errorlevel% neq 0 (
    if %partition_is_cow% neq 0 (
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
