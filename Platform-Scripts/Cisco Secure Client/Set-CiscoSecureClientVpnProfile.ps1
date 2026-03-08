<#
.SYNOPSIS
    Setzt das VPN-Verbindungsprofil fuer Cisco Secure Client nach der Installation.

.DESCRIPTION
    Erstellt die VPN-Profil-XML fuer Cisco Secure Client und startet den VPN-Agentendienst
    neu, damit das Profil sofort in der Oberflaeche erscheint.

    Vorgesehen als Post-Installations-Script in Patch My PC (laeuft als SYSTEM).

.NOTES
    Author:  Marius Gehrmann - Business IT Solutions
    Datum:   2026-03-08
    Getestet: Cisco Secure Client 5.x (csc_vpnagent), AnyConnect 4.x (vpnagent)

.LOG
    C:\ProgramData\CiscoVPN_PostInstall.log
#>

# ==============================================================================
# KONFIGURATION
# ==============================================================================

$VpnName = "Kunden-VPN"          # Anzeigename in Cisco Secure Client
$VpnHost = "vpn.kundenname.de"   # Hostname des VPN-Gateways

# ==============================================================================
# LOGGING
# Direkt in C:\ProgramData\ ohne Unterverzeichnis – SYSTEM hat immer Schreibrecht.
# ==============================================================================

$LogFile = "C:\ProgramData\CiscoVPN_PostInstall.log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string] $Level = "INFO"
    )
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" |
        Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-Log "================================================================"
Write-Log "Cisco Secure Client - VPN Profil Post-Install gestartet"
Write-Log "PowerShell $($PSVersionTable.PSVersion) | 64-bit: $([Environment]::Is64BitProcess) | Benutzer: $env:USERNAME"

# ==============================================================================
# VPN-PROFIL XML
# ==============================================================================

$ProfileDir  = "C:\ProgramData\Cisco\Cisco Secure Client\VPN\Profile"
$ProfileFile = "$ProfileDir\VPN.xml"

$ProfileXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<AnyConnectProfile xmlns="http://schemas.xmlsoap.org/encoding/"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xsi:schemaLocation="http://schemas.xmlsoap.org/encoding/ AnyConnectProfile.xsd">
  <ServerList>
    <HostEntry>
      <HostName>$VpnName</HostName>
      <HostAddress>$VpnHost</HostAddress>
    </HostEntry>
  </ServerList>
</AnyConnectProfile>
"@

# ==============================================================================
# HAUPTLOGIK
# ==============================================================================

try {
    # --- Profilverzeichnis sicherstellen ---
    if (Test-Path $ProfileDir) {
        Write-Log "Profilverzeichnis vorhanden: $ProfileDir"
    } else {
        New-Item -ItemType Directory -Path $ProfileDir -Force -ErrorAction Stop | Out-Null
        Write-Log "Profilverzeichnis erstellt:  $ProfileDir"
    }

    # --- Profil schreiben (UTF-8 ohne BOM) ---
    [System.IO.File]::WriteAllText($ProfileFile, $ProfileXml, [System.Text.Encoding]::UTF8)
    Write-Log "Profil geschrieben: $ProfileFile ($((Get-Item $ProfileFile).Length) Bytes)"

    # --- VPN-Dienst neu starten (liest Profile nur beim Start) ---
    #     Cisco Secure Client 5.x : csc_vpnagent
    #     AnyConnect 4.x          : vpnagent
    $Service = $null
    foreach ($Name in "csc_vpnagent", "vpnagent") {
        $Svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($Svc) { $Service = $Svc; break }
    }

    if ($Service) {
        Write-Log "VPN-Dienst gefunden: $($Service.Name) (Status: $($Service.Status))"
        Restart-Service -Name $Service.Name -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Log "VPN-Dienst neu gestartet. Neuer Status: $((Get-Service $Service.Name).Status)"
    } else {
        Write-Log "Kein VPN-Dienst gefunden (csc_vpnagent / vpnagent)" "WARN"
    }

    Write-Log "Abgeschlossen."
    Write-Log "================================================================"
    exit 0

} catch {
    Write-Log "Unerwarteter Fehler: $($_.Exception.Message)" "ERROR"
    Write-Log "StackTrace: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "================================================================"
    exit 1
}
