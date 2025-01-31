@echo off
title CMF Phone (1) Fastboot ROM Flasher

:: Ensure the script runs as administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    :: Relaunch the script as administrator using PowerShell
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ###############################
echo # Tetris Fastboot ROM Flasher #
echo #   t.me/s/nothing_archive    #
echo ###############################

cd %~dp0

if not exist platform-tools-latest (
    curl --ssl-no-revoke -L https://dl.google.com/android/repository/platform-tools-latest-windows.zip -o platform-tools-latest.zip
    Call :UnZipFile "%~dp0platform-tools-latest.zip", "%~dp0platform-tools-latest"
    del /f /q platform-tools-latest.zip
)

set fastboot=.\platform-tools-latest\platform-tools\fastboot.exe
if not exist %fastboot% (
    echo Fastboot cannot be executed. Aborting
    pause
    exit
)

set boot_partitions=boot dtbo init_boot vendor_boot
set main_partitions=odm_dlkm product system_dlkm vendor_dlkm
set firmware_partitions=apusys ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz lk logo mcf_ota mcupm modem pi_img scp spmfw sspm tee vcp
set logical_partitions=odm_dlkm odm vendor_dlkm product vendor system_dlkm system_ext system
set junk_logical_partitions=null
set vbmeta_partitions=vbmeta vbmeta_system vbmeta_vendor

echo #############################
echo # CHECKING FASTBOOT DEVICES #
echo #############################
%fastboot% devices

echo #############################
echo # CHANGING ACTIVE SLOT TO A #
echo #############################
call :SetActiveSlot

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if %errorlevel% equ 1 (
    call :WipeData
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
        call :FlashImage %%i, %%i.img
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
        call :FlashImage "vbmeta --disable-verity --disable-verification", vbmeta.img
    )
) else (
    if %slot% equ all (
        for %%s in (a b) do (
            call :FlashImage "vbmeta_%%s", vbmeta.img
        )
    ) else (
        call :FlashImage "vbmeta", vbmeta.img
    )
)

:: Flash 'preloader_raw.img' separately
if %slot% equ all (
    for %%s in (a b) do (
        call :FlashImage preloader_%%s preloader_raw.img
    )
) else (
    call :FlashImage preloader_%slot% preloader_raw.img
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

    if %slot% equ all (
        for %%i in (%logical_partitions%) do (
            for %%s in (a b) do (
                call :FlashImage %%i_%%s %%i.img
            )
        )
    ) else (
        for %%i in (%logical_partitions%) do (
            call :FlashImage %%i_%slot% %%i.img
        )
    )

) else (
    call :FlashImage super super.img
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

:UnZipFile
mkdir "%~2"
tar -xf "%~1" -C "%~2"
exit /b

:SetActiveSlot
%fastboot% --set-active=a
if %errorlevel% neq 0 (
    echo Error occured while switching to slot A. Aborting
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

if %slot% equ all (
    for %%i in (%logical_partitions%) do (
        for %%s in (a b) do (
            call :DeleteLogicalPartition %%i_%%s-cow
            call :DeleteLogicalPartition %%i_%%s
            call :CreateLogicalPartition %%i_%%s, 1
        )
    )
) else (
    for %%i in (%logical_partitions%) do (
        call :DeleteLogicalPartition %%i_%slot%-cow
        call :DeleteLogicalPartition %%i_%slot%
        call :CreateLogicalPartition %%i_%slot%, 1
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

:Choice
choice /m "%~1 continue? If unsure say N"
if %errorlevel% equ 2 (
    exit
)
exit /b
