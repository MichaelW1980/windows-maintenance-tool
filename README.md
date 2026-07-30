# Windows Maintenance Tool

## Summary

This package provides three selectable Windows maintenance workflows built around DISM, SFC, component-store cleanup, and an optional component-base reset with shadow-copy removal.

The supplied batch file is intentionally configured with:

```bat
set "DryRun=1"
```

In this state, the maintenance commands are **shown and logged but not executed**. The batch must be reviewed and deliberately changed to `DryRun=0` before a real maintenance run is possible.

Choose the mode according to the maintenance goal:

1. **Health Check + Repair**  
   Intended primarily for users who want Windows servicing and protected system files checked and repaired, together with focused documentation of the DISM and SFC results. It does not perform component-store cleanup.

2. **Repair + Component Store Cleanup**  
   Intended for users who want the repair and documentation work of Mode 1 plus Windows' ordinary component-store cleanup. It allows Windows to remove superseded servicing material that is no longer needed, without resetting the current component base or deleting shadow copies.

3. **Repair + Shadow Copy Purge + Component Base Reset**  
   Intended for users who want the deepest cleanup scope offered by this package and deliberately accept the removal of additional rollback resources. It includes the repair work, attempts to delete shadow copies on the resolved Windows system volume, and resets the component base so incorporated Windows update packages no longer retain their previous uninstall paths. It requires two confirmations.

The package uses four executable files because maintenance control, live CBS logging, report analysis, and ZIP packaging are separate responsibilities:

- `Windows-Maintenance-Tool.bat` — user interface, maintenance execution, safety checks, path initialization, direct logging, and workflow control.
- `Capture-CBSLog.ps1` — captures CBS activity produced during the run without depending on the final state of the rotating CBS log.
- `Analyze-CBSLog.ps1` — creates the focused DISM, SFC, and cleanup reports after the maintenance run is complete.
- `Create-MaintenanceArchive.ps1` — creates and validates the final ZIP archive through .NET compression APIs.

Each run writes its reports into a uniquely named, timestamped working folder under `%LOCALAPPDATA%\Windows Maintenance Tool\Reports`. The complete folder is then stored in a matching ZIP archive, so extracting the archive recreates one clean report folder instead of placing individual files into the extraction destination.

By default, the working folder is removed only after the ZIP has been created and validated successfully. If capture, analysis, packaging, or validation fails, the working folder remains available with whatever evidence was produced.


---

## 1. Read this before running the batch

For a compact pre-run checklist, see `REQUIREMENTS.md`. The detailed operating guidance remains in this README.

### Dry-run mode is enabled by default

The distributed batch is deliberately non-operational until edited:

```bat
set "DryRun=1"
```

With this setting, the batch still exercises its interface, mode selection, watcher coordination, report generation, and archive creation, but it does not run the maintenance, cleanup, shadow-copy, or reset commands.

A dry run skips:

- DISM health checks and repair;
- component-store cleanup;
- SFC;
- shadow-copy deletion;
- `/ResetBase`;
- icon-cache deletion and Explorer restart.

The batch displays a prominent dry-run warning before the mode menu. To permit real execution, review this README and the batch file, then deliberately change the setting to:

```bat
set "DryRun=0"
```

There is no command-line switch that bypasses this setting.

### Working-folder retention is configurable

The distributed batch is intended to use:

```bat
set "KeepWorkingFolder=0"
```

With this setting, the timestamped working folder is removed only after the matching ZIP archive has been created and validated successfully. The ZIP remains as the durable run record.

To retain both the ZIP and the uncompressed working folder after a successful run, change the setting to:

```bat
set "KeepWorkingFolder=1"
```

The working folder is preserved automatically whenever capture, report generation, archive creation, or archive validation fails, regardless of this setting.

### Windows may show an Open File security warning

On Windows 11, Windows may display an **Open File - Security Warning**
before the UAC prompt when the downloaded archive or extracted batch file
retains Internet-zone information.

Whether the warning appears depends on how the package was downloaded,
extracted, copied, or unblocked, and on the system's Attachment Manager
and security-policy configuration.

The warning may state that the publisher could not be verified because the
batch file does not have a digital signature identifying a verified
publisher. This warning does not by itself indicate that the release archive
has been modified.

Before selecting **Run**:

1. confirm that the package came from the official project release;
2. verify the release asset against its published SHA-256 hash; and
3. review the batch file and accompanying documentation.

The **Always ask before opening this file** checkbox controls whether Windows
continues showing this warning for that extracted copy:

- Leave the checkbox selected to retain the warning for later launches.
- Clear the checkbox before selecting **Run** to stop Windows from showing
  the warning on later launches of that copy.

Clearing the checkbox does not digitally sign the batch, does not grant
administrator rights, and does not suppress the separate UAC prompt.

Do not clear the checkbox merely to bypass a warning for a file whose source
or SHA-256 hash has not been verified.

### Administrator rights are required

The batch requests elevation through User Account Control when necessary and
relaunches itself in an elevated Command Prompt.

Administrator rights are required because the tool accesses protected Windows
servicing resources and, during real runs, invokes commands that inspect or
modify protected Windows state. These operations include:

- DISM component-store health checks and repair;
- component-store cleanup and `/ResetBase`;
- System File Checker;
- access to Windows CBS servicing logs; and
- shadow-copy deletion in Mode 3.

The elevation check occurs when the batch starts. The UAC prompt is therefore
expected during dry runs as well as during real maintenance runs.

Dry-run mode skips the maintenance, cleanup, deletion, reset, and icon-cache
commands, but it still exercises the elevated controller, CBS watcher
coordination, report generation, and archive workflow.

### Mode 3 removes additional rollback resources

Mode 3 performs the same ordinary component-store cleanup covered by Mode 2 and additionally attempts to:

- delete client-accessible shadow copies on the resolved Windows system volume;
- reset the current component-store base with `/ResetBase`.

Mode 2 already performs permanent removal of superseded component versions eligible for ordinary cleanup, and running it manually bypasses the scheduled task's normal grace period. Mode 3 goes further: deleted shadow copies are no longer available for restoration, and after `/ResetBase` succeeds, Windows update packages incorporated into the new baseline can no longer be uninstalled through their previous rollback path.

Mode 3 therefore requires:

1. a yes/no confirmation; and
2. the exact typed phrase:

```text
DELETE SHADOW COPIES AND RESET COMPONENT BASE
```

The technical warning and the final typed confirmation are displayed as two
separate screens so that each warning and its associated selector remain
fully visible.

Do not use Mode 3 merely as a test.

### Plan storage space before a real run

The package preserves the servicing records written during the maintenance window in `CBS_Run_Capture.log`. Its size depends on the selected mode, the duration and complexity of Windows servicing, and any other CBS activity occurring at the same time. There is no fixed maximum that applies to every system or Windows release.

In one tested Mode 2 run following a routine Windows quality update, the capture reached approximately **188 MB**. A feature update, a longer repair operation, or unusually active servicing can produce substantially more data. That example should therefore be treated as a reference point, not as a storage ceiling.

During a run, all reports exist inside a timestamped working folder. While that folder is being archived, the system must temporarily accommodate both:

- the uncompressed working folder, including `CBS_Run_Capture.log`; and
- the matching ZIP archive while it is being created and validated.

Additional temporary storage may also be used by Windows servicing and the archive process. Removing the working folder after successful validation reduces the final retained size, but it does not reduce this peak requirement during execution.

Do not begin a real run when the volume containing `%LOCALAPPDATA%` has only a few hundred megabytes free. As a conservative operational rule, keep **several gigabytes of free space for ordinary runs**, and allow considerably more when servicing follows or accompanies a Windows feature update. Also ensure that the Windows temporary-file location has adequate free space.

Insufficient free space can prevent complete capture, report creation, archive creation, or archive validation even if some maintenance commands have already run. In that case, the timestamped working folder is retained for recovery and inspection.

### Each run uses its own timestamped working folder

The batch does not write reports to Desktop, Documents, or `%TEMP%`, and it does not delete stale reports from earlier runs.

A run uses a structure such as:

```text
%LOCALAPPDATA%\Windows Maintenance Tool\Reports\
├── cleanup-report_YYYY-MM-DD_HH-MM-SS\
│   ├── Maintenance_Mode_Log.txt
│   ├── CBS_Run_Capture.log
│   └── mode-specific reports
└── cleanup-report_YYYY-MM-DD_HH-MM-SS.zip
```

The ZIP contains the timestamped folder itself. Extracting the archive therefore recreates:

```text
cleanup-report_YYYY-MM-DD_HH-MM-SS\
    ...
```

rather than scattering the reports into the selected extraction location.

If the intended timestamped name already exists, the batch must choose a non-conflicting suffixed name instead of overwriting or deleting the existing folder or archive.

The tool also uses `%LOCALAPPDATA%\Windows Maintenance Tool\Runtime` for short-lived CBS watcher coordination signals. It does not fall back to Desktop, Documents, or `%TEMP%`. If the Local AppData directories cannot be created or written, initialization fails before maintenance begins.

After finalization, interactive runs offer to open the Reports folder with the validated ZIP selected, or the retained diagnostic folder after failure. The optional `/no-open-prompt` switch suppresses only this final Explorer prompt; mode selection and safety confirmations remain interactive.

### Explorer is restarted during real runs

All three real modes attempt an icon-cache reset near the end. If matching cache files exist and Explorer is running, Explorer is terminated and restarted, so the taskbar and desktop may briefly disappear. A missing cache directory, missing cache files, or an already-stopped Explorer process is treated as not applicable rather than as a fatal condition.

---

## 2. Quick start

1. Extract the complete package to a normal folder. Do not run it from inside a ZIP viewer.
2. Keep the four executable files together:

   ```text
   Windows-Maintenance-Tool.bat
   Capture-CBSLog.ps1
   Analyze-CBSLog.ps1
   Create-MaintenanceArchive.ps1
   ```

3. Confirm that the batch contains:

   ```bat
   set "DryRun=1"
   set "KeepWorkingFolder=0"
   ```

4. Run `Windows-Maintenance-Tool.bat`.
5. If Windows displays an **Open File - Security Warning**, confirm the
   package source and published SHA-256 hash, decide whether Windows should
   continue asking before opening that copy, and select **Run**.
6. Approve the separate UAC prompt.
7. Read the dry-run notice and select a mode.
8. Review the timestamped ZIP archive. If the run or packaging stage fails,
   review the retained timestamped working folder.
9. Only after reviewing the scripts and dry-run behavior, change `DryRun=1`
   to `DryRun=0` for a real maintenance run.

---

## 3. Maintenance modes

The modes build on one another. Mode 1 focuses on checking, repair, and documentation. Mode 2 adds ordinary component-store cleanup. Mode 3 adds the removal of selected shadow copies and a component-base reset.

### Which mode fits which need?

| Mode | Choose this mode when... | Cleanup and rollback effect |
|---|---|---|
| Mode 1 | The main need is to check and repair Windows servicing and protected system files, and to retain focused DISM and SFC documentation. | Does not run component-store cleanup, delete shadow copies, or reset the component base. |
| Mode 2 | You deliberately want to perform ordinary Windows component-store cleanup now rather than waiting for scheduled maintenance, and accept permanent removal of the superseded component versions selected by the servicing stack. | Removes superseded Windows component versions that are eligible for ordinary component-store cleanup. Running the cleanup manually bypasses the scheduled task's normal grace period. It does not delete shadow copies or reset the component base. |
| Mode 3 | The deepest cleanup scope in this package is wanted, and the user has deliberately decided that selected shadow copies and previous uninstall paths for Windows update packages are no longer needed. | Includes the cleanup scope of Mode 2, attempts to delete shadow copies on the resolved Windows system volume, and uses `/ResetBase` so incorporated Windows update packages no longer retain their former uninstall paths. |

The distinction is therefore based on both **maintenance purpose** and **how much rollback material should be retained**.

## Mode 1 — Health Check + Repair

### When to choose Mode 1

Choose Mode 1 when the main purpose is to investigate and repair Windows servicing or protected system-file integrity, while producing focused documentation of what DISM and SFC found and repaired.

It is also the appropriate starting point when component-store cleanup is not currently needed or when the user wants the narrowest maintenance scope offered by the package.

### Operations

1. `DISM /Online /Cleanup-Image /ScanHealth`
2. `DISM /Online /Cleanup-Image /RestoreHealth`
3. `SFC /scannow`
4. Icon-cache reset

### What it does not remove

Mode 1 does not:

- run `StartComponentCleanup`;
- remove superseded component-store material as a cleanup operation;
- delete shadow copies;
- reset the component base.

Repairs performed by DISM or SFC may still replace or correct damaged files and metadata as required.

### Generated archive contents

```text
Maintenance_Mode_Log.txt
CBS_Run_Capture.log
DISM_Repair_Details.txt
SFC_Details.txt
```

Cleanup reports are intentionally not generated in Mode 1.

---

## Mode 2 — Repair + Component Store Cleanup

### When to choose Mode 2

Choose Mode 2 when you deliberately want to perform ordinary Windows component-store cleanup now rather than waiting for scheduled maintenance, and you accept permanent removal of the superseded component versions selected by the servicing stack.

This can be useful after servicing activity has accumulated superseded component versions, while retaining the current component base and leaving shadow copies untouched.

### Operations

1. `DISM /Online /Cleanup-Image /ScanHealth`
2. `DISM /Online /Cleanup-Image /RestoreHealth`
3. `DISM /Online /Cleanup-Image /StartComponentCleanup`
4. `SFC /scannow`
5. Icon-cache reset

### What Mode 2 removes

Mode 2 runs:

`DISM /Online /Cleanup-Image /StartComponentCleanup`

This performs Windows component-store cleanup. It removes superseded versions of Windows components that have been replaced by newer servicing versions and are no longer required as the active component version.

Windows also performs this type of cleanup through its scheduled `StartComponentCleanup` maintenance task. The scheduled task normally retains superseded component versions for a grace period before removing them. Running the DISM command manually performs comparable cleanup immediately, without the scheduled task's 30-day grace period or one-hour execution limit.

The removed data can include older component payloads, manifests, metadata, and other servicing material associated with superseded component versions. Exactly what Windows removes is determined by the servicing stack and the current state of the component store.

This is permanent removal of superseded component-store data. It is not merely temporary-file deletion. However, Mode 2 does not use `/ResetBase`, does not delete shadow copies, and does not force every currently superseded component version into a newly fixed baseline.

Mode 2 therefore performs ordinary component-store cleanup earlier and without the normal scheduled grace period, while Mode 3 additionally resets the component base and removes further rollback capability.

### Generated archive contents

```text
Maintenance_Mode_Log.txt
CBS_Run_Capture.log
DISM_Repair_Details.txt
Cleanup_Details.txt
Cleanup_Content_Retention_Details.txt
SFC_Details.txt
```

---

## Mode 3 — Repair + Shadow Copy Purge + Component Base Reset

### When to choose Mode 3

Choose Mode 3 when the user wants the deepest cleanup scope offered by this package and has deliberately decided that the selected shadow copies and the previous uninstall paths for Windows update packages incorporated into the new component base are no longer needed.

Mode 3 is therefore suited to a deliberate maintenance event, not simply to routine checking or repair. It includes the repair work and component-store cleanup, then removes additional rollback resources.

### Operations

1. `DISM /Online /Cleanup-Image /ScanHealth`
2. `DISM /Online /Cleanup-Image /RestoreHealth`
3. Attempt `vssadmin delete shadows /for=<resolved-system-volume> /all /quiet`
4. `DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase`
5. `SFC /scannow`
6. Icon-cache reset

### What Mode 3 removes in addition to Mode 2

- Client-accessible shadow copies on the resolved Windows system volume, if the VSS deletion command succeeds.
- The former uninstall paths for Windows update packages incorporated into the new `/ResetBase` baseline.

After these operations:

- deleted shadow copies are no longer available for restoration through those snapshots;
- Windows update packages incorporated into the reset baseline can no longer be uninstalled through their former uninstall paths;
- future Windows updates can still be installed normally.

Mode 3 requires both a yes/no confirmation and the exact typed confirmation phrase documented earlier.

### Generated archive contents

```text
Maintenance_Mode_Log.txt
CBS_Run_Capture.log
DISM_Repair_Details.txt
Cleanup_Details.txt
Cleanup_Content_Retention_Details.txt
SFC_Details.txt
Component_Base_Reset_Log.txt
```

---

## 4. Why the package contains four executable files

The four files are not separate tools the user must operate individually. The batch file is the entry point. It calls the three PowerShell helpers automatically.

The separation keeps each responsibility clear and independently testable.

## `Windows-Maintenance-Tool.bat` — maintenance controller

This is the file the user launches.

It is responsible for:

- requesting administrator rights;
- displaying the dry-run warning;
- presenting the three maintenance modes;
- enforcing Mode 3 confirmations;
- running or skipping the selected Windows commands;
- recording command timestamps and exit codes;
- starting and stopping the CBS watcher;
- invoking the report analyzer after logging is complete;
- checking that the reports expected for the selected mode exist;
- creating a unique timestamped working folder for each run;
- invoking the dedicated archive helper;
- validating the archive before removing the working folder;
- retaining the working folder whenever packaging or validation fails;
- honoring the `KeepWorkingFolder` setting after successful validation.

The batch does not interpret the contents of CBS records.

## `Capture-CBSLog.ps1` — reliable live CBS capture

Windows servicing writes detailed operational records to CBS logs. Those logs can grow, rotate, and be replaced during a long maintenance run. Copying only the final `CBS.log` afterward could therefore omit records that existed earlier in the run.

The watcher exists to preserve the servicing evidence generated while the selected maintenance sequence is active. It:

- begins at the current end of the active CBS log so earlier history is excluded;
- copies newly written bytes while Windows continues servicing;
- tolerates log sharing, truncation, recreation, and rotation;
- drains remaining data before switching to a replacement log;
- flushes the capture before the analyzer is allowed to run;
- creates an error sidecar if capture fails.

Its output is `CBS_Run_Capture.log`.

## `Analyze-CBSLog.ps1` — focused report generator

CBS logs are detailed and can be very large. The analyzer creates smaller reports that collect records relevant to the selected maintenance operations.

It reads the completed capture once and generates:

- `DISM_Repair_Details.txt`;
- `SFC_Details.txt`;
- `Cleanup_Details.txt` in Modes 2 and 3;
- `Cleanup_Content_Retention_Details.txt` in Modes 2 and 3.

It is responsible for:

- DISM repair-result extraction;
- the less-noisy SFC extraction logic;
- cleanup-session and cleanup-phase tracking;
- cleanup timeline extraction;
- successful package-transition extraction;
- strict correlation of multiline content-retention mismatch events;
- separation of complete, incomplete, uncorrelated, and out-of-scope records;
- suppressing cleanup reports when Mode 1 is selected.

The division of responsibilities is therefore:

```text
Batch file       -> selects and performs maintenance
CBS watcher      -> preserves servicing evidence from the run
CBS analyzer     -> creates focused reports from that evidence
Archive helper   -> creates and validates the ZIP
```

## `Create-MaintenanceArchive.ps1` — ZIP transaction and validation

The archive helper uses `.NET System.IO.Compression` rather than `tar.exe`. It verifies the source folder and expected mode-specific files, creates a ZIP containing the timestamped root folder, reopens the archive, reads every archived file fully, checks the exact expected file set, and compares each archived uncompressed length with its source file. A partial archive created by the helper is removed after a creation or validation failure. The batch deletes the working folder only after this helper returns exit code `0`.

---

## 5. Generated files

## `Maintenance_Mode_Log.txt`

Created by the batch. It records:

- selected mode;
- start and finish times;
- dry-run state;
- command results;
- watcher start and flush status;
- analyzer exit code;
- archive target and packaging failures.

In dry-run mode, logged zero values for skipped command paths do not mean that the corresponding Windows commands executed.

## `CBS_Run_Capture.log`

Created by the watcher. It contains the CBS activity captured during the maintenance window and is the source used by the analyzer.

It can be large. It is preserved because focused reports are selective and unusual records may require inspection of the original evidence.

The capture is time-scoped, not process-exclusive. Other Windows servicing or Windows Update activity occurring at the same time may also appear.

## `DISM_Repair_Details.txt`

Created by the analyzer. It collects selected records concerning component-store corruption detection, repair, metadata refresh, file-flag repair, and relevant successful completion evidence.

## `SFC_Details.txt`

Created by the analyzer. It focuses on meaningful SFC repair results, including:

- `[SR] Repairing`;
- `[SR] Repair complete`;
- explicit unsuccessful-repair records;
- PnP deployment corrupt-file and repaired-file pairs.

Generic cleanup-phase `CorruptPayloadFile` records are intentionally excluded.

## `Cleanup_Details.txt`

Created in Modes 2 and 3. It contains:

- selected cleanup completion evidence;
- cleanup phase timing and progression;
- package pruning and removal counts where available;
- successful package state transitions;
- content-retention correlation counts;
- incomplete and unclassified diagnostic counts;
- interpretation guardrails.

## `Cleanup_Content_Retention_Details.txt`

Created in Modes 2 and 3. It preserves the selected raw evidence used for content-retention mismatch classification, including:

- retention contexts;
- in-scope hash-mismatch headers;
- `CorruptPayloadFile` markers;
- `RetainFileAsVersion` mismatch records;
- each complete correlated event as its original six-line CBS sequence;
- incomplete, uncorrelated, and out-of-scope records in separate sections.

The report does not equate an observed retention mismatch with a confirmed unrepaired active-system corruption, and it does not claim a repair unless explicit correlated repair evidence exists.

## `Component_Base_Reset_Log.txt`

Created only in Mode 3 by the batch. It records:

- VSS purge targets and commands;
- VSS exit codes;
- the `/ResetBase` command and result;
- dry-run skipped-command entries;
- Mode 3 start and completion times.

The complete `vssadmin` console output is not currently preserved.

## `cleanup-report_YYYY-MM-DD_HH-MM-SS.zip`

Contains the complete timestamped working folder and the reports applicable to the selected mode. Extracting the ZIP recreates that folder as a clean subdirectory.

The archive is treated as successful only after validation confirms that it can be read, that the complete expected mode-specific file set is present exactly once, and that each archived file reports the same uncompressed length as its source in the working folder. Existing timestamped folders and archives are preserved.

---

## 6. Execution sequence

For the selected mode, the batch:

1. verifies Windows PowerShell 5.1, DISM, SFC, all three PowerShell helpers, and the .NET ZIP capability;
2. resolves Local Application Data through the Windows Known Folder API and creates a unique working folder under `%LOCALAPPDATA%\Windows Maintenance Tool\Reports`;
3. places all run-specific logs and reports inside that folder;
4. starts the CBS watcher and waits until it is ready;
5. executes the selected maintenance sequence, or skips it in dry-run mode;
6. asks the watcher to stop and waits for the final flush;
7. invokes the analyzer once with the selected mode;
8. verifies the expected mode-specific report set;
9. creates a ZIP containing the complete timestamped working folder;
10. validates that the archive is readable and contains the expected entries;
11. removes the working folder only when validation succeeds and `KeepWorkingFolder=0`;
12. otherwise preserves the working folder for review or recovery.

If capture cannot start, maintenance is not started. If analysis, archive creation, or archive validation fails, evidence that was already generated remains grouped inside the timestamped working folder.

---

## 7. Requirements and assumptions

- Windows with DISM, SFC, CBS logging, and Windows PowerShell 5.1.
- Administrator rights.
- `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` available.
- All four executable files kept together.
- A writable `%LOCALAPPDATA%\Windows Maintenance Tool\Reports` directory and `%LOCALAPPDATA%\Windows Maintenance Tool\Runtime` directory.
- Sufficient free space on the Local AppData volume for the working folder, ZIP archive, and archive-processing overhead.
- Mode 3 targets the resolved Windows system volume rather than assuming `C:` or `D:`.

PowerShell Core is not required and is not used.

Windows servicing behavior and CBS message formats can differ across Windows versions, builds, language configurations, and future updates.

---

## 8. Interpretation and known limitations

### Focused reports are selective

The derived reports are designed for readability and investigation. They are not exhaustive replacements for `CBS_Run_Capture.log`.

### Concurrent servicing activity may appear

The captured window can include unrelated CBS activity. The analyzer uses session, phase, context, and multiline-correlation rules where necessary, but unusual records may still require manual review.

### Unknown cleanup formats fail closed

Related records that do not satisfy the recognized cleanup correlation rules are reported as incomplete, uncorrelated, or outside classifier scope. They are not silently promoted to complete events.

### Some generic completion records can appear in more than one report

DISM repair and component cleanup can use overlapping CBS vocabulary. A small number of generic success or completion records may therefore be repeated across focused reports.

### VSS console output is not preserved

Mode 3 records VSS commands and exit codes, but not the complete `vssadmin` output. A nonzero VSS result may require separate manual reproduction to determine the exact cause.

### Archive creation is a separate finalization stage

Maintenance and report generation can succeed even if archive creation or validation later fails. The timestamped working folder is therefore retained until the ZIP has been validated. The archive process does not reduce the peak storage needed during the run.

### Exit codes are only part of the evidence

Command exit codes, focused reports, and the raw capture should be considered together. A zero exit code does not automatically redefine every intermediate CBS diagnostic as repaired active-store corruption.

---

## 9. Failure behavior

- If any required PowerShell helper is missing, maintenance is not started.
- If watcher readiness times out, maintenance is not started.
- If the watcher fails, it writes `CBS_Run_Capture.log.error.txt` where possible.
- If watcher shutdown confirmation times out, the batch warns and continues finalization attempts.
- If the analyzer fails, the raw capture remains available inside the timestamped working folder for manual analysis.
- If an expected report is missing, the analyzer stage is treated as failed.
- If ZIP creation or archive validation fails, the timestamped working folder remains intact.
- The working folder is never removed merely because archive creation returned a success code; validation must also succeed.

---

## 10. Verifying a run

A successful run should finish with all of the following:

- the selected maintenance workflow reaches finalization;
- `Capture-CBSLog.ps1` stops and flushes its run-scoped capture;
- `Analyze-CBSLog.ps1` creates the expected reports for the selected mode;
- `Create-MaintenanceArchive.ps1` creates and validates the ZIP archive;
- the batch displays the exact validated archive path; and
- when `KeepWorkingFolder=0`, the uncompressed working folder is removed only after archive validation succeeds.

The final ZIP should contain one timestamped top-level report folder. Its expected files are:

- Mode 1: `CBS_Run_Capture.log`, `DISM_Repair_Details.txt`, `Maintenance_Mode_Log.txt`, and `SFC_Details.txt`;
- Mode 2: all Mode 1 files plus `Cleanup_Details.txt` and `Cleanup_Content_Retention_Details.txt`;
- Mode 3: all Mode 2 files plus `Component_Base_Reset_Log.txt`.

If maintenance, capture, analysis, archive creation, or archive validation fails, inspect the retained working folder shown by the batch. Do not treat a partial or unvalidated ZIP as a completed report.

The current console output may print archive success once from the archive helper and once from the batch. In Mode 3, the timestamp beside the VSS exit code in `Maintenance_Mode_Log.txt` may represent the command-start time; `Component_Base_Reset_Log.txt` contains the more detailed VSS timing. These are presentation details and do not change the recorded exit code or archive-validation result.

---

## 11. Copyright and license

Copyright (C) 2026 MichaelW1980

Additional contributions remain copyright of their respective contributors.

This project is free software: you may redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, **version 3 only**.

The SPDX license identifier for this project is:

```text
GPL-3.0-only
```

The complete license text is provided in the root-level `LICENSE` file.

This software is distributed in the hope that it will be useful, but **without any warranty**; without even the implied warranty of merchantability or fitness for a particular purpose. See the GNU General Public License for the complete terms.
