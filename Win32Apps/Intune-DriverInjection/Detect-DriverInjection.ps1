<#
.SYNOPSIS
    Detection script for a printer driver installed from a specific INF file.

.DESCRIPTION
    This script checks whether a driver package is present in the Windows
    Driver Store whose OriginalFileName matches the configured INF file name.
    If at least one matching driver package is found, the script exits with
    code 0 (detected). Otherwise it exits with code 1 (not detected).

.NOTES
    Author: Marius Gehrmann
    Requires: Windows 10/11, administrative privileges

.INTUNE
    Usage as Intune Win32 App detection rule:
        - Rule type: Custom
        - Script file: Detect-PrinterDriver.ps1
        - Run script as 32-bit process on 64-bit clients: NO (recommended)
        - Detection logic:
            - Exit code 0  => app is detected
            - Non-zero     => app is not detected

.PARAMETER None
    This script has no parameters. Configuration is done via variables
    in the configuration section.

.EVENT LOG
    This script only writes to standard output. Intune will capture the
    exit code. No Windows Event Log entries are created.

.RELEASE NOTES
    V1.0, 10.12.2025 - Initial version to detect printer driver based on INF.
#>

#region Configuration

# Name of the INF file that was used to install the printer driver.
# IMPORTANT: Must match the INF name in Install-PrinterDriver.ps1.
$DriverInfName = 'KOAXGJ__.inf'

#endregion Configuration

try {
    # Load DISM cmdlets if not already available
    Import-Module Dism -ErrorAction SilentlyContinue | Out-Null

    # Query all drivers in the Driver Store and filter by the INF filename
    $matchingDrivers = Get-WindowsDriver -Online -All |
        Where-Object { (Split-Path $_.OriginalFileName -Leaf) -ieq $DriverInfName }

    if ($matchingDrivers) {
        Write-Host ("Driver(s) found for INF '{0}': {1}" -f $DriverInfName, ($matchingDrivers.Driver -join ', '))
        exit 0  # Detected
    }
    else {
        Write-Host ("No driver found for INF '{0}'." -f $DriverInfName)
        exit 1  # Not detected
    }
}
catch {
    # In case of error, treat as not detected so Intune can try to install again
    Write-Host ("Error while detecting driver for INF '{0}': {1}" -f $DriverInfName, $_.Exception.Message)
    exit 1
}

<#
(Get-WindowsDriver -Online -All).ProviderName -ieq "Konica Minolta"

Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -ieq "Konica Minolta" }

(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -ieq "Konica Minolta" }).OriginalFileName



if ((Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -ieq "Konica Minolta" }).OriginalFileName -contains $DriverInfName) {
    Write-Host gibbet
}

#>