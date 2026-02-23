<#
.SYNOPSIS
    Gibt einem Manager Site-Collection-Admin-Zugriff auf die OneDrive-Site eines Benutzers.

.DESCRIPTION
    Setzt einen Manager als Site Collection Administrator auf der persoenlichen
    OneDrive-for-Business-Site eines Benutzers. Typischer Anwendungsfall: Vorgesetzter
    muss nach Austritt eines Mitarbeiters auf dessen OneDrive-Daten zugreifen.

.PARAMETER AdminUrl
    SharePoint Online Admin Center URL.
    Beispiel: https://contoso-admin.sharepoint.com

.PARAMETER UserUPN
    UPN des Benutzers, auf dessen OneDrive zugegriffen werden soll.

.PARAMETER ManagerUPN
    UPN des Managers, der Zugriff erhalten soll.

.PARAMETER Remove
    Entfernt den Manager-Zugriff anstatt ihn zu setzen.

.EXAMPLE
    .\Set-OneDriveManagerAccess.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "max.mustermann@contoso.com" -ManagerUPN "chef@contoso.com"

.EXAMPLE
    .\Set-OneDriveManagerAccess.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "max.mustermann@contoso.com" -ManagerUPN "chef@contoso.com" -Remove

.NOTES
    Erfordert:
    - Windows PowerShell 5.1 (NICHT PowerShell 7 - SPO-Modul liefert dort 400 Bad Request)
    - Microsoft.Online.SharePoint.PowerShell Modul (wird bei Bedarf automatisch installiert)
    - SharePoint Administrator oder Global Administrator Rechte

.AUTHOR
    Marius Gehrmann - marius@gehrmann.io

#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, HelpMessage = "SharePoint Admin URL (https://TENANT-admin.sharepoint.com)")]
    [ValidatePattern('^https://.+-admin\.sharepoint\.com/?$')]
    [string]$AdminUrl,

    [Parameter(Mandatory, HelpMessage = "UPN des Benutzers (OneDrive-Besitzer)")]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string]$UserUPN,

    [Parameter(Mandatory, HelpMessage = "UPN des Managers (erhaelt Zugriff)")]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string]$ManagerUPN,

    [Parameter(HelpMessage = "Entfernt den Zugriff statt ihn zu setzen")]
    [switch]$Remove
)

# ============================================================================
# PowerShell-Version pruefen
# ============================================================================

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Error "Dieses Skript muss in Windows PowerShell 5.1 ausgefuehrt werden (powershell.exe / ISE). Das SPO-Modul ist nicht mit PowerShell 7+ kompatibel."
    exit 1
}

# ============================================================================
# Microsoft.Online.SharePoint.PowerShell laden
# ============================================================================

if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
    Write-Host "Modul 'Microsoft.Online.SharePoint.PowerShell' wird installiert..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Force -AllowClobber -Scope CurrentUser
}
Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop

# ============================================================================
# Verbindung zu SharePoint Online
# ============================================================================

Write-Host "Verbinde zu SharePoint Online: $AdminUrl" -ForegroundColor Cyan

try {
    Connect-SPOService -Url $AdminUrl -ErrorAction Stop
} catch {
    Write-Error "Verbindung zu SharePoint Online fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# OneDrive-Site des Benutzers suchen
# ============================================================================

Write-Host "Suche OneDrive-Site von '$UserUPN'..." -ForegroundColor Cyan

try {
    $userSiteUrl = (Get-SPOSite -IncludePersonalSite $true -Limit All -ErrorAction Stop |
        Where-Object { $_.Owner -like "*$UserUPN*" } |
        Select-Object -ExpandProperty Url)
} catch {
    Write-Error "Fehler beim Abrufen der Sites: $($_.Exception.Message)"
    Disconnect-SPOService
    exit 1
}

if (-not $userSiteUrl) {
    Write-Error "Keine OneDrive-Site fuer '$UserUPN' gefunden. Moeglicherweise hat der Benutzer kein OneDrive oder die Site wurde bereits geloescht."
    Disconnect-SPOService
    exit 1
}

Write-Host "  Gefunden: $userSiteUrl" -ForegroundColor Green

# ============================================================================
# Manager-Zugriff setzen oder entfernen
# ============================================================================

$isAdmin = -not $Remove

if ($PSCmdlet.ShouldProcess($userSiteUrl, "Site-Collection-Admin '$ManagerUPN' $(if ($isAdmin) { 'setzen' } else { 'entfernen' })")) {
    try {
        Set-SPOUser -Site $userSiteUrl -LoginName $ManagerUPN -IsSiteCollectionAdmin $isAdmin -ErrorAction Stop
        if ($isAdmin) {
            Write-Host "  '$ManagerUPN' wurde als Site-Collection-Admin auf dem OneDrive von '$UserUPN' gesetzt." -ForegroundColor Green
        } else {
            Write-Host "  Site-Collection-Admin-Zugriff von '$ManagerUPN' auf dem OneDrive von '$UserUPN' wurde entfernt." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Fehler beim Aendern der Berechtigung: $($_.Exception.Message)"
    }
}

# ============================================================================
# Verbindung trennen
# ============================================================================

Disconnect-SPOService
Write-Host "Verbindung getrennt." -ForegroundColor Cyan
