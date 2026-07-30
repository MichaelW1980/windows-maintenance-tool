@echo off
CLS
setlocal EnableExtensions EnableDelayedExpansion

:: Windows Maintenance Tool - v8.0.3.3

set "DryRun=1"
set "KeepWorkingFolder=0"
set "DryRunNoticeShown=0"
set "OpenResultPrompt=1"
set "FinalExitCode=0"

:: /no-open-prompt suppresses only the final Explorer prompt. The maintenance
:: mode selection and destructive-operation confirmations remain interactive.
if /i "%~1"=="/no-open-prompt" set "OpenResultPrompt=0"

set "ScriptDirectory=%~dp0"
set "PowerShellExe=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "DismExe=%SystemRoot%\System32\Dism.exe"
set "SfcExe=%SystemRoot%\System32\sfc.exe"
set "VssAdminExe=%SystemRoot%\System32\vssadmin.exe"
set "ExplorerExe=%SystemRoot%\explorer.exe"
set "CBSWatcherScript=%ScriptDirectory%Capture-CBSLog.ps1"
set "CBSRunAnalyzer=%ScriptDirectory%Analyze-CBSLog.ps1"
set "ArchiveScript=%ScriptDirectory%Create-MaintenanceArchive.ps1"

:: Request administrator rights if needed and preserve supported switches.
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    if not exist "%PowerShellExe%" (
        echo ERROR: Windows PowerShell was not found. Administrator rights cannot be requested.
        echo %PowerShellExe%
        endlocal
        exit /b 1
    )
    echo Requesting administrator rights...
    set "ElevationArguments=/d /c ""%~f0"" %*"
    "%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:ComSpec -ArgumentList $env:ElevationArguments -Verb RunAs -ErrorAction Stop"
    set "ElevationError=!errorlevel!"
    endlocal & exit /b !ElevationError!
)

call :INITIALIZE_ENVIRONMENT
if errorlevel 1 goto INITIALIZATION_FAILED

set "CBSCaptureStarted=0"
set "CBSCaptureLaunched=0"
set "RunPrepared=0"
set "ArchiveValidated=0"
set "WorkingFolderRemoved=0"
set "WorkingFolder="
set "RunBaseName="
set "ArchivePath="
set "CBSStopSignal="
set "CBSReadySignal="
set "CBSDoneSignal="

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
echo     - Attempt vssadmin shadow-copy purge on the Windows system volume
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
echo on the resolved Windows system volume using vssadmin.
echo.
echo Configured shadow-copy purge target: %ShadowPurgeVolumes%
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
choice /c YN /n /m "Continue to final confirmation? [Y/N]: "
if errorlevel 2 goto MENU

CLS
echo ==================================================
echo              FINAL CONFIRMATION
echo ==================================================
echo.
echo Successfully deleted shadow copies will no longer
echo be available.
echo.
echo ResetBase removes former uninstall paths for Windows
echo update packages incorporated into the new component-
echo store baseline.
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
echo Extended cleanup mode not confirmed!
echo Returning to selection menu...
timeout /t 3 /nobreak >nul
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
    "%DismExe%" /Online /Cleanup-Image /ScanHealth
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
    "%DismExe%" /Online /Cleanup-Image /RestoreHealth
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
    "%DismExe%" /Online /Cleanup-Image /StartComponentCleanup
    set "LastError=!errorlevel!"
)
>> "%MaintenanceLog%" echo StartComponentCleanup exit code: !LastError! at %date% %time%
exit /b 0

:RUN_SHADOW_PURGE
echo.
echo [%~1] Attempting shadow-copy purge ^(vssadmin^)...
>> "%ResetBaseLog%" echo Shadow-copy purge command started: %date% %time%
>> "%ResetBaseLog%" echo Configured purge target: %ShadowPurgeVolumes%

if not "%VssAdminAvailable%"=="1" (
    echo WARNING: vssadmin.exe is unavailable. Shadow-copy purge is not applicable.
    >> "%ResetBaseLog%" echo Shadow-copy purge not applicable: vssadmin.exe unavailable.
    >> "%MaintenanceLog%" echo Shadow-copy purge not applicable: vssadmin.exe unavailable at %date% %time%
    exit /b 0
)

for %%V in (%ShadowPurgeVolumes%) do (
    if "%DryRun%"=="1" (
        echo DRY RUN: Skipping shadow-copy purge for %%V.
        >> "%ResetBaseLog%" echo Command skipped: vssadmin delete shadows /for=%%V /all /quiet
        set "ShadowPurgeError=0"
    ) else (
        >> "%ResetBaseLog%" echo Command: vssadmin delete shadows /for=%%V /all /quiet
        "%VssAdminExe%" delete shadows /for=%%V /all /quiet
        set "ShadowPurgeError=!errorlevel!"
    )
    >> "%ResetBaseLog%" echo Shadow-copy purge %%V exit code: !ShadowPurgeError!
    >> "%MaintenanceLog%" echo Shadow-copy purge %%V exit code: !ShadowPurgeError! at %date% %time%
)

>> "%ResetBaseLog%" echo Shadow-copy purge command completed: %date% %time%
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
    "%DismExe%" /Online /Cleanup-Image /StartComponentCleanup /ResetBase
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
    "%SfcExe%" /scannow
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

if not exist "%ArchiveScript%" (
    echo ERROR: Required archive script was not found:
    echo %ArchiveScript%
    exit /b 1
)

set "RunTimestamp="
for /f "delims=" %%I in ('^""%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"^"') do if not defined RunTimestamp set "RunTimestamp=%%I"

if not defined RunTimestamp (
    echo ERROR: The run timestamp could not be generated.
    exit /b 1
)

set "RunBaseStem=cleanup-report_!RunTimestamp!"
set "RunBaseName=!RunBaseStem!"
set /a "RunCollisionIndex=0"

:CHECK_RUN_NAME_COLLISION
if not exist "%ReportsRoot%\!RunBaseName!" if not exist "%ReportsRoot%\!RunBaseName!.zip" goto RUN_NAME_AVAILABLE
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
set "WorkingFolder=%ReportsRoot%\!RunBaseName!"
set "ArchivePath=%ReportsRoot%\!RunBaseName!.zip"
set "RunControlStem=cleanup_cbs_!RunTimestamp!_!RANDOM!_!RANDOM!"
set "CBSStopSignal=%RuntimeRoot%\!RunControlStem!_stop.signal"
set "CBSReadySignal=%RuntimeRoot%\!RunControlStem!_ready.signal"
set "CBSDoneSignal=%RuntimeRoot%\!RunControlStem!_done.signal"
del "!CBSStopSignal!" "!CBSReadySignal!" "!CBSDoneSignal!" >nul 2>&1

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
"%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%CBSRunAnalyzer%" -SourceLog "%CBSRunLog%" -Mode "%MaintenanceModeNumber%" -DISMRepairLog "%DISMRepairLog%" -CleanupLog "%CleanupLog%" -ContentRetentionLog "%CleanupContentRetentionLog%" -SFCLog "%SFCLog%"
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
start "CBS Run Capture" /b "%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%CBSWatcherScript%" -SourcePath "%windir%\Logs\CBS\CBS.log" -DestinationPath "%CBSRunLog%" -StopSignalPath "%CBSStopSignal%" -ReadySignalPath "%CBSReadySignal%" -DoneSignalPath "%CBSDoneSignal%"
if errorlevel 1 (
    echo ERROR: The CBS watcher process could not be launched.
    >> "%MaintenanceLog%" echo CBS capture launch failed at %date% %time%
    exit /b 1
)
set "CBSCaptureLaunched=1"

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
if not "%CBSCaptureLaunched%"=="1" exit /b 0

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
set "CBSCaptureLaunched=0"
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
call :STOP_CBS_CAPTURE
echo.
echo Maintenance was not started because run-scoped CBS capture failed.
echo No DISM, SFC, cleanup, shadow-copy, or icon-cache command was run.
if defined WorkingFolder (
    echo.
    echo The timestamped working folder was preserved:
    echo !WorkingFolder!
)
set "FinalExitCode=1"
call :PROMPT_OPEN_RESULT
goto END

:WORKSPACE_PREPARE_FAILED
echo.
echo Maintenance was not started because the run workspace could not be prepared.
echo No DISM, SFC, cleanup, shadow-copy, or icon-cache command was run.
echo.
echo Required report root:
echo %ReportsRoot%
set "FinalExitCode=1"
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

"%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ArchiveScript%" -SourcePath "%WorkingFolder%" -DestinationPath "%ArchivePath%" -ExpectedFiles "%ExpectedArchiveFiles%"
set "ArchiveError=!errorlevel!"

if not "!ArchiveError!"=="0" (
    echo WARNING: ZIP archive creation or validation failed with exit code !ArchiveError!.
    >> "%MaintenanceLog%" echo Archive creation or validation failed with exit code !ArchiveError! at %date% %time%
    exit /b 1
)

if not exist "%ArchivePath%" (
    echo WARNING: Archive validation returned success, but the ZIP was not found.
    >> "%MaintenanceLog%" echo Archive validation failed: output file missing at %date% %time%
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

if not exist "%IconCachePath%" (
    echo Icon cache reset not applicable: cache directory was not found.
    >> "%MaintenanceLog%" echo Icon cache reset not applicable: directory missing at %date% %time%
    exit /b 0
)

dir /b /a-d "%IconCachePath%\iconcache_*.db" >nul 2>&1
if errorlevel 1 (
    echo Icon cache reset not applicable: no icon cache database files were found.
    >> "%MaintenanceLog%" echo Icon cache reset not applicable: no matching files at %date% %time%
    exit /b 0
)

set "ExplorerWasRunning=0"
"%SystemRoot%\System32\tasklist.exe" /fi "imagename eq explorer.exe" 2>nul | "%SystemRoot%\System32\find.exe" /i "explorer.exe" >nul 2>&1
if not errorlevel 1 set "ExplorerWasRunning=1"

if "!ExplorerWasRunning!"=="1" (
    "%SystemRoot%\System32\taskkill.exe" /f /im explorer.exe >nul 2>&1
)

pushd "%IconCachePath%" >nul 2>&1
if errorlevel 1 (
    echo WARNING: Icon cache directory became unavailable.
    >> "%MaintenanceLog%" echo Icon cache reset failed: directory unavailable at %date% %time%
    exit /b 1
)

del /f /q iconcache_*.db >nul 2>&1
set "IconCacheDeleteError=!errorlevel!"
popd >nul 2>&1

if exist "%SystemRoot%\System32\ie4uinit.exe" "%SystemRoot%\System32\ie4uinit.exe" -show >nul 2>&1
if "!ExplorerWasRunning!"=="1" if exist "%ExplorerExe%" start "" "%ExplorerExe%" >nul 2>&1

if not "!IconCacheDeleteError!"=="0" (
    echo WARNING: One or more icon cache files could not be deleted.
    >> "%MaintenanceLog%" echo Icon cache reset completed with deletion warnings at %date% %time%
    exit /b 1
)

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
set "CBSCaptureStarted=0"
set "CBSCaptureLaunched=0"
set "ArchiveValidated=0"
set "WorkingFolderRemoved=0"
set "WorkingFolder="
set "RunBaseName="
set "ArchivePath="
set "CBSStopSignal="
set "CBSReadySignal="
set "CBSDoneSignal="
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

if "%ArchiveValidated%"=="1" (
    set "FinalExitCode=0"
    echo ==================================================
    echo MAINTENANCE AND REPORT FINALIZATION COMPLETED.
    echo.
    echo Mode:
    echo - %MaintenanceMode%
    echo.
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
    set "FinalExitCode=1"
    echo ==================================================
    echo MAINTENANCE FINALIZATION INCOMPLETE.
    echo.
    echo Mode:
    echo - %MaintenanceMode%
    echo.
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
call :PROMPT_OPEN_RESULT
goto END

:MENU_EXIT
CLS
set "FinalExitCode=0"
goto END

:INITIALIZATION_FAILED
echo.
echo ==================================================
echo INITIALIZATION FAILED.
echo.
echo The tool could not initialize its required Local AppData paths or capabilities.
echo No maintenance command was run, and no fallback location was used.
echo ==================================================
echo.
echo Press any key to close this window.
pause >nul
set "FinalExitCode=1"
goto END

:PROMPT_OPEN_RESULT
if not "%OpenResultPrompt%"=="1" exit /b 0
if not "%ExplorerAvailable%"=="1" (
    echo.
    echo Explorer is unavailable, so the result folder cannot be opened automatically.
    exit /b 0
)

if "%ArchiveValidated%"=="1" (
    echo.
    choice /c YN /n /m "Open the Reports folder? [Y/N]: "
    if errorlevel 2 exit /b 0
    "%ExplorerExe%" /select,"%ArchivePath%" >nul 2>&1
    if errorlevel 1 echo NOTICE: Explorer could not select the archive. The maintenance result is unchanged.
    exit /b 0
)

if defined WorkingFolder if exist "%WorkingFolder%" (
    echo.
    choice /c YN /n /m "Open the diagnostic folder? [Y/N]: "
    if errorlevel 2 exit /b 0
    "%ExplorerExe%" "%WorkingFolder%" >nul 2>&1
    if errorlevel 1 echo NOTICE: Explorer could not open the diagnostic folder. The maintenance result is unchanged.
)
exit /b 0

:INITIALIZE_ENVIRONMENT
if not exist "%PowerShellExe%" (
    echo ERROR: Windows PowerShell 5.1 was not found:
    echo %PowerShellExe%
    exit /b 1
)

"%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -Command "if ($PSVersionTable.PSVersion.Major -ge 5) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell 5.1 or later could not be confirmed.
    exit /b 1
)

if not exist "%DismExe%" (
    echo ERROR: DISM was not found:
    echo %DismExe%
    exit /b 1
)
if not exist "%SfcExe%" (
    echo ERROR: SFC was not found:
    echo %SfcExe%
    exit /b 1
)
if not exist "%CBSWatcherScript%" (
    echo ERROR: Required CBS watcher script was not found:
    echo %CBSWatcherScript%
    exit /b 1
)
if not exist "%CBSRunAnalyzer%" (
    echo ERROR: Required CBS analyzer script was not found:
    echo %CBSRunAnalyzer%
    exit /b 1
)
if not exist "%ArchiveScript%" (
    echo ERROR: Required archive script was not found:
    echo %ArchiveScript%
    exit /b 1
)

"%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [void][System.IO.Compression.ZipFile]" >nul 2>&1
if errorlevel 1 (
    echo ERROR: The required .NET ZIP capability is unavailable.
    exit /b 1
)

set "LocalApplicationData="
for /f "delims=" %%I in ('^""%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -Command "[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)"^"') do if not defined LocalApplicationData set "LocalApplicationData=%%I"
if not defined LocalApplicationData (
    echo ERROR: Windows Local Application Data could not be resolved.
    exit /b 1
)

"%PowerShellExe%" -NoLogo -NoProfile -NonInteractive -Command "if ([string]::IsNullOrWhiteSpace($env:LocalApplicationData) -or -not [System.IO.Path]::IsPathRooted($env:LocalApplicationData)) { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows Local Application Data did not resolve to a rooted path:
    echo %LocalApplicationData%
    exit /b 1
)

set "ToolDataRoot=%LocalApplicationData%\Windows Maintenance Tool"
set "ReportsRoot=%ToolDataRoot%\Reports"
set "RuntimeRoot=%ToolDataRoot%\Runtime"
set "IconCachePath=%LocalApplicationData%\Microsoft\Windows\Explorer"
set "ShadowPurgeVolumes=%SystemDrive%"

mkdir "%ReportsRoot%" >nul 2>&1
if errorlevel 1 if not exist "%ReportsRoot%" (
    echo ERROR: The Reports directory could not be created:
    echo %ReportsRoot%
    echo No fallback destination will be used.
    exit /b 1
)

mkdir "%RuntimeRoot%" >nul 2>&1
if errorlevel 1 if not exist "%RuntimeRoot%" (
    echo ERROR: The runtime directory could not be created:
    echo %RuntimeRoot%
    echo No fallback destination will be used.
    exit /b 1
)

call :VERIFY_WRITABLE_DIRECTORY "%ReportsRoot%"
if errorlevel 1 (
    echo ERROR: The Reports directory is not writable:
    echo %ReportsRoot%
    echo No fallback destination will be used.
    exit /b 1
)

call :VERIFY_WRITABLE_DIRECTORY "%RuntimeRoot%"
if errorlevel 1 (
    echo ERROR: The runtime directory is not writable:
    echo %RuntimeRoot%
    echo No fallback destination will be used.
    exit /b 1
)

set "ExplorerAvailable=0"
if exist "%ExplorerExe%" set "ExplorerAvailable=1"
set "VssAdminAvailable=0"
if exist "%VssAdminExe%" set "VssAdminAvailable=1"
exit /b 0

:VERIFY_WRITABLE_DIRECTORY
set "WriteProbe=%~1\.wmt_write_test_%RANDOM%_%RANDOM%.tmp"
> "%WriteProbe%" echo write-test
if not exist "%WriteProbe%" exit /b 1
del "%WriteProbe%" >nul 2>&1
if exist "%WriteProbe%" exit /b 1
exit /b 0

:END
if not "%CBSCaptureLaunched%"=="1" (
    if defined CBSStopSignal del "%CBSStopSignal%" >nul 2>&1
    if defined CBSReadySignal del "%CBSReadySignal%" >nul 2>&1
    if defined CBSDoneSignal del "%CBSDoneSignal%" >nul 2>&1
)
endlocal & exit /b %FinalExitCode%
