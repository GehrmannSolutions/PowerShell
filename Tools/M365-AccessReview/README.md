# M365 Groups Access Review Tool

PowerShell-Skript zur umfassenden Prüfung aller Berechtigungen und Einstellungen rund um Microsoft 365 Gruppen, Teams und SharePoint.

## Voraussetzungen

- **PowerShell 5.1+** (als Administrator)
- **Globale Administrator-Rechte** im M365-Tenant
- Internetverbindung (Module werden bei Bedarf automatisch installiert)

### Module (werden automatisch installiert)

| Modul | Zweck |
|---|---|
| Microsoft.Graph.Authentication | Graph API Authentifizierung |
| Microsoft.Graph.Groups | M365-Gruppen auslesen |
| Microsoft.Graph.Identity.DirectoryManagement | Admin-Rollen, Directory Settings |
| Microsoft.Graph.Users | Benutzer-Informationen |
| Microsoft.Graph.Identity.SignIns | Authorization Policies |
| MicrosoftTeams | Teams-Richtlinien (Guest, Messaging, Meeting, Channel) |

> **Hinweis:** SharePoint Online wird **nicht** über das SPO-Modul abgefragt, sondern über die Graph SharePoint Admin API. Grund: Das SPO-Modul (`Microsoft.Online.SharePoint.PowerShell`) liefert eine inkompatible Version von `Microsoft.Identity.Client.dll` mit, die zu DLL-Versionskonflikten mit dem Graph-Modul führt.

### Graph API Scopes

Das Skript fordert folgende delegated Permissions an:

- `Directory.Read.All`
- `Group.Read.All`
- `GroupMember.Read.All`
- `Policy.Read.All`
- `Organization.Read.All`
- `User.Read.All`
- `SharePointTenantSettings.Read.All`
- `Sites.Read.All`

Beim ersten Start wird ein Admin-Consent im Browser abgefragt.

## Verwendung

```powershell
# Standard (Report wird im Skript-Verzeichnis gespeichert)
.\M365-Groups-AccessReview.ps1

# Eigenen Export-Pfad angeben
.\M365-Groups-AccessReview.ps1 -ExportPath "C:\Reports\AccessReview.html"
```

Der Report wird als HTML-Datei erstellt und kann direkt im Browser geöffnet werden:

```powershell
Invoke-Item '.\M365-AccessReview-20260223-130947.html'
```

## Was wird geprüft?

### 1. Microsoft 365 Gruppen-Erstellungsrichtlinien
- Wer darf M365-Gruppen erstellen? (Alle / eingeschränkt auf Sicherheitsgruppe)
- Naming-Policy (Prefix/Suffix)
- Blockierte Wörter
- Gäste als Gruppen-Owner erlaubt?
- Gast-Zugriff auf Gruppen
- Sensitivity Labels (MIP)
- Usage Guidelines URL

### 2. Gruppen-Ablaufrichtlinien
- Gültigkeitsdauer (Tage)
- Angewendet auf welche Gruppen
- Benachrichtigungs-E-Mails

### 3. SharePoint Online Tenant-Einstellungen (via Graph API)
- **Sharing Capability** (Deaktiviert / Nur Externe / Neue und existierende Gäste)
- Domain-Einschränkungen für Freigaben (Allow-/Block-Liste)
- Resharing durch Externe erlaubt?
- Einladungs-Matching (Account-Verifizierung)
- Site-Erstellung erlaubt?
- Idle Session Sign Out
- Legacy Auth Protocols
- Loop, Newsfeed, Mobile Notifications

### 4. SharePoint Sites der M365-Gruppen
- Alle M365-Gruppen mit zugehöriger SharePoint-Site
- URL-Übersicht

### 5. Microsoft Teams Richtlinien
- **Gast-Einstellungen:** Anrufe, Chat (bearbeiten/löschen/erstellen), GIFs, Memes, Sticker, Bildschirm teilen
- **Client-Konfiguration:** Externe User, Gast-Zugriff, Cloud-Storage (DropBox/GoogleDrive/Box/ShareFile), E-Mail in Channel
- **Meeting-Richtlinien:** Alle Policies mit Anonymous Join, External Chat, Recording
- **Channel-Richtlinien:** Private/Shared Channel Erstellung

### 6. Externe Freigabe (Entra ID)
- Gast-Benutzer-Zugriffsrechte (Vollzugriff / Eingeschränkt / Stark eingeschränkt)
- Wer darf Gäste einladen? (Niemand / Admins / Alle Mitglieder / Jeder inkl. Gäste)
- Selbstregistrierung per E-Mail

### 7. M365-Gruppen mit externen Mitgliedern
- Scan aller M365-Gruppen auf Gast-Mitglieder
- Auflistung der Gäste pro Gruppe (Name, E-Mail)

### 8. Administrative Rollen
- Global Administrator
- Groups Administrator
- SharePoint Administrator
- Teams Administrator
- User Administrator
- Guest Inviter
- Exchange Administrator
- Compliance Administrator
- Security Administrator

Jeweils mit Mitglieder-Auflistung.

## Report

Der HTML-Report enthält:
- Farbcodierte Bewertungen (Grün = OK, Gelb = Warnung, Rot = Kritisch)
- Aufklappbare Detail-Sektionen
- Tabellen mit allen Einstellungen und Werten
- Timestamp und Tenant-Information

## Bekannte Einschränkungen

- **MSAL DLL-Konflikt:** Das Skript lädt die MSAL-Assemblies aus dem Graph-Modul manuell vor, um Konflikte mit MicrosoftTeams (MSAL v4.81) zu vermeiden. In einer neuen PowerShell-Session sollte das problemlos funktionieren.
- **SharePoint Sites:** Die Auflistung zeigt nur Sites die einer M365-Gruppe zugeordnet sind, keine standalone Kommunikationsseiten. Der Graph-Endpoint `/sites/getAllSites` erfordert Application Permissions und ist mit delegated Auth nicht verfügbar.
- **Laufzeit:** Bei vielen Gruppen (256+) kann der Scan auf externe Mitglieder einige Minuten dauern.

## Troubleshooting

### "Method not found: WithLogging" Fehler
In einer frischen PowerShell-Session starten. Das Problem entsteht durch verschiedene MSAL-Versionen die von Graph, SPO und Teams mitgeliefert werden.

### Teams-Verbindung schlägt fehl
Sicherstellen dass das `MicrosoftTeams`-Modul aktuell ist:
```powershell
Update-Module MicrosoftTeams -Force
```

### Admin Consent
Beim ersten Start mit neuen Scopes muss ein Global Admin den Consent im Browser bestätigen. Bei Problemen den bestehenden Consent entfernen:
```
https://entra.microsoft.com > Enterprise Applications > Microsoft Graph Command Line Tools > Permissions > Review permissions
```

## Autor

Marius Gehrmann - Business IT Solutions
