# Intune Policy Assignment Manager

Interaktives PowerShell-Script zum Massenneuzuweisen von Intune-Policies auf
**All Users** oder **All Devices** – mit optionalen Assignment Filtern und
integrierter Empfehlungslogik für sichere Autopilot-Deployments.

---

## Hintergrund & Motivation

### Das Problem: RebootRequired und Autopilot

Während eines Windows Autopilot-Deployments durchläuft das Gerät den
**Enrollment Status Page (ESP)** in zwei aufeinanderfolgenden Phasen:

```
┌─────────────────────────────────────────────────────────────────┐
│  DEVICE SETUP PHASE                                             │
│  (läuft vor dem User Login, als SYSTEM)                         │
│                                                                 │
│  → Hier greifen: All Devices Zuweisungen                        │
│  → MDM-Policies werden angewendet                               │
│  → Reboot-Risiko: HOCH                                          │
├─────────────────────────────────────────────────────────────────┤
│  ACCOUNT SETUP PHASE                                            │
│  (läuft nach dem User Login)                                    │
│                                                                 │
│  → Hier greifen: All Users Zuweisungen                          │
│  → Reboot-Risiko: GERING (User ist bereits angemeldet)          │
└─────────────────────────────────────────────────────────────────┘
```

Bestimmte MDM-Policies setzen nach ihrer Anwendung den Registry-Schlüssel:

```
HKLM\SOFTWARE\Microsoft\Provisioning\OMADM\SyncML\RebootRequired
```

Sobald Intune dieses Flag erkennt, leitet es **während der Device Setup Phase
einen Neustart ein** – noch bevor der Benutzer seinen Account eingerichtet hat.

### Warum das ein echtes Problem ist

Dieses Szenario ist besonders kritisch, wenn das Onboarding auf
**Windows Hello for Business (WHfB) mit Passwordless Authentication** setzt:

- Der Benutzer erhält beim Onboarding nur seine **E-Mail-Adresse** sowie
  einen vom Admin in Entra ID generierten **Temporary Access Pass (TAP)**
  als Passwort- und MFA-Ersatz.
- Der TAP hat eine begrenzte Gültigkeitsdauer und ist für einen einmaligen
  Gebrauch ausgelegt, beziehungsweise kann in der klassischen Windows Anmeldung nicht verwendet werden.
- Der unerwartete Reboot in der Device Phase **unterbricht den WHfB-Setup-Flow**.
  Der Benutzer muss sich erneut authentifizieren – oft ist der TAP aber bereits
  verbraucht oder abgelaufen.
- Das Ergebnis: Ein **fehlgeschlagenes, halbfertiges Onboarding**, das manuellen
  Eingriff durch den Administrator erfordert.

### Die Lösung: All Users statt All Devices

Policies, die mit **All Users** zugewiesen werden, greifen erst in der
**Account Setup Phase** – also nach dem Device Setup und nach dem ersten
User Login. Sie können daher in der kritischen Device Phase **keinen Neustart
auslösen**.

Für Policies, die zwingend vor dem User Login aktiv sein müssen (z.B. BitLocker,
Netzwerkkonfiguration), bleibt **All Devices** die richtige Wahl – idealerweise
kombiniert mit einem **Assignment Filter**, der Autopilot-Geräte während des
Enrollments gezielt ein- oder ausschließt.

---

### Credits & weiterführende Quellen

Die Erkenntnisse über den RebootRequired-Mechanismus und dessen Auswirkungen
auf Autopilot stammen maßgeblich aus der hervorragenden Arbeit von **Rudy Ooms**
(auch bekannt als "Call4Cloud"):

> **"Autopilot Unexpected Reboot – What Really Triggers a Device Restart
> and How to Fix It?"**
> Rudy Ooms, Patch My PC Blog
> https://patchmypc.com/blog/autopilot-unexpected-reboot-what-really-triggers-a-device-restart-and-how-to-fix-it/

Rudy hat mit seiner Analyse tiefgreifend aufgeschlüsselt, welche Policy-Typen
und CSP-Einstellungen das RebootRequired-Flag setzen, wie der interne Intune
Management Agent (IME) darauf reagiert und wie man das Verhalten durch
Assignment-Strategien kontrollieren kann. Herzlichen Dank für diese Arbeit,
die diese Lösung erst möglich gemacht hat.

---

## Was das Script macht

Das Script lädt alle Policies aus drei Quellen – und filtert dabei automatisch auf **Windows-Policies**:

| Quelle | API-Endpunkt | Windows-Filter | Enthält |
|--------|-------------|----------------|---------|
| **Settings Catalog** | `deviceManagement/configurationPolicies` | `platforms -match 'windows'` | Moderne Konfigurationspolicies inkl. neuer Endpoint Security |
| **Device Configurations** | `deviceManagement/deviceConfigurations` | `@odata.type -match 'windows'` | Klassische/Legacy Konfigurationsprofile |
| **Endpoint Security Intents** | `deviceManagement/intents` | Template-Lookup: `platformType -match 'windows'` | Ältere, Template-basierte Endpoint Security Policies |

Policies anderer Plattformen (macOS, iOS, Android, Linux) werden ignoriert.

Nach dem Laden wählt der Administrator einen **Bearbeitungsmodus**:

| Modus | Beschreibung |
|-------|-------------|
| **[1] Manuell** | Zuweisungsart pro Policy selbst wählen, Filter-Auswahl pro Policy |
| **[2] Auto** | Empfehlung automatisch anwenden, Filter-Auswahl pro Policy |
| **[3] Auto+** | Empfehlung automatisch anwenden, ohne Filter-Auswahl (schnellster Modus) |

In allen Modi kann jede einzelne Policy mit **[S]** übersprungen werden.

Für jede Policy wird (je nach Modus) abgefragt:

1. **Zuweisungsart** – All Users oder All Devices (immer mit Empfehlung angezeigt)
2. **Assignment Filter** – Auswahl aus allen im Tenant vorhandenen Filtern (entfällt bei Auto+)
3. **Filter-Typ** – Include oder Exclude
4. **Bestätigung** – Zusammenfassung vor dem Schreiben (entfällt im Auto-Modus)

Am Ende wird ein **CSV-Protokoll** aller vorgenommenen Änderungen gespeichert.

---

## Empfehlungslogik

Das Script berechnet pro Policy eine Empfehlung basierend auf Template-Familie
und Policy-Name:

| Erkennungsmerkmal | Empfehlung | Begründung |
|---|---|---|
| Endpoint Security Template (`endpointSecurity*`) | **All Users** | Häufige Auslöser für RebootRequired in der Device Phase |
| Endpoint Security Disk Encryption | **All Devices** | BitLocker muss vor dem User Login aktiv sein |
| Endpoint Security Intents (Legacy) | **All Users** | Gleiches Reboot-Risiko wie neue ES-Policies |
| Name enthält `Update`, `WUfB`, `Windows Update` | **All Users** | Update-Policies setzen regelmäßig RebootRequired |
| Name enthält `DomainJoin`, `Domain Join`, `HybridJoin`, `HAADJ` | **All Devices** | Hybrid Entra Join muss in der Device Phase konfiguriert werden – zwingend vor dem User Login |
| Name enthält `BitLocker`, `Encryption`, `Verschlüsselung` | **All Devices** | Muss vor dem User Login greifen |
| Name enthält `WiFi`, `VPN`, `SCEP`, `PKCS`, `Certificate` | **All Devices** | Netzwerk/Zertifikate werden in der Device Phase benötigt |
| Alles andere | **All Users** | Vorsichtsempfehlung für sicheres Autopilot-Deployment |

> **Hinweis:** Die Empfehlung ist eine Heuristik auf Basis von Name und
> Template-Familie. Die finale Entscheidung liegt beim Administrator –
> das Script fragt vor jeder Änderung explizit nach Bestätigung.

---

## Voraussetzungen

### PowerShell-Module

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
```

### Microsoft Graph Berechtigungen

Das Script benötigt folgende Delegated Permissions (interaktiver Login):

| Permission | Verwendung |
|-----------|-----------|
| `DeviceManagementConfiguration.ReadWrite.All` | Lesen und Schreiben von Configuration Policies & Device Configurations |
| `DeviceManagementManagedDevices.ReadWrite.All` | Lesen und Schreiben von Endpoint Security Intents |

---

## Verwendung

### Alle Policies bearbeiten

```powershell
.\Set-IntunePolicyAssignment.ps1
```

Das Script fragt nach dem Laden zunächst, ob alle gefundenen Windows-Policies bearbeitet
werden sollen. Danach wird der **Bearbeitungsmodus** gewählt:

```
  Zuweisungsart-Modus:
  [1] Manuell – Zuweisungsart pro Policy selbst wählen
  [2] Auto    – Empfehlung automatisch anwenden, Filter pro Policy abfragen
  [3] Auto+   – Empfehlung automatisch anwenden, ohne Filter (schnellster Modus)
```

**Manuell [1]** – Klassischer interaktiver Modus: Pro Policy Zuweisungsart wählen, Filter
auswählen und explizit mit J/N bestätigen.

**Auto [2]** – Das Script wendet die berechnete Empfehlung automatisch an. Pro Policy wird
nur noch der optionale Assignment Filter abgefragt. Mit `[Enter]` bestätigen oder `[S]`
zum Überspringen.

**Auto+ [3]** – Schnellster Modus: Empfehlung wird sofort gesetzt, keine Filter-Auswahl.
Nur `[Enter]` oder `[S]` pro Policy nötig. Geeignet für schnelle Massenneuzuweisung.

---

### Nur Endpoint Security Policies

```powershell
.\Set-IntunePolicyAssignment.ps1 -NurEndpointSecurity
```

### Nur Settings Catalog Policies

```powershell
.\Set-IntunePolicyAssignment.ps1 -NurConfigurationPolicies
```

### Nur Legacy Device Configurations

```powershell
.\Set-IntunePolicyAssignment.ps1 -NurDeviceConfigurations
```

### Testlauf ohne Änderungen (WhatIf)

```powershell
.\Set-IntunePolicyAssignment.ps1 -WhatIf
```

### Benutzerdefinierter Exportpfad für das Protokoll

```powershell
.\Set-IntunePolicyAssignment.ps1 -ExportPfad "C:\Logs\IntuneAssignment.csv"
```

---

## Ausgabe & Protokoll

### Konsolenausgabe (Beispiel)

```
━━━ Endpoint Security (Settings Catalog)

──────────────────────────────────────────────────────────────────────
[3/47] Intune_EndpointProtection_Standard_WIN
  Kategorie:  Endpoint Security (Settings Catalog)
  Template:   endpointSecurityEndpointProtection
  Aktuell:    Gruppe: a3f82c1b...

  ✓ EMPFEHLUNG: AllUsers
    Endpoint Security Policies können OMADM RebootRequired setzen.
    All Users verhindert Ausführung in der Autopilot Device Phase.

  Neue Zuweisungsart:
  [1] All Users ← Empfohlen
  [2] All Devices
  [S] Überspringen
```

### CSV-Protokoll

Das Protokoll enthält pro geänderter Policy folgende Felder:

| Feld | Beschreibung |
|------|-------------|
| `Timestamp` | Zeitpunkt der Änderung |
| `PolicyName` | Anzeigename der Policy |
| `PolicyId` | GUID der Policy |
| `PolicyType` | API-Endpunkt-Typ |
| `Kategorie` | Anzeigekategorie |
| `NeueZuweisung` | AllUsers oder AllDevices |
| `FilterName` | Name des gewählten Filters (leer = kein Filter) |
| `FilterId` | GUID des Filters |
| `FilterTyp` | include, exclude oder none |
| `Empfehlung` | Berechnete Empfehlung des Scripts |
| `EmpfehlungGefolgt` | True/False – wurde der Empfehlung gefolgt? |

---

## Microsofts offizielle Empfehlungen zur Zuweisung

> Quellen: [Assign device profiles in Microsoft Intune](https://learn.microsoft.com/en-us/mem/intune/configuration/device-profile-assign) und
> [Create assignment filters](https://learn.microsoft.com/en-us/mem/intune/fundamentals/filters)
> (Stand: Februar 2026)

### All Devices vs. All Users – wann was?

Microsoft empfiehlt die Entscheidung anhand einer klaren Grundregel:

| Frage | Empfehlung |
|-------|-----------|
| Sollen die Einstellungen **immer auf dem Gerät** aktiv sein, unabhängig davon wer angemeldet ist? | **All Devices** (Gerätezuweisung) |
| Sollen die Einstellungen **dem Benutzer folgen**, egal auf welchem Gerät er sich anmeldet? | **All Users** (Benutzerzuweisung) |

#### Wann All Devices (Gerätezuweisung)?

Microsoft nennt folgende typische Szenarien:
- Geräte **ohne dedizierten Benutzer** (Kiosk, geteilte Geräte, Schicht-/Lagergeräte)
- **DFCI/BIOS-Profile** – Hardware-Einstellungen, die vor dem User-Login aktiv sein müssen
- **BitLocker/Verschlüsselung** – muss vor der Benutzeranmeldung greifen
- **Browser-Einstellungen** (z.B. Edge), die auf einem Gerät für alle Benutzer gelten sollen
- **Userless-Enrollments** (Shared iPad, Microsoft Entra Shared Device Mode)

#### Wann All Users (Benutzerzuweisung)?

Microsoft nennt folgende typische Szenarien:
- **E-Mail-Profile** – folgen dem Benutzer auf alle seine Geräte
- **Benutzerzertifikate** (SCEP/PKCS aus Benutzersicht)
- **App-Einstellungen** (OneDrive, Office) – die für einen Benutzer auf all seinen Geräten gelten sollen
- **Geräte, die der Benutzer selbst registriert** und mit seinem Domänenkonto anmeldet
- Allgemein: alles, was zu einem **Feature des Benutzers** gehört

---

### Windows CSP Scope – Gerät oder Benutzer?

Windows-Policies basieren auf **Configuration Service Providers (CSPs)**. Diese sind
intern entweder im **Device Scope** oder **User Scope** verankert:

- **Device Scope CSPs** → müssen an **Gerätegruppen** (All Devices) zugewiesen werden
- **User Scope CSPs** → müssen an **Benutzergruppen** (All Users) zugewiesen werden

Werden sie falsch zugewiesen, können Einstellungen nicht oder nicht korrekt angewendet
werden. Im Intune Settings Catalog ist in der Einstellungsbeschreibung jeweils
angegeben, ob eine Einstellung geräte- oder benutzerbezogen ist.

> Weiterführend: [Device scope vs. user scope settings](https://learn.microsoft.com/en-us/mem/intune/configuration/settings-catalog#device-scope-vs-user-scope-settings)

---

### Assignment Filter – Microsofts Best Practices

#### Wann Filter statt Gruppen?

Microsoft empfiehlt Filter insbesondere in **latenz-sensitiven Szenarien** wie
dem Autopilot-Enrollment:

> *"In latency-sensitive scenarios, use assignment filters to target specific
> devices, and assign your policies to user groups. Don't assign to device groups."*
> — Microsoft Learn

**Hintergrund:** Dynamische Microsoft Entra Gerätegruppen haben beim Enrollment eine
Berechnungslatenz. Das Gerät kann Policies empfangen, **bevor** die Gruppenmitgliedschaft
berechnet wurde. Das führt dazu, dass Ausschlussgruppen noch nicht greifen und
ungewünschte Policies ausgerollt werden.

Assignment Filter hingegen werden **direkt beim Geräte-Check-in ausgewertet** –
ohne Latenz.

#### Filterregel: Autopilot-Geräte gezielt steuern

Um Policies während des Autopilot-Enrollments auszuschließen oder einzuschließen,
empfiehlt sich der Filter auf Basis des `enrollmentProfileName`:

```
(device.enrollmentProfileName -eq "Autopilot-Profil-Name")
```

Damit lassen sich z.B. Policies, die RebootRequired setzen könnten, für
Autopilot-Geräte während des Deployments gezielt **excluden**.

#### Technische Limits

| Limit | Wert |
|-------|------|
| Maximale Anzahl Filter pro Tenant | **200** |
| Maximale Zeichenlänge pro Filter | **3.072 Zeichen** |
| Geräte müssen in Intune enrolled sein | Ja |

#### Unterstützte Gruppenkonstellationen (Auszug)

Microsoft dokumentiert genau, welche Include/Exclude-Kombinationen unterstützt werden:

| Szenario | Support |
|----------|---------|
| Dynamische Gerätegruppe **include** + dynamische Gerätegruppe **exclude** | ⚠ Teilweise – nicht empfohlen bei Autopilot (Latenz) |
| Statische Gerätegruppe **include** + statische Gerätegruppe **exclude** | ✅ Unterstützt |
| Dynamische Benutzergruppe **include** + Gerätegruppe **exclude** | ❌ Nicht unterstützt |
| Benutzergruppe **include** + Benutzergruppe **exclude** | ✅ Unterstützt |

> Vollständige Matrix: [Assign device profiles – Exclude groups](https://learn.microsoft.com/en-us/mem/intune/configuration/device-profile-assign#exclude-groups-from-a-policy-assignment)

---

### Gesamtempfehlung für Autopilot-Umgebungen (Microsoft + Praxis)

Kombiniert aus Microsofts offizieller Dokumentation und den Erkenntnissen aus dem
RebootRequired-Problem ergibt sich folgende Empfehlung:

```
┌────────────────────────────────────────────────────────────────────┐
│  Policy muss vor User-Login aktiv sein?                            │
│  (BitLocker, Netzwerk, BIOS)                                       │
│                                                                    │
│   JA  → All Devices + Assignment Filter (ggf. Autopilot exclude)   │
│   NEIN → All Users  (greift erst in User Phase → kein Reboot)      │
├────────────────────────────────────────────────────────────────────┤
│  Niemals: Dynamische Gerätegruppen als Exclude in Autopilot-       │
│  Szenarien → Latenz führt zu ungewollten Deployments!              │
│  Stattdessen: Assignment Filter nutzen                             │
└────────────────────────────────────────────────────────────────────┘
```

---

## Weiterführende Dokumentation (Microsoft Learn)

### Windows Autopilot & ESP

| Thema | Link |
|-------|------|
| Übersicht Windows Autopilot | https://learn.microsoft.com/en-us/autopilot/windows-autopilot |
| Enrollment Status Page (ESP) – Konfiguration & Verhalten | https://learn.microsoft.com/en-us/autopilot/enrollment-status |
| Troubleshooting Autopilot-Deployments | https://learn.microsoft.com/en-us/autopilot/troubleshooting-faq |
| Autopilot-Szenarien (User-driven, Self-deploying, Pre-provisioning) | https://learn.microsoft.com/en-us/autopilot/tutorial/autopilot-scenarios |

### Intune Zuweisungen & Filter

| Thema | Link |
|-------|------|
| Geräteprofile zuweisen – All Users / All Devices / Gruppen | https://learn.microsoft.com/en-us/mem/intune/configuration/device-profile-assign |
| Assignment Filter erstellen und verwenden | https://learn.microsoft.com/en-us/mem/intune/fundamentals/filters |
| Unterstützte Filter-Eigenschaften (enrollmentProfileName, etc.) | https://learn.microsoft.com/en-us/mem/intune/fundamentals/filters-device-properties |
| Filter-Ausdruckssyntax | https://learn.microsoft.com/en-us/mem/intune/fundamentals/filters-supported-workloads |

### Endpoint Security

| Thema | Link |
|-------|------|
| Endpoint Security Policies – Übersicht | https://learn.microsoft.com/en-us/mem/intune/protect/endpoint-security |
| Endpoint Protection (Defender, Firewall, ASR) | https://learn.microsoft.com/en-us/mem/intune/protect/endpoint-security-edr-policy |
| Attack Surface Reduction (ASR) Rules | https://learn.microsoft.com/en-us/mem/intune/protect/endpoint-security-asr-policy |
| Antivirus-Policies in Intune | https://learn.microsoft.com/en-us/mem/intune/protect/endpoint-security-antivirus-policy |
| BitLocker-Verschlüsselung via Intune | https://learn.microsoft.com/en-us/mem/intune/protect/encrypt-devices |

### Windows Hello for Business & Passwordless

| Thema | Link |
|-------|------|
| Windows Hello for Business – Übersicht | https://learn.microsoft.com/en-us/windows/security/identity-protection/hello-for-business/ |
| WHfB in Intune konfigurieren | https://learn.microsoft.com/en-us/mem/intune/protect/windows-hello |
| Passwordless Authentication in Microsoft Entra ID | https://learn.microsoft.com/en-us/entra/identity/authentication/concept-authentication-passwordless |
| Temporary Access Pass (TAP) einrichten | https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-temporary-access-pass |
| TAP und WHfB im Onboarding kombinieren | https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-temporary-access-pass#use-a-temporary-access-pass |

### Microsoft Graph API (verwendete Endpunkte)

| Ressource | Link |
|-----------|------|
| `deviceManagement/configurationPolicies` (Settings Catalog) | https://learn.microsoft.com/en-us/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy |
| `deviceManagement/deviceConfigurations` (Legacy) | https://learn.microsoft.com/en-us/graph/api/resources/intune-deviceconfig-deviceconfiguration |
| `deviceManagement/intents` (Endpoint Security Legacy) | https://learn.microsoft.com/en-us/graph/api/resources/intune-deviceintent-devicemanagementintent |
| `deviceManagement/assignmentFilters` | https://learn.microsoft.com/en-us/graph/api/resources/intune-policyset-deviceandappmanagementassignmentfilter |
| Assignment Target Types (allDevices, allLicensedUsers) | https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-alldevicesassignmenttarget |
| Graph Explorer (interaktives Testen) | https://developer.microsoft.com/en-us/graph/graph-explorer |

---

## Autor

**Marius Gehrmann**
Business IT Solutions
marius@gehrmann.io
