# Shared helpers: load and validate an environment configuration file.

function Import-LabConfig {
    <#
    .SYNOPSIS
        Loads a .psd1 environment configuration and checks that the required sections exist.
    .PARAMETER Path
        Path to the configuration file.
    .PARAMETER Required
        Top-level sections the calling script needs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Required = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path. Copy config/example.psd1 and pass it with -ConfigPath."
    }
    $config = Import-PowerShellDataFile -LiteralPath $Path

    $missing = $Required | Where-Object { -not $config.ContainsKey($_) }
    if ($missing) {
        throw "Configuration $Path is missing section(s): $($missing -join ', ')"
    }
    $config
}

function Assert-LabDomain {
    <#
    .SYNOPSIS
        Stops if the current AD domain is not the one the configuration was written for.
    .DESCRIPTION
        Guards against running a configuration against the wrong domain.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $domain = Get-ADDomain
    if ($domain.DNSRoot -ne $Config.Domain.Name) {
        throw "Configuration is for '$($Config.Domain.Name)' but this domain is '$($domain.DNSRoot)'. Use the matching -ConfigPath."
    }
    $domain
}

function Get-LabOUPath {
    <#
    .SYNOPSIS
        Returns the distinguished name of an OU under the configured root OU.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$DomainDN,

        # Child OU name; omit for the root OU itself
        [string]$Name
    )

    $root = "OU=$($Config.OUs.Root),$DomainDN"
    if ($Name) { "OU=$Name,$root" } else { $root }
}

Export-ModuleMember -Function Import-LabConfig, Assert-LabDomain, Get-LabOUPath
