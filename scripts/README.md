# Scripts

PowerShell used to build the lab. Each script matches a doc in [`docs/`](../docs/).

| Script | Builds | Run on |
|---|---|---|
| `01-dc-setup.ps1` | Static IP, hostname, AD DS forest, DNS forwarder (`-Stage Network / Forest / Post`) | DC01 |
| `02-ad-structure.ps1` | OUs, computer redirection, users, groups | DC01 |
| `03-client-join.ps1` | DNS, pre-flight checks, domain join | WS01 |
| `05-gpo-sales-restrictions.ps1` | Sales GPO with security filtering | DC01 |
| `07-windows-laps.ps1` | LAPS schema, reader group, OU permissions | DC01 |
| `08-least-privilege.ps1` | Delegated join account, machine account quota, AGDLP reader group, `WS - LAPS` values | DC01 |
| `export-gpos.ps1` | XML/HTML reports and backups of every lab GPO into [`gpo/`](../gpo/) | DC01 |

Steps 04 and 06 were built in GPMC. Only the Group Policy Preferences item in 06 (local group membership) has no PowerShell equivalent; the other settings are registry-backed and could be set with `Set-GPRegistryValue`, as step 08 does for LAPS. `export-gpos.ps1` records what the GPMC-built GPOs contain.

## Configuration

Nothing environment-specific is hard-coded. Domain name, IP addresses, OU names, groups, users and GPO names come from a configuration file:

| File | Purpose |
|---|---|
| [`config/lab.psd1`](../config/lab.psd1) | This lab (`corp.internal`) — the default |
| [`config/example.psd1`](../config/example.psd1) | Template with neutral values for another environment |

To use the scripts elsewhere, copy the template to `config/<name>.local.psd1` (ignored by git), adjust the values, and pass it:

```powershell
.\02-ad-structure.ps1 -ConfigPath ..\config\my-env.local.psd1 -WhatIf
```

Scripts that change AD check that the current domain matches the configuration and stop if it doesn't, so a config can't be applied to the wrong domain by accident.

Secrets are never stored in configuration. Passwords and credentials can be passed as `SecureString` / `PSCredential` parameters (`-UserPassword`, `-DsrmPassword`, `-Credential`) for unattended runs, or are prompted for only when actually needed.

## Conventions

- **Config-driven** — one set of scripts, one configuration file per environment.
- **Idempotent** — each script checks current state and only changes what is missing, so re-running it is safe.
- **`-WhatIf` / `-Confirm`** — every change goes through `ShouldProcess`; preview first with `-WhatIf`.
- **Interactive or unattended** — prompts only for missing secrets; everything can be supplied as parameters.
- **Comment-based help** — `Get-Help .\02-ad-structure.ps1 -Full`.
- **Linted and validated** — PSScriptAnalyzer and a configuration check run on every change via GitHub Actions.
