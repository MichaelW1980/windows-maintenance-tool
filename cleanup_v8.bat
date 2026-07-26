@echo off
CLS
setlocal EnableExtensions EnableDelayedExpansion

:: Windows repair and component maintenance batch - v8.0.1

set "DryRun=1"
set "KeepWorkingFolder=0"
set "DryRunNoticeShown=0"

:: Request administrator rights if needed.
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator rights...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/d /c ""%~f0""' -Verb RunAs"
    exit /b
)

set "DesktopPath=%USERPROFILE%\Desktop"
set "CBSWatcherScript=%~dp0Watch-CBSLog.ps1"
set "CBSRunAnalyzer=%~dp0Analyze-CBSRun.ps1"
set "TarExe=%SystemRoot%\System32\tar.exe"
set "CBSStopSignal=%TEMP%\cleanup_cbs_stop_%RANDOM%_%RANDOM%.signal"
set "CBSReadySignal=%TEMP%\cleanup_cbs_ready_%RANDOM%_%RANDOM%.signal"
set "CBSDoneSignal=%TEMP%\cleanup_cbs_done_%RANDOM%_%RANDOM%.signal"
set "ArchiveTimestampFile=%TEMP%\cleanup_archive_timestamp_%RANDOM%_%RANDOM%.txt"
set "CBSCaptureStarted=0"
set "RunPrepared=0"
set "ArchiveValidated=0"
set "WorkingFolderRemoved=0"
set "WorkingFolder="
set "RunBaseName="
set "ArchivePath="

if "%DryRun%"=="1" if "%DryRunNoticeShown%"=="0" (
    call :SHOW_DRYRUN_NOTICE
    set "DryRunNoticeShown=1"
)

:MENU
CLS
call :RESET_LOG_FLAGS

echo ======================================================
echo         CHOOSE YOUR PREFERRED MAINTENANCE MODE
echo ======================================================
echo.
echo [1] Health Check + Repair
echo     - DISM ScanHealth
echo     - DISM RestoreHealth
echo     - SFC scan
echo     - Icon cache reset
echo.
echo [2] Repair + Component Store Cleanup
echo     - DISM ScanHealth
echo     - DISM RestoreHealth
echo     - DISM StartComponentCleanup
echo     - SFC scan
echo     - Icon cache reset
echo.
echo [3] Repair + Shadow Copy Purge + Component Base Reset
echo     - DISM ScanHealth
echo     - DISM RestoreHealth
echo     - Attempt vssadmin shadow-copy purge on C:
echo     - Attempt vssadmin shadow-copy purge on D:
echo     - DISM StartComponentCleanup /ResetBase
echo     - SFC scan
echo     - Icon cache reset
echo.
echo [Q] Quit
echo.
choice /c 123Q /n /m "Choose 1, 2, 3, or Q: "
if errorlevel 4 goto MENU_EXIT
if errorlevel 3 goto CONFIRM_COMPONENT_BASE_RESET
if errorlevel 2 goto ConfirmComponentStoreCleanup
if errorlevel 1 goto BASIC_RECOVERY

:BASIC_RECOVERY
CLS
set "MaintenanceMode=Health Check + Repair"
set "MaintenanceModeNumber=1"
set "LogMaintenance=1"
set "LogDISMRepair=1"
set "LogSFC=1"

call :PREPARE_RUN_WORKSPACE
if errorlevel 1 goto WORKSPACE_PREPARE_FAILED

echo.
echo ==================================================
echo       HEALTH CHECK + REPAIR
echo ==================================================
echo.
echo Selected mode: %MaintenanceMode%
echo.
> "%MaintenanceLog%" echo Selected mode: %MaintenanceMode%
>> "%MaintenanceLog%" echo Started: %date% %time%
>> "%MaintenanceLog%" echo DryRun: %DryRun%
>> "%MaintenanceLog%" echo Working folder: %WorkingFolder%
>> "%MaintenanceLog%" echo KeepWorkingFolder: %KeepWorkingFolder%

call :START_CBS_CAPTURE
if errorlevel 1 goto CAPTURE_START_FAILED

call :RUN_SCANHEALTH "1/4"
call :RUN_RESTOREHEALTH "2/4"

call :RUN_SFC "3/4"

echo.
echo [4/4] Clearing Icon Cache Databases...
call :RESET_ICON_CACHE

goto FINALIZE

:ConfirmComponentStoreCleanup
cls
echo.
echo ==================================================
echo       REPAIR + COMPONENT STORE CLEANUP
echo ==================================================
echo.
echo This mode will run:
echo.
echo   DISM /Online /Cleanup-Image /StartComponentCleanup
echo.
echo This removes superseded versions of updated components from
echo the Windows component store and can reduce the WinSxS size.
echo.
echo Practical effect:
echo - Removes superseded versions of updated components
echo - May reduce rollback/uninstall material for recent updates
echo - Does NOT use /ResetBase
echo - Does NOT delete restore points or shadow copies
echo.
if "%DryRun%"=="1" echo DRY RUN: The real cleanup command will be skipped.
echo.
choice /c YN /n /m "Continue with component store cleanup? [Y/N]: "
if errorlevel 2 goto MENU
if errorlevel 1 goto COMPONENT_STORE_CLEANUP

:COMPONENT_STORE_CLEANUP
CLS
set "MaintenanceMode=Repair + Component Store Cleanup"
set "MaintenanceModeNumber=2"
set "LogMaintenance=1"
set "LogDISMRepair=1"
set "LogCleanup=1"
set "LogSFC=1"

call :PREPARE_RUN_WORKSPACE
if errorlevel 1 goto WORKSPACE_PREPARE_FAILED

echo.
echo ==================================================
echo       REPAIR + COMPONENT STORE CLEANUP
echo ==================================================
echo.
echo Selected mode: %MaintenanceMode%
echo.
> "%MaintenanceLog%" echo Selected mode: %MaintenanceMode%
>> "%MaintenanceLog%" echo Started: %date% %time%
>> "%MaintenanceLog%" echo DryRun: %DryRun%
>> "%MaintenanceLog%" echo Working folder: %WorkingFolder%
>> "%MaintenanceLog%" echo KeepWorkingFolder: %KeepWorkingFolder%

call :START_CBS_CAPTURE
if errorlevel 1 goto CAPTURE_START_FAILED

call :RUN_SCANHEALTH "1/5"
call :RUN_RESTOREHEALTH "2/5"

call :RUN_STARTCOMPONENTCLEANUP "3/5"

call :RUN_SFC "4/5"

echo.
echo [5/5] Clearing Icon Cache Databases...
call :RESET_ICON_CACHE

goto FINALIZE

:CONFIRM_COMPONENT_BASE_RESET
CLS
echo ==================================================
echo       SHADOW COPY PURGE + COMPONENT BASE RESET
echo ==================================================
echo.
echo Technical warning:
echo.
echo This mode attempts to delete client-accessible shadow copies
echo for configured volumes using vssadmin.
echo.
echo Configured shadow-copy purge targets: C: and D:
echo.
echo Then it runs:
echo.
echo   DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
echo.
echo ResetBase resets the base of superseded components and removes
echo superseded component versions from the component store.
echo.
echo After it completes, Windows update packages incorporated into
echo the new component-store baseline no longer retain their former
echo uninstall paths. Future Windows updates are not blocked.
echo.
if "%DryRun%"=="1" echo DRY RUN: Shadow-copy purge and ResetBase commands will be skipped.
echo.
choice /c YN /n /m "Continue to typed confirmation? [Y/N]: "
if errorlevel 2 goto MENU

echo.
echo FINAL CONFIRMATION:
echo Successfully deleted shadow copies will no longer be available,
echo and ResetBase removes former uninstall paths for Windows update
echo packages incorporated into the new component-store baseline.
echo.
echo To start this extended cleanup mode, type exactly:
echo.
echo   DELETE SHADOW COPIES AND RESET COMPONENT BASE
echo.
echo Anything else returns to the selection menu.
echo.
set "ConfirmText="
set /p "ConfirmText=Confirmation: "
if /i "%ConfirmText%"=="DELETE SHADOW COPIES AND RESET COMPONENT BASE" goto COMPONENT_BASE_RESET_MODE

echo.
echo Extended cleanup mode not confirmed. Returning to selection menu.
pause
goto MENU

:COMPONENT_BASE_RESET_MODE
CLS
set "MaintenanceMode=Repair + Shadow Copy Purge + Component Base Reset"
set "MaintenanceModeNumber=3"
set "LogMaintenance=1"
set "LogDISMRepair=1"
set "LogCleanup=1"
set "LogSFC=1"
set "LogResetBase=1"

call :PREPARE_RUN_WORKSPACE
if errorlevel 1 goto WORKSPACE_PREPARE_FAILED

echo ==================================================
echo       SHADOW COPY PURGE + COMPONENT BASE RESET
echo ==================================================
echo.
echo Selected mode: %MaintenanceMode%
echo.
> "%MaintenanceLog%" echo Selected mode: %MaintenanceMode%
>> "%MaintenanceLog%" echo Started: %date% %time%
>> "%MaintenanceLog%" echo DryRun: %DryRun%
>> "%MaintenanceLog%" echo Working folder: %WorkingFolder%
>> "%MaintenanceLog%" echo KeepWorkingFolder: %KeepWorkingFolder%
> "%ResetBaseLog%" echo Component base reset mode started: %date% %time%
>> "%ResetBaseLog%" echo DryRun: %DryRun%

call :START_CBS_CAPTURE
if errorlevel 1 goto CAPTURE_START_FAILED

call :RUN_SCANHEALTH "1/6"
call :RUN_RESTOREHEALTH "2/6"

call :RUN_SHADOW_PURGE "3/6"
call :RUN_RESETBASE "4/6"

call :RUN_SFC "5/6"

echo.
echo [6/6] Clearing Icon Cache Databases...
call :RESET_ICON_CACHE

>> "%ResetBaseLog%" echo Component base reset mode completed: %date% %time%
goto FINALIZE

:RUN_SCANHEALTH
echo.
echo [%~1] Scanning Component Store ^(ScanHealth^)...
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping DISM ScanHealth.
    set "LastError=0"
) else (
    Dism /Online /Cleanup-Image /ScanHealth
    set "LastError=!errorlevel!"
)
>> "%MaintenanceLog%" echo ScanHealth exit code: !LastError! at %date% %time%
exit /b 0

:RUN_RESTOREHEALTH
echo.
echo [%~1] Repairing Component Store ^(RestoreHealth^)...
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping DISM RestoreHealth.
    set "LastError=0"
) else (
    Dism /Online /Cleanup-Image /RestoreHealth
    set "LastError=!errorlevel!"
)
>> "%MaintenanceLog%" echo RestoreHealth exit code: !LastError! at %date% %time%
exit /b 0

:RUN_STARTCOMPONENTCLEANUP
echo.
echo [%~1] Cleaning WinSxS Store ^(StartComponentCleanup^)...
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping DISM StartComponentCleanup.
    set "LastError=0"
) else (
    Dism /Online /Cleanup-Image /StartComponentCleanup
    set "LastError=!errorlevel!"
)
>> "%MaintenanceLog%" echo StartComponentCleanup exit code: !LastError! at %date% %time%
exit /b 0

:RUN_SHADOW_PURGE
echo.
echo [%~1] Attempting shadow-copy purge ^(vssadmin^)...
>> "%ResetBaseLog%" echo Shadow-copy purge command started: %date% %time%
>> "%ResetBaseLog%" echo Configured purge targets: C: and D:
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping shadow-copy purge for C: and D:.
    >> "%ResetBaseLog%" echo Command skipped: vssadmin delete shadows /for=C: /all /quiet
    >> "%ResetBaseLog%" echo Command skipped: vssadmin delete shadows /for=D: /all /quiet
    set "ShadowPurgeC=0"
    set "ShadowPurgeD=0"
) else (
    >> "%ResetBaseLog%" echo Command: vssadmin delete shadows /for=C: /all /quiet
    vssadmin delete shadows /for=C: /all /quiet
    set "ShadowPurgeC=!errorlevel!"

    >> "%ResetBaseLog%" echo Command: vssadmin delete shadows /for=D: /all /quiet
    vssadmin delete shadows /for=D: /all /quiet
    set "ShadowPurgeD=!errorlevel!"
)
>> "%ResetBaseLog%" echo Shadow-copy purge command completed: %date% %time%
>> "%ResetBaseLog%" echo Shadow-copy purge C: exit code: !ShadowPurgeC!
>> "%ResetBaseLog%" echo Shadow-copy purge D: exit code: !ShadowPurgeD!
>> "%MaintenanceLog%" echo Shadow-copy purge C: exit code: !ShadowPurgeC! at %date% %time%
>> "%MaintenanceLog%" echo Shadow-copy purge D: exit code: !ShadowPurgeD! at %date% %time%
exit /b 0

:RUN_RESETBASE
echo.
echo [%~1] Resetting Component Base ^(StartComponentCleanup /ResetBase^)...
>> "%ResetBaseLog%" echo ResetBase command started: %date% %time%
>> "%ResetBaseLog%" echo Command: Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping DISM StartComponentCleanup /ResetBase.
    set "LastError=0"
) else (
    Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    set "LastError=!errorlevel!"
)
>> "%ResetBaseLog%" echo ResetBase command completed: %date% %time%
>> "%ResetBaseLog%" echo ResetBase exit code: !LastError!
>> "%MaintenanceLog%" echo ResetBase exit code: !LastError! at %date% %time%
exit /b 0

:RUN_SFC
echo.
echo [%~1] Verifying System File Integrity ^(SFC^)...
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping SFC /scannow.
    set "LastError=0"
) else (
    sfc /scannow
    set "LastError=!errorlevel!"
)
>> "%MaintenanceLog%" echo SFC exit code: !LastError! at %date% %time%
exit /b 0


:PREPARE_RUN_WORKSPACE
if not exist "%CBSWatcherScript%" (
    echo ERROR: Required CBS watcher script was not found:
    echo %CBSWatcherScript%
    exit /b 1
)

if not exist "%CBSRunAnalyzer%" (
    echo ERROR: Required CBS run analyzer was not found:
    echo %CBSRunAnalyzer%
    exit /b 1
)

if not exist "%TarExe%" (
    echo ERROR: Required Windows archive utility was not found:
    echo %TarExe%
    exit /b 1
)

set "RunTimestamp="
del "%ArchiveTimestampFile%" >nul 2>&1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -Command "[DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss') | Set-Content -LiteralPath $env:ArchiveTimestampFile -Encoding ASCII"
if errorlevel 1 (
    echo ERROR: Could not generate the run timestamp.
    del "%ArchiveTimestampFile%" >nul 2>&1
    exit /b 1
)

if exist "%ArchiveTimestampFile%" set /p "RunTimestamp="<"%ArchiveTimestampFile%"
del "%ArchiveTimestampFile%" >nul 2>&1

if not defined RunTimestamp (
    echo ERROR: The generated run timestamp could not be read.
    exit /b 1
)

set "RunBaseStem=cleanup-report_!RunTimestamp!"
set "RunBaseName=!RunBaseStem!"
set /a "RunCollisionIndex=0"

:CHECK_RUN_NAME_COLLISION
if not exist "%DesktopPath%\!RunBaseName!" if not exist "%DesktopPath%\!RunBaseName!.zip" goto RUN_NAME_AVAILABLE
set /a "RunCollisionIndex+=1"
if !RunCollisionIndex! GTR 99 (
    echo ERROR: Could not find an unused timestamped report name.
    exit /b 1
)
if !RunCollisionIndex! LSS 10 (
    set "RunCollisionSuffix=0!RunCollisionIndex!"
) else (
    set "RunCollisionSuffix=!RunCollisionIndex!"
)
set "RunBaseName=!RunBaseStem!_!RunCollisionSuffix!"
goto CHECK_RUN_NAME_COLLISION

:RUN_NAME_AVAILABLE
set "WorkingFolder=%DesktopPath%\!RunBaseName!"
set "ArchivePath=%DesktopPath%\!RunBaseName!.zip"
mkdir "!WorkingFolder!" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not create the timestamped working folder:
    echo !WorkingFolder!
    set "WorkingFolder="
    set "ArchivePath="
    exit /b 1
)

set "LogPath=!WorkingFolder!"
set "MaintenanceLog=!LogPath!\Maintenance_Mode_Log.txt"
set "DISMRepairLog=!LogPath!\DISM_Repair_Details.txt"
set "CleanupLog=!LogPath!\Cleanup_Details.txt"
set "CleanupContentRetentionLog=!LogPath!\Cleanup_Content_Retention_Details.txt"
set "SFCLog=!LogPath!\SFC_Details.txt"
set "ResetBaseLog=!LogPath!\Component_Base_Reset_Log.txt"
set "CBSRunLog=!LogPath!\CBS_Run_Capture.log"
set "RunPrepared=1"
set "ArchiveValidated=0"
set "WorkingFolderRemoved=0"
exit /b 0


:ANALYZE_CBS_RUN
if not exist "%CBSRunAnalyzer%" (
    echo WARNING: Required CBS run analyzer was not found:
    echo %CBSRunAnalyzer%
    >> "%MaintenanceLog%" echo CBS run analyzer failed: script missing at %date% %time%
    exit /b 1
)

del "%DISMRepairLog%" "%CleanupLog%" "%CleanupContentRetentionLog%" "%SFCLog%" >nul 2>&1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%CBSRunAnalyzer%" -SourceLog "%CBSRunLog%" -Mode "%MaintenanceModeNumber%" -DISMRepairLog "%DISMRepairLog%" -CleanupLog "%CleanupLog%" -ContentRetentionLog "%CleanupContentRetentionLog%" -SFCLog "%SFCLog%"
set "CBSAnalyzerError=!errorlevel!"
>> "%MaintenanceLog%" echo CBS run analyzer exit code: !CBSAnalyzerError! at %date% %time%

if not "!CBSAnalyzerError!"=="0" (
    echo WARNING: CBS run analyzer failed with exit code !CBSAnalyzerError!.
    echo The raw CBS_Run_Capture.log remains available for manual analysis.
    exit /b !CBSAnalyzerError!
)

set "CBSAnalyzerMissingOutput=0"
if not exist "%DISMRepairLog%" (
    echo WARNING: CBS analyzer did not create DISM_Repair_Details.txt.
    >> "%MaintenanceLog%" echo CBS analyzer output missing: DISM_Repair_Details.txt at %date% %time%
    set "CBSAnalyzerMissingOutput=1"
)
if not exist "%SFCLog%" (
    echo WARNING: CBS analyzer did not create SFC_Details.txt.
    >> "%MaintenanceLog%" echo CBS analyzer output missing: SFC_Details.txt at %date% %time%
    set "CBSAnalyzerMissingOutput=1"
)
if not "%MaintenanceModeNumber%"=="1" (
    if not exist "%CleanupLog%" (
        echo WARNING: CBS analyzer did not create Cleanup_Details.txt.
        >> "%MaintenanceLog%" echo CBS analyzer output missing: Cleanup_Details.txt at %date% %time%
        set "CBSAnalyzerMissingOutput=1"
    )
    if not exist "%CleanupContentRetentionLog%" (
        echo WARNING: CBS analyzer did not create Cleanup_Content_Retention_Details.txt.
        >> "%MaintenanceLog%" echo CBS analyzer output missing: Cleanup_Content_Retention_Details.txt at %date% %time%
        set "CBSAnalyzerMissingOutput=1"
    )
)

if "!CBSAnalyzerMissingOutput!"=="1" exit /b 2
exit /b 0

:START_CBS_CAPTURE
if not exist "%CBSWatcherScript%" (
    echo ERROR: Required CBS watcher script was not found:
    echo %CBSWatcherScript%
    >> "%MaintenanceLog%" echo CBS capture failed: watcher script missing at %date% %time%
    exit /b 1
)

if not exist "%CBSRunAnalyzer%" (
    echo ERROR: Required CBS run analyzer was not found:
    echo %CBSRunAnalyzer%
    >> "%MaintenanceLog%" echo Maintenance preflight failed: CBS run analyzer missing at %date% %time%
    exit /b 1
)

del "%CBSStopSignal%" "%CBSReadySignal%" "%CBSDoneSignal%" >nul 2>&1

echo.
echo Starting run-scoped CBS capture...
start "CBS Run Capture" /b "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%CBSWatcherScript%" -SourcePath "%windir%\Logs\CBS\CBS.log" -DestinationPath "%CBSRunLog%" -StopSignalPath "%CBSStopSignal%" -ReadySignalPath "%CBSReadySignal%" -DoneSignalPath "%CBSDoneSignal%"

set /a "CBSWaitCount=0"
:WAIT_FOR_CBS_READY
if exist "%CBSReadySignal%" goto CBS_CAPTURE_READY
if exist "%CBSRunLog%.error.txt" goto CBS_CAPTURE_ERROR
set /a "CBSWaitCount+=1"
if !CBSWaitCount! GEQ 60 goto CBS_CAPTURE_TIMEOUT
>nul 2>&1 ping 127.0.0.1 -n 2
goto WAIT_FOR_CBS_READY

:CBS_CAPTURE_READY
set "CBSCaptureStarted=1"
>> "%MaintenanceLog%" echo CBS run capture started: %date% %time%
>> "%MaintenanceLog%" echo CBS run capture file: %CBSRunLog%
exit /b 0

:CBS_CAPTURE_ERROR
echo ERROR: CBS capture could not start. See:
echo %CBSRunLog%.error.txt
>> "%MaintenanceLog%" echo CBS capture failed to start at %date% %time%
exit /b 1

:CBS_CAPTURE_TIMEOUT
echo ERROR: CBS capture did not become ready.
>> "%MaintenanceLog%" echo CBS capture readiness timeout at %date% %time%
exit /b 1

:STOP_CBS_CAPTURE
if not "%CBSCaptureStarted%"=="1" exit /b 0

echo.
echo Stopping and flushing run-scoped CBS capture...
> "%CBSStopSignal%" echo stop

set /a "CBSWaitCount=0"
:WAIT_FOR_CBS_DONE
if exist "%CBSDoneSignal%" goto CBS_CAPTURE_DONE
set /a "CBSWaitCount+=1"
if !CBSWaitCount! GEQ 120 goto CBS_STOP_TIMEOUT
>nul 2>&1 ping 127.0.0.1 -n 2
goto WAIT_FOR_CBS_DONE

:CBS_CAPTURE_DONE
set "CBSCaptureStarted=0"
>> "%MaintenanceLog%" echo CBS run capture stopped and flushed: %date% %time%
del "%CBSStopSignal%" "%CBSReadySignal%" "%CBSDoneSignal%" >nul 2>&1
exit /b 0

:CBS_STOP_TIMEOUT
echo WARNING: CBS capture stop confirmation timed out.
>> "%MaintenanceLog%" echo CBS capture stop timeout at %date% %time%
exit /b 1

:GENERATE_SCOPED_REPORTS
call :ANALYZE_CBS_RUN
exit /b %errorlevel%

:CAPTURE_START_FAILED
echo.
echo Maintenance was not started because run-scoped CBS capture failed.
echo No DISM, SFC, cleanup, shadow-copy, or icon-cache command was run.
if defined WorkingFolder (
    echo.
    echo The timestamped working folder was preserved:
    echo !WorkingFolder!
)
pause
goto END

:WORKSPACE_PREPARE_FAILED
echo.
echo Maintenance was not started because the run workspace could not be prepared.
echo No DISM, SFC, cleanup, shadow-copy, or icon-cache command was run.
pause
goto END


:CREATE_LOG_ARCHIVE
if not "%RunPrepared%"=="1" (
    echo WARNING: Archive creation skipped because no run workspace exists.
    exit /b 1
)

call :SET_EXPECTED_ARCHIVE_FILES
call :VERIFY_EXPECTED_REPORTS
if errorlevel 1 exit /b 1

if exist "%ArchivePath%" (
    echo WARNING: The intended archive path became occupied during the run:
    echo %ArchivePath%
    >> "%MaintenanceLog%" echo Archive creation failed: target already exists at %date% %time%
    exit /b 1
)

>> "%MaintenanceLog%" echo Archive target: %ArchivePath%

pushd "%DesktopPath%" >nul 2>&1
if errorlevel 1 (
    echo WARNING: Could not access the Desktop for archive creation.
    >> "%MaintenanceLog%" echo Archive creation failed: Desktop path unavailable at %date% %time%
    exit /b 1
)

"%TarExe%" -caf "%ArchivePath%" "%RunBaseName%"
set "ArchiveError=!errorlevel!"
popd >nul 2>&1

if not "!ArchiveError!"=="0" (
    echo WARNING: ZIP archive creation failed with exit code !ArchiveError!.
    >> "%MaintenanceLog%" echo Archive creation failed with exit code !ArchiveError! at %date% %time%
    exit /b 1
)

if not exist "%ArchivePath%" (
    echo WARNING: The archive command returned success, but the ZIP was not found.
    >> "%MaintenanceLog%" echo Archive creation failed: output file missing at %date% %time%
    exit /b 1
)

"%TarExe%" -tf "%ArchivePath%" >nul 2>&1
set "ArchiveListError=!errorlevel!"
if not "!ArchiveListError!"=="0" (
    echo WARNING: The ZIP archive could not be listed for validation.
    >> "%MaintenanceLog%" echo Archive validation failed: tar list exit code !ArchiveListError! at %date% %time%
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip=[System.IO.Compression.ZipFile]::OpenRead($env:ArchivePath); try { $base=[System.IO.Path]::GetFileName($env:WorkingFolder.TrimEnd([char[]]'\\/')); $expected=@($env:ExpectedArchiveFiles -split '\|' | Where-Object { $_ }); $entries=@($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }); if ($entries.Count -ne $expected.Count) { throw ('Expected {0} file entries but found {1}.' -f $expected.Count,$entries.Count) }; $expectedPaths=@($expected | ForEach-Object { $base + '/' + $_ }); foreach ($name in $expected) { $wanted=$base + '/' + $name; $matches=@($entries | Where-Object { (($_.FullName -replace '\\','/').TrimStart([char[]]'./')) -ceq $wanted }); if ($matches.Count -ne 1) { throw ('Expected exactly one archive entry: ' + $wanted) }; $source=Join-Path -Path $env:WorkingFolder -ChildPath $name; if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ('Source file missing during validation: ' + $source) }; $length=(Get-Item -LiteralPath $source).Length; if ($matches[0].Length -ne $length) { throw ('Length mismatch for ' + $wanted) } }; $unexpected=@($entries | Where-Object { $normalized=(($_.FullName -replace '\\','/').TrimStart([char[]]'./')); $expectedPaths -cnotcontains $normalized }); if ($unexpected.Count -ne 0) { throw ('Unexpected archive file entries: ' + (($unexpected | ForEach-Object FullName) -join ', ')) } } finally { $zip.Dispose() }"
set "ArchiveValidationError=!errorlevel!"
if not "!ArchiveValidationError!"=="0" (
    echo WARNING: ZIP archive validation failed with exit code !ArchiveValidationError!.
    >> "%MaintenanceLog%" echo Archive validation failed with exit code !ArchiveValidationError! at %date% %time%
    exit /b 1
)

set "ArchiveValidated=1"
echo ZIP archive created and validated:
echo %ArchivePath%

if "%KeepWorkingFolder%"=="0" (
    call :REMOVE_WORKING_FOLDER
) else (
    echo Working folder retained by configuration:
    echo %WorkingFolder%
)
exit /b 0

:SET_EXPECTED_ARCHIVE_FILES
if "%MaintenanceModeNumber%"=="1" (
    set "ExpectedArchiveFiles=Maintenance_Mode_Log.txt|CBS_Run_Capture.log|DISM_Repair_Details.txt|SFC_Details.txt"
    exit /b 0
)
if "%MaintenanceModeNumber%"=="2" (
    set "ExpectedArchiveFiles=Maintenance_Mode_Log.txt|CBS_Run_Capture.log|DISM_Repair_Details.txt|Cleanup_Details.txt|Cleanup_Content_Retention_Details.txt|SFC_Details.txt"
    exit /b 0
)
set "ExpectedArchiveFiles=Maintenance_Mode_Log.txt|CBS_Run_Capture.log|DISM_Repair_Details.txt|Cleanup_Details.txt|Cleanup_Content_Retention_Details.txt|SFC_Details.txt|Component_Base_Reset_Log.txt"
exit /b 0

:VERIFY_EXPECTED_REPORTS
set "ArchiveInputMissing=0"
if not exist "%MaintenanceLog%" set "ArchiveInputMissing=1"
if not exist "%CBSRunLog%" set "ArchiveInputMissing=1"
if not exist "%DISMRepairLog%" set "ArchiveInputMissing=1"
if not exist "%SFCLog%" set "ArchiveInputMissing=1"
if not "%MaintenanceModeNumber%"=="1" (
    if not exist "%CleanupLog%" set "ArchiveInputMissing=1"
    if not exist "%CleanupContentRetentionLog%" set "ArchiveInputMissing=1"
)
if "%MaintenanceModeNumber%"=="3" if not exist "%ResetBaseLog%" set "ArchiveInputMissing=1"

if "%ArchiveInputMissing%"=="1" (
    echo WARNING: One or more expected report files are missing.
    >> "%MaintenanceLog%" echo Archive creation skipped: expected report file missing at %date% %time%
    exit /b 1
)
exit /b 0

:REMOVE_WORKING_FOLDER
if not defined WorkingFolder exit /b 1
if not exist "%WorkingFolder%" (
    set "WorkingFolderRemoved=1"
    exit /b 0
)

rmdir /s /q "%WorkingFolder%" >nul 2>&1
if exist "%WorkingFolder%" (
    echo WARNING: The validated ZIP is available, but the working folder could not be removed:
    echo %WorkingFolder%
    exit /b 1
)

set "WorkingFolderRemoved=1"
echo Working folder removed after successful archive validation.
exit /b 0

:RESET_ICON_CACHE
if "%DryRun%"=="1" (
    echo DRY RUN: Skipping icon cache reset.
    >> "%MaintenanceLog%" echo Icon cache reset skipped by DryRun at %date% %time%
    exit /b 0
)
taskkill /f /im explorer.exe >nul 2>&1
cd /d "%USERPROFILE%\AppData\Local\Microsoft\Windows\Explorer" 2>nul
del /f /s /q iconcache_*.db >nul 2>&1
"%windir%\System32\ie4uinit.exe" -show >nul 2>&1
start "" "%windir%\explorer.exe"
>> "%MaintenanceLog%" echo Icon cache reset completed at %date% %time%
exit /b 0


:SHOW_DRYRUN_NOTICE
CLS
echo ==================================================
echo       DRY RUN MODE IS ENABLED
echo ==================================================
echo.
echo Maintenance commands will be skipped.
echo Log collection and generated log files will still run.
echo.
echo To use this file in earnest, edit it and change:
echo.
echo   set "DryRun=1"
echo.
echo to:
echo.
echo   set "DryRun=0"
echo.
pause
exit /b 0

:RESET_LOG_FLAGS
set "MaintenanceModeNumber="
set "LogMaintenance=0"
set "LogDISMRepair=0"
set "LogCleanup=0"
set "LogSFC=0"
set "LogResetBase=0"
set "RunPrepared=0"
set "ArchiveValidated=0"
set "WorkingFolderRemoved=0"
set "WorkingFolder="
set "RunBaseName="
set "ArchivePath="
exit /b 0

:FINALIZE
echo.
set "FinalizationFailed=0"

call :STOP_CBS_CAPTURE
if errorlevel 1 set "FinalizationFailed=1"

if "!FinalizationFailed!"=="0" (
    call :GENERATE_SCOPED_REPORTS
    if errorlevel 1 set "FinalizationFailed=1"
)

>> "%MaintenanceLog%" echo Finished: %date% %time%

if "!FinalizationFailed!"=="0" (
    call :CREATE_LOG_ARCHIVE
    if errorlevel 1 set "FinalizationFailed=1"
) else (
    >> "%MaintenanceLog%" echo Archive creation skipped because finalization failed at %date% %time%
)

echo ==================================================
echo MAINTENANCE COMPLETE.
echo.
echo Mode:
echo - %MaintenanceMode%
echo.
if "%ArchiveValidated%"=="1" (
    echo Validated ZIP archive:
    echo - %ArchivePath%
    if "%WorkingFolderRemoved%"=="1" (
        echo.
        echo The uncompressed working folder was removed after validation.
    ) else (
        echo.
        echo Working folder retained:
        echo - %WorkingFolder%
    )
) else (
    echo WARNING: A validated ZIP archive was not completed.
    if exist "%ArchivePath%" (
        echo A partial or unvalidated archive may exist at:
        echo - %ArchivePath%
    )
    echo.
    echo The timestamped working folder was preserved:
    echo - %WorkingFolder%
)
echo ==================================================
pause
goto END

:MENU_EXIT
CLS
goto END

:END
del "%CBSStopSignal%" "%CBSReadySignal%" "%CBSDoneSignal%" "%ArchiveTimestampFile%" >nul 2>&1
endlocal
exit /b
