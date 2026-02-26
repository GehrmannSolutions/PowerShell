<#
.SYNOPSIS
    Aktiviert Windows 10 ESU (Extended Security Updates).

.DESCRIPTION
    Mehrstufiger Ablauf mit Registry-Flags:
    Phase 0 -> 1: Voraussetzungs-KBs pruefen, bei Bedarf Neustart anfordern
    Phase 1 -> 2: ESU MAK-Key installieren und alle verfuegbaren Jahre aktivieren

    Der MAK-Key wird aus der Registry gelesen (per Intune OMA-URI bereitgestellt):
    HKLM:\SOFTWARE\BusinessITSolutions\ESU\MakKey

    Bei ausstehendem Neustart wird eine BurntToast-Notification an den
    angemeldeten Benutzer gesendet.

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Remediation Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 26.02.2026 - Erstversion
#>

$registryPath = "HKLM:\SOFTWARE\BusinessITSolutions\ESU"

# ESU Activation IDs
$esuYears = @(
    @{ Name = "Year 1"; ActivationId = "f520e45e-7413-4a34-a497-d2765967d094" }
    @{ Name = "Year 2"; ActivationId = "1043add5-23b1-4afb-9a0f-64343c8f3f8d" }
    @{ Name = "Year 3"; ActivationId = "83d49986-add3-41d7-ba33-87c7bfb5c0fb" }
)

# --- Hilfsfunktionen ---

function Set-ESUPhase {
    param([int]$Phase)
    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }
    Set-ItemProperty -Path $registryPath -Name "Phase" -Value $Phase -Type DWord -Force
}

function Get-ESUPhase {
    if (Test-Path $registryPath) {
        $val = (Get-ItemProperty -Path $registryPath -Name "Phase" -ErrorAction SilentlyContinue).Phase
        if ($null -ne $val) { return [int]$val }
    }
    return 0
}

function Test-PendingReboot {
    $pendingReboot = $false

    # Component Based Servicing
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $pendingReboot = $true
    }

    # Windows Update
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $pendingReboot = $true
    }

    # Pending File Rename Operations
    $pfro = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($pfro.PendingFileRenameOperations) {
        $pendingReboot = $true
    }

    return $pendingReboot
}

function Send-UserToast {
    param([string]$Title, [string]$Message)

    # Angemeldeten Benutzer ermitteln
    $explorerProcess = Get-Process -Name "explorer" -IncludeUserName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $explorerProcess) {
        Write-Host "Kein angemeldeter Benutzer gefunden - Toast kann nicht angezeigt werden."
        return
    }

    $loggedOnUser = $explorerProcess.UserName
    Write-Host "Angemeldeter Benutzer: $loggedOnUser"

    # Scheduled Task erstellen der als angemeldeter User laeuft
    $toastScript = @"
try {
    # BurntToast installieren falls nicht vorhanden
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Install-Module -Name BurntToast -Force -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module BurntToast -ErrorAction Stop

    `$text1 = New-BTText -Text '$Title'
    `$text2 = New-BTText -Text '$Message'
    `$binding = New-BTBinding -Children `$text1, `$text2
    `$visual = New-BTVisual -BindingGeneric `$binding
    `$content = New-BTContent -Visual `$visual

    Submit-BTNotification -Content `$content
}
catch {
    # Fallback: msg.exe
    msg.exe * /TIME:120 "$Title - $Message"
}
"@

    $scriptPath = "$env:ProgramData\BusinessITSolutions\ESU-Toast.ps1"
    $scriptDir = Split-Path $scriptPath -Parent
    if (-not (Test-Path $scriptDir)) {
        New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
    }
    $toastScript | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

    # Einmaligen Scheduled Task erstellen
    $taskName = "BusinessITSolutions-ESU-Toast"

    # Bestehenden Task entfernen falls vorhanden
    schtasks.exe /Delete /TN $taskName /F 2>$null

    # Task als angemeldeter User erstellen und sofort ausfuehren
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User $loggedOnUser -RunLevel Limited -Force | Out-Null

    Write-Host "Toast-Notification geplant fuer Benutzer $loggedOnUser."
}

function Install-KBViaWindowsUpdate {
    param([string]$KBNumber)

    Write-Host "Versuche $KBNumber ueber Windows Update zu installieren..."

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searchResult = $searcher.Search("IsInstalled=0 AND Type='Software'")

        $targetUpdate = $null
        foreach ($update in $searchResult.Updates) {
            foreach ($kb in $update.KBArticleIDs) {
                if ($kb -eq $KBNumber.Replace("KB", "")) {
                    $targetUpdate = $update
                    break
                }
            }
            if ($targetUpdate) { break }
        }

        if (-not $targetUpdate) {
            Write-Host "$KBNumber wurde nicht in den verfuegbaren Updates gefunden."
            return $false
        }

        Write-Host "$KBNumber gefunden: $($targetUpdate.Title). Starte Download und Installation..."

        $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        $updatesToDownload.Add($targetUpdate) | Out-Null

        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToDownload
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -ne 2) {
            Write-Host "Download von $KBNumber fehlgeschlagen (ResultCode: $($downloadResult.ResultCode))."
            return $false
        }

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        $updatesToInstall.Add($targetUpdate) | Out-Null

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        if ($installResult.ResultCode -eq 2) {
            Write-Host "$KBNumber erfolgreich installiert."
            return $true
        }
        else {
            Write-Host "Installation von $KBNumber fehlgeschlagen (ResultCode: $($installResult.ResultCode))."
            return $false
        }
    }
    catch {
        Write-Host "Fehler bei Windows Update Installation von $KBNumber : $($_.Exception.Message)"
        return $false
    }
}

# === Hauptlogik ===

try {
    # --- Vorpruefung: Windows 10 22H2? ---
    $build = [System.Environment]::OSVersion.Version
    if ($build.Major -ne 10 -or $build.Build -ge 22000) {
        Write-Host "Kein Windows 10 - ESU nicht zustaendig."
        exit 0
    }

    if ($build.Build -lt 19045) {
        Write-Host "Windows 10 ist nicht auf Version 22H2 (Build: $($build.Build)). Upgrade auf 22H2 erforderlich bevor ESU aktiviert werden kann."
        exit 1
    }

    # --- MAK-Key aus Registry lesen ---
    $makKey = $null
    if (Test-Path $registryPath) {
        $makKey = (Get-ItemProperty -Path $registryPath -Name "MakKey" -ErrorAction SilentlyContinue).MakKey
    }

    if ([string]::IsNullOrWhiteSpace($makKey)) {
        Write-Host "ESU MAK-Key nicht in Registry vorhanden ($registryPath\MakKey). Bitte per Intune OMA-URI bereitstellen."
        exit 1
    }

    # --- Aktuelle Phase ermitteln ---
    $currentPhase = Get-ESUPhase

    # --- Phase 0/1: KBs pruefen und ggf. installieren ---
    if ($currentPhase -lt 2) {
        $hotfixes = Get-HotFix -ErrorAction SilentlyContinue
        $needsReboot = $false
        $kbsMissing = @()

        # KB5066791 pruefen
        $hasKB5066791 = $hotfixes | Where-Object { $_.HotFixID -eq "KB5066791" }
        if (-not $hasKB5066791) {
            Write-Host "KB5066791 fehlt. Versuche Installation..."
            $installed = Install-KBViaWindowsUpdate -KBNumber "KB5066791"
            if ($installed) {
                $needsReboot = $true
            }
            else {
                $kbsMissing += "KB5066791"
            }
        }
        else {
            Write-Host "KB5066791 ist installiert."
        }

        # KB5072653 pruefen (muss nach KB5066791 installiert werden)
        $hasKB5072653 = $hotfixes | Where-Object { $_.HotFixID -eq "KB5072653" }
        if (-not $hasKB5072653) {
            if ($kbsMissing.Count -eq 0) {
                Write-Host "KB5072653 fehlt. Versuche Installation..."
                $installed = Install-KBViaWindowsUpdate -KBNumber "KB5072653"
                if ($installed) {
                    $needsReboot = $true
                }
                else {
                    $kbsMissing += "KB5072653"
                }
            }
            else {
                # KB5066791 konnte nicht installiert werden, KB5072653 haengt davon ab
                $kbsMissing += "KB5072653"
            }
        }
        else {
            Write-Host "KB5072653 ist installiert."
        }

        # Falls KBs nicht installiert werden konnten
        if ($kbsMissing.Count -gt 0) {
            Write-Host "Folgende KBs konnten nicht installiert werden: $($kbsMissing -join ', '). Bitte Windows Updates manuell installieren."
            Send-UserToast -Title "Windows Update erforderlich" -Message "Bitte installieren Sie alle ausstehenden Windows Updates und starten Sie den Computer neu. Fehlend: $($kbsMissing -join ', ')"
            exit 1
        }

        # Pruefen ob Neustart noetig ist
        if ($needsReboot -or (Test-PendingReboot)) {
            Write-Host "Neustart erforderlich nach KB-Installation. Setze Phase auf 1."
            Set-ESUPhase -Phase 1
            Send-UserToast -Title "Neustart erforderlich" -Message "Fuer die Aktivierung der erweiterten Sicherheitsupdates (ESU) ist ein Neustart erforderlich. Bitte starten Sie Ihren Computer zeitnah neu."
            exit 0
        }
    }

    # --- Phase 1 -> 2: ESU aktivieren ---
    Write-Host "Starte ESU-Aktivierung mit MAK-Key..."

    # MAK-Key installieren
    $ipkOutput = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /ipk $makKey 2>&1 | Out-String
    Write-Host "slmgr /ipk: $($ipkOutput.Trim())"

    if ($ipkOutput -match "error|fehler" -and $ipkOutput -notmatch "successfully|erfolgreich") {
        Write-Host "Fehler bei der Installation des ESU MAK-Keys."
        exit 1
    }

    # Alle ESU-Jahre aktivieren
    $activatedCount = 0
    foreach ($year in $esuYears) {
        Write-Host "Versuche ESU $($year.Name) zu aktivieren (ID: $($year.ActivationId))..."

        $atoOutput = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /ato $($year.ActivationId) 2>&1 | Out-String
        Write-Host "slmgr /ato $($year.Name): $($atoOutput.Trim())"

        if ($atoOutput -match "successfully|erfolgreich") {
            Write-Host "ESU $($year.Name) erfolgreich aktiviert."
            $activatedCount++
        }
        else {
            Write-Host "ESU $($year.Name) konnte nicht aktiviert werden (ggf. noch nicht verfuegbar)."
        }
    }

    if ($activatedCount -eq 0) {
        Write-Host "Keine ESU-Jahre konnten aktiviert werden."
        exit 1
    }

    # Aktivierung verifizieren
    $verifyOutput = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /dlv $($esuYears[0].ActivationId) 2>&1 | Out-String
    if ($verifyOutput -match "License Status:\s*Licensed" -or $verifyOutput -match "Lizenzstatus:\s*Lizenziert") {
        Write-Host "ESU-Aktivierung erfolgreich verifiziert."
        Set-ESUPhase -Phase 2
        exit 0
    }
    else {
        Write-Host "ESU-Aktivierung konnte nicht verifiziert werden."
        Write-Host $verifyOutput
        exit 1
    }
}
catch {
    Write-Host "Fehler bei ESU-Remediation: $($_.Exception.Message)"
    exit 1
}
