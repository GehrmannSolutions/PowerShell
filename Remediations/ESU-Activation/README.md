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
| `Remediate-ESUActivation.ps1` | Installiert KBs und aktiviert ESU (MAK-Key als Variable oben im Skript) |

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
| ESU nicht aktiv | 1 | Remediation |

## Voraussetzungen

### 1. MAK-Key ins Skript eintragen

Den ESU MAK-Key **vor dem Upload in Intune** oben im Remediation-Skript eintragen:

```powershell
# === KONFIGURATION - MAK-Key hier eintragen ===
$makKey = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
# ==============================================
```

**Sicherheit:** Das Skript liegt in Intune und ist durch RBAC geschuetzt. Nur Nutzer mit der Intune-Admin-Rolle koennen es einsehen - identisches Schutzniveau wie jede andere Konfiguration in Intune.

> **Warum nicht per OMA-URI Custom Policy?**
> Der Intune Registry CSP (`./Device/Vendor/MSFT/Registry/...`) ist **deprecated** und unterstuetzt keine
> beliebigen Pfade unter `HKLM\SOFTWARE\`. Er funktioniert ausschliesslich mit Pfaden unter
> `SOFTWARE\Policies\` die von einem definierten CSP verwaltet werden. Microsoft bestaetigt dies
> explizit: *"I didn't find articles describing setting an arbitrary registry key via CSP."*
> Quelle: [Microsoft Q&A - Arbitrary Policy and general Registry keys via Intune](https://learn.microsoft.com/en-gb/answers/questions/1805419/arbitrary-policy-and-general-registry-keys-via-int)

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

1. MAK-Key in `Remediate-ESUActivation.ps1` eintragen (siehe Abschnitt Voraussetzungen)
2. **Endpunktanalyse** > **Proaktive Wartung** > **Skriptpaket erstellen**
3. Detection-Skript: `Detect-ESUActivation.ps1`
4. Remediation-Skript: `Remediate-ESUActivation.ps1` (mit eingetragenem MAK-Key)
5. Einstellungen:
   - Skript im 64-Bit-PowerShell ausfuehren: **Ja**
   - Skript mit angemeldeten Anmeldeinformationen ausfuehren: **Nein** (SYSTEM-Kontext)
6. Zeitplan: **Taeglich** (fuer Phase-Erkennung nach Neustart)
7. Zuweisung: Windows 10 Geraetegruppe

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
