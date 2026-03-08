# Rename-PDF24Printer

Post-installation script for **Patch My PC** that renames the virtual printer installed by PDF24 Creator from `PDF24` to `FreePDF`.

## Background

PDF24 Creator installs a virtual printer named `PDF24`. This script is deployed as a post-installation action in Patch My PC to rename it to a standardized name (`FreePDF`) immediately after setup completes.

## Script

| Script | Function |
|---|---|
| `Rename-PDF24Printer.ps1` | Renames the `PDF24` printer to `FreePDF` |

## Usage

**Patch My PC – Post-Installation Script**

1. Open the Patch My PC Publisher
2. Navigate to the desired PDF24 Creator package
3. Under **Post-Installation Script**, reference `Rename-PDF24Printer.ps1`
4. Runs automatically in SYSTEM context after installation

**Manual execution:**

```powershell
.\Rename-PDF24Printer.ps1
```

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Printer successfully renamed |
| `1` | Printer not found or unexpected error |

## Requirements

| Requirement | Detail |
|---|---|
| PowerShell | 5.1+ |
| Permissions | Administrator / SYSTEM |
| Modules | None |
| Target app | PDF24 Creator (any version that installs the `PDF24` printer) |

## Author

Marius Gehrmann - Business IT Solutions
