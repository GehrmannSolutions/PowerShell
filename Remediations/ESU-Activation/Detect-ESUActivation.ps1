<#
.SYNOPSIS
    Erkennt ob Windows 10 ESU (Extended Security Updates) aktiviert werden muss.

.DESCRIPTION
    Prueft den ESU-Aktivierungsstatus in dieser Reihenfolge:
    1. Windows 10 22H2 vorhanden?
    2. ESU bereits lizenziert? (slmgr /dlv)
    3. Neustart ausstehend aus vorherigem Lauf? (Phase-Flag)
    4. Voraussetzungs-KBs installiert? (KB5066791, KB5072653)

    Exit 0 = compliant (ESU aktiv, Zwischenphase, oder nicht zustaendig)
    Exit 1 = non-compliant (Remediation erforderlich)

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Detection Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 26.02.2026 - Erstversion
    V1.1, 08.03.2026 - Unbenutzte Variablen entfernt, Description aktualisiert
#>

$registryPath = "HKLM:\SOFTWARE\BusinessITSolutions\ESU"
$esuYear1Id   = "f520e45e-7413-4a34-a497-d2765967d094"

# --- 1. Windows-Version pruefen ---
# Windows 10 = Major 10, Build < 22000. 22H2 = Build 19045
$build = [System.Environment]::OSVersion.Version

if ($build.Major -ne 10 -or $build.Build -ge 22000) {
    Write-Host "Kein Windows 10 - ESU nicht zustaendig (Build: $($build.Build))."
    exit 0
}

if ($build.Build -lt 19045) {
    Write-Host "Windows 10 nicht auf Version 22H2 (Build: $($build.Build)). Upgrade erforderlich."
    exit 1
}

# --- 2. ESU bereits aktiviert? ---
try {
    $esuCheckOutput = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /dlv $esuYear1Id 2>&1 | Out-String

    if ($esuCheckOutput -match "License Status:\s*Licensed" -or $esuCheckOutput -match "Lizenzstatus:\s*Lizenziert") {
        Write-Host "ESU Year 1 ist bereits aktiviert und lizenziert."
        if (Test-Path $registryPath) {
            Set-ItemProperty -Path $registryPath -Name "Phase" -Value 2 -ErrorAction SilentlyContinue
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
        Write-Host "ESU Phase 1: KBs installiert, Neustart ausstehend."
        exit 0
    }

    if ($phase -eq 2) {
        Write-Host "ESU Phase 2: Aktivierung abgeschlossen."
        exit 0
    }
}

# --- 4. Voraussetzungs-KBs pruefen ---
$hotfixes = Get-HotFix -ErrorAction SilentlyContinue
$kbsMissing = @()
if (-not ($hotfixes | Where-Object { $_.HotFixID -eq "KB5066791" })) { $kbsMissing += "KB5066791" }
if (-not ($hotfixes | Where-Object { $_.HotFixID -eq "KB5072653" })) { $kbsMissing += "KB5072653" }

if ($kbsMissing.Count -gt 0) {
    Write-Host "Voraussetzungs-KBs fehlen: $($kbsMissing -join ', ')."
    exit 1
}

# --- 5. ESU nicht aktiv, Remediation erforderlich ---
Write-Host "ESU nicht aktiviert. KBs vorhanden, Aktivierung ausstehend."
exit 1
