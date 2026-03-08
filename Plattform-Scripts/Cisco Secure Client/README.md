# Cisco Secure Client – VPN Profil Post-Install

Patch My PC Post-Installations-Script, das nach der Installation von Cisco Secure Client
automatisch das VPN-Verbindungsprofil setzt und den VPN-Agentendienst neu startet.

## Hintergrund

Cisco Secure Client liest VPN-Profile aus einem festgelegten Verzeichnis, allerdings nur
beim Start des `csc_vpnagent`-Dienstes. Da Patch My PC das Post-Install-Script ausfuehrt
waehrend der Dienst bereits laeuft (und das zu diesem Zeitpunkt noch leere Profilverzeichnis
eingelesen hat), genuegt es nicht, die Datei lediglich zu kopieren – der Dienst muss
anschliessend neu gestartet werden, damit das Profil in der Oberflaeche erscheint.

## Dateien

| Datei | Funktion |
|---|---|
| `Set-CiscoSecureClientVpnProfile.ps1` | Erstellt die Profil-XML und startet den VPN-Dienst neu |

## Konfiguration

Vor dem Deployment die beiden Variablen am Anfang des Scripts anpassen:

```powershell
$VpnName = "Kunden-VPN"          # Anzeigename in der Dropdown-Liste
$VpnHost = "vpn.kundenname.de"   # Hostname des VPN-Gateways
```

## Profilpfad

Das Script schreibt die Profil-XML an den folgenden Ort:

```
C:\ProgramData\Cisco\Cisco Secure Client\VPN\Profile\VPN.xml
```

Kompatibel mit:
- **Cisco Secure Client 5.x** (Dienst: `csc_vpnagent`)
- **AnyConnect 4.x** (Dienst: `vpnagent`, automatischer Fallback)

## Logging

```
C:\ProgramData\CiscoVPN_PostInstall.log
```

## Einsatz in Patch My PC

Script als Post-Install-Command konfigurieren:

```
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "Set-CiscoSecureClientVpnProfile.ps1"
```

> **Hinweis:** Das Script muss zusammen mit dem konfigurierten Skriptpfad im selben
> Verzeichnis liegen, aus dem Patch My PC es aufruft. Alternativ absoluten Pfad angeben.
