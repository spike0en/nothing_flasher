@echo off
title Nothing Phone 3 Fastboot ROM Flasher

echo ################################
echo # Metroid Fastboot ROM Flasher #
echo ################################

cd %~dp0

if not exist platform-tools-latest (
    echo Downloading latest platform drivers...
    Call :GetFile "https://dl.google.com/android/repository/platform-tools-latest-windows.zip" , "%~dp0platform-tools-latest.zip"
    Call :UnZipFile "%~dp0platform-tools-latest", "%~dp0platform-tools-latest.zip"
    del /f /q platform-tools-latest.zip
)

set fastboot=.\platform-tools-latest\platform-tools\fastboot.exe
if not exist %fastboot% (
    echo Fastboot cannot be executed. Aborting
    pause
    exit
)

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

:GetFile
set "dwn=%temp%\download.vbs"
if exist "%dwn%" del /f /q "%dwn%"

>%dwn% echo strUrl = "%~1"
>>%dwn% echo strFile = "%~2"
>>%dwn% echo Set Post = CreateObject("MSXML2.XMLHTTP")
>>%dwn% echo Post.open "GET", strUrl, False
>>%dwn% echo Post.send
>>%dwn% echo Set aGet = CreateObject("ADODB.Stream")
>>%dwn% echo aGet.Type = 1
>>%dwn% echo aGet.Open
>>%dwn% echo aGet.Write Post.responseBody
>>%dwn% echo aGet.SaveToFile strFile, 2
>>%dwn% echo aGet.Close

cscript //nologo "%dwn%" >nul 2>&1
if exist "%dwn%" del /f /q "%dwn%"
exit /b

:UnZipFile
set "uzp=%temp%\unzip.vbs"
if exist "%uzp%" del /f /q "%uzp%"

>%uzp%  echo Set fso = CreateObject("Scripting.FileSystemObject")
>>%uzp% echo If NOT fso.FolderExists(fso.GetAbsolutePathName("%~1")) Then
>>%uzp% echo     fso.CreateFolder(fso.GetAbsolutePathName("%~1"))
>>%uzp% echo End If
>>%uzp% echo Set objShell = CreateObject("Shell.Application")
>>%uzp% echo Set FilesInZip = objShell.NameSpace(fso.GetAbsolutePathName("%~2")).Items
>>%uzp% echo objShell.NameSpace(fso.GetAbsolutePathName("%~1")).CopyHere FilesInZip
>>%uzp% echo Set fso = Nothing
>>%uzp% echo Set objShell = Nothing

cscript //nologo "%uzp%" >nul 2>&1
if exist "%uzp%" del /f /q "%uzp%"
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
