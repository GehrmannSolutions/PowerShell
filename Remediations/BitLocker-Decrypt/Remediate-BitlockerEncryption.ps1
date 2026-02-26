<#
.SYNOPSIS
    Hebt die BitLocker-Verschluesselung auf allen Laufwerken auf.

.DESCRIPTION
    Deaktiviert BitLocker auf allen verschluesselten Laufwerken und startet
    die Entschluesselung. Der Vorgang laeuft im Hintergrund weiter, auch
    nach Neustart.

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Remediation Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 24.02.2026 - Erstversion
    V1.1, 26.02.2026 - Alle Laufwerke entschluesseln, nicht nur C:
#>

try {
    $allVolumes = Get-BitLockerVolume -ErrorAction Stop

    $encryptedVolumes = $allVolumes | Where-Object {
        $_.VolumeStatus -notin "FullyDecrypted", "DecryptionInProgress"
    }

    if (-not $encryptedVolumes) {
        Write-Host "Kein Laufwerk erfordert Entschluesselung."
        exit 0
    }

    $errors = @()

    foreach ($volume in $encryptedVolumes) {
        try {
            Disable-BitLocker -MountPoint $volume.MountPoint -ErrorAction Stop
            Write-Host "Entschluesselung gestartet auf $($volume.MountPoint)"
        }
        catch {
            $errors += "$($volume.MountPoint): $($_.Exception.Message)"
        }
    }

    if ($errors) {
        Write-Host "Fehler bei: $($errors -join '; ')"
        exit 1
    }

    exit 0
}
catch {
    Write-Host "Fehler bei BitLocker-Entschluesselung: $($_.Exception.Message)"
    exit 1
}
