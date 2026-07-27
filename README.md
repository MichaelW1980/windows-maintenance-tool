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
   Intended for users who want the deepest cleanup scope offered by this package and deliberately accept the removal of additional rollback resources. It includes the repair work, attempts to delete shadow copies on `C:` and `D:`, and resets the component base so incorporated Windows update packages no longer retain their previous uninstall paths. It requires two confirmations.

The package uses three executable files because maintenance control, live CBS logging, and report analysis are separate responsibilities:

- `cleanup_v8.bat` — user interface, maintenance execution, safety checks, direct logging, working-folder management, and archive creation.
- `Watch-CBSLog.ps1` — captures CBS activity produced during the run without depending on the final state of the rotating CBS log.
- `Analyze-CBSRun.ps1` — creates the focused DISM, SFC, and cleanup reports after the maintenance run is complete.

Each run writes its reports into a uniquely named, timestamped working folder on the current user’s Desktop. The complete folder is then stored in a matching ZIP archive, so extracting the archive recreates one clean report folder instead of placing individual files into the extraction destination.

By default, the working folder is removed only after the ZIP has been created and validated successfully. If capture, analysis, packaging, or validation fails, the working folder remains available with whatever evidence was produced.


---

## 1. Read this before running the batch

For a compact pre-run checklist, see `REQUIREMENTS.md`. The detailed explanations remain in this README.

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

- delete client-accessible shadow copies on `C:`;
- delete client-accessible shadow copies on `D:`;
- reset the current component-store base with `/ResetBase`.

Mode 2 already removes superseded component versions that Windows no longer needs to retain during normal cleanup. Mode 3 goes further: deleted shadow copies are no longer available for restoration, and after `/ResetBase` succeeds, Windows update packages incorporated into the new baseline can no longer be uninstalled through their previous rollback path.

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

Do not begin a real run when the Desktop volume has only a few hundred megabytes free. As a conservative operational rule, keep **several gigabytes of free space for ordinary runs**, and allow considerably more when servicing follows or accompanies a Windows feature update. Also ensure that the Windows temporary-file location has adequate free space.

Insufficient free space can prevent complete capture, report creation, archive creation, or archive validation even if some maintenance commands have already run. In that case, the timestamped working folder is retained for recovery and inspection.

### Each run uses its own timestamped working folder

The batch does not write fixed-name loose reports directly onto the Desktop and does not delete stale reports from earlier runs.

A run uses a structure such as:

```text
Desktop\
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

### Explorer is restarted during real runs

All three real modes reset the icon cache near the end. Windows Explorer is terminated and restarted, so the taskbar and desktop may briefly disappear.

---

## 2. Quick start

1. Extract the complete package to a normal folder. Do not run it from inside a ZIP viewer.
2. Keep the three executable files together:

   ```text
   cleanup_v8.bat
   Watch-CBSLog.ps1
   Analyze-CBSRun.ps1
   ```

3. Confirm that the batch contains:

   ```bat
   set "DryRun=1"
   set "KeepWorkingFolder=0"
   ```

4. Run `cleanup_v8.bat`.
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
| Mode 2 | The repair and documentation work of Mode 1 is wanted together with ordinary cleanup of superseded component-store material. | Windows may remove superseded component versions and related servicing payloads that normal `StartComponentCleanup` determines are no longer required. Shadow copies and the current component base are left unchanged. |
| Mode 3 | The deepest cleanup scope in this package is wanted, and the user has deliberately decided that selected shadow copies and previous uninstall paths for Windows update packages are no longer needed. | Includes the cleanup scope of Mode 2, attempts to delete shadow copies on `C:` and `D:`, and uses `/ResetBase` so incorporated Windows update packages no longer retain their former uninstall paths. |

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

Choose Mode 2 when the repair and documentation work of Mode 1 is wanted together with Windows' ordinary component-store cleanup.

This can be useful after servicing activity has accumulated superseded component versions, or whenever the user wants Windows to remove component-store material that its normal cleanup process considers no longer necessary, while retaining the current component base and leaving shadow copies untouched.

### Operations

1. `DISM /Online /Cleanup-Image /ScanHealth`
2. `DISM /Online /Cleanup-Image /RestoreHealth`
3. `DISM /Online /Cleanup-Image /StartComponentCleanup`
4. `SFC /scannow`
5. Icon-cache reset

### What Mode 2 removes

Mode 2 allows Windows servicing to remove:

- superseded component versions;
- related servicing payloads that ordinary `StartComponentCleanup` determines are no longer required;
- some older fallback material associated with those superseded components.

Mode 2 does not:

- use `/ResetBase`;
- delete shadow copies;
- remove the former uninstall paths of Windows update packages by establishing a new component base.

It is the package's ordinary component-store cleanup mode.

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
3. Attempt `vssadmin delete shadows /for=C: /all /quiet`
4. Attempt `vssadmin delete shadows /for=D: /all /quiet`
5. `DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase`
6. `SFC /scannow`
7. Icon-cache reset

### What Mode 3 removes in addition to Mode 2

- Client-accessible shadow copies on `C:`, if the VSS deletion command succeeds.
- Client-accessible shadow copies on `D:`, if that volume exists and the VSS deletion command succeeds.
- The former uninstall paths for Windows update packages incorporated into the new `/ResetBase` baseline.

After these operations:

- deleted shadow copies are no longer available for restoration through those snapshots;
- Windows update packages incorporated into the reset baseline can no longer be uninstalled through their former uninstall paths;
- future Windows updates can still be installed normally;
- a missing, unsupported, or otherwise unsuitable `D:` target may produce a nonzero VSS exit code even if the remaining Mode 3 operations succeed.

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

## 4. Why the package contains three executable files

The three files are not three separate tools the user must operate individually. The batch file is the entry point. It calls the two PowerShell helpers automatically.

The separation keeps each responsibility clear and independently testable.

## `cleanup_v8.bat` — maintenance controller

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
- archiving that complete folder as a matching ZIP;
- validating the archive before removing the working folder;
- retaining the working folder whenever packaging or validation fails;
- honoring the `KeepWorkingFolder` setting after successful validation.

The batch does not interpret the contents of CBS records.

## `Watch-CBSLog.ps1` — reliable live CBS capture

Windows servicing writes detailed operational records to CBS logs. Those logs can grow, rotate, and be replaced during a long maintenance run. Copying only the final `CBS.log` afterward could therefore omit records that existed earlier in the run.

The watcher exists to preserve the servicing evidence generated while the selected maintenance sequence is active. It:

- begins at the current end of the active CBS log so earlier history is excluded;
- copies newly written bytes while Windows continues servicing;
- tolerates log sharing, truncation, recreation, and rotation;
- drains remaining data before switching to a replacement log;
- flushes the capture before the analyzer is allowed to run;
- creates an error sidecar if capture fails.

Its output is `CBS_Run_Capture.log`.

## `Analyze-CBSRun.ps1` — focused report generator

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
```

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

1. verifies that both PowerShell helpers and the required archive utility are present;
2. creates a unique timestamped working folder on the Desktop;
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
- Windows `tar.exe` available for ZIP creation and archive inspection.
- All three executable files kept together.
- A writable Desktop and temporary directory.
- Sufficient free space on the Desktop and temporary-file volumes for the timestamped working folder, ZIP archive, and archive-processing overhead.
- Mode 3 is configured to attempt shadow-copy deletion on both `C:` and `D:`. Edit the batch if those are not the intended volumes.

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

- If either PowerShell helper is missing, maintenance is not started.
- If watcher readiness times out, maintenance is not started.
- If the watcher fails, it writes `CBS_Run_Capture.log.error.txt` where possible.
- If watcher shutdown confirmation times out, the batch warns and continues finalization attempts.
- If the analyzer fails, the raw capture remains available inside the timestamped working folder for manual analysis.
- If an expected report is missing, the analyzer stage is treated as failed.
- If ZIP creation or archive validation fails, the timestamped working folder remains intact.
- The working folder is never removed merely because archive creation returned a success code; validation must also succeed.

---

## 10. Validation status

The maintenance, watcher, analyzer, and v8 packaging architecture has been tested through:

- an all-modes offline analyzer regression harness;
- 51 successful regression checks with no failures on a known detailed capture;
- dry-run execution of Modes 1, 2, and 3;
- real execution of Modes 1, 2, and 3 on the development system;
- cleanup examples containing 602 complete correlated chains, 1 complete chain, and 0 chains;
- Mode 1 cleanup-report suppression;
- watcher startup, live capture, stop, and final flush;
- correct mode-specific report generation;
- timestamped working-folder and whole-folder ZIP creation;
- exact mode-specific archive-content validation; and
- post-validation working-folder removal with `KeepWorkingFolder=0`.

The v8 packaging path was exercised successfully on Windows through real executions of all three modes on July 26, 2026. Each run produced one ZIP containing a single matching timestamped root folder and exactly the expected mode-specific file set. In all three runs, the validated ZIP remained and the uncompressed working folder was removed as configured.

The real-run validation archives were:

- Mode 1: `cleanup-report_2026-07-26_16-58-25.zip`  
  SHA-256: `f27616251b9c3be2e9186aff20071ab65c713a5ef788e8c3993b1f3e0959caa1`
- Mode 2: `cleanup-report_2026-07-26_17-07-26.zip`  
  SHA-256: `615d63fe61db484bce5e90c1c956e21ba981d100e54d9d7c628323d3e154d01c`
- Mode 3: `cleanup-report_2026-07-26_17-18-11.zip`  
  SHA-256: `9b6185339d75b531bb66879779d6c7d53502c4a5ac980a8479f033f8a5b62423`

Post-run review of the Mode 3 system CBS log confirmed that records written after the captured final SFC line were limited to TrustedInstaller/TiWorker automatic shutdown, completion confirmation for outstanding sessions, cache statistics, and component finalization. No additional maintenance result or failure was omitted from the run capture.

The timestamp-collision suffix path and deliberately forced capture, analysis, archive, validation, or removal failures were not triggered as part of these three real runs. Their safeguards remain implemented and documented, but those exceptional branches should not be described as exhaustively Windows-tested.

On the tested development system, the completed validation is sufficient for this v8 package to be treated as the canonical release.

Successful validation provides confidence in the tested configuration but cannot guarantee identical behavior on every Windows build or future servicing format.

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
