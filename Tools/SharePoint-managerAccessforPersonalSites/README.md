# Set-ManagerAccessforPersonalSites

Gibt einem Manager Site-Collection-Admin-Zugriff auf die OneDrive-for-Business-Site eines Benutzers.

## Anwendungsfall

Ein Mitarbeiter verlaesst das Unternehmen oder ist laengerfristig abwesend. Der Vorgesetzte muss auf die OneDrive-Daten zugreifen, um Dateien zu sichern oder weiterzubearbeiten.

## Voraussetzungen

- **Windows PowerShell 5.1** (ISE oder `powershell.exe` - **nicht** PowerShell 7/pwsh!)
- **SharePoint Administrator** oder **Global Administrator** Rechte
- Modul `Microsoft.Online.SharePoint.PowerShell` (wird bei Bedarf automatisch installiert)

## Verwendung

### Zugriff gewaehren

```powershell
.\Set-ManagerAccessforPersonalSites.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "max.mustermann@contoso.com" -ManagerUPN "chef@contoso.com"
```

### Zugriff wieder entziehen

```powershell
.\Set-ManagerAccessforPersonalSites.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "max.mustermann@contoso.com" -ManagerUPN "chef@contoso.com" -Remove
```

### Dry-Run (WhatIf)

```powershell
.\Set-ManagerAccessforPersonalSites.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -UserUPN "max.mustermann@contoso.com" -ManagerUPN "chef@contoso.com" -WhatIf
```

## Parameter

| Parameter | Pflicht | Beschreibung |
|---|---|---|
| `-AdminUrl` | Ja | SharePoint Admin URL (`https://TENANT-admin.sharepoint.com`) |
| `-UserUPN` | Ja | UPN des Benutzers, auf dessen OneDrive zugegriffen werden soll |
| `-ManagerUPN` | Ja | UPN des Managers, der Zugriff erhalten soll |
| `-Remove` | Nein | Entfernt den Zugriff anstatt ihn zu setzen |
| `-WhatIf` | Nein | Zeigt an was passieren wuerde, ohne Aenderungen vorzunehmen |

## AdminUrl finden

Die SharePoint Admin URL basiert auf der **initialen Tenant-Domain** (nicht der Vanity-Domain aus dem UPN!):

1. **Entra Admin Center** > Tenant-Eigenschaften > initiale Domain (`xxx.onmicrosoft.com`)
2. Der Teil vor `.onmicrosoft.com` ist der Tenant-Name
3. Die URL ist: `https://TENANTNAME-admin.sharepoint.com`

Alternativ: Direkt im **SharePoint Admin Center** in der Adressleiste nachschauen.

## Was passiert technisch?

1. `Connect-SPOService` verbindet zum SharePoint Admin Center (Browser-Auth)
2. `Get-SPOSite -IncludePersonalSite` listet alle OneDrive-Sites auf
3. Site des angegebenen Benutzers finden (Owner-Match)
4. `Set-SPOUser -IsSiteCollectionAdmin` setzt/entfernt den Manager als Site-Collection-Admin
5. Verbindung trennen

> **Hinweis:** Site-Collection-Admin hat Vollzugriff auf alle Inhalte der Site. Nach Abschluss der Datensicherung sollte der Zugriff mit `-Remove` wieder entzogen werden.

## Warum PowerShell 5.1?

Das SPO-Modul (`Microsoft.Online.SharePoint.PowerShell`) funktioniert **nur in Windows PowerShell 5.1**. In PowerShell 7 liefert `Connect-SPOService` konstant `400 Bad Request` - unabhaengig von URL oder Authentifizierung.

## Verworfene Ansaetze

### PnP.PowerShell als Alternative zum SPO-Modul

PnP.PowerShell wurde als moderner Ersatz evaluiert, scheiterte aber an mehreren Punkten:

| Problem | Details |
|---|---|
| ClientId erforderlich | PnP.PowerShell 3.x erfordert seit Sept 2024 eine eigene Entra ID App-Registrierung |
| Multi-Tenant-App deprecated | Die alte PnP Management Shell App (`31359c7f-...`) wurde Sept 2024 abgeschaltet |
| Graph PS App unzureichend | Die Microsoft Graph PowerShell App (`14d82eec-...`) hat nur `Sites.Read.All` - keine SharePoint-Admin-Schreibrechte |
| Assembly-Konflikte | PnP.PowerShell und SPO-Modul koennen nicht in der gleichen Session geladen werden (`Microsoft.Online.SharePoint.Client.Tenant` DLL-Konflikt) |

### Auto-Erkennung der Admin URL

Die SharePoint Admin URL laesst sich nicht zuverlaessig automatisch aus dem UPN ableiten (Vanity-Domain ≠ Tenant-Domain). Folgende Ansaetze wurden evaluiert:

| Ansatz | Ergebnis |
|---|---|
| Admin URL aus UPN-Domain ableiten | Vanity-Domain aus UPN ≠ Tenant-Name (initiale `.onmicrosoft.com`-Domain) - nicht ableitbar |
| Device Code Flow + Graph API | `AADSTS70003` - Grant Type vom Tenant per Conditional Access blockiert |
| Device Code Flow mit Azure CLI App | `AADSTS700016` - App nicht im Tenant registriert |
| Auth Code Flow (PKCE) + Graph `/sites/root` | **Funktioniert** - liefert korrekte SharePoint Root URL. Aber `Connect-SPOService` scheiterte danach trotzdem mit 400 (PS7-Problem) |
| PKCE + SPO-Modul im Kindprozess (PS 5.1) | SPO-Modul im Subprocess ebenfalls 400 |

Die PKCE-Erkennung ueber Graph API hat technisch funktioniert. Das Problem lag immer beim SPO-Modul in PS7, nicht bei der URL-Erkennung. Da das SPO-Modul nur in PS 5.1 funktioniert und dort die manuelle URL-Eingabe zumutbar ist, wurde auf Auto-Erkennung verzichtet.
