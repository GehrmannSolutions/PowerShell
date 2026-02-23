# PowerShell Admin Toolbox

Zentrale Sammlung von PowerShell-Skripten und Tools fuer die Administration von Microsoft-Infrastrukturen (Intune, M365, Entra ID).

## Uebersicht

```
PowerShell/
├── Intune-DriverInjection/                       Druckertreiber-Deployment via Intune
├── Tools/
│   ├── M365-AccessReview/                        M365 Gruppen & Berechtigungs-Audit
│   └── SharePoint-managerAccessforPersonalSites/ OneDrive-Zugriff fuer Vorgesetzte
└── README.md
```

## Projekte

### [Intune-DriverInjection](Intune-DriverInjection/)

Automatisiertes Druckertreiber-Management ueber Microsoft Intune fuer Windows 10/11.

Stellt drei Skripte bereit, die als Win32-App in Intune paketiert werden:

| Skript | Funktion |
|---|---|
| `Install-DriverInjection.ps1` | Installiert Druckertreiber via `pnputil.exe` in den Windows Driver Store |
| `Uninstall-DriverInjection.ps1` | Entfernt den Treiber aus dem Driver Store |
| `Detect-DriverInjection.ps1` | Intune Detection Rule - prueft ob der Treiber vorhanden ist |

**Einsatz:** Win32 Content Prep Tool > `.intunewin` > Intune Deployment > SYSTEM-Kontext

---

### [M365-AccessReview](Tools/M365-AccessReview/)

Umfassendes Access Review Tool fuer Microsoft 365 Gruppen, Teams und SharePoint.

Prueft in einem Durchlauf:

- **Gruppen-Erstellung:** Wer darf M365-Gruppen/Teams/SharePoint-Sites erstellen?
- **Gruppen-Ablaufrichtlinien:** Werden ungenutzte Gruppen automatisch bereinigt?
- **SharePoint Tenant-Settings:** Sharing, Site-Creation, Domain-Restrictions, Resharing
- **Teams-Richtlinien:** Gast-Einstellungen, Meeting-Policies, Channel-Policies, Cloud-Storage
- **Externe Freigabe (Entra ID):** Wer darf Gaeste einladen? Gast-Zugriffsrechte?
- **Externe Mitglieder:** Scan aller 256 Gruppen auf Gast-User
- **Admin-Rollen:** Global Admin, Teams Admin, SharePoint Admin etc. mit allen Mitgliedern

**Output:** Farbcodierter HTML-Report mit Bewertungen (OK / Warnung / Kritisch)

---

### [SharePoint-managerAccessforPersonalSites](Tools/SharePoint-managerAccessforPersonalSites/)

Gibt einem Manager Site-Collection-Admin-Zugriff auf die OneDrive-Site eines Benutzers (z.B. nach Austritt eines Mitarbeiters).

```powershell
# Zugriff gewaehren
.\Set-ManagerAccessforPersonalSites.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "user@contoso.com" -ManagerUPN "chef@contoso.com"

# Zugriff entziehen
.\Set-ManagerAccessforPersonalSites.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "user@contoso.com" -ManagerUPN "chef@contoso.com" -Remove
```

**Features:** WhatIf-Support, UPN-Validierung, automatische Modul-Installation

---

## Voraussetzungen

| Tool | PowerShell | Rechte | Module |
|---|---|---|---|
| Intune-DriverInjection | 5.1+ | SYSTEM (via Intune) | Keine |
| M365-AccessReview | 5.1+ (Admin) | Global Admin | Microsoft.Graph, MicrosoftTeams |
| SharePoint-managerAccess | 5.1 (ISE) | SharePoint Admin | Microsoft.Online.SharePoint.PowerShell |

## Konventionen

- **Sprache:** Skript-Ausgaben und Dokumentation auf Deutsch
- **Logging:** Strukturierte Logs mit Timestamps und Farbcodierung
- **Error Handling:** Try-Catch mit graceful Degradation (z.B. Teams-Check wird uebersprungen wenn Verbindung fehlschlaegt)
- **Module:** Werden bei Bedarf automatisch installiert
- **Reports:** HTML mit CSS-Styling, direkt im Browser oeffenbar

## Autor

Marius Gehrmann - Business IT Solutions
