<#
.SYNOPSIS
    Uninstalls a printer driver that was installed from a specific INF file.

.DESCRIPTION
    This script looks for driver packages in the Windows Driver Store whose
    OriginalFileName matches the configured INF file name. For each matching
    driver (e.g. oemXX.inf), pnputil.exe is used to uninstall and delete the
    driver from the Driver Store.

.NOTES
    Author: Marius Gehrmann
    Requires: Windows 10/11, pnputil.exe, administrative privileges

.INTUNE
    Usage as Intune Win32 App:
        - Uninstall command:
            powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-PrinterDriver.ps1
        - Runs as SYSTEM by default (recommended for drivers).

.PARAMETER None
    This script has no parameters. Configuration is done via variables
    in the configuration section.

.EVENT LOG
    Currently this script only writes to a log file on disk and not
    into the Windows Event Log. This section is reserved for future
    extension if needed.

.RELEASE NOTES
    V1.0, 10.12.2025 - Initial version to uninstall printer driver INF via pnputil.
    V1.1, 10.12.2025 - Fixed string interpolation for $publishedName in log message (InvalidVariableReferenceWithDrive).
#>

#region Configuration

# Name of the INF file that was used to install the printer driver.
# IMPORTANT: Must match the INF name in Install-PrinterDriver.ps1.
$DriverInfName = 'KOAXGJ__.inf'

# Folder for log files
$LogFolder = 'C:\ProgramData\IntuneLogs\PrinterDriver'

#endregion Configuration

#region Helper functions

function New-LogFolder {
    <#
        .SYNOPSIS
            Creates the log folder if it does not exist.
    #>
    if (-not (Test-Path -Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }
}

function Get-LogFilePath {
    <#
        .SYNOPSIS
            Returns the full path of the log file.
    #>
    $dateStamp = Get-Date -Format 'yyyyMMdd'
    return Join-Path -Path $LogFolder -ChildPath "PrinterDriverUninstall_$dateStamp.log"
}

function Write-Log {
    <#
        .SYNOPSIS
            Writes a message to the log file and console.
        .PARAMETER Message
            Log message text.
        .PARAMETER Level
            Log level (INFO, WARN, ERROR).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine   = "[$timestamp] [$Level] $Message"

    Write-Host $logLine
    Add-Content -Path $Global:LogFilePath -Value $logLine
}

function Get-PnPUtilPath {
    <#
        .SYNOPSIS
            Returns the correct pnputil.exe path (handles 32/64 bit).
    #>
    if ($env:PROCESSOR_ARCHITEW6432 -or $env:PROCESSOR_ARCHITECTURE -eq 'x86') {
        return (Join-Path $env:WINDIR 'sysnative\pnputil.exe')
    }
    else {
        return (Join-Path $env:WINDIR 'System32\pnputil.exe')
    }
}

#endregion Helper functions

#region Main

New-LogFolder
$Global:LogFilePath = Get-LogFilePath
Write-Log -Message "=== Starting printer driver uninstallation ==="

try {
    $pnputil = Get-PnPUtilPath

    if (-not (Test-Path -Path $pnputil)) {
        Write-Log -Message "pnputil.exe not found at: $pnputil" -Level 'ERROR'
        throw "pnputil.exe not found."
    }

    Write-Log -Message "Using pnputil: $pnputil"
    Write-Log -Message "Searching for drivers whose OriginalFileName equals '$DriverInfName'"

    # Use Get-WindowsDriver to find drivers that were originally installed from this INF
    Import-Module Dism -ErrorAction SilentlyContinue | Out-Null

    $drivers = Get-WindowsDriver -Online -All |
        Where-Object { (Split-Path $_.OriginalFileName -Leaf) -ieq $DriverInfName }

    if (-not $drivers) {
        Write-Log -Message "No driver packages found for INF '$DriverInfName'. Nothing to uninstall."
        Write-Log -Message "=== Printer driver uninstallation completed (nothing to do) ==="
        exit 0
    }

    Write-Log -Message ("Found {0} matching driver package(s)." -f $drivers.Count)

    $overallExitCode = 0

    foreach ($driver in $drivers) {
        $publishedName = $driver.Driver  # e.g. oem23.inf
        Write-Log -Message "Attempting to delete driver package: $publishedName (Original: $(Split-Path $driver.OriginalFileName -Leaf))"

        # /delete-driver oemXX.inf /uninstall /force
        $arguments = "/delete-driver $publishedName /uninstall /force"
        Write-Log -Message "Executing: pnputil $arguments"

        $process = Start-Process -FilePath $pnputil -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

        # WICHTIGER FIX: $publishedName in Subexpression kapseln, weil danach ein ":" kommt
        Write-Log -Message ("pnputil exit code for {0}: {1}" -f $publishedName, $process.ExitCode)

        if ($process.ExitCode -ne 0) {
            Write-Log -Message "Failed to remove driver package $publishedName." -Level 'ERROR'
            $overallExitCode = 1
        }
        else {
            Write-Log -Message "Successfully removed driver package $publishedName."
        }
    }

    if ($overallExitCode -eq 0) {
        Write-Log -Message "=== Printer driver uninstallation completed successfully ==="
        exit 0
    }
    else {
        Write-Log -Message "=== Printer driver uninstallation completed with errors ===" -Level 'WARN'
        exit 1
    }
}
catch {
    Write-Log -Message "Exception: $($_.Exception.Message)" -Level 'ERROR'
    Write-Log -Message "=== Printer driver uninstallation failed ===" -Level 'ERROR'
    exit 1
}

#endregion Main