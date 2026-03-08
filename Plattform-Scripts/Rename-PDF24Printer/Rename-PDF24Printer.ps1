<#
.SYNOPSIS
    Renames the PDF24 virtual printer to "FreePDF".

.DESCRIPTION
    Post-installation script for Patch My PC.
    Locates the printer named "PDF24" installed by PDF24 Creator and renames it to "FreePDF".
    Runs in SYSTEM context as executed by Patch My PC.

.NOTES
    Author:  Marius Gehrmann - Business IT Solutions
    Date:    2026-03-08
    Version: 2.0

.EXIT CODES
    0 - Printer successfully renamed
    1 - Printer not found or unexpected error

.RELEASE NOTES
    2026-03-08: Rewritten to target the printer object instead of the registry display name
#>

$SourceName = "PDF24"
$TargetName = "FreePDF"

try {
    $printer = Get-Printer -Name $SourceName -ErrorAction SilentlyContinue

    if (-not $printer) {
        Write-Warning "Printer '$SourceName' not found. PDF24 Creator may not be installed yet."
        Exit 1
    }

    Write-Host "Renaming printer '$SourceName' to '$TargetName'..."
    Rename-Printer -Name $SourceName -NewName $TargetName -ErrorAction Stop
    Write-Host "Printer successfully renamed to '$TargetName'."

    Exit 0
}
catch {
    Write-Error "Failed to rename printer: $($_.Exception.Message)"
    Exit 1
}
