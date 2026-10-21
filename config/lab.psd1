# Configuration for this lab (corp.internal on UTM). See example.psd1 for a template.
# No secrets here — the scripts prompt for passwords at run time.
@{
    Domain = @{
        Name    = 'corp.internal'
        NetBIOS = 'CORP'
    }

    DomainController = @{
        ComputerName   = 'DC01'
        InterfaceAlias = 'Ethernet'
        IPAddress      = '192.168.64.10'
        PrefixLength   = 24
        Gateway        = '192.168.64.1'
        DnsForwarder   = '192.168.64.1'
    }

    Client = @{
        ComputerName   = 'WS01'
        InterfaceAlias = 'Ethernet'
        DnsServer      = '192.168.64.10'
    }

    OUs = @{
        Root      = 'LAB'
        Children  = @('Users', 'Groups', 'Workstations', 'Servers')
        Computers = 'Workstations'
        Users     = 'Users'
        Groups    = 'Groups'
    }

    Groups = @{
        'GG_IT'    = @('nikos')
        'GG_Sales' = @('maria', 'giorgos')
    }

    SalesRestrictionsGpo = @{
        Name       = 'USR - Sales Restrictions'
        TargetOU   = 'Users'
        ApplyGroup = 'GG_Sales'
    }

    Laps = @{
        TargetOU      = 'Workstations'
        ReaderGroup   = 'GG_LAPS_Readers'
        ReaderMembers = @('GG_IT', 'Domain Admins')
    }
}
