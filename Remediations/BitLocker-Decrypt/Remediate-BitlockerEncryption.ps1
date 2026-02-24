<#
.SYNOPSIS
    Hebt die BitLocker-Verschluesselung auf dem Systemlaufwerk auf.

.DESCRIPTION
    Deaktiviert BitLocker auf C: und startet die Entschluesselung.
    Der Vorgang laeuft im Hintergrund weiter, auch nach Neustart.

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Remediation Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 24.02.2026 - Erstversion
#>

try {
    $bitlockerVolume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop

    if ($bitlockerVolume.VolumeStatus -eq "FullyDecrypted") {
        Write-Host "BitLocker ist bereits deaktiviert auf C:."
        exit 0
    }

    if ($bitlockerVolume.VolumeStatus -eq "DecryptionInProgress") {
        Write-Host "Entschluesselung laeuft bereits auf C: ($($bitlockerVolume.EncryptionPercentage)% noch verschluesselt)."
        exit 0
    }

    # BitLocker deaktivieren und Entschluesselung starten
    Disable-BitLocker -MountPoint "C:" -ErrorAction Stop

    Write-Host "BitLocker-Entschluesselung wurde gestartet auf C:."
    exit 0
}
catch {
    Write-Host "Fehler bei BitLocker-Entschluesselung: $($_.Exception.Message)"
    exit 1
}
