<#
.SYNOPSIS
    Erkennt ob das Systemlaufwerk mit BitLocker verschluesselt ist.

.DESCRIPTION
    Prueft den BitLocker-Verschluesselungsstatus des Systemlaufwerks (C:).
    Exit 1 = verschluesselt (Remediation wird ausgeloest).
    Exit 0 = nicht verschluesselt (kein Handlungsbedarf).

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Detection Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 24.02.2026 - Erstversion
#>

try {
    $bitlockerVolume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop

    switch ($bitlockerVolume.VolumeStatus) {
        "FullyDecrypted" {
            Write-Host "BitLocker ist nicht aktiv auf C: - kein Handlungsbedarf."
            exit 0
        }
        "DecryptionInProgress" {
            Write-Host "BitLocker-Entschluesselung laeuft bereits auf C:."
            exit 0
        }
        default {
            # FullyEncrypted, EncryptionInProgress, etc.
            Write-Host "BitLocker ist aktiv auf C: (Status: $($bitlockerVolume.VolumeStatus), Methode: $($bitlockerVolume.EncryptionMethod))."
            exit 1
        }
    }
}
catch {
    Write-Host "Fehler bei BitLocker-Pruefung: $($_.Exception.Message)"
    exit 1
}
