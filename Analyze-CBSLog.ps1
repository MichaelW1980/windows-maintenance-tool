[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceLog,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 3)]
    [int]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DISMRepairLog,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CleanupLog,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ContentRetentionLog,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SFCLog
)

# Analyze all CBS-derived reports in one streaming pass.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function New-StringList {
    New-Object 'System.Collections.Generic.List[string]'
}

function New-ObjectList {
    New-Object 'System.Collections.Generic.List[object]'
}

function Test-ContainsAny {
    param([string]$Line, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Line.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Add-Section {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string]$Title,
        [System.Collections.IEnumerable]$Lines,
        [string]$EmptyText = 'No matching records were found.'
    )

    $Target.Add(('=' * 78))
    $Target.Add($Title)
    $Target.Add(('=' * 78))

    $added = 0
    foreach ($line in $Lines) {
        $Target.Add([string]$line)
        $added++
    }
    if ($added -eq 0) { $Target.Add($EmptyText) }
    $Target.Add('')
}

function Write-OutputFile {
    param(
        [string]$Path,
        [System.Collections.IEnumerable]$Lines
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $tempPath = $Path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllLines($tempPath, [string[]]@($Lines), $encoding)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-FlatReport {
    param(
        [string]$Path,
        [System.Collections.IEnumerable]$Lines,
        [string]$EmptyText
    )

    $materialized = @($Lines)
    if ($materialized.Count -eq 0) {
        $materialized = @($EmptyText)
    }
    Write-OutputFile -Path $Path -Lines $materialized
}

function Add-IncompleteEvent {
    param(
        [System.Collections.Generic.List[object]]$Target,
        [hashtable]$Pending,
        [string]$Reason
    )

    if ($null -eq $Pending) { return }
    $Pending.Reason = $Reason
    $Target.Add([pscustomobject]$Pending)
}

$SourceLog = [System.IO.Path]::GetFullPath($SourceLog)
$DISMRepairLog = [System.IO.Path]::GetFullPath($DISMRepairLog)
$CleanupLog = [System.IO.Path]::GetFullPath($CleanupLog)
$ContentRetentionLog = [System.IO.Path]::GetFullPath($ContentRetentionLog)
$SFCLog = [System.IO.Path]::GetFullPath($SFCLog)

if (-not (Test-Path -LiteralPath $SourceLog -PathType Leaf)) {
    throw "CBS source log was not found: $SourceLog"
}

$dismPatterns = @(
    'Finished repairing CBS Store',
    'Finished repairing CSI store',
    'Processing complete, session(Corruption Detecting)',
    'Processing complete, session(Corruption Repairing)',
    'Total Detected Corruption',
    'Total Repaired Corruption',
    'CBS Manifest Corruption',
    'CBS Metadata Corruption',
    'CSI Manifest Corruption',
    'CSI Metadata Corruption',
    'CSI Payload Corruption',
    'CSI FileFlags Corrupt',
    'CSI FileFlags Repaired',
    'SetComponentFileFlag(',
    'CSI Registry Metadata refreshed',
    'CSI Store Metadata refreshed',
    'Primitive installers committed',
    'No payload missing but suspected file flag corruption detected',
    'RepairStagedFileFlags',
    'HRESULT = 0x00000000 - S_OK'
)

$sfcPatterns = @(
    '[SR] Repairing',
    '[SR] Repair complete',
    'Cannot repair member file',
    'Repair failed',
    'Could not reproject corrupted file',
    'DEPLOY [Pnp] Corrupt file:',
    'DEPLOY [Pnp] Repaired file:'
)

$cleanupPatterns = @(
    'Maint: begin scavenge',
    'Scavenge: Start CSI',
    'Scavenge: Begin CSI Store',
    'Scavenge: Begin planning',
    'Scavenge: Planning Complete',
    'Scavenge: List processing complete',
    'Scavenge: Completed',
    'Maint: end scavenge',
    'Maint: processing complete',
    'Reboot required: no',
    'HRESULT = 0x00000000 - S_OK'
)

$timelineTokens = @(
    'Maint: processing started.',
    'Maint: launch type:',
    'Maint: begin deep clean',
    'Maint: Deepclean: packages pruned:',
    'Maint: Deepclean: packages removed:',
    'Maint: end deep clean',
    'Maint: begin drain catalogs',
    'Maint: end drain catalogs',
    'Maint: begin archive logs',
    'Maint: end archive logs',
    'Maint: begin scavenge',
    'Scavenge: Start CSI',
    'Scavenge: Begin CSI Store',
    'Scavenge: Begin planning',
    'Scavenge: Planning Complete',
    'Scavenge: List processing complete',
    'Scavenge: Completed',
    'Maint: end scavenge',
    'Maint: disposition:',
    'Maint: processing complete.'
)

$headerRegex = [regex]"CSI\s+([0-9a-fA-F]+)\s+Hashes for file member .*?'([^']+)' do not match\."
$markerRegex = [regex]"CSI\s+([0-9a-fA-F]+)@.*Attempting to mark store corrupt with category .*?'CorruptPayloadFile'"
$retainRegex = [regex]"CSI\s+([0-9a-fA-F]+)@.*STATUS_SXS_FILE_HASH_MISMATCH.*ComponentStore::CRawStoreLayout::RetainFileAsVersion"
$contextRegex = [regex]"CSI\s+([0-9a-fA-F]+)\s+Scavenge: Attempting content retention of: (.+?) as baseline keyform: (.+)$"
$hashRegex = [regex]'b:([0-9a-fA-F]{64})'
$completionRegex = [regex]'Maint: completed, interruptions: (\d+), \(this pass: time: (\d+) seconds, used space change: .*?, hr: ([^,]+), source: ([^)]+)\)'

$dismDetails = New-StringList
$sfcDetails = New-StringList
$existingCleanup = New-StringList
$timeline = New-StringList
$packageCompletion = New-StringList
$contexts = New-ObjectList
$scopedHeaders = New-StringList
$scopedMarkers = New-StringList
$scopedRetains = New-StringList
$outOfScopeRelated = New-StringList
$events = New-ObjectList
$incompleteEvents = New-ObjectList

$pendingStart = New-StringList
$inCleanup = $false
$inScavenge = $false
$activeContext = $null
$cleanupSessionId = 0
$contextId = 0
$pending = $null
$lineNumber = 0

$reader = New-Object System.IO.StreamReader($SourceLog, [System.Text.Encoding]::UTF8, $true, 65536)
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        $lineNumber++

        if (Test-ContainsAny $line $dismPatterns) {
            $dismDetails.Add($line)
        }

        if (Test-ContainsAny $line $sfcPatterns) {
            $sfcDetails.Add($line)
        }

        if (Test-ContainsAny $line $cleanupPatterns) {
            $existingCleanup.Add($line)
        }

        $headerMatch = $headerRegex.Match($line)
        $markerMatch = $markerRegex.Match($line)
        $retainMatch = $retainRegex.Match($line)
        $strictScope = $inCleanup -and $inScavenge -and ($null -ne $activeContext)

        if ($headerMatch.Success) {
            if ($strictScope) { $scopedHeaders.Add($line) }
            else { $outOfScopeRelated.Add(('Line {0}: {1}' -f $lineNumber, $line)) }
        }
        if ($markerMatch.Success) {
            if ($strictScope) { $scopedMarkers.Add($line) }
            else { $outOfScopeRelated.Add(('Line {0}: {1}' -f $lineNumber, $line)) }
        }
        if ($retainMatch.Success) {
            if ($strictScope) { $scopedRetains.Add($line) }
            else { $outOfScopeRelated.Add(('Line {0}: {1}' -f $lineNumber, $line)) }
        }

        $acceptedPendingLine = $false
        if ($null -ne $pending) {
            switch ($pending.Stage) {
                'expected' {
                    if ($line.StartsWith(' Expected:')) {
                        $hashMatch = $hashRegex.Match($line)
                        if ($hashMatch.Success) {
                            $pending.Raw.Add($line)
                            $pending.ExpectedLine = $line
                            $pending.ExpectedHash = $hashMatch.Groups[1].Value
                            $pending.Stage = 'actual'
                            $acceptedPendingLine = $true
                        }
                    }
                }
                'actual' {
                    if ($line.StartsWith(' Actual:')) {
                        $hashMatch = $hashRegex.Match($line)
                        if ($hashMatch.Success) {
                            $pending.Raw.Add($line)
                            $pending.ActualLine = $line
                            $pending.ActualHash = $hashMatch.Groups[1].Value
                            $pending.Stage = 'marker'
                            $acceptedPendingLine = $true
                        }
                    }
                }
                'marker' {
                    if ($markerMatch.Success -and $strictScope) {
                        $pending.Raw.Add($line)
                        $pending.MarkerLine = $line
                        $pending.MarkerCsi = $markerMatch.Groups[1].Value
                        $pending.Stage = 'retain'
                        $acceptedPendingLine = $true
                    }
                }
                'retain' {
                    if ($retainMatch.Success -and $strictScope) {
                        $pending.Raw.Add($line)
                        $pending.RetainLine = $line
                        $pending.RetainCsi = $retainMatch.Groups[1].Value
                        $pending.Stage = 'gle'
                        $acceptedPendingLine = $true
                    }
                }
                'gle' {
                    if ($line.StartsWith('[gle=')) {
                        $pending.Raw.Add($line)
                        $pending.GleLine = $line
                        $pending.Complete = $true
                        $events.Add([pscustomobject]$pending)
                        $pending = $null
                        $acceptedPendingLine = $true
                    }
                }
            }

            if (-not $acceptedPendingLine -and $null -ne $pending) {
                Add-IncompleteEvent $incompleteEvents $pending ('Unexpected line {0} while expecting {1}' -f $lineNumber, $pending.Stage)
                $pending = $null
            }
        }

        if ($acceptedPendingLine) { continue }

        if ($line.Contains('Maint: processing started.') -and $line.Contains('Client: DISM Package Manager Provider')) {
            $pendingStart.Clear()
            $pendingStart.Add($line)
        }
        elseif ($pendingStart.Count -gt 0 -and $line.Contains('Maint: launch type:')) {
            $pendingStart.Add($line)
        }

        $bufferedStartComponentCleanup = $false
        foreach ($startLine in $pendingStart) {
            if ($startLine.Contains('Maint: launch type: StartComponentCleanup')) {
                $bufferedStartComponentCleanup = $true
                break
            }
        }

        $cleanupStartDetected = $line.Contains('Maint: begin deep clean') -or
            ($line.Contains('Maint: begin scavenge') -and $bufferedStartComponentCleanup)

        if ($cleanupStartDetected -and -not $inCleanup) {
            $cleanupSessionId++
            $inCleanup = $true
            foreach ($startLine in $pendingStart) { $timeline.Add($startLine) }
            $pendingStart.Clear()
        }

        if ($inCleanup -and (Test-ContainsAny $line $timelineTokens)) {
            if ($timeline.Count -eq 0 -or $timeline[$timeline.Count - 1] -ne $line) {
                $timeline.Add($line)
            }
        }

        if ($inCleanup) {
            $completionMatch = $completionRegex.Match($line)
            if ($completionMatch.Success) {
                $timeline.Add(('Cleanup pass completion summary: interruptions={0}; time={1} seconds; result={2}; source={3}' -f
                    $completionMatch.Groups[1].Value,
                    $completionMatch.Groups[2].Value,
                    $completionMatch.Groups[3].Value,
                    $completionMatch.Groups[4].Value))
            }

            if ($line.Contains('Reporting package change completion for package:')) {
                $packageCompletion.Add($line)
            }
        }

        if ($inCleanup -and $line.Contains('Maint: begin scavenge')) {
            $inScavenge = $true
            $activeContext = $null
        }

        $contextMatch = $contextRegex.Match($line)
        if ($inCleanup -and $inScavenge -and $contextMatch.Success) {
            $contextId++
            $activeContext = [pscustomobject]@{
                Id = $contextId
                CleanupSession = $cleanupSessionId
                Line = $line
                Csi = $contextMatch.Groups[1].Value
                Source = $contextMatch.Groups[2].Value
                Baseline = $contextMatch.Groups[3].Value
            }
            $contexts.Add($activeContext)
        }
        elseif ($contextMatch.Success) {
            $outOfScopeRelated.Add(('Line {0}: {1}' -f $lineNumber, $line))
        }

        if ($inScavenge -and $line.Contains('Maint: end scavenge')) {
            if ($null -ne $pending) {
                Add-IncompleteEvent $incompleteEvents $pending 'Scavenge ended before event completion'
                $pending = $null
            }
            $inScavenge = $false
            $activeContext = $null
        }

        if ($inCleanup -and $line.Contains('Maint: processing complete.')) {
            if ($null -ne $pending) {
                Add-IncompleteEvent $incompleteEvents $pending 'Cleanup session ended before event completion'
                $pending = $null
            }
            $inCleanup = $false
            $inScavenge = $false
            $activeContext = $null
        }

        $strictScope = $inCleanup -and $inScavenge -and ($null -ne $activeContext)
        if ($headerMatch.Success -and $strictScope) {
            $rawLines = New-StringList
            $rawLines.Add($line)
            $pending = @{
                Stage = 'expected'
                Complete = $false
                Raw = $rawLines
                StartLineNumber = $lineNumber
                HeaderLine = $line
                HeaderCsi = $headerMatch.Groups[1].Value
                File = $headerMatch.Groups[2].Value
                Context = $activeContext
                ExpectedLine = ''
                ActualLine = ''
                MarkerLine = ''
                RetainLine = ''
                GleLine = ''
                ExpectedHash = ''
                ActualHash = ''
                MarkerCsi = ''
                RetainCsi = ''
                Reason = ''
            }
        }
    }
}
finally {
    $reader.Dispose()
}

if ($null -ne $pending) {
    Add-IncompleteEvent $incompleteEvents $pending 'End of file before event completion'
    $pending = $null
}

$successfulPackages = @($packageCompletion | Where-Object {
    $_.Contains('current: Absent') -and
    $_.Contains('target: Absent') -and
    $_.Contains('status: 0x0')
})
$otherPackages = @($packageCompletion | Where-Object { $successfulPackages -notcontains $_ })

$consumedHeaders = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$consumedMarkers = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$consumedRetains = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($event in $events) {
    [void]$consumedHeaders.Add($event.HeaderLine)
    [void]$consumedMarkers.Add($event.MarkerLine)
    [void]$consumedRetains.Add($event.RetainLine)
}

$uncorrelatedHeaders = @($scopedHeaders | Where-Object { -not $consumedHeaders.Contains($_) })
$uncorrelatedMarkers = @($scopedMarkers | Where-Object { -not $consumedMarkers.Contains($_) })
$uncorrelatedRetains = @($scopedRetains | Where-Object { -not $consumedRetains.Contains($_) })

$summaryLines = @(
    'Classifier: cleanup_retention_hash_mismatch_v1',
    'Classifier scope: recognized DISM cleanup session + active scavenge phase + active content-retention context',
    'Complete event signature: hash header + Expected hash + Actual hash + CorruptPayloadFile marker + RetainFileAsVersion mismatch + GLE line',
    "Cleanup sessions recognized: $cleanupSessionId",
    "Content-retention contexts observed: $($contexts.Count)",
    "Hash-mismatch headers observed in classifier scope: $($scopedHeaders.Count)",
    "CorruptPayloadFile markers observed in classifier scope: $($scopedMarkers.Count)",
    "RetainFileAsVersion mismatch records observed in classifier scope: $($scopedRetains.Count)",
    "Complete correlated event chains: $($events.Count)",
    "Incomplete candidate chains: $($incompleteEvents.Count)",
    "Uncorrelated in-scope hash-mismatch headers: $($uncorrelatedHeaders.Count)",
    "Uncorrelated in-scope CorruptPayloadFile markers: $($uncorrelatedMarkers.Count)",
    "Uncorrelated in-scope RetainFileAsVersion records: $($uncorrelatedRetains.Count)",
    "Related records outside classifier scope: $($outOfScopeRelated.Count)",
    "Successful package-removal completion records: $($successfulPackages.Count)",
    "Other package-change completion records: $($otherPackages.Count)",
    '',
    'Interpretation guardrail:',
    'These are cleanup content-retention comparison events. They are not counted as',
    'active-store corruption repairs unless an explicit, correlated repair signature exists.',
    'Incomplete, uncorrelated, and out-of-scope records are preserved separately and are',
    'not forced into the confirmed event count.'
)

$cleanupOutput = New-StringList
Add-Section $cleanupOutput 'BASELINE CLEANUP EXTRACTION' $existingCleanup 'No cleanup/scavenge detail matches were found in the run-scoped CBS capture.'
Add-Section $cleanupOutput 'CLEANUP PHASE TIMELINE' $timeline 'No recognized cleanup phase timeline was found.'
Add-Section $cleanupOutput 'PACKAGE CHANGE COMPLETION RECORDS' $packageCompletion 'No package-change completion records were found in the recognized cleanup session.'
Add-Section $cleanupOutput 'CONTENT-RETENTION CORRELATION SUMMARY' $summaryLines

$detailOutput = New-StringList
$detailOutput.Add('CBS run cleanup content-retention classifier output - Option B raw evidence')
$sourceInfo = Get-Item -LiteralPath $SourceLog
$detailOutput.Add('Classifier: cleanup_retention_hash_mismatch_v1')
$detailOutput.Add('Source file: ' + $sourceInfo.Name)
$detailOutput.Add('Source size: ' + $sourceInfo.Length + ' bytes')
$detailOutput.Add('')

$contextLegend = New-StringList
foreach ($context in $contexts) {
    $contextLegend.Add(('CR-{0:D2} | CleanupSession={1} | CSI={2} | Source={3} | Baseline={4}' -f
        $context.Id, $context.CleanupSession, $context.Csi, $context.Source, $context.Baseline))
}
Add-Section $detailOutput 'CONTENT-RETENTION CONTEXT LEGEND' $contextLegend 'No recognized content-retention contexts were found.'
Add-Section $detailOutput 'HASH-MISMATCH HEADERS IN CLASSIFIER SCOPE' $scopedHeaders 'No in-scope hash-mismatch headers were found.'
Add-Section $detailOutput 'CORRUPTPAYLOADFILE MARKERS IN CLASSIFIER SCOPE' $scopedMarkers 'No in-scope CorruptPayloadFile markers were found.'
Add-Section $detailOutput 'RETAINFILEASVERSION MISMATCH RECORDS IN CLASSIFIER SCOPE' $scopedRetains 'No in-scope RetainFileAsVersion mismatch records were found.'

$rawEventLines = New-StringList
foreach ($event in $events) {
    foreach ($rawLine in $event.Raw) { $rawEventLines.Add($rawLine) }
}
Add-Section $detailOutput 'COMPLETE CORRELATED EVENT CHAINS - RAW SIX-LINE RECORDS' $rawEventLines 'No complete correlated content-retention mismatch chains were found.'

$incompleteLines = New-StringList
$incompleteNumber = 0
foreach ($event in $incompleteEvents) {
    $incompleteNumber++
    $incompleteLines.Add(('Incomplete event {0:D4} | StartLine={1} | Reason={2}' -f $incompleteNumber, $event.StartLineNumber, $event.Reason))
    foreach ($rawLine in $event.Raw) { $incompleteLines.Add($rawLine) }
    $incompleteLines.Add('')
}
Add-Section $detailOutput 'INCOMPLETE CANDIDATE EVENT CHAINS' $incompleteLines 'No incomplete candidate chains were found.'
Add-Section $detailOutput 'UNCORRELATED IN-SCOPE HASH-MISMATCH HEADERS' $uncorrelatedHeaders 'No uncorrelated in-scope hash-mismatch headers were found.'
Add-Section $detailOutput 'UNCORRELATED IN-SCOPE CORRUPTPAYLOADFILE MARKERS' $uncorrelatedMarkers 'No uncorrelated in-scope CorruptPayloadFile markers were found.'
Add-Section $detailOutput 'UNCORRELATED IN-SCOPE RETAINFILEASVERSION RECORDS' $uncorrelatedRetains 'No uncorrelated in-scope RetainFileAsVersion records were found.'
Add-Section $detailOutput 'RELATED RECORDS OUTSIDE CLASSIFIER SCOPE' $outOfScopeRelated 'No related records were found outside the classifier scope.'

Write-FlatReport -Path $DISMRepairLog -Lines $dismDetails -EmptyText 'No DISM repair detail matches were found in the run-scoped CBS capture.'
Write-FlatReport -Path $SFCLog -Lines $sfcDetails -EmptyText 'No SFC detail matches were found in the run-scoped CBS capture.'

if ($Mode -ge 2) {
    Write-OutputFile -Path $CleanupLog -Lines $cleanupOutput
    Write-OutputFile -Path $ContentRetentionLog -Lines $detailOutput
}

Write-Host ('CBS run analyzer completed. Mode={0}; DISM lines={1}; SFC lines={2}; complete cleanup chains={3}; incomplete cleanup chains={4}; out-of-scope cleanup records={5}' -f
    $Mode, $dismDetails.Count, $sfcDetails.Count, $events.Count, $incompleteEvents.Count, $outOfScopeRelated.Count)
exit 0
