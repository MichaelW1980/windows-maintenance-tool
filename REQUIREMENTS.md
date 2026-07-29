# Requirements and pre-run checklist

This checklist applies to Windows Maintenance Tool v8.0.3.2. Read `README.md` for the full operating and safety details.

## Platform and privileges

- A supported Windows installation with DISM, SFC, CBS logging, and Windows PowerShell 5.1.
- Administrator rights. The batch requests elevation through UAC when necessary.
- `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`.
- `%SystemRoot%\System32\Dism.exe` and `%SystemRoot%\System32\sfc.exe`.
- The .NET `System.IO.Compression.FileSystem` ZIP capability available to Windows PowerShell.
- `vssadmin.exe` is optional outside Mode 3. If unavailable in Mode 3, the shadow-copy step is reported as not applicable and the remaining selected workflow can continue.

PowerShell Core is not required. `tar.exe` is not used.

## Keep these files together

```text
Windows-Maintenance-Tool.bat
Capture-CBSLog.ps1
Analyze-CBSLog.ps1
Create-MaintenanceArchive.ps1
```

The batch locates all companion scripts relative to its own directory through `%~dp0`; the current working directory does not need to match the package directory.

## Report and runtime storage

The tool resolves Local Application Data through the Windows Known Folder API and uses only:

```text
%LOCALAPPDATA%\Windows Maintenance Tool\Reports
%LOCALAPPDATA%\Windows Maintenance Tool\Runtime
```

- Timestamped working folders and validated ZIP archives are stored in `Reports`.
- Short-lived CBS watcher signal files are stored in `Runtime`.
- Desktop, Documents, and `%TEMP%` are not used for tool-owned files.
- There is no automatic fallback. If either Local AppData directory cannot be created or written, initialization fails before maintenance begins.
- Ensure that the Local AppData volume has several gigabytes of free space for ordinary runs and more after major Windows servicing activity. During ZIP creation, both the working folder and archive exist at the same time.

## Safety defaults

The distributed batch remains configured with:

```bat
set "DryRun=1"
set "KeepWorkingFolder=0"
```

- `DryRun=1` skips DISM, SFC, shadow-copy deletion, `/ResetBase`, and icon-cache deletion while still exercising capture, report generation, and ZIP packaging.
- Change to `DryRun=0` only after reviewing the scripts and completing a dry run.
- `KeepWorkingFolder=0` removes the uncompressed working folder only after the ZIP has been created and deeply validated.
- Every capture, analysis, archive, or validation failure preserves the working folder.

## Mode 3

Mode 3 attempts shadow-copy deletion on the resolved Windows system volume, not hard-coded `C:` or `D:` targets, and then runs `/ResetBase`. It requires both the yes/no confirmation and the exact typed phrase shown by the batch. Deleted shadow copies and reset package uninstall paths cannot be restored by this tool.

## End-of-run interaction

Interactive runs offer to open the Reports folder with the validated ZIP selected, or the retained diagnostic folder after failure. Use:

```text
Windows-Maintenance-Tool.bat /no-open-prompt
```

to suppress only that final Explorer prompt. Mode selection and destructive-operation confirmations remain interactive. Explorer launch failure never changes the maintenance exit status.

## Before a real run

Run each selected mode with `DryRun=1` after downloading, moving, or editing the package. Confirm that elevation, companion-script discovery, Local AppData initialization, CBS capture, report generation, ZIP validation, and the final folder prompt complete successfully. Change to `DryRun=0` only after reviewing the scripts and confirming the dry run on the target system.
