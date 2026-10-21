# GPO exports

One folder per GPO, produced by [`scripts/export-gpos.ps1`](../scripts/export-gpos.ps1) on DC01:

| File | Use |
|---|---|
| `report.html` | Human-readable settings, same view as GPMC → *Settings* |
| `report.xml` | Same report as XML — the format Intune **Group Policy analytics** imports (Phase 4) |
| `{GUID}/` + `manifest.xml` | `Backup-GPO` output; restore with `Import-GPO` or GPMC |

The GPMC-built GPOs (`WS - Logon Banner`, `WS - Remote Desktop`, `WS - LAPS`) have no script that shows their settings, so these exports are their record.

Re-run the export after every GPO change and commit the result. The reports contain lab SIDs and object names, no passwords.

> Not yet populated: run `.\scripts\export-gpos.ps1` on DC01 and commit the output.
