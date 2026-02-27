# PowerShell Admin Toolbox

Zentrale Sammlung von PowerShell-Skripten und Tools fuer die Administration von Microsoft-Infrastrukturen (Intune, M365, Entra ID).

## Uebersicht

```
PowerShell/
├── Intune-DriverInjection/                       Druckertreiber-Deployment via Intune
├── Remediations/
│   ├── BitLocker-Decrypt/                        BitLocker-Entschluesselung per Intune Remediation
│   └── ESU-Activation/                           Windows 10 ESU-Aktivierung per Intune Remediation
├── Tools/
│   ├── Intune-PolicyAssignment/                  Massenneuzuweisung von Intune-Policies (All Users / All Devices)
│   ├── M365-AccessReview/                        M365 Gruppen & Berechtigungs-Audit
│   └── SharePoint-OneDriveManagerAccess/         OneDrive-Zugriff fuer Vorgesetzte
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

### [BitLocker-Decrypt](Remediations/BitLocker-Decrypt/)

Intune Proactive Remediation zum Aufheben der BitLocker-Verschluesselung auf allen Laufwerken.

| Skript | Funktion |
|---|---|
| `Detect-BitlockerEncryption.ps1` | Prueft ob BitLocker auf einem Laufwerk aktiv ist |
| `Remediate-BitlockerEncryption.ps1` | Deaktiviert BitLocker und startet die Entschluesselung |

**Einsatz:** Intune > Endpunktanalyse > Proaktive Wartung > SYSTEM-Kontext, stundlich oder taeglich

---

### [ESU-Activation](Remediations/ESU-Activation/)

Intune Proactive Remediation zur automatischen Aktivierung von **Windows 10 Extended Security Updates (ESU)** ueber MAK-Key.

| Skript | Funktion |
|---|---|
| `Detect-ESUActivation.ps1` | Prueft ob ESU aktiviert werden muss |
| `Remediate-ESUActivation.ps1` | Installiert Voraussetzungs-KBs und aktiviert ESU per `slmgr.vbs` |

Mehrphasiger Ablauf: KB-Check → Neustart-Koordination (BurntToast-Notification) → MAK-Aktivierung (alle drei ESU-Jahre).

**Einsatz:** Intune > Endpunktanalyse > Proaktive Wartung > SYSTEM-Kontext, taeglich

---

### [Intune-PolicyAssignment](Tools/Intune-PolicyAssignment/)

Interaktives Tool zur Massenneuzuweisung von Intune-Policies auf **All Users** oder **All Devices** – mit optionalen Assignment Filtern und integrierter Empfehlungslogik.

**Hintergrund:** Bestimmte MDM-Policies setzen den OMADM-Registry-Schluessel `RebootRequired`, was waehrend des Autopilot-Deployments (ESP Device Phase) zu unerwarteten Neustarts fuehrt und den WHfB-Passwordless-Onboarding-Prozess mit TAP unterbricht.

Unterstuetzt drei Bearbeitungsmodi:

| Modus | Verhalten |
|---|---|
| `[1] Manuell` | Zuweisungsart und Filter pro Policy selbst waehlen |
| `[2] Auto` | Empfehlung automatisch anwenden, Filter noch abfragen |
| `[3] Auto+` | Empfehlung automatisch anwenden, ohne Filter-Abfrage |

Filtert automatisch auf **Windows-Policies** (configurationPolicies, deviceConfigurations, intents).
Exportiert ein CSV-Protokoll aller vorgenommenen Aenderungen.

**Einsatz:** Einmalig/selten – bei Neueinrichtung oder Umstrukturierung von Policy-Zuweisungen

---

### [M365-AccessReview](Tools/M365-AccessReview/)

Umfassendes Access Review Tool fuer Microsoft 365 Gruppen, Teams und SharePoint.

Prueft in einem Durchlauf:

- **Gruppen-Erstellung:** Wer darf M365-Gruppen/Teams/SharePoint-Sites erstellen?
- **Gruppen-Ablaufrichtlinien:** Werden ungenutzte Gruppen automatisch bereinigt?
- **SharePoint Tenant-Settings:** Sharing, Site-Creation, Domain-Restrictions, Resharing
- **Teams-Richtlinien:** Gast-Einstellungen, Meeting-Policies, Channel-Policies, Cloud-Storage
- **Externe Freigabe (Entra ID):** Wer darf Gaeste einladen? Gast-Zugriffsrechte?
- **Externe Mitglieder:** Scan aller M365-Gruppen auf Gast-User
- **Admin-Rollen:** Global Admin, Teams Admin, SharePoint Admin etc. mit allen Mitgliedern

**Output:** Farbcodierter HTML-Report mit Bewertungen (OK / Warnung / Kritisch)

---

### [SharePoint-OneDriveManagerAccess](Tools/SharePoint-OneDriveManagerAccess/)

Gibt einem Manager Site-Collection-Admin-Zugriff auf die OneDrive-Site eines Benutzers (z.B. nach Austritt eines Mitarbeiters).

```powershell
# Zugriff gewaehren
.\Set-OneDriveManagerAccess.ps1 -AdminUrl "https://TENANT-admin.sharepoint.com" -UserUPN "user@domain.com" -ManagerUPN "manager@domain.com"

# Zugriff entziehen
.\Set-OneDriveManagerAccess.ps1 -AdminUrl "https://TENANT-admin.sharepoint.com" -UserUPN "user@domain.com" -ManagerUPN "manager@domain.com" -Remove
```

**Features:** WhatIf-Support, UPN-Validierung, automatische Modul-Installation

---

## Voraussetzungen

| Tool | PowerShell | Rechte | Module |
|---|---|---|---|
| Intune-DriverInjection | 5.1+ | SYSTEM (via Intune) | Keine |
| BitLocker-Decrypt | 5.1+ | SYSTEM (via Intune) | Keine |
| ESU-Activation | 5.1+ | SYSTEM (via Intune) | BurntToast (auto-installiert), slmgr.vbs |
| Intune-PolicyAssignment | 7+ | Intune Admin | Microsoft.Graph.Authentication |
| M365-AccessReview | 5.1+ (Admin) | Global Admin | Microsoft.Graph, MicrosoftTeams |
| SharePoint-OneDriveManagerAccess | **5.1 (ISE)** | SharePoint Admin | Microsoft.Online.SharePoint.PowerShell |

## Konventionen

- **Sprache:** Skript-Ausgaben und Dokumentation auf Deutsch
- **Logging:** Strukturierte Logs mit Timestamps und Farbcodierung
- **Error Handling:** Try-Catch mit graceful Degradation (z.B. Teams-Check wird uebersprungen wenn Verbindung fehlschlaegt)
- **Module:** Werden bei Bedarf automatisch installiert
- **Reports:** HTML mit CSS-Styling, direkt im Browser oeffenbar

## Autor

Marius Gehrmann - Business IT Solutions
