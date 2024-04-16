@echo off
title Nothing Phone 2a Fastboot ROM Flasher (t.me/NothingPhone2a)

echo #############################################################################
echo #                Pacman Fastboot ROM Flasher                                #
echo #                   Developed/Tested By                                     #
echo #  HELLBOY017, viralbanda, spike0en, PHATwalrus, arter97, AntoninoScordino  #
echo #          [Nothing Phone (2a) Telegram Dev Team]                           #
echo #############################################################################

cd %~dp0

if not exist platform-tools-latest (
    curl -L https://dl.google.com/android/repository/platform-tools-latest-windows.zip -o platform-tools-latest.zip
    Call :UnZipFile "%~dp0platform-tools-latest", "%~dp0platform-tools-latest.zip"
    del /f /q platform-tools-latest.zip
)

set fastboot=.\platform-tools-latest\platform-tools\fastboot.exe
if not exist %fastboot% (
    echo Fastboot cannot be executed. Aborting
    pause
    exit
)

set boot_partitions=boot dtbo init_boot vendor_boot
set firmware_partitions=apusys audio_dsp ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz lk logo mcf_ota mcupm md1img mvpu_algo pi_img scp spmfw sspm tee vcp
set logical_partitions=odm vendor system_ext system
set vbmeta_partitions=vbmeta_system vbmeta_vendor

echo #############################
echo # CHECKING FASTBOOT DEVICES #
echo #############################
%fastboot% devices

%fastboot% getvar current-slot 2>&1 | find /c "current-slot: a" > tmpFile.txt
set /p active_slot= < tmpFile.txt
del /f /q tmpFile.txt
if %active_slot% equ 0 (
    echo #############################
    echo # CHANGING ACTIVE SLOT TO A #
    echo #############################
    call :SetActiveSlot
)

echo ###################
echo # FORMATTING DATA #
echo ###################
choice /m "Wipe Data?"
if %errorlevel% equ 1 (
    echo Please ignore "Did you mean to format this partition?" warnings.
    call :ErasePartition userdata
    call :ErasePartition metadata
)

echo ############################
echo # FLASHING BOOT PARTITIONS #
echo ############################
choice /m "Flash images on both slots? If unsure, say N."
if %errorlevel% equ 1 (
    set slot=all
) else (
    set slot=a
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

echo ##########################             
echo # REBOOTING TO FASTBOOTD #       
echo ##########################
%fastboot% reboot fastboot
if %errorlevel% neq 0 (
    echo Error occured while rebooting to fastbootd. Aborting
    pause
    exit
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

:: 'preloader_raw.img' must be flashed at a different partition name
if %slot% equ all (
    for %%s in (a b) do (
            call :FlashImage preloader_%%s, preloader_raw.img
        ) 
) else (
    call :FlashImage preloader_%slot%, preloader_raw.img
)

echo ###################
echo # FLASHING VBMETA #
echo ###################
set disable_avb=0
choice /m "Disable android verified boot?, If unsure, say N. Bootloader won't be lockable if you select Y."
if %errorlevel% equ 1 (
    set disable_avb=1
    call :FlashImage "vbmeta --disable-verity --disable-verification", vbmeta.img
) else (
    call :FlashImage "vbmeta", vbmeta.img
)

echo ###############################
echo # FLASHING LOGICAL PARTITIONS #
echo ###############################
echo Flash logical partition images?
echo If you're about to install a custom ROM that distributes its own logical partitions, say N.
choice /m "If unsure, say Y."
if %errorlevel% equ 1 (
    if not exist super.img (
        if exist super_empty.img (
            call :WipeSuperPartition
        ) else (
            call :ResizeLogicalPartition
        )
        if %slot% equ all (
            for %%i in (%logical_partitions%) do (
                for %%s in (a b) do (
                    call :FlashImage %%i_%%s, %%i.img
                )
            ) 
        ) else (
            for %%i in (%logical_partitions%) do (
                call :FlashImage %%i_%slot%, %%i.img
            )
        )
    ) else (
        call :FlashImage super, super.img
    )
)

echo ####################################
echo # FLASHING OTHER VBMETA PARTITIONS #
echo ####################################
for %%i in (%vbmeta_partitions%) do (
    if %disable_avb% equ 1 (
            if %slot% equ all (
                for %%i in (%vbmeta_partitions%) do (
                    for %%s in (a b) do (
                        call :FlashImage "%%i_%%s --disable-verity --disable-verification", %%i.img
                    )
                ) 
            ) else (
                for %%i in (%vbmeta_partitions%) do (
                    call :FlashImage "%%i_%slot% --disable-verity --disable-verification", %%i.img
                )
        )
    ) else (
            if %slot% equ all (
                for %%i in (%vbmeta_partitions%) do (
                    for %%s in (a b) do (
                        call :FlashImage "%%i_%%s --disable-verity --disable-verification", %%i.img
                    )
                ) 
            ) else (
                for %%i in (%vbmeta_partitions%) do (
                    call :FlashImage "%%i_%slot% --disable-verity --disable-verification", %%i.img
                )
        )
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

:UnZipFile
if not exist "%~dp0platform-tools-latest" (
    powershell -command "Expand-Archive -Path '%~dp0platform-tools-latest.zip' -DestinationPath '%~dp0platform-tools-latest' -Force"
)
exit /b

:ErasePartition
%fastboot% erase %~1
if %errorlevel% neq 0 (
    call :Choice "Erasing %~1 partition failed"
)
exit /b

:SetActiveSlot
%fastboot% --set-active=a
if %errorlevel% neq 0 (
    echo Error occured while switching to slot A. Aborting
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
for %%i in (%logical_partitions%) do (
    for %%s in (a b) do (
        call :DeleteLogicalPartition %%i_%%s-cow
        call :DeleteLogicalPartition %%i_%%s
        call :CreateLogicalPartition %%i_%%s, 1
    )
)
exit /b

:DeleteLogicalPartition
%fastboot% delete-logical-partition %~1
if %errorlevel% neq 0 (
    call :Choice "Deleting %~1 partition failed"
)
exit /b

:CreateLogicalPartition
%fastboot% create-logical-partition %~1 %~2
if %errorlevel% neq 0 (
    call :Choice "Creating %~1 partition failed"
)
exit /b

:FlashImage
%fastboot% flash %~1 %~2
if %errorlevel% neq 0 (
    call :Choice "Flashing %~2 failed"
)
exit /b

:Choice
choice /m "%~1 continue? If unsure say N"
if %errorlevel% equ 2 (
    exit
)
exit /b
