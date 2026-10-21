<#
.SYNOPSIS
    Exports every GPO linked under the lab's root OU to gpo/: XML and HTML reports plus a backup.

.DESCRIPTION
    The reports make GPMC-built settings reviewable without a lab, and the XML report is the
    format Intune Group Policy analytics imports (Phase 4). Re-run after every GPO change and
    commit the result. Reports contain SIDs and object names, no passwords.

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.PARAMETER Path
    Output folder. Defaults to gpo/ at the repository root.

.EXAMPLE
    .\export-gpos.ps1 -WhatIf
#>
#Requires -Modules GroupPolicy, ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1'),
    [string]$Path = (Join-Path $PSScriptRoot '..\gpo')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, OUs
$domain = Assert-LabDomain -Config $config
$domainDN = $domain.DistinguishedName

$ous = @(Get-LabOUPath -Config $config -DomainDN $domainDN) +
    @($config.OUs.Children | ForEach-Object { Get-LabOUPath -Config $config -DomainDN $domainDN -Name $_ })
$gpos = $ous |
    Where-Object { Get-ADObject -Filter "DistinguishedName -eq '$_'" } |
    ForEach-Object { (Get-GPInheritance -Target $_).GpoLinks.DisplayName } |
    Sort-Object -Unique

foreach ($name in $gpos) {
    $dir = Join-Path $Path ($name -replace '[\s-]+', '-')
    if ($PSCmdlet.ShouldProcess($name, "Export to $dir")) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Get-GPOReport -Name $name -ReportType Xml -Path (Join-Path $dir 'report.xml')
        Get-GPOReport -Name $name -ReportType Html -Path (Join-Path $dir 'report.html')

        # Backup-GPO adds a {GUID} folder per run; keep only the latest
        Get-ChildItem -Path $dir -Directory -Filter '{*}' | Remove-Item -Recurse -Force
        Backup-GPO -Name $name -Path $dir | Out-Null
    }
}

$gpos
