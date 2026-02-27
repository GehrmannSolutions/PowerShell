<#
.SYNOPSIS
    Intune Policy Assignment Manager - Massenneuzuweisung von Policies

.DESCRIPTION
    Listet alle Configuration Policies, Device Configurations und Endpoint Security
    Policies aus Intune auf und ersetzt deren Zuweisungen interaktiv durch
    "All Users" oder "All Devices" (wahlweise mit Assignment Filter).

    Pro Policy wird abgefragt:
      - Neue Zuweisungsart (All Users / All Devices)
      - Optionaler Assignment Filter (inkl. Include/Exclude)

    Dazu wird eine Empfehlung angezeigt, die auf folgendem Hintergrund basiert:

    AUTOPILOT / REBOOTREQUIRED-PROBLEM:
    ─────────────────────────────────────────────────────────────────────────────
    Bestimmte MDM-Policies setzen den Registry-Schlüssel:
      HKLM\SOFTWARE\Microsoft\Provisioning\OMADM\SyncML\RebootRequired

    Dieser Schlüssel löst während der Autopilot Device Phase (ESP Device Setup)
    einen unerwarteten Neustart aus. Dadurch wird der Windows Hello for Business /
    Passwordless-Onboarding-Prozess unterbrochen – der Benutzer muss sich nach
    dem Neustart erneut authentifizieren.

    EMPFEHLUNG:
      → "All Users": Policies greifen erst in der USER Phase (nach Device Setup).
        Kein Reboot-Risiko während Autopilot. Empfohlen für alle Policies, die
        nicht zwingend vor dem User Login aktiv sein müssen.

      → "All Devices": Policies greifen in der DEVICE Phase. Nur verwenden, wenn
        die Policy VOR dem User Login aktiv sein muss (z.B. BitLocker, Netzwerk).
        In diesem Fall ggf. Autopilot-Filter setzen, um den Effekt einzugrenzen.

    Quelle: https://patchmypc.com/blog/autopilot-unexpected-reboot-what-really-
            triggers-a-device-restart-and-how-to-fix-it/

.PARAMETER NurEndpointSecurity
    Verarbeitet nur Endpoint Security Policies (configurationPolicies mit
    endpointSecurity* templateFamily + Intents).

.PARAMETER NurConfigurationPolicies
    Verarbeitet nur Settings Catalog Policies (configurationPolicies ohne
    Endpoint Security templateFamily).

.PARAMETER NurDeviceConfigurations
    Verarbeitet nur Legacy Device Configurations.

.PARAMETER ExportPfad
    Pfad für das Änderungsprotokoll (CSV). Standard: Scriptverzeichnis.

.NOTES
    Benötigte Graph-Berechtigungen:
      - DeviceManagementConfiguration.ReadWrite.All
      - DeviceManagementManagedDevices.ReadWrite.All

    Getestet mit: Microsoft.Graph PowerShell Module v2.x

.AUTHOR
    Marius Gehrmann - Business IT Solutions (marius@gehrmann.io)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$NurEndpointSecurity,

    [Parameter(Mandatory = $false)]
    [switch]$NurConfigurationPolicies,

    [Parameter(Mandatory = $false)]
    [switch]$NurDeviceConfigurations,

    [Parameter(Mandatory = $false)]
    [string]$ExportPfad = "$PSScriptRoot\PolicyAssignment-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

$ErrorActionPreference = "Stop"

# ============================================================================
# KONSTANTEN
# ============================================================================

$GraphBaseUri = "https://graph.microsoft.com/beta"

# ============================================================================
# HILFSFUNKTIONEN
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Typ = "Info"
    )
    switch ($Typ) {
        "Erfolg"     { Write-Host $Message -ForegroundColor Green }
        "Warnung"    { Write-Host $Message -ForegroundColor Yellow }
        "Fehler"     { Write-Host $Message -ForegroundColor Red }
        "Info"       { Write-Host $Message -ForegroundColor Cyan }
        "Header"     { Write-Host $Message -ForegroundColor Magenta }
        "Empfehlung" { Write-Host $Message -ForegroundColor DarkGreen }
        "Grau"       { Write-Host $Message -ForegroundColor DarkGray }
        default      { Write-Host $Message }
    }
}

function Get-GraphAllPages {
    param([string]$Uri)

    $ergebnisse = [System.Collections.Generic.List[object]]::new()

    try {
        $antwort = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        if ($antwort['value']) {
            $ergebnisse.AddRange([object[]]$antwort['value'])
        }
        while (-not [string]::IsNullOrEmpty($antwort['@odata.nextLink'])) {
            $antwort = Invoke-MgGraphRequest -Method GET -Uri $antwort['@odata.nextLink'] -ErrorAction Stop
            if ($antwort['value']) {
                $ergebnisse.AddRange([object[]]$antwort['value'])
            }
        }
    }
    catch {
        Write-ColorOutput "  Fehler beim Laden von ${Uri}: $($_.Exception.Message)" "Fehler"
    }

    return $ergebnisse.ToArray()
}

function Get-PolicyZuweisungen {
    param(
        [string]$PolicyId,
        [string]$PolicyType
    )

    $uri = "$GraphBaseUri/deviceManagement/$PolicyType/$PolicyId/assignments"
    return Get-GraphAllPages -Uri $uri
}

function Get-ZuweisungAnzeige {
    param($Zuweisungen)

    if (-not $Zuweisungen -or $Zuweisungen.Count -eq 0) {
        return "Keine Zuweisung"
    }

    $texte = foreach ($z in $Zuweisungen) {
        $odataType = $z.target.'@odata.type'
        $filterInfo = ""

        if (-not [string]::IsNullOrEmpty($z.target.deviceAndAppManagementAssignmentFilterId)) {
            $filterId = $z.target.deviceAndAppManagementAssignmentFilterId
            $kurzId   = $filterId.Substring(0, [Math]::Min(8, $filterId.Length))
            $filterInfo = " [Filter: ${kurzId}... ($($z.target.deviceAndAppManagementAssignmentFilterType))]"
        }

        switch ($odataType) {
            "#microsoft.graph.allDevicesAssignmentTarget"          { "All Devices$filterInfo" }
            "#microsoft.graph.allLicensedUsersAssignmentTarget"    { "All Users$filterInfo" }
            "#microsoft.graph.groupAssignmentTarget"               {
                $gId = $z.target.groupId
                "Gruppe: $($gId.Substring(0, [Math]::Min(8, $gId.Length)))...$filterInfo"
            }
            "#microsoft.graph.exclusionGroupAssignmentTarget"      {
                $gId = $z.target.groupId
                "Ausschluss: $($gId.Substring(0, [Math]::Min(8, $gId.Length)))...$filterInfo"
            }
            default { $odataType }
        }
    }

    return ($texte -join " | ")
}

function Get-Empfehlung {
    param(
        [string]$PolicyType,
        [string]$PolicyName,
        [string]$TemplateFamily
    )

    # Endpoint Security Policies → hohes Reboot-Risiko in Device Phase
    $endpointSecurityFamilies = @(
        "endpointSecurityEndpointProtection",
        "endpointSecurityAttackSurfaceReduction",
        "endpointSecurityAccountProtection",
        "endpointSecurityAntivirus",
        "endpointSecurityFirewall",
        "endpointSecurityEndpointDetectionAndResponse",
        "endpointSecurityDiskEncryption"
    )

    if ($TemplateFamily -in $endpointSecurityFamilies) {
        # BitLocker/Disk Encryption ausnahmsweise All Devices empfehlen
        if ($TemplateFamily -eq "endpointSecurityDiskEncryption") {
            return @{
                Empfehlung   = "AllDevices"
                Begruendung  = "BitLocker/Disk Encryption muss vor dem User Login aktiv sein → All Devices. Ggf. Autopilot-Gerätefilter nutzen."
                Symbol       = "⚠"
            }
        }
        return @{
            Empfehlung   = "AllUsers"
            Begruendung  = "Endpoint Security Policies (Familie: $TemplateFamily) können OMADM RebootRequired setzen. All Users verhindert Ausführung in der Autopilot Device Phase."
            Symbol       = "✓"
        }
    }

    # Endpoint Security Legacy Intents
    if ($PolicyType -eq "intents") {
        return @{
            Empfehlung   = "AllUsers"
            Begruendung  = "Endpoint Security Intent-Policies werden in der Device Phase ausgeführt → Reboot-Risiko während Autopilot. All Users empfohlen."
            Symbol       = "✓"
        }
    }

    # Windows Update / WUfB Policies → Reboot-Risiko
    if ($PolicyName -match "Update|WUfB|Windows Update|Feature Update|Quality Update|Qualitätsupdate|Funktionsupdate") {
        return @{
            Empfehlung   = "AllUsers"
            Begruendung  = "Update-Policies können RebootRequired setzen. All Users verhindert Reboot-Trigger in der Autopilot Device Phase."
            Symbol       = "✓"
        }
    }

    # Domain Join (Hybrid Entra Join) → muss in der Device Phase greifen
    if ($PolicyName -match "DomainJoin|Domain.?Join|HybridJoin|Hybrid.?Join|HAADJ|Domain Join") {
        return @{
            Empfehlung   = "AllDevices"
            Begruendung  = "Domain Join Policies konfigurieren den Hybrid Entra Join und müssen in der Device Phase aktiv sein – vor dem User Login. All Devices ist zwingend erforderlich."
            Symbol       = "⚠"
        }
    }

    # BitLocker / Verschlüsselung → muss vor User Login aktiv sein
    if ($PolicyName -match "BitLocker|Encryption|Verschlüsselung|Laufwerk") {
        return @{
            Empfehlung   = "AllDevices"
            Begruendung  = "Verschlüsselung muss vor dem User Login aktiv sein → All Devices sinnvoll. Ggf. Autopilot-Filter hinzufügen."
            Symbol       = "⚠"
        }
    }

    # Netzwerk / Wi-Fi / VPN → oft vor User Login benötigt
    if ($PolicyName -match "WiFi|Wi-Fi|VPN|Network|Netzwerk|WLAN|Zertifikat|Certificate|SCEP|PKCS") {
        return @{
            Empfehlung   = "AllDevices"
            Begruendung  = "Netzwerk- und Zertifikat-Konfigurationen werden typischerweise vor dem User Login benötigt."
            Symbol       = "⚠"
        }
    }

    # Standard: All Users (sicherer für Autopilot)
    return @{
        Empfehlung   = "AllUsers"
        Begruendung  = "Standardempfehlung: All Users ist für Autopilot sicherer, da Policies erst nach dem Device Setup greifen und keinen Reboot im ESP Device Phase auslösen."
        Symbol       = "✓"
    }
}

function Set-PolicyZuweisung {
    param(
        [string]$PolicyId,
        [string]$PolicyType,
        [string]$ZuweisungTyp,
        [string]$FilterId     = "",
        [string]$FilterTyp    = "none"
    )

    $odataTargetType = switch ($ZuweisungTyp) {
        "AllUsers"   { "#microsoft.graph.allLicensedUsersAssignmentTarget" }
        "AllDevices" { "#microsoft.graph.allDevicesAssignmentTarget" }
    }

    $target = [ordered]@{
        "@odata.type"                                        = $odataTargetType
        "deviceAndAppManagementAssignmentFilterType"         = $FilterTyp
    }

    if (-not [string]::IsNullOrEmpty($FilterId)) {
        $target["deviceAndAppManagementAssignmentFilterId"] = $FilterId
    }

    $body = @{
        "assignments" = @(
            @{ "target" = $target }
        )
    } | ConvertTo-Json -Depth 10

    $uri = "$GraphBaseUri/deviceManagement/$PolicyType/$PolicyId/assign"

    if ($PSCmdlet.ShouldProcess($PolicyId, "Zuweisung setzen: $ZuweisungTyp")) {
        try {
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
            return $true
        }
        catch {
            Write-ColorOutput "  Fehler beim Setzen der Zuweisung: $($_.Exception.Message)" "Fehler"
            return $false
        }
    }
    return $true
}

function Show-FilterAuswahl {
    param($Filter)

    Write-Host ""
    Write-Host "  Verfügbare Assignment Filter:" -ForegroundColor Cyan
    Write-Host "  [0] Kein Filter" -ForegroundColor White

    for ($i = 0; $i -lt $Filter.Count; $i++) {
        $f            = $Filter[$i]
        $plattform    = if ($f.platform) { " ($($f.platform))" } else { "" }
        $regeltyp     = if ($f.assignmentFilterManagementType) { " [$($f.assignmentFilterManagementType)]" } else { "" }
        Write-Host "  [$($i + 1)] $($f.displayName)$plattform$regeltyp" -ForegroundColor White
    }

    Write-Host ""
    $eingabe = Read-Host "  Filter-Nummer"

    if ($eingabe -match '^\d+$') {
        $index = [int]$eingabe
        if ($index -eq 0)                                    { return $null }
        elseif ($index -ge 1 -and $index -le $Filter.Count) { return $Filter[$index - 1] }
    }

    Write-ColorOutput "  Ungültige Eingabe – kein Filter gesetzt." "Warnung"
    return $null
}

function Invoke-PolicyBearbeitung {
    param(
        [hashtable]$Policy,
        [array]$AvailableFilter,
        [hashtable]$Stats,
        [int]$AktuellerIndex,
        [int]$Gesamt,
        [string]$AutoModus = "Manuell"   # "Manuell" | "EmpfehlungMitFilter" | "EmpfehlungOhneFilter"
    )

    $empfehlung = Get-Empfehlung `
        -PolicyType     $Policy.PolicyType `
        -PolicyName     $Policy.displayName `
        -TemplateFamily ($Policy.TemplateFamily ?? "")

    Write-Host ""
    Write-Host ("─" * 70) -ForegroundColor DarkGray
    Write-Host "[$AktuellerIndex/$Gesamt] " -ForegroundColor DarkGray -NoNewline
    Write-ColorOutput $Policy.displayName "Header"
    Write-Host "  Kategorie:  $($Policy.Kategorie)" -ForegroundColor DarkGray

    if (-not [string]::IsNullOrEmpty($Policy.TemplateFamily)) {
        Write-Host "  Template:   $($Policy.TemplateFamily)" -ForegroundColor DarkGray
    }

    # Aktuelle Zuweisung laden und anzeigen
    try {
        $aktuelleZuweisungen = Get-PolicyZuweisungen -PolicyId $Policy.id -PolicyType $Policy.PolicyType
        $zuweisungText = Get-ZuweisungAnzeige -Zuweisungen $aktuelleZuweisungen
    }
    catch {
        $zuweisungText = "Fehler beim Laden"
    }
    Write-Host "  Aktuell:    $zuweisungText" -ForegroundColor DarkGray

    # Empfehlung anzeigen
    Write-Host ""
    $empfSymbolFarbe = if ($empfehlung.Empfehlung -eq "AllUsers") { "Green" } else { "Yellow" }
    Write-Host "  $($empfehlung.Symbol) EMPFEHLUNG: " -ForegroundColor $empfSymbolFarbe -NoNewline
    Write-Host $empfehlung.Empfehlung -ForegroundColor $empfSymbolFarbe
    Write-Host "    $($empfehlung.Begruendung)" -ForegroundColor DarkGreen

    # ── ZUWEISUNGSART ───────────────────────────────────────────────────────
    $zuweisungTyp = $null

    if ($AutoModus -eq "Manuell") {
        # Manuelle Auswahl
        Write-Host ""
        $empfUsersLabel   = if ($empfehlung.Empfehlung -eq "AllUsers")   { " ← Empfohlen" } else { "" }
        $empfDevicesLabel = if ($empfehlung.Empfehlung -eq "AllDevices") { " ← Empfohlen" } else { "" }

        Write-Host "  Neue Zuweisungsart:" -ForegroundColor White
        Write-Host "  [1] All Users$empfUsersLabel"    -ForegroundColor $(if ($empfehlung.Empfehlung -eq "AllUsers")   { "Green" } else { "White" })
        Write-Host "  [2] All Devices$empfDevicesLabel" -ForegroundColor $(if ($empfehlung.Empfehlung -eq "AllDevices") { "Yellow" } else { "White" })
        Write-Host "  [S] Überspringen" -ForegroundColor DarkYellow
        Write-Host ""

        $auswahl = Read-Host "  Auswahl"

        if ($auswahl -in @("S", "s")) {
            Write-ColorOutput "  → Übersprungen." "Warnung"
            $Stats.Uebersprungen++
            return
        }

        $zuweisungTyp = switch ($auswahl) {
            "1" { "AllUsers" }
            "2" { "AllDevices" }
            default {
                Write-ColorOutput "  Ungültige Eingabe – übersprungen." "Warnung"
                $Stats.Uebersprungen++
                return
            }
        }
    }
    else {
        # Auto-Modus: Empfehlung direkt übernehmen, [S] zum Überspringen
        $zuweisungTyp   = $empfehlung.Empfehlung
        $autoFarbe      = if ($zuweisungTyp -eq "AllUsers") { "Green" } else { "Yellow" }
        Write-Host ""
        Write-Host "  → Auto: Zuweisung wird als " -ForegroundColor DarkGray -NoNewline
        Write-Host $zuweisungTyp -ForegroundColor $autoFarbe -NoNewline
        Write-Host " gesetzt." -ForegroundColor DarkGray
        Write-Host "  [S] zum Überspringen dieser Policy." -ForegroundColor DarkYellow
        Write-Host ""

        $skipCheck = Read-Host "  Weiter? [Enter / S]"
        if ($skipCheck -in @("S", "s")) {
            Write-ColorOutput "  → Übersprungen." "Warnung"
            $Stats.Uebersprungen++
            return
        }
    }

    # ── FILTER ──────────────────────────────────────────────────────────────
    $gewaehlterFilter = $null
    $filterTyp        = "none"

    if ($AutoModus -eq "EmpfehlungOhneFilter") {
        # Kein Filter im schnellen Auto-Modus
    }
    elseif ($AvailableFilter.Count -gt 0) {
        $gewaehlterFilter = Show-FilterAuswahl -Filter $AvailableFilter

        if ($gewaehlterFilter) {
            Write-Host ""
            Write-Host "  Filter-Anwendung für '$($gewaehlterFilter.displayName)':" -ForegroundColor White
            Write-Host "  [1] Include  (nur Geräte/User, die dem Filter entsprechen)" -ForegroundColor White
            Write-Host "  [2] Exclude  (Geräte/User, die dem Filter entsprechen, ausschließen)" -ForegroundColor White
            Write-Host ""
            $filterTypAuswahl = Read-Host "  Auswahl [1]"
            $filterTyp = switch ($filterTypAuswahl) {
                "2"     { "exclude" }
                default { "include" }
            }
        }
    }
    else {
        Write-ColorOutput "  Keine Assignment Filter vorhanden – Zuweisung ohne Filter." "Warnung"
    }

    # ── ZUSAMMENFASSUNG ─────────────────────────────────────────────────────
    Write-Host ""
    Write-Host ("  ┌─ Zusammenfassung " + ("─" * 50)) -ForegroundColor DarkGray
    Write-Host "  │ Policy:    $($Policy.displayName)" -ForegroundColor White
    Write-Host "  │ Zuweisung: $zuweisungTyp" -ForegroundColor $(if ($zuweisungTyp -eq "AllUsers") { "Green" } else { "Yellow" })

    if ($gewaehlterFilter) {
        Write-Host "  │ Filter:    $($gewaehlterFilter.displayName) ($filterTyp)" -ForegroundColor White
    }
    else {
        Write-Host "  │ Filter:    Kein Filter" -ForegroundColor DarkGray
    }

    if ($AutoModus -ne "Manuell") {
        Write-Host "  │ Modus:     Auto (Empfehlung)" -ForegroundColor DarkGray
    }
    Write-Host ("  └" + ("─" * 67)) -ForegroundColor DarkGray
    Write-Host ""

    # Im Auto-Modus entfällt die explizite J/N-Bestätigung (wurde bereits per Enter/S quittiert)
    if ($AutoModus -eq "Manuell") {
        $bestaetigung = Read-Host "  Zuweisung setzen? [J/N]"
        if ($bestaetigung -notin @("J", "j")) {
            Write-ColorOutput "  → Abgebrochen." "Warnung"
            $Stats.Uebersprungen++
            return
        }
    }

    # Zuweisung anwenden
    $filterId = if ($gewaehlterFilter) { $gewaehlterFilter.id } else { "" }
    $erfolg   = Set-PolicyZuweisung `
        -PolicyId    $Policy.id `
        -PolicyType  $Policy.PolicyType `
        -ZuweisungTyp $zuweisungTyp `
        -FilterId    $filterId `
        -FilterTyp   $filterTyp

    if ($erfolg) {
        Write-ColorOutput "  ✓ Zuweisung erfolgreich gesetzt." "Erfolg"
        $Stats.Erfolgreich++

        # Protokoll-Eintrag
        $Stats.Protokoll += [PSCustomObject]@{
            Timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            PolicyName       = $Policy.displayName
            PolicyId         = $Policy.id
            PolicyType       = $Policy.PolicyType
            Kategorie        = $Policy.Kategorie
            NeueZuweisung    = $zuweisungTyp
            FilterName       = if ($gewaehlterFilter) { $gewaehlterFilter.displayName } else { "" }
            FilterId         = $filterId
            FilterTyp        = $filterTyp
            Empfehlung       = $empfehlung.Empfehlung
            EmpfehlungGefolgt = ($zuweisungTyp -eq $empfehlung.Empfehlung)
        }
    }
    else {
        $Stats.Fehler++
    }
}

# ============================================================================
# HAUPTPROGRAMM
# ============================================================================

Write-Host ""
Write-ColorOutput "╔══════════════════════════════════════════════════════════════════╗" "Header"
Write-ColorOutput "║   INTUNE POLICY ASSIGNMENT MANAGER                              ║" "Header"
Write-ColorOutput "║   Business IT Solutions - Marius Gehrmann                      ║" "Header"
Write-ColorOutput "╚══════════════════════════════════════════════════════════════════╝" "Header"
Write-Host ""
Write-ColorOutput "AUTOPILOT-HINWEIS:" "Warnung"
Write-Host "  Policies mit 'All Devices' werden in der DEVICE Phase des ESP" -ForegroundColor White
Write-Host "  ausgeführt. Lösen sie RebootRequired aus, wird der WHfB-" -ForegroundColor White
Write-Host "  Passwordless-Onboarding mit TAP unterbrochen!" -ForegroundColor White
Write-Host "  → 'All Users' lässt Policies erst nach dem Device Setup greifen." -ForegroundColor DarkGreen
Write-Host ""

# ============================================================================
# GRAPH VERBINDUNG
# ============================================================================

Write-ColorOutput "Verbinde mit Microsoft Graph..." "Info"

$benoethigteScopes = @(
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.ReadWrite.All"
)

try {
    $ctx = Get-MgContext
    if (-not $ctx) {
        Connect-MgGraph -Scopes $benoethigteScopes -NoWelcome
        $ctx = Get-MgContext
    }
    else {
        $fehlendeScopes = $benoethigteScopes | Where-Object { $_ -notin $ctx.Scopes }
        if ($fehlendeScopes.Count -gt 0) {
            Write-ColorOutput "Fehlende Berechtigungen: $($fehlendeScopes -join ', ')" "Warnung"
            Write-ColorOutput "Erneute Verbindung mit allen Scopes..." "Info"
            Connect-MgGraph -Scopes $benoethigteScopes -NoWelcome
            $ctx = Get-MgContext
        }
    }
    Write-ColorOutput "Verbunden als: $($ctx.Account) (Tenant: $($ctx.TenantId.Substring(0,8))...)" "Erfolg"
}
catch {
    Write-ColorOutput "Verbindungsfehler: $($_.Exception.Message)" "Fehler"
    exit 1
}

Write-Host ""

# ============================================================================
# ASSIGNMENT FILTER LADEN
# ============================================================================

Write-ColorOutput "Lade Assignment Filter..." "Info"
$alleFilter = @(Get-GraphAllPages -Uri "$GraphBaseUri/deviceManagement/assignmentFilters")

if ($alleFilter.Count -gt 0) {
    Write-ColorOutput "$($alleFilter.Count) Assignment Filter gefunden." "Erfolg"
}
else {
    Write-ColorOutput "Keine Assignment Filter gefunden. Zuweisungen werden ohne Filter gesetzt." "Warnung"
}

# ============================================================================
# POLICIES LADEN
# ============================================================================

$allePolicies = [System.Collections.Generic.List[hashtable]]::new()

# 1. Configuration Policies (Settings Catalog + neue Endpoint Security)
if (-not $NurDeviceConfigurations -and -not $NurEndpointSecurity) {
    Write-ColorOutput "Lade Configuration Policies (Settings Catalog)..." "Info"

    $selectFelder   = "`$select=id,name,description,platforms,technologies,templateReference"
    $configPolicies = @(Get-GraphAllPages -Uri "$GraphBaseUri/deviceManagement/configurationPolicies?$selectFelder")

    $windowsConfigPolicies = @($configPolicies | Where-Object { $_.platforms -match 'windows' })

    foreach ($p in $windowsConfigPolicies) {
        $templateFamily = $p['templateReference']?['templateFamily'] ?? ""
        $kategorie      = if ($templateFamily -like "endpointSecurity*") { "Endpoint Security (Settings Catalog)" } else { "Settings Catalog" }

        $allePolicies.Add(@{
            id             = $p['id']
            displayName    = $p['name'] ?? "(kein Name)"
            description    = $p['description'] ?? ""
            TemplateFamily = $templateFamily
            PolicyType     = "configurationPolicies"
            Kategorie      = $kategorie
        })
    }

    Write-ColorOutput "$($windowsConfigPolicies.Count) von $($configPolicies.Count) Configuration Policies sind Windows-Policies." "Erfolg"
}

# 2. Device Configurations (Legacy)
if (-not $NurEndpointSecurity -and -not $NurConfigurationPolicies) {
    Write-ColorOutput "Lade Device Configurations (Legacy)..." "Info"

    # @odata.type wird bei deviceConfigurations immer mitgeliefert (z.B. #microsoft.graph.windows10GeneralConfiguration)
    $selectFelder     = "`$select=id,displayName,description"
    $deviceConfigs    = @(Get-GraphAllPages -Uri "$GraphBaseUri/deviceManagement/deviceConfigurations?$selectFelder")

    $windowsDeviceConfigs = @($deviceConfigs | Where-Object { $_['@odata.type'] -match 'windows' })

    foreach ($p in $windowsDeviceConfigs) {
        $allePolicies.Add(@{
            id             = $p['id']
            displayName    = $p['displayName'] ?? "(kein Name)"
            description    = $p['description'] ?? ""
            TemplateFamily = ""
            PolicyType     = "deviceConfigurations"
            Kategorie      = "Device Configuration (Legacy)"
        })
    }

    Write-ColorOutput "$($windowsDeviceConfigs.Count) von $($deviceConfigs.Count) Device Configurations sind Windows-Policies." "Erfolg"
}

# 3. Endpoint Security Intents (Legacy Template-basiert)
if (-not $NurConfigurationPolicies -and -not $NurDeviceConfigurations) {
    Write-ColorOutput "Lade Endpoint Security Intents..." "Info"

    # Template-Lookup für Plattformfilterung laden
    $templateLookup = @{}
    $templates = @(Get-GraphAllPages -Uri "$GraphBaseUri/deviceManagement/templates?`$select=id,platformType")
    foreach ($t in $templates) {
        $templateLookup[$t['id']] = $t['platformType'] ?? ""
    }

    $selectFelder = "`$select=id,displayName,description,templateId"
    $intents      = @(Get-GraphAllPages -Uri "$GraphBaseUri/deviceManagement/intents?$selectFelder")

    $windowsIntents = @($intents | Where-Object { $templateLookup[$_['templateId']] -match 'windows' })

    foreach ($p in $windowsIntents) {
        $allePolicies.Add(@{
            id             = $p['id']
            displayName    = $p['displayName'] ?? "(kein Name)"
            description    = $p['description'] ?? ""
            TemplateFamily = ""
            PolicyType     = "intents"
            Kategorie      = "Endpoint Security (Intent)"
        })
    }

    Write-ColorOutput "$($windowsIntents.Count) von $($intents.Count) Endpoint Security Intents sind Windows-Policies." "Erfolg"
}

# Sortieren: nach Kategorie, dann Name
$allePolicies = @($allePolicies | Sort-Object { $_.Kategorie }, { $_.displayName })

Write-Host ""
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "Info"
Write-ColorOutput "  Gesamt: $($allePolicies.Count) Policies gefunden" "Info"
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "Info"
Write-Host ""

if ($allePolicies.Count -eq 0) {
    Write-ColorOutput "Keine Policies gefunden. Script wird beendet." "Warnung"
    exit 0
}

$bestaetigung = Read-Host "Alle $($allePolicies.Count) Windows-Policies einzeln bearbeiten? [J/N]"
if ($bestaetigung -notin @("J", "j")) {
    Write-ColorOutput "Abgebrochen." "Warnung"
    exit 0
}

Write-Host ""
Write-Host "  Zuweisungsart-Modus:" -ForegroundColor White
Write-Host "  [1] Manuell – Zuweisungsart pro Policy selbst wählen" -ForegroundColor White
Write-Host "  [2] Auto    – Empfehlung automatisch anwenden, Filter pro Policy abfragen" -ForegroundColor White
Write-Host "  [3] Auto+   – Empfehlung automatisch anwenden, ohne Filter (schnellster Modus)" -ForegroundColor White
Write-Host ""
$modusEingabe = Read-Host "  Modus wählen [1]"

$autoModus = switch ($modusEingabe) {
    "2"     { "EmpfehlungMitFilter" }
    "3"     { "EmpfehlungOhneFilter" }
    default { "Manuell" }
}

if ($autoModus -ne "Manuell") {
    Write-ColorOutput "  → Auto-Modus aktiv: Empfehlung wird pro Policy automatisch gesetzt." "Empfehlung"
    Write-ColorOutput "    Mit [S] kann jede Policy übersprungen werden." "Empfehlung"
}
Write-Host ""

# ============================================================================
# INTERAKTIVE BEARBEITUNG
# ============================================================================

$stats = @{
    Erfolgreich    = 0
    Uebersprungen  = 0
    Fehler         = 0
    Protokoll      = [System.Collections.Generic.List[PSCustomObject]]::new()
}

$aktuelleKategorie = ""
$index             = 0

foreach ($policy in $allePolicies) {
    $index++

    # Kategorietrennlinie bei Wechsel
    if ($policy.Kategorie -ne $aktuelleKategorie) {
        $aktuelleKategorie = $policy.Kategorie
        Write-Host ""
        Write-ColorOutput "━━━ $aktuelleKategorie " "Info"
    }

    Invoke-PolicyBearbeitung `
        -Policy          $policy `
        -AvailableFilter $alleFilter `
        -Stats           $stats `
        -AktuellerIndex  $index `
        -Gesamt          $allePolicies.Count `
        -AutoModus       $autoModus
}

# ============================================================================
# PROTOKOLL EXPORTIEREN
# ============================================================================

if ($stats.Protokoll.Count -gt 0) {
    try {
        $stats.Protokoll | Export-Csv -Path $ExportPfad -NoTypeInformation -Encoding UTF8 -Delimiter ";"
        Write-ColorOutput "Protokoll gespeichert: $ExportPfad" "Erfolg"
    }
    catch {
        Write-ColorOutput "Protokoll konnte nicht gespeichert werden: $($_.Exception.Message)" "Warnung"
    }
}

# ============================================================================
# ABSCHLUSSZUSAMMENFASSUNG
# ============================================================================

Write-Host ""
Write-ColorOutput "╔══════════════════════════════════════════════════════════════════╗" "Header"
Write-ColorOutput "║  ABSCHLUSSZUSAMMENFASSUNG                                        ║" "Header"
Write-ColorOutput "╚══════════════════════════════════════════════════════════════════╝" "Header"
Write-Host ""
Write-ColorOutput "  Erfolgreich geändert: $($stats.Erfolgreich)" "Erfolg"
Write-ColorOutput "  Übersprungen:         $($stats.Uebersprungen)" "Warnung"

if ($stats.Fehler -gt 0) {
    Write-ColorOutput "  Fehler:               $($stats.Fehler)" "Fehler"
}

# Empfehlungsabweichungen anzeigen
$abweichungen = $stats.Protokoll | Where-Object { -not $_.EmpfehlungGefolgt }
if ($abweichungen.Count -gt 0) {
    Write-Host ""
    Write-ColorOutput "  Hinweis: Bei $($abweichungen.Count) Policy/Policies wurde von der Empfehlung abgewichen:" "Warnung"
    foreach ($a in $abweichungen) {
        Write-Host "    - $($a.PolicyName): $($a.NeueZuweisung) (Empfehlung war: $($a.Empfehlung))" -ForegroundColor Yellow
    }
}

Write-Host ""
