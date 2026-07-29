[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedFiles
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Exit codes:
#   0 = archive created and validated
#   1 = invalid argument or source directory
#   2 = expected source report set is invalid or incomplete
#   3 = destination archive already exists
#   4 = archive creation failed
#   5 = created archive is missing
#   6 = archive validation failed

$createdByThisRun = $false
$zip = $null

function Remove-PartialArchive {
    if ($script:createdByThisRun -and (Test-Path -LiteralPath $DestinationPath)) {
        Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-ArchivePath {
    param([string]$Path)
    return (($Path -replace '\\', '/').TrimStart([char[]]'./'))
}

try {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        throw 'SourcePath is empty.'
    }
    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        throw 'DestinationPath is empty.'
    }

    $SourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    $DestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        [Console]::Error.WriteLine("Source working folder was not found: $SourcePath")
        exit 1
    }

    $expected = @(
        $ExpectedFiles -split '\|' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($expected.Count -eq 0) {
        [Console]::Error.WriteLine('ExpectedFiles did not contain any file names.')
        exit 2
    }

    $duplicateExpected = @(
        $expected |
            Group-Object |
            Where-Object { $_.Count -ne 1 }
    )
    if ($duplicateExpected.Count -ne 0) {
        [Console]::Error.WriteLine(('ExpectedFiles contains duplicate names: ' + (($duplicateExpected | ForEach-Object Name) -join ', ')))
        exit 2
    }

    foreach ($name in $expected) {
        if ([System.IO.Path]::IsPathRooted($name) -or $name.Contains('/') -or $name.Contains('\')) {
            [Console]::Error.WriteLine("Expected report names must be simple file names: $name")
            exit 2
        }

        $sourceFile = Join-Path -Path $SourcePath -ChildPath $name
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
            [Console]::Error.WriteLine("Expected source report is missing: $sourceFile")
            exit 2
        }
    }

    if (Test-Path -LiteralPath $DestinationPath) {
        [Console]::Error.WriteLine("Destination archive already exists: $DestinationPath")
        exit 3
    }

    $destinationParent = Split-Path -Parent $DestinationPath
    if ([string]::IsNullOrWhiteSpace($destinationParent) -or
        -not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        [Console]::Error.WriteLine("Destination directory is unavailable: $destinationParent")
        exit 1
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # From this point onward, any destination file belongs to this invocation
        # and may be removed if creation or validation does not complete.
        $createdByThisRun = $true
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $SourcePath,
            $DestinationPath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $true
        )
    }
    catch {
        Remove-PartialArchive
        [Console]::Error.WriteLine(("ZIP archive creation failed: " + $_.Exception.Message))
        exit 4
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        Remove-PartialArchive
        [Console]::Error.WriteLine("Archive creation returned without producing the destination file: $DestinationPath")
        exit 5
    }

    try {
        $baseName = [System.IO.Path]::GetFileName($SourcePath.TrimEnd([char[]]'\/'))
        $expectedPaths = @($expected | ForEach-Object { "$baseName/$_" })

        $zip = [System.IO.Compression.ZipFile]::OpenRead($DestinationPath)
        $fileEntries = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })

        if ($fileEntries.Count -ne $expected.Count) {
            throw "Expected $($expected.Count) file entries but found $($fileEntries.Count)."
        }

        foreach ($name in $expected) {
            $wanted = "$baseName/$name"
            $matches = @(
                $fileEntries |
                    Where-Object { (Normalize-ArchivePath $_.FullName) -ceq $wanted }
            )

            if ($matches.Count -ne 1) {
                throw "Expected exactly one archive entry: $wanted"
            }

            $sourceFile = Join-Path -Path $SourcePath -ChildPath $name
            $sourceLength = (Get-Item -LiteralPath $sourceFile).Length
            if ($matches[0].Length -ne $sourceLength) {
                throw "Uncompressed length mismatch for $wanted."
            }

            # Read the complete entry so malformed compressed data is detected,
            # rather than validating only ZIP metadata.
            $entryStream = $matches[0].Open()
            try {
                $buffer = New-Object byte[] 65536
                while ($entryStream.Read($buffer, 0, $buffer.Length) -gt 0) { }
            }
            finally {
                $entryStream.Dispose()
            }
        }

        $unexpected = @(
            $fileEntries |
                Where-Object { $expectedPaths -cnotcontains (Normalize-ArchivePath $_.FullName) }
        )
        if ($unexpected.Count -ne 0) {
            throw ('Unexpected archive file entries: ' + (($unexpected | ForEach-Object FullName) -join ', '))
        }
    }
    catch {
        if ($null -ne $zip) {
            $zip.Dispose()
            $zip = $null
        }
        Remove-PartialArchive
        [Console]::Error.WriteLine(("ZIP archive validation failed: " + $_.Exception.Message))
        exit 6
    }
    finally {
        if ($null -ne $zip) {
            $zip.Dispose()
            $zip = $null
        }
    }

    Write-Output "Archive created and validated: $DestinationPath"
    exit 0
}
catch {
    Remove-PartialArchive
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
