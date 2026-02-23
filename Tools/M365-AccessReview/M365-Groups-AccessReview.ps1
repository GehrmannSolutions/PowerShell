<#
.SYNOPSIS
    Microsoft 365 Gruppen Access Review Tool

.DESCRIPTION
    Prüft umfassend alle Berechtigungen und Einstellungen rund um Microsoft 365 Gruppen,
    Teams, SharePoint und externe Freigaben.

    Prüft:
    - M365 Gruppen-Erstellungsrichtlinien
    - SharePoint Online Tenant-Einstellungen (Sharing, Site-Creation)
    - Teams-Richtlinien (Guest, Messaging, Meeting, Channels)
    - Azure AD Gast-Einstellungen
    - M365-Gruppen mit externen Mitgliedern
    - Administrative Rollen

.NOTES
    Erfordert:
    - Globale Administrator-Rechte
    - Module: Microsoft.Graph, Microsoft.Online.SharePoint.PowerShell, MicrosoftTeams

.AUTHOR
    Erstellt für M365 Access Review
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "$PSScriptRoot\M365-AccessReview-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
)

# ============================================================================
# Hilfsfunktionen
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    switch ($Type) {
        "Success" { Write-Host $Message -ForegroundColor Green }
        "Warning" { Write-Host $Message -ForegroundColor Yellow }
        "Error"   { Write-Host $Message -ForegroundColor Red }
        "Info"    { Write-Host $Message -ForegroundColor Cyan }
        "Header"  { Write-Host $Message -ForegroundColor Magenta }
        default   { Write-Host $Message }
    }
}

$script:HtmlReport = @()
$script:TotalSteps = 11
$script:CurrentStep = 0

function Step {
    param([string]$Message)
    $script:CurrentStep++
    Write-ColorOutput "`n[$($script:CurrentStep)/$($script:TotalSteps)] $Message" -Type Info
}

function Add-ReportSection {
    param(
        [string]$Title,
        [string]$Content,
        [string]$Status = "Info"
    )
    $color = switch ($Status) {
        "Success"  { "#28a745" }
        "Warning"  { "#ffc107" }
        "Critical" { "#dc3545" }
        default    { "#17a2b8" }
    }
    $script:HtmlReport += @"
    <div class="section">
        <h2 style="color: $color;">$Title</h2>
        <div class="content">$Content</div>
    </div>
"@
}

function Export-HtmlReport {
    param([string]$Path)
    $tenantName = try { (Get-MgOrganization).DisplayName } catch { "Unbekannt" }
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Microsoft 365 Access Review - $(Get-Date -Format 'dd.MM.yyyy HH:mm')</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 20px; border-left: 4px solid; padding-left: 10px; }
        .section { background: white; padding: 20px; margin: 15px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .content { margin-top: 10px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-enabled { color: #28a745; font-weight: bold; }
        .status-disabled { color: #dc3545; font-weight: bold; }
        .status-restricted { color: #ffc107; font-weight: bold; }
        .info-box { background-color: #e7f3ff; border-left: 4px solid #0078d4; padding: 10px; margin: 10px 0; }
        .warning-box { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .critical-box { background-color: #f8d7da; border-left: 4px solid #dc3545; padding: 10px; margin: 10px 0; }
        .timestamp { color: #666; font-size: 0.9em; }
        code { background-color: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-family: 'Courier New', monospace; }
    </style>
</head>
<body>
    <h1>Microsoft 365 Access Review Report</h1>
    <p class="timestamp">Erstellt am: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')</p>
    <p class="timestamp">Tenant: $tenantName</p>

    $($script:HtmlReport -join "`n")

    <div class="section">
        <p class="timestamp">Report Ende - Erstellt mit M365-Groups-AccessReview.ps1</p>
    </div>
</body>
</html>
"@
    $html | Out-File -FilePath $Path -Encoding UTF8
    Write-ColorOutput "HTML-Report erstellt: $Path" -Type Success
}

# ============================================================================
# Hauptskript
# ============================================================================

Write-ColorOutput "================================================================" -Type Header
Write-ColorOutput "   Microsoft 365 Gruppen Access Review Tool" -Type Header
Write-ColorOutput "================================================================" -Type Header
Write-Host ""

# ============================================================================
# Hilfsfunktion: Modul prüfen, installieren und laden
# ============================================================================

function Install-RequiredModule {
    param([string[]]$Names)
    foreach ($moduleName in $Names) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            Write-ColorOutput "  Modul '$moduleName' wird installiert..." -Type Warning
            Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser
        }
        Import-Module $moduleName -ErrorAction Stop
        Write-ColorOutput "  + $moduleName" -Type Success
    }
}

# ============================================================================
# Schritt 1: Microsoft Graph - Module laden und verbinden
# ============================================================================
# WICHTIG: Microsoft.Graph, Microsoft.Online.SharePoint.PowerShell und
# MicrosoftTeams liefern unterschiedliche Versionen von
# Microsoft.Identity.Client.dll (MSAL). PowerShell's Assembly-Resolver
# kann die falsche Version laden, was zu "Method not found" Fehlern führt.
# Fix: MSAL-DLLs aus dem Graph-Modul manuell vorladen BEVOR Import-Module.
# ============================================================================

Step "Lade Microsoft Graph Module und verbinde..."

# MSAL-Assemblies aus dem Graph-Modul vorladen um DLL-Versionskonflikte zu vermeiden
$graphAuthModulePath = (Get-Module -ListAvailable Microsoft.Graph.Authentication |
    Sort-Object Version -Descending | Select-Object -First 1).ModuleBase

if ($graphAuthModulePath) {
    $depsPath = Join-Path $graphAuthModulePath "Dependencies"
    if (Test-Path $depsPath) {
        $msalDlls = @(
            "Microsoft.Identity.Client.dll",
            "Microsoft.IdentityModel.Abstractions.dll"
        )
        foreach ($dll in $msalDlls) {
            $dllPath = Join-Path $depsPath $dll
            if (Test-Path $dllPath) {
                try {
                    [System.Reflection.Assembly]::LoadFrom($dllPath) | Out-Null
                    Write-ColorOutput "  + Vorgeladen: $dll" -Type Success
                } catch {
                    Write-ColorOutput "  Warnung beim Vorladen von $dll : $($_.Exception.Message)" -Type Warning
                }
            }
        }
    }
}

$graphModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Groups",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users",
    "Microsoft.Graph.Identity.SignIns"
)
Install-RequiredModule -Names $graphModules

$scopes = @(
    "Directory.Read.All",
    "Group.Read.All",
    "GroupMember.Read.All",
    "Policy.Read.All",
    "Organization.Read.All",
    "User.Read.All",
    "SharePointTenantSettings.Read.All",
    "Sites.Read.All"
)

try {
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
} catch {
    Write-ColorOutput "  Fehler bei Graph-Verbindung: $($_.Exception.Message)" -Type Error
    exit 1
}

$context = Get-MgContext
Write-ColorOutput "  Verbunden als: $($context.Account)" -Type Success

$tenant = Get-MgOrganization
Write-ColorOutput "  Tenant: $($tenant.DisplayName)" -Type Success

# ============================================================================
# Schritt 2: Microsoft Teams - Modul laden und verbinden
# ============================================================================
# Hinweis: SharePoint Online wird NICHT mehr über das SPO-Modul abgefragt,
# sondern über die Graph SharePoint Admin API (SharePointTenantSettings.Read.All).
# Grund: Das SPO-Modul liefert MSAL v4.74 mit, was mit Graph's v4.78 kollidiert.
# ============================================================================

Step "Lade Microsoft Teams Modul und verbinde..."

try {
    Install-RequiredModule -Names @("MicrosoftTeams")
    Connect-MicrosoftTeams -ErrorAction Stop | Out-Null
    Write-ColorOutput "  Microsoft Teams verbunden" -Type Success
    $teamsConnected = $true
} catch {
    Write-ColorOutput "  Fehler bei Teams-Verbindung: $($_.Exception.Message)" -Type Error
    Write-ColorOutput "  Teams-Prüfungen werden übersprungen" -Type Warning
    $teamsConnected = $false
}

# ============================================================================
# Schritt 5: Microsoft 365 Gruppen-Erstellungsrichtlinien
# ============================================================================

Step "Prüfe Microsoft 365 Gruppen-Erstellungsrichtlinien..."

try {
    $groupSettingsResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groupSettings" -ErrorAction Stop
    $groupSetting = $groupSettingsResponse.value | Where-Object { $_.displayName -eq "Group.Unified" }

    if ($groupSetting) {
        $enableGroupCreation = ($groupSetting.values | Where-Object { $_.name -eq "EnableGroupCreation" }).value
        $groupCreationAllowedGroupId = ($groupSetting.values | Where-Object { $_.name -eq "GroupCreationAllowedGroupId" }).value
        $usageGuidelinesUrl = ($groupSetting.values | Where-Object { $_.name -eq "UsageGuidelinesUrl" }).value
        $classificationList = ($groupSetting.values | Where-Object { $_.name -eq "ClassificationList" }).value
        $enableMIPLabels = ($groupSetting.values | Where-Object { $_.name -eq "EnableMIPLabels" }).value
        $allowGuestsToBeGroupOwner = ($groupSetting.values | Where-Object { $_.name -eq "AllowGuestsToBeGroupOwner" }).value
        $allowGuestsToAccessGroups = ($groupSetting.values | Where-Object { $_.name -eq "AllowGuestsToAccessGroups" }).value
        $groupLifecyclePolicy = ($groupSetting.values | Where-Object { $_.name -eq "GroupLifecyclePolicy" }).value
        $prefixSuffixNaming = ($groupSetting.values | Where-Object { $_.name -eq "PrefixSuffixNamingRequirement" }).value
        $customBlockedWords = ($groupSetting.values | Where-Object { $_.name -eq "CustomBlockedWordsList" }).value

        $html = "<table><tr><th>Einstellung</th><th>Wert</th><th>Status</th></tr>"

        if ($enableGroupCreation -eq "false") {
            Write-ColorOutput "  Gruppen-Erstellung ist EINGESCHRÄNKT" -Type Warning

            if ($groupCreationAllowedGroupId) {
                $allowedGroup = Get-MgGroup -GroupId $groupCreationAllowedGroupId
                $members = Get-MgGroupMember -GroupId $groupCreationAllowedGroupId -All

                Write-ColorOutput "    Berechtigte Gruppe: $($allowedGroup.DisplayName) ($($members.Count) Mitglieder)" -Type Info

                $html += "<tr><td>Gruppen-Erstellung</td><td><span class='status-restricted'>EINGESCHRÄNKT</span></td><td>Nur für spezifische Gruppe</td></tr>"
                $html += "<tr><td>Berechtigte Gruppe</td><td><code>$($allowedGroup.DisplayName)</code></td><td>$($members.Count) Mitglieder</td></tr>"

                $membersList = ""
                foreach ($member in $members) {
                    $user = Get-MgUser -UserId $member.Id -ErrorAction SilentlyContinue
                    if ($user) {
                        $membersList += "$($user.DisplayName) ($($user.UserPrincipalName))<br>"
                    }
                }
                $html += "<tr><td colspan='3'><details><summary>Berechtigte Benutzer anzeigen ($($members.Count))</summary>$membersList</details></td></tr>"
            } else {
                $html += "<tr><td>Gruppen-Erstellung</td><td><span class='status-disabled'>DEAKTIVIERT</span></td><td>Niemand kann Gruppen erstellen</td></tr>"
            }
        } else {
            Write-ColorOutput "  Alle Benutzer dürfen M365-Gruppen erstellen" -Type Warning
            $html += "<tr><td>Gruppen-Erstellung</td><td><span class='status-enabled'>AKTIVIERT</span></td><td>Alle Benutzer</td></tr>"
        }

        # Gast-Einstellungen in Gruppen
        $html += "<tr><td>Gäste als Gruppen-Owner erlaubt</td><td><code>$allowGuestsToBeGroupOwner</code></td><td>"
        if ($allowGuestsToBeGroupOwner -eq "true") { $html += "<span class='status-disabled'>Risiko</span>" } else { $html += "<span class='status-enabled'>OK</span>" }
        $html += "</td></tr>"

        $html += "<tr><td>Gäste Zugriff auf Gruppen</td><td><code>$allowGuestsToAccessGroups</code></td><td>"
        if ($allowGuestsToAccessGroups -eq "true") { $html += "<span class='status-restricted'>Aktiviert</span>" } else { $html += "<span class='status-enabled'>Deaktiviert</span>" }
        $html += "</td></tr>"

        # Naming Policy
        $html += "<tr><td>Naming-Policy (Prefix/Suffix)</td><td><code>$(if($prefixSuffixNaming){"$prefixSuffixNaming"}else{"Nicht konfiguriert"})</code></td><td>"
        if (-not $prefixSuffixNaming) { $html += "<span class='status-restricted'>Empfohlen</span>" } else { $html += "<span class='status-enabled'>OK</span>" }
        $html += "</td></tr>"

        $html += "<tr><td>Blockierte Wörter</td><td><code>$(if($customBlockedWords){"$customBlockedWords"}else{"Nicht konfiguriert"})</code></td><td></td></tr>"
        $html += "<tr><td>Usage Guidelines URL</td><td><code>$(if($usageGuidelinesUrl){"$usageGuidelinesUrl"}else{"Nicht konfiguriert"})</code></td><td></td></tr>"
        $html += "<tr><td>Klassifizierungen</td><td><code>$(if($classificationList){"$classificationList"}else{"Nicht konfiguriert"})</code></td><td></td></tr>"
        $html += "<tr><td>Sensitivity Labels (MIP)</td><td><code>$enableMIPLabels</code></td><td></td></tr>"

        $html += "</table>"

        $status = if ($enableGroupCreation -ne "false") { "Warning" } else { "Success" }
        Add-ReportSection -Title "Microsoft 365 Gruppen-Erstellungsrichtlinien" -Content $html -Status $status
    } else {
        Write-ColorOutput "  Keine Group.Unified-Einstellungen konfiguriert - Standard gilt (alle dürfen erstellen)" -Type Warning
        $html = "<table><tr><th>Einstellung</th><th>Wert</th></tr>"
        $html += "<tr><td>Gruppen-Erstellung</td><td><span class='status-enabled'>STANDARD (Alle Benutzer)</span></td></tr>"
        $html += "</table><div class='warning-box'>Keine Einschränkungen konfiguriert. Alle Benutzer können M365-Gruppen erstellen.</div>"
        Add-ReportSection -Title "Microsoft 365 Gruppen-Erstellungsrichtlinien" -Content $html -Status "Warning"
    }
} catch {
    Write-ColorOutput "  Fehler: $($_.Exception.Message)" -Type Error
}

# ============================================================================
# Schritt 6: Gruppen-Ablaufrichtlinien
# ============================================================================

Step "Prüfe Gruppen-Ablaufrichtlinien..."

try {
    $lifecycleResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groupLifecyclePolicies" -ErrorAction Stop
    $lifecyclePolicies = $lifecycleResponse.value

    $html = ""

    if ($lifecyclePolicies -and $lifecyclePolicies.Count -gt 0) {
        $html += "<table><tr><th>Einstellung</th><th>Wert</th></tr>"
        foreach ($policy in $lifecyclePolicies) {
            $html += "<tr><td>Gültigkeitsdauer (Tage)</td><td><strong>$($policy.groupLifetimeInDays)</strong></td></tr>"

            $managedGroupTypes = switch ($policy.managedGroupTypes) {
                "All" { "Alle M365-Gruppen" }
                "Selected" { "Ausgewählte Gruppen" }
                "None" { "Keine" }
                default { $policy.managedGroupTypes }
            }
            $html += "<tr><td>Angewendet auf</td><td>$managedGroupTypes</td></tr>"

            $contacts = $policy.alternateNotificationEmails
            $html += "<tr><td>Benachrichtigungs-E-Mails</td><td><code>$(if($contacts){"$contacts"}else{"Keine konfiguriert"})</code></td></tr>"
        }
        $html += "</table>"
        Write-ColorOutput "  Ablaufrichtlinie konfiguriert" -Type Success
        Add-ReportSection -Title "Gruppen-Ablaufrichtlinien" -Content $html -Status "Success"
    } else {
        $html += "<div class='warning-box'>Keine Ablaufrichtlinie konfiguriert. Ungenutzte Gruppen werden nie automatisch bereinigt.</div>"
        Write-ColorOutput "  Keine Ablaufrichtlinie konfiguriert" -Type Warning
        Add-ReportSection -Title "Gruppen-Ablaufrichtlinien" -Content $html -Status "Warning"
    }
} catch {
    Write-ColorOutput "  Fehler: $($_.Exception.Message)" -Type Error
}

# ============================================================================
# Schritt 7: SharePoint Online Einstellungen (via Graph API)
# ============================================================================

Step "Prüfe SharePoint Online Tenant-Einstellungen (via Graph API)..."

try {
    $spoSettings = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/admin/sharepoint/settings" -ErrorAction Stop

    $html = "<h3>Externe Freigabe</h3>"
    $html += "<table><tr><th>Einstellung</th><th>Wert</th><th>Bewertung</th></tr>"

    # Sharing Capability
    $sharingCapDesc = switch ($spoSettings.sharingCapability) {
        "disabled"                       { "Externe Freigabe deaktiviert" }
        "externalUserSharingOnly"        { "Nur existierende externe Benutzer" }
        "externalUserAndGuestSharing"    { "Neue und existierende Gäste" }
        "existingExternalUserSharingOnly" { "Nur bereits eingeladene Externe" }
        default { "$($spoSettings.sharingCapability)" }
    }
    $sharingStatus = if ($spoSettings.sharingCapability -eq "disabled") { "status-enabled" }
                     elseif ($spoSettings.sharingCapability -eq "externalUserAndGuestSharing") { "status-disabled" }
                     else { "status-restricted" }
    $html += "<tr><td>Sharing Capability (Tenant)</td><td><span class='$sharingStatus'>$sharingCapDesc</span></td><td><code>$($spoSettings.sharingCapability)</code></td></tr>"

    # Sharing Domain Restriction
    $domainMode = switch ($spoSettings.sharingDomainRestrictionMode) {
        "none"      { "Keine Einschränkung" }
        "allowList" { "Nur erlaubte Domains" }
        "blockList" { "Blockierte Domains" }
        default     { "$($spoSettings.sharingDomainRestrictionMode)" }
    }
    $html += "<tr><td>Domain-Einschränkung für Freigaben</td><td><code>$domainMode</code></td><td>"
    if ($spoSettings.sharingDomainRestrictionMode -eq "none") {
        $html += "<span class='status-restricted'>Keine Einschränkung</span>"
    } else {
        $html += "<span class='status-enabled'>Konfiguriert</span>"
    }
    $html += "</td></tr>"

    if ($spoSettings.sharingAllowedDomainList) {
        $html += "<tr><td>Erlaubte Domains</td><td colspan='2'><code>$($spoSettings.sharingAllowedDomainList)</code></td></tr>"
    }
    if ($spoSettings.sharingBlockedDomainList) {
        $html += "<tr><td>Blockierte Domains</td><td colspan='2'><code>$($spoSettings.sharingBlockedDomainList)</code></td></tr>"
    }

    # Resharing
    $html += "<tr><td>Externe können weiterteilen</td><td><code>$($spoSettings.isResharingByExternalUsersEnabled)</code></td><td>"
    if ($spoSettings.isResharingByExternalUsersEnabled) { $html += "<span class='status-disabled'>Erlaubt</span>" } else { $html += "<span class='status-enabled'>Blockiert</span>" }
    $html += "</td></tr>"

    # Require Accepting User Match
    $html += "<tr><td>Einladung muss vom eingeladenen Account akzeptiert werden</td><td><code>$($spoSettings.isRequireAcceptingUserToMatchInvitedUserEnabled)</code></td><td>"
    if ($spoSettings.isRequireAcceptingUserToMatchInvitedUserEnabled) { $html += "<span class='status-enabled'>OK</span>" } else { $html += "<span class='status-disabled'>Risiko</span>" }
    $html += "</td></tr>"

    $html += "</table>"

    # Site Creation
    $html += "<h3>Site-Erstellung</h3>"
    $html += "<table><tr><th>Einstellung</th><th>Wert</th><th>Bewertung</th></tr>"

    $html += "<tr><td>Site-Erstellung erlaubt</td><td><code>$($spoSettings.isSiteCreationEnabled)</code></td><td>"
    if ($spoSettings.isSiteCreationEnabled) {
        $html += "<span class='status-restricted'>Aktiviert (User können Sites erstellen)</span>"
    } else {
        $html += "<span class='status-enabled'>Deaktiviert (eingeschränkt)</span>"
    }
    $html += "</td></tr>"

    $html += "<tr><td>Site-Erstellungs-UI angezeigt</td><td><code>$($spoSettings.isSiteCreationUIEnabled)</code></td><td></td></tr>"
    $html += "<tr><td>Standard Managed Path</td><td><code>$($spoSettings.siteCreationDefaultManagedPath)</code></td><td></td></tr>"
    $html += "<tr><td>Standard Storage Limit (MB)</td><td><code>$($spoSettings.siteCreationDefaultStorageLimitInMB)</code></td><td></td></tr>"
    $html += "<tr><td>Automatische Speicherlimits</td><td><code>$($spoSettings.isSitesStorageLimitAutomatic)</code></td><td></td></tr>"

    $html += "</table>"

    # Weitere Einstellungen
    $html += "<h3>Weitere Einstellungen</h3>"
    $html += "<table><tr><th>Einstellung</th><th>Wert</th></tr>"
    $html += "<tr><td>Legacy Auth Protocols</td><td><code>$($spoSettings.isLegacyAuthProtocolsEnabled)</code></td></tr>"
    $html += "<tr><td>Kommentare auf Site Pages</td><td><code>$($spoSettings.isCommentingOnSitePagesEnabled)</code></td></tr>"
    $html += "<tr><td>Loop aktiviert</td><td><code>$($spoSettings.isLoopEnabled)</code></td></tr>"
    $html += "<tr><td>Mac Sync App</td><td><code>$($spoSettings.isMacSyncAppEnabled)</code></td></tr>"
    $html += "<tr><td>SharePoint Newsfeed</td><td><code>$($spoSettings.isSharePointNewsfeedEnabled)</code></td></tr>"
    $html += "<tr><td>SharePoint Mobile Notifications</td><td><code>$($spoSettings.isSharePointMobileNotificationEnabled)</code></td></tr>"

    # Idle Session Sign Out
    $idleSession = $spoSettings.idleSessionSignOut
    if ($idleSession) {
        $html += "<tr><td>Idle Session Sign Out</td><td><code>Aktiviert: $($idleSession.isEnabled), Warn nach: $($idleSession.warnAfterInSeconds)s, Sign-Out nach: $($idleSession.signOutAfterInSeconds)s</code></td></tr>"
    }

    $html += "</table>"

    $status = if ($spoSettings.sharingCapability -eq "externalUserAndGuestSharing") { "Warning" }
              elseif ($spoSettings.sharingCapability -eq "disabled") { "Success" }
              else { "Info" }

    Write-ColorOutput "  SharePoint Tenant-Einstellungen ausgelesen" -Type Success
    Add-ReportSection -Title "SharePoint Online - Tenant-Einstellungen (via Graph)" -Content $html -Status $status

} catch {
    Write-ColorOutput "  Fehler bei SharePoint-Einstellungen: $($_.Exception.Message)" -Type Error
    Add-ReportSection -Title "SharePoint Online" -Content "<div class='critical-box'>SharePoint-Einstellungen konnten nicht gelesen werden: $($_.Exception.Message)</div>" -Status "Critical"
}

# Alle SharePoint Sites auflisten
Step "Prüfe SharePoint Sites..."

try {
    # SharePoint-Sites der M365-Gruppen auflisten (über Gruppen-zu-Site Mapping)
    # Hinweis: /sites?search=* und /sites/getAllSites sind mit delegated Perms eingeschränkt,
    # daher nutzen wir die M365-Gruppen (bereits geladen ab Schritt 9) und holen deren Sites.
    Write-ColorOutput "  Lade Sites der M365-Gruppen..." -Type Info

    $groupSites = @()
    $m365GroupsForSites = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All -Property Id,DisplayName

    $counter = 0
    foreach ($grp in $m365GroupsForSites) {
        $counter++
        if ($counter % 50 -eq 0) {
            Write-Progress -Activity "Lade Gruppen-Sites" -Status "$counter von $($m365GroupsForSites.Count)" -PercentComplete (($counter / $m365GroupsForSites.Count) * 100)
        }
        try {
            $site = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($grp.Id)/sites/root?`$select=id,displayName,webUrl" -ErrorAction Stop
            $groupSites += [PSCustomObject]@{
                GroupName   = $grp.DisplayName
                SiteName    = $site.displayName
                WebUrl      = $site.webUrl
            }
        } catch {
            # Manche Gruppen haben keine Site (z.B. nur Mail-Gruppen)
        }
    }
    Write-Progress -Activity "Lade Gruppen-Sites" -Completed

    $html = "<p><strong>Zusammenfassung:</strong></p>"
    $html += "<ul>"
    $html += "<li>M365-Gruppen gesamt: <strong>$($m365GroupsForSites.Count)</strong></li>"
    $html += "<li>Davon mit SharePoint-Site: <strong>$($groupSites.Count)</strong></li>"
    $html += "</ul>"

    if ($groupSites.Count -gt 0) {
        $html += "<table><tr><th>Gruppenname</th><th>Site-URL</th></tr>"
        foreach ($gs in $groupSites | Sort-Object GroupName) {
            $html += "<tr><td>$($gs.GroupName)</td><td><code>$($gs.WebUrl)</code></td></tr>"
        }
        $html += "</table>"
    }

    Write-ColorOutput "  $($groupSites.Count) Gruppen-Sites gefunden" -Type Success
    Add-ReportSection -Title "SharePoint Sites - M365-Gruppen" -Content $html -Status "Info"

} catch {
    Write-ColorOutput "  Fehler beim Laden der Sites: $($_.Exception.Message)" -Type Error
}

# ============================================================================
# Schritt 9: Teams-Richtlinien
# ============================================================================

Step "Prüfe Microsoft Teams Richtlinien..."

if ($teamsConnected) {
    try {
        $html = ""

        # Teams Guest Configuration
        $guestConfig = Get-CsTeamsGuestCallingConfiguration -ErrorAction SilentlyContinue
        $guestMsgConfig = Get-CsTeamsGuestMessagingConfiguration -ErrorAction SilentlyContinue
        $guestMeetingConfig = Get-CsTeamsGuestMeetingConfiguration -ErrorAction SilentlyContinue

        $html += "<h3>Gast-Einstellungen in Teams</h3>"
        $html += "<table><tr><th>Einstellung</th><th>Wert</th><th>Bewertung</th></tr>"

        if ($guestConfig) {
            $html += "<tr><td>Gäste dürfen Anrufe tätigen</td><td><code>$($guestConfig.AllowPrivateCalling)</code></td><td>"
            if ($guestConfig.AllowPrivateCalling) { $html += "<span class='status-restricted'>Aktiviert</span>" } else { $html += "<span class='status-enabled'>Deaktiviert</span>" }
            $html += "</td></tr>"
        }

        if ($guestMsgConfig) {
            $html += "<tr><td>Gäste: Chat bearbeiten</td><td><code>$($guestMsgConfig.AllowUserEditMessage)</code></td><td></td></tr>"
            $html += "<tr><td>Gäste: Chat löschen</td><td><code>$($guestMsgConfig.AllowUserDeleteMessage)</code></td><td></td></tr>"
            $html += "<tr><td>Gäste: Chat erstellen</td><td><code>$($guestMsgConfig.AllowUserChat)</code></td><td></td></tr>"
            $html += "<tr><td>Gäste: GIFs senden</td><td><code>$($guestMsgConfig.AllowGiphy)</code></td><td></td></tr>"
            $html += "<tr><td>Gäste: Memes senden</td><td><code>$($guestMsgConfig.AllowMemes)</code></td><td></td></tr>"
            $html += "<tr><td>Gäste: Sticker senden</td><td><code>$($guestMsgConfig.AllowStickers)</code></td><td></td></tr>"
            $html += "<tr><td>Gäste: Immersive Reader</td><td><code>$($guestMsgConfig.AllowImmersiveReader)</code></td><td></td></tr>"
        }

        if ($guestMeetingConfig) {
            $html += "<tr><td>Gäste: Bildschirm teilen</td><td><code>$($guestMeetingConfig.AllowIPVideo)</code></td><td></td></tr>"
            $screenShareMode = $guestMeetingConfig.ScreenSharingMode
            $html += "<tr><td>Gäste: Screen Sharing Modus</td><td><code>$screenShareMode</code></td><td></td></tr>"
        }

        $html += "</table>"

        # Teams Client Configuration
        $clientConfig = Get-CsTeamsClientConfiguration -ErrorAction SilentlyContinue
        if ($clientConfig) {
            $html += "<h3>Teams Client-Konfiguration</h3>"
            $html += "<table><tr><th>Einstellung</th><th>Wert</th><th>Bewertung</th></tr>"
            $html += "<tr><td>Externe Benutzer erlaubt</td><td><code>$($clientConfig.AllowExternalUsersToConnect)</code></td><td>"
            if ($clientConfig.AllowExternalUsersToConnect) { $html += "<span class='status-restricted'>Aktiviert</span>" } else { $html += "<span class='status-enabled'>Deaktiviert</span>" }
            $html += "</td></tr>"
            $html += "<tr><td>Gast-Zugriff erlaubt</td><td><code>$($clientConfig.AllowGuestUser)</code></td><td>"
            if ($clientConfig.AllowGuestUser) { $html += "<span class='status-restricted'>Aktiviert</span>" } else { $html += "<span class='status-enabled'>Deaktiviert</span>" }
            $html += "</td></tr>"
            $html += "<tr><td>DropBox erlaubt</td><td><code>$($clientConfig.AllowDropBox)</code></td><td></td></tr>"
            $html += "<tr><td>Google Drive erlaubt</td><td><code>$($clientConfig.AllowGoogleDrive)</code></td><td></td></tr>"
            $html += "<tr><td>ShareFile erlaubt</td><td><code>$($clientConfig.AllowShareFile)</code></td><td></td></tr>"
            $html += "<tr><td>Box erlaubt</td><td><code>$($clientConfig.AllowBox)</code></td><td></td></tr>"
            $html += "<tr><td>E-Mail in Channel erlaubt</td><td><code>$($clientConfig.AllowEmailIntoChannel)</code></td><td></td></tr>"
            $html += "</table>"
        }

        # Teams Meeting Policies
        $meetingPolicies = Get-CsTeamsMeetingPolicy -ErrorAction SilentlyContinue
        if ($meetingPolicies) {
            $html += "<h3>Meeting-Richtlinien</h3>"
            $html += "<table><tr><th>Policy-Name</th><th>Anonyme Join</th><th>Externer Zugriff</th><th>Chat</th><th>Aufnahme</th></tr>"
            foreach ($policy in $meetingPolicies) {
                $html += "<tr>"
                $html += "<td><strong>$($policy.Identity)</strong></td>"
                $html += "<td><code>$($policy.AllowAnonymousUsersToJoinMeeting)</code></td>"
                $html += "<td><code>$($policy.AllowExternalNonTrustedMeetingChat)</code></td>"
                $html += "<td><code>$($policy.AllowMeetingChat)</code></td>"
                $html += "<td><code>$($policy.AllowCloudRecording)</code></td>"
                $html += "</tr>"
            }
            $html += "</table>"
        }

        # Teams Channels Policy
        $channelPolicies = Get-CsTeamsChannelsPolicy -ErrorAction SilentlyContinue
        if ($channelPolicies) {
            $html += "<h3>Channel-Richtlinien</h3>"
            $html += "<table><tr><th>Policy</th><th>Private Channels erstellen</th><th>Shared Channels erstellen</th></tr>"
            foreach ($policy in $channelPolicies) {
                $html += "<tr>"
                $html += "<td><strong>$($policy.Identity)</strong></td>"
                $html += "<td><code>$($policy.AllowPrivateChannelCreation)</code></td>"
                $html += "<td><code>$($policy.AllowSharedChannelCreation)</code></td>"
                $html += "</tr>"
            }
            $html += "</table>"
        }

        Write-ColorOutput "  Teams-Richtlinien ausgelesen" -Type Success
        Add-ReportSection -Title "Microsoft Teams - Richtlinien" -Content $html -Status "Info"

    } catch {
        Write-ColorOutput "  Fehler: $($_.Exception.Message)" -Type Error
    }
} else {
    Add-ReportSection -Title "Microsoft Teams" -Content "<div class='critical-box'>Microsoft Teams Verbindung fehlgeschlagen. Teams-Prüfungen wurden übersprungen.</div>" -Status "Critical"
}

# ============================================================================
# Schritt 10: Externe Freigabe - Azure AD
# ============================================================================

Step "Prüfe externe Freigabe-Einstellungen (Entra ID)..."

try {
    $authPolicy = Get-MgPolicyAuthorizationPolicy

    $html = "<table><tr><th>Einstellung</th><th>Wert</th><th>Bedeutung</th></tr>"

    # Guest User Access
    $guestUserRoleId = $authPolicy.GuestUserRoleId
    $guestUserAccess = switch ($guestUserRoleId) {
        "10dae51f-b6af-4016-8d66-8c2a99b929b3" { "Gleiche Berechtigungen wie Mitglieder" }
        "a0b1b346-4d3e-4e8b-98f8-753987be4970" { "Eingeschränkter Zugriff (Standard)" }
        "2af84b1e-32c8-42b7-82bc-daa82404023b" { "Stark eingeschränkter Zugriff" }
        default { "Unbekannt: $guestUserRoleId" }
    }

    $html += "<tr><td>Gast-Benutzer-Zugriffsrechte</td><td><code>$guestUserAccess</code></td><td>"
    if ($guestUserRoleId -eq "10dae51f-b6af-4016-8d66-8c2a99b929b3") {
        $html += "<span class='status-disabled'>RISIKO: Gäste haben gleiche Rechte wie Mitglieder</span>"
    } else {
        $html += "<span class='status-enabled'>Eingeschränkt</span>"
    }
    $html += "</td></tr>"

    # Wer darf Gäste einladen?
    $allowInvites = $authPolicy.AllowInvitesFrom
    $html += "<tr><td>Wer darf Gäste einladen?</td><td><code>$allowInvites</code></td><td>"

    switch ($allowInvites) {
        "none" {
            $html += "<span class='status-enabled'>Niemand</span>"
            Write-ColorOutput "  Gast-Einladungen sind DEAKTIVIERT" -Type Success
        }
        "adminsAndGuestInviters" {
            $html += "<span class='status-restricted'>Nur Admins und Guest Inviters</span>"
            Write-ColorOutput "  Nur Admins und Guest Inviters können Gäste einladen" -Type Warning
        }
        "adminsGuestInvitersAndAllMembers" {
            $html += "<span class='status-disabled'>Admins, Guest Inviters und ALLE Mitglieder</span>"
            Write-ColorOutput "  ALLE Mitglieder können Gäste einladen" -Type Warning
        }
        "everyone" {
            $html += "<span class='status-disabled'>JEDER (inkl. Gäste)</span>"
            Write-ColorOutput "  KRITISCH: Auch Gäste können weitere Gäste einladen!" -Type Error
        }
        default { $html += "$allowInvites" }
    }
    $html += "</td></tr>"

    # Email-Verifizierung
    $allowEmailVerified = $authPolicy.AllowEmailVerifiedUsersToJoinOrganization
    $html += "<tr><td>Selbstregistrierung per E-Mail</td><td><code>$allowEmailVerified</code></td><td>"
    if ($allowEmailVerified) { $html += "<span class='status-disabled'>AKTIVIERT (Risiko)</span>" } else { $html += "<span class='status-enabled'>Deaktiviert</span>" }
    $html += "</td></tr>"

    $html += "</table>"

    $status = if ($allowInvites -eq "everyone" -or $allowEmailVerified) { "Critical" }
              elseif ($allowInvites -eq "adminsGuestInvitersAndAllMembers") { "Warning" }
              else { "Success" }

    Add-ReportSection -Title "Externe Freigabe - Entra ID Einstellungen" -Content $html -Status $status
    Write-ColorOutput "  Entra ID Gast-Einstellungen geprüft" -Type Success
} catch {
    Write-ColorOutput "  Fehler: $($_.Exception.Message)" -Type Error
}

# ============================================================================
# Schritt 11: M365-Gruppen mit externen Mitgliedern
# ============================================================================

Step "Prüfe M365-Gruppen mit externen Mitgliedern..."

try {
    Write-ColorOutput "  Lade alle M365-Gruppen..." -Type Info
    $m365Groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All -Property Id,DisplayName,Mail,CreatedDateTime,Visibility

    Write-ColorOutput "  Gefunden: $($m365Groups.Count) M365-Gruppen" -Type Info
    Write-ColorOutput "  Prüfe externe Mitglieder (dies kann einige Minuten dauern)..." -Type Info

    $groupsWithGuests = @()
    $totalGuests = 0
    $counter = 0

    foreach ($group in $m365Groups) {
        $counter++
        Write-Progress -Activity "Prüfe Gruppen auf externe Mitglieder" -Status "$counter von $($m365Groups.Count): $($group.DisplayName)" -PercentComplete (($counter / $m365Groups.Count) * 100)

        $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction SilentlyContinue
        $guests = $members | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' } | ForEach-Object {
            Get-MgUser -UserId $_.Id -ErrorAction SilentlyContinue | Where-Object { $_.UserType -eq 'Guest' }
        }

        if ($guests.Count -gt 0) {
            $groupsWithGuests += [PSCustomObject]@{
                GroupName  = $group.DisplayName
                GroupMail  = $group.Mail
                GuestCount = $guests.Count
                Visibility = $group.Visibility
                Created    = $group.CreatedDateTime
                Guests     = $guests
            }
            $totalGuests += $guests.Count
        }
    }

    Write-Progress -Activity "Prüfe Gruppen auf externe Mitglieder" -Completed

    $html = "<p><strong>Zusammenfassung:</strong></p>"
    $html += "<ul>"
    $html += "<li>Gesamt M365-Gruppen: <strong>$($m365Groups.Count)</strong></li>"
    $html += "<li>Gruppen mit externen Mitgliedern: <strong>$($groupsWithGuests.Count)</strong></li>"
    $html += "<li>Gesamt externe Mitglieder: <strong>$totalGuests</strong></li>"
    $html += "</ul>"

    if ($groupsWithGuests.Count -gt 0) {
        $html += "<table><tr><th>Gruppenname</th><th>E-Mail</th><th>Sichtbarkeit</th><th>Anzahl Gäste</th><th>Erstellt</th></tr>"
        foreach ($g in $groupsWithGuests | Sort-Object -Property GuestCount -Descending) {
            $html += "<tr><td>$($g.GroupName)</td><td><code>$($g.GroupMail)</code></td><td>$($g.Visibility)</td><td><strong>$($g.GuestCount)</strong></td><td>$($g.Created.ToString('dd.MM.yyyy'))</td></tr>"
            $html += "<tr><td colspan='5'><details><summary>Gast-Details anzeigen</summary><ul>"
            foreach ($guest in $g.Guests) {
                $html += "<li>$($guest.DisplayName) - <code>$($guest.Mail)</code></li>"
            }
            $html += "</ul></details></td></tr>"
        }
        $html += "</table>"
        Write-ColorOutput "  $($groupsWithGuests.Count) Gruppen haben externe Mitglieder" -Type Warning
        Add-ReportSection -Title "M365-Gruppen mit externen Mitgliedern" -Content $html -Status "Warning"
    } else {
        $html += "<div class='info-box'>Keine M365-Gruppen mit externen Mitgliedern gefunden.</div>"
        Write-ColorOutput "  Keine Gruppen mit externen Mitgliedern" -Type Success
        Add-ReportSection -Title "M365-Gruppen mit externen Mitgliedern" -Content $html -Status "Success"
    }
} catch {
    Write-ColorOutput "  Fehler: $($_.Exception.Message)" -Type Error
}

# ============================================================================
# Schritt 12: Administrative Rollen
# ============================================================================

Step "Analysiere Benutzerrollen und Berechtigungen..."

try {
    $adminRoles = Get-MgDirectoryRole -All

    $html = "<table><tr><th>Rollenname</th><th>Anzahl Mitglieder</th><th>Relevante Berechtigungen</th></tr>"

    $relevantRoles = @(
        "Global Administrator",
        "Groups Administrator",
        "SharePoint Administrator",
        "Teams Administrator",
        "User Administrator",
        "Guest Inviter",
        "Exchange Administrator",
        "Compliance Administrator",
        "Security Administrator"
    )

    foreach ($role in $adminRoles) {
        if ($role.DisplayName -in $relevantRoles) {
            $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All

            $permissions = switch ($role.DisplayName) {
                "Global Administrator"       { "Vollzugriff auf alle Einstellungen" }
                "Groups Administrator"       { "Erstellen und verwalten von Gruppen" }
                "SharePoint Administrator"   { "SharePoint-Sites und -Einstellungen" }
                "Teams Administrator"        { "Teams und Teams-Richtlinien" }
                "User Administrator"         { "Benutzer und Gruppen verwalten" }
                "Guest Inviter"              { "Externe Benutzer einladen" }
                "Exchange Administrator"     { "Exchange Online und Mail-Gruppen" }
                "Compliance Administrator"   { "Compliance und DLP" }
                "Security Administrator"     { "Sicherheitseinstellungen" }
                default                      { "Diverse" }
            }

            $html += "<tr><td><strong>$($role.DisplayName)</strong></td><td>$($members.Count)</td><td>$permissions</td></tr>"

            if ($members.Count -gt 0) {
                $html += "<tr><td colspan='3'><details><summary>Mitglieder anzeigen ($($members.Count))</summary><ul>"
                foreach ($member in $members) {
                    $user = Get-MgUser -UserId $member.Id -ErrorAction SilentlyContinue
                    if ($user) {
                        $html += "<li>$($user.DisplayName) - <code>$($user.UserPrincipalName)</code></li>"
                    }
                }
                $html += "</ul></details></td></tr>"
            }
        }
    }

    $html += "</table>"

    Write-ColorOutput "  Admin-Rollen analysiert" -Type Success
    Add-ReportSection -Title "Administrative Rollen" -Content $html -Status "Info"
} catch {
    Write-ColorOutput "  Fehler: $($_.Exception.Message)" -Type Error
}

# ============================================================================
# Export und Cleanup
# ============================================================================

Write-Host ""
Write-ColorOutput "================================================================" -Type Header
Write-ColorOutput "   Analyse abgeschlossen - Erstelle Report..." -Type Header
Write-ColorOutput "================================================================" -Type Header

Export-HtmlReport -Path $ExportPath

Write-ColorOutput "`nACCESS REVIEW ABGESCHLOSSEN" -Type Success
Write-ColorOutput "Report gespeichert unter:" -Type Info
Write-ColorOutput "  $ExportPath" -Type Success
Write-ColorOutput "Öffne den Report mit:" -Type Info
Write-ColorOutput "  Invoke-Item '$ExportPath'" -Type Info

# Verbindungen trennen
try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue } catch {}
Write-ColorOutput "Verbindungen getrennt" -Type Success

Write-Host ""
