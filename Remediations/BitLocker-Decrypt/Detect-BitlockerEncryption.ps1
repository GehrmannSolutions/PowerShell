<#
.SYNOPSIS
    Erkennt ob Laufwerke mit BitLocker verschluesselt sind.

.DESCRIPTION
    Prueft den BitLocker-Verschluesselungsstatus aller Laufwerke.
    Exit 1 = mindestens ein Laufwerk verschluesselt (Remediation wird ausgeloest).
    Exit 0 = kein Laufwerk verschluesselt (kein Handlungsbedarf).

.NOTES
    Author: Marius Gehrmann - Business IT Solutions
    Verwendung: Intune Proactive Remediation (Detection Script)
    Ausfuehrung: Im SYSTEM-Kontext, 64-Bit

.RELEASE NOTES
    V1.0, 24.02.2026 - Erstversion
    V1.1, 26.02.2026 - Alle Laufwerke pruefen, nicht nur C:
#>

try {
    $allVolumes = Get-BitLockerVolume -ErrorAction Stop

    $encryptedVolumes = $allVolumes | Where-Object {
        $_.VolumeStatus -notin "FullyDecrypted", "DecryptionInProgress"
    }

    if ($encryptedVolumes) {
        $details = ($encryptedVolumes | ForEach-Object {
            "$($_.MountPoint) (Status: $($_.VolumeStatus), Methode: $($_.EncryptionMethod))"
        }) -join ", "
        Write-Host "BitLocker aktiv auf: $details"
        exit 1
    }

    # Ggf. laufende Entschluesselungen melden
    $decrypting = $allVolumes | Where-Object { $_.VolumeStatus -eq "DecryptionInProgress" }
    if ($decrypting) {
        $details = ($decrypting | ForEach-Object {
            "$($_.MountPoint) ($($_.EncryptionPercentage)%)"
        }) -join ", "
        Write-Host "Entschluesselung laeuft bereits: $details"
    }
    else {
        Write-Host "Kein Laufwerk mit BitLocker verschluesselt."
    }

    exit 0
}
catch {
    Write-Host "Fehler bei BitLocker-Pruefung: $($_.Exception.Message)"
    exit 1
}
