# Intune Driver Injection Scripts

Sammlung von PowerShell-Skripten für die Installation, Deinstallation und Erkennung von Druckertreibern über Microsoft Intune.

## Übersicht

Diese drei Skripte ermöglichen die automatisierte Verwaltung von Druckertreibern in Windows über Intune Win32 Apps oder PowerShell-Skript-Deployments:

- **Install-DriverInjection.ps1** - Installiert einen Druckertreiber aus einer INF-Datei
- **Uninstall-DriverInjection.ps1** - Deinstalliert den Treiber aus dem Windows Driver Store
- **Detect-DriverInjection.ps1** - Erkennt, ob der Treiber bereits installiert ist

## Voraussetzungen

- Windows 10/11
- Administrative Rechte (Skripte laufen als SYSTEM in Intune)
- PowerShell 5.1 oder höher
- DISM PowerShell-Modul (normalerweise vorinstalliert)
- `pnputil.exe` (standardmäßig in Windows enthalten)

## Skript-Beschreibungen

### Install-DriverInjection.ps1

Installiert einen Druckertreiber-Paket in den Windows Driver Store mittels `pnputil.exe`.

**Funktionsweise:**
- Sucht nach der konfigurierten INF-Datei im gleichen Verzeichnis wie das Skript
- Verwendet `pnputil.exe /add-driver /install` zum Hinzufügen des Treibers
- Erstellt detaillierte Log-Dateien unter `C:\ProgramData\IntuneLogs\PrinterDriver`
- Exit Code 0 = Erfolg, Exit Code 1 = Fehler

### Uninstall-DriverInjection.ps1

Entfernt den Druckertreiber aus dem Windows Driver Store.

**Funktionsweise:**
- Durchsucht den Driver Store nach Treibern, deren `OriginalFileName` dem konfigurierten INF-Namen entspricht
- Verwendet `pnputil.exe /delete-driver /uninstall /force` zum Entfernen
- Behandelt automatisch "oem*.inf" Dateien (Windows benennt installierte Treiber um)
- Erstellt detaillierte Log-Dateien

### Detect-DriverInjection.ps1

Prüft, ob der Druckertreiber im System installiert ist.

**Funktionsweise:**
- Verwendet `Get-WindowsDriver` zum Abfragen des Driver Store
- Vergleicht den `OriginalFileName` mit dem konfigurierten INF-Namen
- Exit Code 0 = Treiber gefunden (installiert)
- Exit Code 1 = Treiber nicht gefunden (nicht installiert)

## Konfiguration

In jedem Skript muss die Variable `$DriverInfName` angepasst werden:

```powershell
# Name der INF-Datei (MUSS in allen drei Skripten identisch sein!)
$DriverInfName = 'KOAXGJ__.inf'
```

**Wichtig:** Der INF-Name muss in allen drei Skripten übereinstimmen!

## Verwendung in Microsoft Intune

### Als Win32 App (empfohlen für Treiber)

1. **Paket erstellen:**
   - Alle drei Skripte in einen Ordner legen
   - INF-Datei und alle benötigten Treiberdateien hinzufügen
   - Mit dem [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) als `.intunewin` verpacken

2. **App in Intune anlegen:**
   - **Install command:**
     ```cmd
     powershell.exe -ExecutionPolicy Bypass -File .\Install-DriverInjection.ps1
     ```
   - **Uninstall command:**
     ```cmd
     powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-DriverInjection.ps1
     ```
   - **Detection rule:**
     - Rule type: Custom (PowerShell script)
     - Script file: `Detect-DriverInjection.ps1`
     - Run script as 32-bit: NO

3. **Zuweisen:**
   - Required/Available nach Bedarf
   - Läuft automatisch als SYSTEM

### Als PowerShell-Skript (alternative Methode)

- **Run this script using the logged on credentials:** NO
- **Enforce script signature check:** Nach Bedarf
- **Run script in 64 bit PowerShell Host:** YES

## Standalone-Verwendung

Die Skripte können auch manuell ausgeführt werden:

```powershell
# Installation
.\Install-DriverInjection.ps1

# Deinstallation
.\Uninstall-DriverInjection.ps1

# Detection
.\Detect-DriverInjection.ps1
```

**Hinweis:** Erfordert administrative Rechte!

## Log-Dateien

Alle Skripte erstellen Log-Dateien unter:
```
C:\ProgramData\IntuneLogs\PrinterDriver\
```

**Log-Dateinamen:**
- `PrinterDriverInstall_YYYYMMDD.log`
- `PrinterDriverUninstall_YYYYMMDD.log`

Das Detection-Skript loggt nur zur Konsole (für Intune-Detection-Logs).

## Wichtige Hinweise

### OEM-INF Problem

Windows benennt installierte Treiber-INF-Dateien automatisch um:
- **Originaler Name:** `KOAXGJ__.inf`
- **Im Driver Store:** `oem123.inf` (Beispiel)

Die Skripte lösen dieses Problem durch:
1. **OriginalFileName-Eigenschaft:** `Get-WindowsDriver` speichert den ursprünglichen Pfad
2. **Dateinamen-Extraktion:** `Split-Path -Leaf` extrahiert nur den Dateinamen
3. **Case-insensitive Vergleich:** `-ieq` für Groß-/Kleinschreibung-unabhängigen Vergleich

### Driver Store Eigenschaften

Die `Get-WindowsDriver` Cmdlet liefert folgende relevante Eigenschaften:
- `OriginalFileName` - Vollständiger Pfad zur originalen INF (z.B. `C:\Windows\System32\DriverStore\FileRepository\koaxgj__.inf_amd64_...\koaxgj__.inf`)
- `Driver` - OEM-Name im Driver Store (z.B. `oem123.inf`)
- `ProviderName` - Hersteller des Treibers (z.B. "Konica Minolta")

### 32-bit vs 64-bit PowerShell

Die Skripte erkennen automatisch, ob sie in 32-bit PowerShell auf einem 64-bit System laufen und verwenden dann `sysnative` für den Zugriff auf `pnputil.exe`.

## Fehlerbehebung

### Treiber wird nicht erkannt, obwohl installiert

**Problem:** `OriginalFileName` enthält den vollständigen Pfad, nicht nur den Dateinamen.

**Lösung:** Die Skripte verwenden `Split-Path -Leaf`, um nur den Dateinamen zu extrahieren.

### "PublishedName" ist leer

**Problem:** Die Eigenschaft heißt `Driver`, nicht `PublishedName`.

**Lösung:** Alle Skripte verwenden jetzt die korrekte Eigenschaft `Driver`.

### pnputil.exe nicht gefunden

**Problem:** Bei 32-bit PowerShell auf 64-bit System wird `System32` zu `SysWOW64` umgeleitet.

**Lösung:** Die Skripte verwenden `sysnative`, um die echte `System32` zu erreichen.

### Installation schlägt fehl

1. Prüfen Sie die Log-Datei unter `C:\ProgramData\IntuneLogs\PrinterDriver\`
2. Stellen Sie sicher, dass alle Treiberdateien im gleichen Verzeichnis wie die INF-Datei liegen
3. Prüfen Sie, ob die INF-Datei korrekt signiert ist (bei aktivierter Treiberprüfung)

### Detection funktioniert nicht

1. Testen Sie die Detection manuell:
   ```powershell
   Get-WindowsDriver -Online -All | Where-Object { (Split-Path $_.OriginalFileName -Leaf) -ieq 'KOAXGJ__.inf' }
   ```
2. Prüfen Sie, ob `$DriverInfName` in allen drei Skripten identisch ist
3. Achten Sie auf Groß-/Kleinschreibung im Dateinamen

## Best Practices

1. **Versionierung:** Nutzen Sie Versionsnummern in Ihrem Intune-App-Namen (z.B. "Konica Minolta Driver v3.9")
2. **Testen:** Testen Sie die Skripte zuerst auf einem Test-System
3. **Logging:** Behalten Sie die Log-Dateien für Troubleshooting bei
4. **Dependencies:** Geben Sie in Intune ggf. Dependencies an (z.B. Windows-Version)
5. **Detection:** Verwenden Sie immer das Detection-Skript für zuverlässige Erkennung

## Autor

Marius Gehrmann

## Version

- V1.0, 10.12.2025 - Initiale Version
- V1.1, 10.12.2025 - Fix für OEM-INF Erkennung und Driver-Eigenschaft

## Lizenz

Diese Skripte werden ohne Gewährleistung bereitgestellt. Verwendung auf eigene Verantwortung.
