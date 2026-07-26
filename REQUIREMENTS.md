# Requirements Before Running

This file is a compact pre-run checklist for the Windows Repair and Component Maintenance Batch. Read the full `README.md` for detailed explanations of the modes, generated reports, limitations, archive behavior, and failure handling.

## Required environment

- A supported Windows installation with DISM, SFC, CBS logging, and Windows PowerShell 5.1.
- Administrator rights. The batch requests elevation through UAC.
- `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` available.
- `%SystemRoot%\System32\tar.exe` available for ZIP creation and archive inspection.
- The following three executable files kept together in the same extracted folder:

  ```text
  cleanup_v8.bat
  Watch-CBSLog.ps1
  Analyze-CBSRun.ps1
  ```

- A writable Desktop and Windows temporary-file location.
- The package must be extracted before use. Do not run the batch from inside a ZIP viewer.

## Dry-run default

The distributed batch is intentionally configured with:

```bat
set "DryRun=1"
```

In this state, the maintenance commands are shown and logged but are not executed. Review the batch and README first. A real maintenance run requires a deliberate edit to:

```bat
set "DryRun=0"
```

## Working-folder retention default

The distributed batch is configured with:

```bat
set "KeepWorkingFolder=0"
```

Each run first creates a uniquely named, timestamped working folder on the Desktop. The complete folder is stored inside a matching ZIP archive. After the archive has been created and validated successfully, the working folder is removed by default.

To retain both the ZIP and the uncompressed working folder after successful validation, change the setting to:

```bat
set "KeepWorkingFolder=1"
```

The working folder is preserved automatically whenever capture, analysis, ZIP creation, or archive validation fails, regardless of this setting.

## Disk-storage requirement

This requirement concerns **disk storage**, not system memory or RAM.

The package creates an uncompressed `CBS_Run_Capture.log` while Windows maintenance is running. The capture has no fixed maximum size. Its size depends on:

- the selected maintenance mode;
- the duration and complexity of servicing;
- the amount of repair or component-store work performed;
- concurrent CBS or Windows Update activity;
- the Windows build and servicing format.

In one tested Mode 2 run after a routine Windows quality update, the CBS capture reached approximately **188 MB**. This is an example, not an upper limit. Servicing around a Windows feature update, or a longer repair operation, can produce substantially more data.

During archive creation and validation, free space must accommodate both:

- the complete uncompressed timestamped working folder; and
- the matching ZIP archive while it is being created and checked.

Windows servicing and the archive process may also use additional temporary storage. Removing the working folder after successful validation reduces the final retained size, but it does not reduce the peak storage requirement during execution.

Before a real run:

- keep **several gigabytes of free space for ordinary runs**;
- allow considerably more space when running after or around a Windows feature update;
- check free space on the volume containing the Desktop;
- check free space on the Windows temporary-file volume.

Do not begin a real run when only a few hundred megabytes are available. Insufficient space can prevent complete capture, report generation, ZIP creation, or archive validation after maintenance has already started.

## Existing Desktop reports

The batch does not delete fixed-name loose reports from the Desktop. Each run uses a new timestamped folder and matching ZIP name. If the intended name is already occupied, the batch uses a suffixed non-conflicting name instead of deleting or overwriting the existing folder or archive.

A failed run may leave both its timestamped working folder and a partial or unvalidated ZIP. Preserve the working folder until the failure has been understood.

## Mode 3 preparation

Mode 3 additionally:

- attempts to delete client-accessible shadow copies on `C:` and `D:`;
- runs `StartComponentCleanup /ResetBase`;
- removes the former uninstall paths for Windows update packages incorporated into the new component-store baseline.

Use Mode 3 only when those additional rollback resources are no longer required. Confirm that `C:` and `D:` are the intended shadow-copy targets, or edit the batch before running it.

## Additional operational note

All three real modes reset the icon cache near the end. Windows Explorer is restarted, so the taskbar and Desktop may briefly disappear.
