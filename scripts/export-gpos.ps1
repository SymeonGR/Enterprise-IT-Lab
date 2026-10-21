#Requires -Modules GroupPolicy
<#
.SYNOPSIS
    Export every lab GPO to gpo/ as an XML + HTML report and a restorable backup. Run on DC01.
.DESCRIPTION
    The reports make the GPMC-built settings reviewable without a lab. The XML report is also
    what Intune's Group Policy analytics imports (Phase 4). Re-run after every GPO change and
    commit the result. Reports contain no passwords; LAPS passwords live on computer objects.
.EXAMPLE
    .\export-gpos.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..\gpo')
)

$ErrorActionPreference = 'Stop'

$gpos = 'WS - Logon Banner', 'USR - Sales Restrictions', 'WS - Remote Desktop', 'WS - LAPS'

foreach ($name in $gpos) {
    $dir = Join-Path $Path ($name -replace '[\s-]+', '-')
    if ($PSCmdlet.ShouldProcess($name, "Export to $dir")) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Get-GPOReport -Name $name -ReportType Xml  -Path (Join-Path $dir 'report.xml')
        Get-GPOReport -Name $name -ReportType Html -Path (Join-Path $dir 'report.html')

        # Backup-GPO adds a new {GUID} folder on each run; keep only the latest
        Get-ChildItem -Path $dir -Directory -Filter '{*}' | Remove-Item -Recurse -Force
        Backup-GPO -Name $name -Path $dir | Out-Null
    }
}
