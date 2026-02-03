<#
.SYNOPSIS
    Installs a printer driver from an INF file using pnputil.

.DESCRIPTION
    This script installs a printer driver package into the Windows Driver Store
    using pnputil.exe. The INF file is expected to be located in the same folder
    as this script (the script root). The script is designed to be used in an
    Intune Win32 app deployment, but it can also be used standalone.

.NOTES
    Author: Marius Gehrmann
    Requires: Windows 10/11, pnputil.exe, administrative privileges

.INTUNE
    Usage as Intune Win32 App:
        - Package content:
            - Install-PrinterDriver.ps1
            - Uninstall-PrinterDriver.ps1
            - Detect-PrinterDriver.ps1 (optional, for detection)
            - <YourPrinterDriver>.inf and all required driver files
        - Install command:
            powershell.exe -ExecutionPolicy Bypass -File .\Install-PrinterDriver.ps1
        - Uninstall command:
            powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-PrinterDriver.ps1
        - Install behavior:
            - Runs as SYSTEM by default for Win32 apps (recommended for drivers)
        - Detection:
            - Use Detect-PrinterDriver.ps1 as a custom PowerShell detection rule
              (0 = detected, non-zero = not detected).

    If used as an Intune PowerShell script assignment (not Win32 app):
        - Run this script using the logged on credentials: NO
        - Enforce script signature check: As required by your org (e.g. NO for testing, YES if signed)
        - Run script in 64 bit PowerShell Host: YES

.PARAMETER None
    This script has no parameters. Configuration is done via variables
    in the configuration section.

.EVENT LOG
    Currently this script only writes to a log file on disk and not
    into the Windows Event Log. This section is reserved for future
    extension if needed.

.RELEASE NOTES
    V1.0, 10.12.2025 - Initial version to install printer driver INF via pnputil.
#>

#region Configuration

# Name of the INF file that contains the printer driver.
# IMPORTANT: Change this to match your actual INF file name.
$DriverInfName = 'KOAXGJ__.inf'

# Folder for log files (must be writable by SYSTEM / admin)
$LogFolder = 'C:\ProgramData\IntuneLogs\PrinterDriver'

# Build full path to INF file (it is expected to be in the same folder as this script)
$DriverInfPath = Join-Path -Path $PSScriptRoot -ChildPath $DriverInfName

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
    return Join-Path -Path $LogFolder -ChildPath "PrinterDriverInstall_$dateStamp.log"
}

function Write-Log {
    <#
        .SYNOPSIS
            Writes a message to the log file and to the console.
        .PARAMETER Message
            The log message text.
        .PARAMETER Level
            The log level (INFO, WARN, ERROR).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine   = "[$timestamp] [$Level] $Message"

    # Write to console (for Intune logs) and to file
    Write-Host $logLine
    Add-Content -Path $Global:LogFilePath -Value $logLine
}

function Get-PnPUtilPath {
    <#
        .SYNOPSIS
            Returns the correct pnputil.exe path, taking 32/64bit into account.
    #>
    if ($env:PROCESSOR_ARCHITEW6432 -or $env:PROCESSOR_ARCHITECTURE -eq 'x86') {
        # 32-bit PowerShell on 64-bit OS -> use sysnative to reach real System32
        return (Join-Path $env:WINDIR 'sysnative\pnputil.exe')
    }
    else {
        return (Join-Path $env:WINDIR 'System32\pnputil.exe')
    }
}

#endregion Helper functions

#region Main

# Prepare logging
New-LogFolder
$Global:LogFilePath = Get-LogFilePath
Write-Log -Message "=== Starting printer driver installation ==="

try {
    # Check if INF file exists in script root
    if (-not (Test-Path -Path $DriverInfPath)) {
        Write-Log -Message "INF file not found: $DriverInfPath" -Level 'ERROR'
        throw "INF file not found."
    }

    Write-Log -Message "INF file found: $DriverInfPath"
    $pnputil = Get-PnPUtilPath

    if (-not (Test-Path -Path $pnputil)) {
        Write-Log -Message "pnputil.exe not found at: $pnputil" -Level 'ERROR'
        throw "pnputil.exe not found."
    }

    Write-Log -Message "Using pnputil: $pnputil"

    # Build argument list for pnputil
    # /add-driver <path> /install
    $arguments = "/add-driver `"$DriverInfPath`" /install"

    Write-Log -Message "Executing: pnputil $arguments"

    $process = Start-Process -FilePath $pnputil -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden

    Write-Log -Message "pnputil exit code: $($process.ExitCode)"

    if ($process.ExitCode -eq 0) {
        Write-Log -Message "Printer driver installation successful."
        Write-Log -Message "=== Printer driver installation completed successfully ==="
        exit 0
    }
    else {
        Write-Log -Message "Printer driver installation failed with exit code $($process.ExitCode)." -Level 'ERROR'
        throw "pnputil failed with exit code $($process.ExitCode)."
    }
}
catch {
    Write-Log -Message "Exception: $($_.Exception.Message)" -Level 'ERROR'
    Write-Log -Message "=== Printer driver installation failed ===" -Level 'ERROR'
    exit 1
}

#endregion Main