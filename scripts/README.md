# Scripts

PowerShell used to build the lab. Each script matches a doc in [`docs/`](../docs/).

| Script | Builds | Run on |
|---|---|---|
| `01-dc-setup.ps1` | Static IP, hostname, AD DS forest, DNS forwarder (`-Stage Network / Forest / Post`) | DC01 |
| `02-ad-structure.ps1` | OUs, computer redirection, users, groups | DC01 |
| `03-client-join.ps1` | DNS, pre-flight checks, domain join | WS01 |
| `05-gpo-sales-restrictions.ps1` | Sales GPO with security filtering | DC01 |
| `07-windows-laps.ps1` | LAPS schema, reader group, OU permissions | DC01 |

Steps 04 and 06 use Security Options and Group Policy Preferences, which have no native PowerShell cmdlets; they are built in GPMC.

## Conventions

- **Idempotent** — each script checks current state and only changes what is missing, so re-running it is safe.
- **`-WhatIf` / `-Confirm`** — every change goes through `ShouldProcess`; preview first with `-WhatIf`.
- **Parameters with lab defaults** — names, OUs and addresses are parameters, not hard-coded values.
- **No secrets** — passwords are prompted as `SecureString` at run time and never stored.
- **Comment-based help** — `Get-Help .\02-ad-structure.ps1 -Full`.
- **Linted** — [PSScriptAnalyzer](../PSScriptAnalyzerSettings.psd1) runs on every change via GitHub Actions.
