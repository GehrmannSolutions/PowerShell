<#
.SYNOPSIS
    Erkennt ob Windows 10 ESU (Extended Security Updates) aktiviert werden muss.

.DESCRIPTION
    Prueft den ESU-Aktivierungsstatus in mehreren Stufen:
    - Windows 10 22H2 vorhanden?
    - ESU bereits lizenziert?
    - Voraussetzungs-KBs (KB5066791, KB5072653) installiert?
    - MAK-Key in Registry vorhanden?
    - Neustart ausstehend (Phase 1)?

    Exit 0 = compliant (ESU aktiv, oder Zwischenphase/nicht zustaendig)
    Exit 1 = non-compliant (Remediation erforderlich)

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Detection Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 26.02.2026 - Erstversion
#>

$registryPath = "HKLM:\SOFTWARE\BusinessITSolutions\ESU"

# --- 1. Windows-Version pruefen ---
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$build = [System.Environment]::OSVersion.Version

# Windows 10 = Major 10, Build < 22000. 22H2 = Build 19045
if ($build.Major -ne 10 -or $build.Build -ge 22000) {
    Write-Host "Kein Windows 10 - ESU nicht zustaendig (Build: $($build.Build))."
    exit 0
}

if ($build.Build -lt 19045) {
    Write-Host "Windows 10 ist nicht auf Version 22H2 (Build: $($build.Build)). Upgrade auf 22H2 erforderlich."
    exit 1
}

# --- 2. ESU bereits aktiviert? ---
try {
    $slmgrOutput = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /dlv 2>&1 | Out-String

    # Pruefen ob mindestens ESU Year 1 lizenziert ist
    $esuLicensed = $false
    $esuNames = @("ESU-Year1", "ESU Year1", "Win10 ESU Year1", "ESU-Year 1")

    # Alle Lizenzinfos abfragen fuer ESU-spezifische Activation IDs
    $esuYear1Id = "f520e45e-7413-4a34-a497-d2765967d094"
    $esuCheckOutput = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /dlv $esuYear1Id 2>&1 | Out-String

    if ($esuCheckOutput -match "License Status:\s*Licensed" -or $esuCheckOutput -match "Lizenzstatus:\s*Lizenziert") {
        Write-Host "ESU Year 1 ist bereits aktiviert und lizenziert."
        $esuLicensed = $true
    }

    if ($esuLicensed) {
        # Phase auf 2 setzen falls noch nicht geschehen
        if (Test-Path $registryPath) {
            $currentPhase = (Get-ItemProperty -Path $registryPath -Name "Phase" -ErrorAction SilentlyContinue).Phase
            if ($currentPhase -ne 2) {
                Set-ItemProperty -Path $registryPath -Name "Phase" -Value 2 -ErrorAction SilentlyContinue
            }
        }
        exit 0
    }
}
catch {
    Write-Host "Warnung: slmgr-Pruefung fehlgeschlagen: $($_.Exception.Message)"
}

# --- 3. Phase-Flag pruefen ---
if (Test-Path $registryPath) {
    $phase = (Get-ItemProperty -Path $registryPath -Name "Phase" -ErrorAction SilentlyContinue).Phase

    if ($phase -eq 1) {
        # KBs installiert, warten auf Neustart - als compliant melden
        Write-Host "ESU Phase 1: KBs installiert, Neustart ausstehend. Warte auf Neustart."
        exit 0
    }

    if ($phase -eq 2) {
        # Sollte oben schon gefangen werden, aber Sicherheitsnetz
        Write-Host "ESU Phase 2: Aktivierung abgeschlossen."
        exit 0
    }
}

# --- 4. Voraussetzungs-KBs pruefen ---
$hotfixes = Get-HotFix -ErrorAction SilentlyContinue

$kb5066791 = $hotfixes | Where-Object { $_.HotFixID -eq "KB5066791" }
$kb5072653 = $hotfixes | Where-Object { $_.HotFixID -eq "KB5072653" }

$kbStatus = @()
if (-not $kb5066791) { $kbStatus += "KB5066791 fehlt" }
if (-not $kb5072653) { $kbStatus += "KB5072653 fehlt" }

if ($kbStatus.Count -gt 0) {
    Write-Host "ESU-Voraussetzungen nicht erfuellt: $($kbStatus -join ', ')."
    exit 1
}

# --- 5. MAK-Key in Registry pruefen ---
$makKey = $null
if (Test-Path $registryPath) {
    $makKey = (Get-ItemProperty -Path $registryPath -Name "MakKey" -ErrorAction SilentlyContinue).MakKey
}

if ([string]::IsNullOrWhiteSpace($makKey)) {
    Write-Host "ESU MAK-Key nicht in Registry vorhanden ($registryPath\MakKey). Bitte per Intune OMA-URI bereitstellen."
    exit 1
}

# --- 6. Alles vorhanden, ESU aber nicht aktiv ---
Write-Host "ESU nicht aktiviert. Voraussetzungen erfuellt (KBs vorhanden, MAK-Key vorhanden). Remediation erforderlich."
exit 1
