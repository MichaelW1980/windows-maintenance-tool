[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $true)]
    [string]$StopSignalPath,

    [Parameter(Mandatory = $true)]
    [string]$ReadySignalPath,

    [Parameter(Mandatory = $true)]
    [string]$DoneSignalPath,

    [int]$PollMilliseconds = 250
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$sourceStream = $null
$destinationStream = $null
$buffer = New-Object byte[] 65536
$currentCreationTimeUtc = $null
$currentPosition = 0L

function Open-SourceStream {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$StartAtEnd
    )

    while (-not (Test-Path -LiteralPath $SourcePath)) {
        if (Test-Path -LiteralPath $StopSignalPath) { return $false }
        Start-Sleep -Milliseconds $PollMilliseconds
    }

    $script:sourceStream = New-Object System.IO.FileStream(
        $SourcePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete),
        65536,
        [System.IO.FileOptions]::SequentialScan
    )

    $sourceInfo = Get-Item -LiteralPath $SourcePath
    $script:currentCreationTimeUtc = $sourceInfo.CreationTimeUtc

    if ($StartAtEnd) {
        $script:currentPosition = $script:sourceStream.Seek(0, [System.IO.SeekOrigin]::End)
    }
    else {
        $script:currentPosition = 0L
        [void]$script:sourceStream.Seek(0, [System.IO.SeekOrigin]::Begin)
    }

    return $true
}

function Copy-NewBytes {
    while ($true) {
        $bytesRead = $script:sourceStream.Read($buffer, 0, $buffer.Length)
        if ($bytesRead -le 0) { break }

        $destinationStream.Write($buffer, 0, $bytesRead)
        $script:currentPosition += $bytesRead
    }

    $destinationStream.Flush()
}

try {
    $destinationDirectory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        [void](New-Item -ItemType Directory -Path $destinationDirectory -Force)
    }

    foreach ($signalPath in @($ReadySignalPath, $DoneSignalPath)) {
        Remove-Item -LiteralPath $signalPath -Force -ErrorAction SilentlyContinue
    }

    $destinationStream = New-Object System.IO.FileStream(
        $DestinationPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read,
        65536,
        [System.IO.FileOptions]::SequentialScan
    )

    # The first source file starts at EOF so the capture is scoped to this run.
    if (-not (Open-SourceStream -StartAtEnd $true)) { return }

    [System.IO.File]::WriteAllText($ReadySignalPath, (Get-Date).ToString('o'))

    while (-not (Test-Path -LiteralPath $StopSignalPath)) {
        Copy-NewBytes

        $switchToNewFile = $false
        if (Test-Path -LiteralPath $SourcePath) {
            try {
                $pathInfo = Get-Item -LiteralPath $SourcePath

                # A shorter path file means truncation/recreation. A different
                # creation time normally means CBS.log was rotated and replaced.
                if ($pathInfo.Length -lt $currentPosition -or
                    $pathInfo.CreationTimeUtc -ne $currentCreationTimeUtc) {
                    $switchToNewFile = $true
                }
            }
            catch {
                # CBS may be between rename and recreation. Retry next cycle.
            }
        }

        if ($switchToNewFile) {
            # Drain the old file handle one last time, then continue from byte 0
            # of the newly created active CBS.log.
            Copy-NewBytes
            $sourceStream.Dispose()
            $sourceStream = $null
            [void](Open-SourceStream -StartAtEnd $false)
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }

    # Capture bytes written immediately before the stop signal was observed.
    Copy-NewBytes
}
catch {
    $errorPath = "$DestinationPath.error.txt"
    $_ | Out-String | Set-Content -LiteralPath $errorPath -Encoding UTF8
    exit 1
}
finally {
    if ($null -ne $sourceStream) { $sourceStream.Dispose() }
    if ($null -ne $destinationStream) {
        $destinationStream.Flush()
        $destinationStream.Dispose()
    }

    try {
        [System.IO.File]::WriteAllText($DoneSignalPath, (Get-Date).ToString('o'))
    }
    catch { }
}
