# ESU-Activation Remediation

Intune Proactive Remediation zur automatischen Aktivierung von Windows 10 Extended Security Updates (ESU).

## Uebersicht

Deckt den kompletten Prozess ab:
- Voraussetzungs-KBs pruefen und installieren
- Neustart koordinieren (BurntToast-Notification an den Benutzer)
- ESU per MAK-Key aktivieren (alle verfuegbaren Jahre)

## Skripte

| Datei | Zweck |
|---|---|
| `Detect-ESUActivation.ps1` | Prueft ob ESU aktiviert werden muss |
| `Remediate-ESUActivation.ps1` | Installiert KBs und aktiviert ESU |

## Mehrstufiger Ablauf (Phasen)

Die Remediation nutzt Registry-Flags unter `HKLM:\SOFTWARE\BusinessITSolutions\ESU` um den Fortschritt ueber Neustarts hinweg zu verfolgen:

| Phase | Bedeutung | Detection | Remediation |
|---|---|---|---|
| 0 | Noch nichts passiert | Exit 1 (non-compliant) | KBs pruefen/installieren |
| 1 | KBs installiert, Neustart ausstehend | Exit 0 (warte) | ESU aktivieren |
| 2 | ESU aktiviert | Exit 0 (compliant) | - |

## Detection-Logik

| Pruefung | Exit Code | Aktion |
|---|---|---|
| Kein Windows 10 | 0 | Nicht zustaendig |
| Windows 10 < 22H2 | 1 | Upgrade erforderlich |
| ESU bereits lizenziert | 0 | Keine |
| Phase 1 (Neustart ausstehend) | 0 | Warte auf Neustart |
| KBs fehlen | 1 | Remediation |
| MAK-Key fehlt | 1 | Remediation (meldet Fehler) |
| ESU nicht aktiv | 1 | Remediation |

## Voraussetzungen

### 1. MAK-Key per Intune bereitstellen

Der ESU MAK-Key muss ueber ein Intune Custom Configuration Profile (OMA-URI) in die Registry geschrieben werden:

**Intune > Geraete > Konfiguration > Erstellen > Windows 10 und hoeher > Benutzerdefiniert**

| Einstellung | Wert |
|---|---|
| Name | `ESU MAK-Key` |
| OMA-URI | `./Device/Vendor/MSFT/Registry/HKLM\SOFTWARE\BusinessITSolutions\ESU/MakKey` |
| Datentyp | `Zeichenfolge` |
| Wert | `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (Ihr ESU MAK-Key) |

**Alternativ:** PowerShell-Skript als Intune Platform Script:

```powershell
$registryPath = "HKLM:\SOFTWARE\BusinessITSolutions\ESU"
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}
Set-ItemProperty -Path $registryPath -Name "MakKey" -Value "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" -Type String -Force
```

### 2. MAK-Key beschaffen

1. [Microsoft 365 Admin Center](https://admin.microsoft.com) > **Billing** > **Your Products** > **Volume Licensing**
2. **View contracts** > License-ID auswaehlen > **View product keys**
3. Benoetigte Rolle: **Product Key Reader** oder **VL Administrator**

### 3. Voraussetzungs-KBs

Die folgenden KBs werden vom Remediation-Skript automatisch ueber Windows Update installiert:

| KB | Beschreibung |
|---|---|
| KB5066791 | Mindest-Update fuer Windows 10 22H2 |
| KB5072653 | ESU Licensing Preparation Package (muss nach KB5066791 installiert werden) |

Falls die automatische Installation fehlschlaegt, erhaelt der Benutzer eine Toast-Notification.

## Intune-Konfiguration

1. **Endpunktanalyse** > **Proaktive Wartung** > **Skriptpaket erstellen**
2. Detection-Skript: `Detect-ESUActivation.ps1`
3. Remediation-Skript: `Remediate-ESUActivation.ps1`
4. Einstellungen:
   - Skript im 64-Bit-PowerShell ausfuehren: **Ja**
   - Skript mit angemeldeten Anmeldeinformationen ausfuehren: **Nein** (SYSTEM-Kontext)
5. Zeitplan: **Taeglich** (fuer Phase-Erkennung nach Neustart)
6. Zuweisung: Windows 10 Geraetegruppe

## Benutzer-Benachrichtigung

Bei ausstehendem Neustart oder fehlenden Updates wird eine **BurntToast Toast-Notification** an den angemeldeten Benutzer gesendet. Das Skript:

1. Ermittelt den angemeldeten Benutzer ueber den Explorer-Prozess
2. Erstellt einen einmaligen Scheduled Task der als Benutzer laeuft
3. Der Task installiert bei Bedarf das BurntToast-Modul und zeigt die Notification an
4. Fallback auf `msg.exe` falls BurntToast nicht installiert werden kann

## ESU Activation IDs

| Jahr | Zeitraum | Activation ID |
|---|---|---|
| Year 1 | Nov 2025 - Okt 2026 | `f520e45e-7413-4a34-a497-d2765967d094` |
| Year 2 | Nov 2026 - Okt 2027 | `1043add5-23b1-4afb-9a0f-64343c8f3f8d` |
| Year 3 | Nov 2027 - Okt 2028 | `83d49986-add3-41d7-ba33-87c7bfb5c0fb` |

## Hinweise

- Das Remediation-Skript versucht **alle drei ESU-Jahre** zu aktivieren. Noch nicht verfuegbare Jahre werden ohne Fehler uebersprungen.
- ESU-Lizenzen sind **kumulativ**: Wer erst in Jahr 2 einsteigt, muss auch Jahr 1 nachkaufen.
- Die Remediation laeuft im **SYSTEM-Kontext** und benoetigt keine Benutzerinteraktion ausser dem Neustart.
- Preis: 61 USD/Geraet (Year 1), verdoppelt sich jaehrlich, max. 3 Jahre.
- **Kostenlos** fuer Azure VMs, Windows 365, Azure Virtual Desktop.

## Quellen (Microsoft)

- [ESU-Programm (Extended Security Updates) fuer Windows 10](https://learn.microsoft.com/de-de/windows/whats-new/extended-security-updates) - Uebersicht, Preise, FAQ
- [Enable Windows 10 Extended Security Updates (ESU)](https://learn.microsoft.com/en-us/windows/whats-new/enable-extended-security-updates) - Voraussetzungen, MAK-Key, Aktivierung per slmgr
- [KB5066791 - Cumulative Update fuer Windows 10 22H2](https://support.microsoft.com/help/5066791) - Mindest-Update
- [KB5072653 - ESU Licensing Preparation Package](https://support.microsoft.com/help/5072653) - Vorbereitungspaket fuer ESU-Lizenzierung
- [Windows 10 End of Support](https://www.microsoft.com/windows/end-of-support) - Allgemeine Informationen zum Supportende
- [Windows 10 Consumer ESU](https://www.microsoft.com/windows/extended-security-updates) - ESU fuer Privatpersonen
- [When to use Windows 10 Extended Security Updates](https://techcommunity.microsoft.com/blog/windows-itpro-blog/when-to-use-windows-10-extended-security-updates/4102628) - Microsoft Tech Community Blog
- [Volume Licensing Rollen (Product Key Reader / VL Administrator)](https://learn.microsoft.com/de-de/microsoft-365/commerce/licenses/manage-user-roles-vl) - Berechtigungen fuer MAK-Key Zugriff
- [slmgr.vbs Optionen](https://learn.microsoft.com/en-us/windows-server/get-started/activation-slmgr-vbs-options) - Referenz fuer Software Licensing Management Tool
- [VAMT Proxy Activation](https://learn.microsoft.com/en-us/windows/deployment/volume-activation/proxy-activation-vamt) - Massenaktivierung ohne Internet
- [Windows Lifecycle FAQ](https://learn.microsoft.com/de-de/lifecycle/faq/windows) - Lebenszyklus-Informationen
