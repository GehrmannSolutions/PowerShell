# BitLocker-Decrypt Remediation

Intune Proactive Remediation zum Aufheben der BitLocker-Verschluesselung auf dem Systemlaufwerk (C:).

## Skripte

| Datei | Zweck |
|---|---|
| `Detect-BitlockerEncryption.ps1` | Prueft ob BitLocker auf C: aktiv ist |
| `Remediate-BitlockerEncryption.ps1` | Deaktiviert BitLocker und startet die Entschluesselung |

## Detection-Logik

| Status | Exit Code | Aktion |
|---|---|---|
| Nicht verschluesselt | 0 | Keine |
| Entschluesselung laeuft | 0 | Keine |
| Verschluesselt | 1 | Remediation wird ausgeloest |

## Intune-Konfiguration

1. **Endpunktanalyse** > **Proaktive Wartung** > **Skriptpaket erstellen**
2. Detection-Skript: `Detect-BitlockerEncryption.ps1`
3. Remediation-Skript: `Remediate-BitlockerEncryption.ps1`
4. Einstellungen:
   - Skript im 64-Bit-PowerShell ausfuehren: **Ja**
   - Skript mit angemeldeten Anmeldeinformationen ausfuehren: **Nein** (SYSTEM-Kontext)
5. Zeitplan: Stuendlich oder taeglich, je nach Dringlichkeit

## Hinweise

- Die Entschluesselung laeuft im Hintergrund und uebersteht Neustarts.
- Je nach Festplattengroesse und -auslastung kann der Vorgang mehrere Stunden dauern.
- Die Recovery Keys in Entra ID / Intune bleiben erhalten, werden aber nach der Entschluesselung nicht mehr benoetigt.
