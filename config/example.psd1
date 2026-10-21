# Example environment configuration.
# Copy to a new file, change the values for your environment, and pass it with -ConfigPath.
# Never put passwords or other secrets in this file — the scripts prompt for them at run time.
@{
    Domain = @{
        Name    = 'contoso.internal'   # FQDN of the forest root domain
        NetBIOS = 'CONTOSO'
    }

    DomainController = @{
        ComputerName   = 'DC01'
        InterfaceAlias = 'Ethernet'
        IPAddress      = '10.0.10.10'
        PrefixLength   = 24
        Gateway        = '10.0.10.1'
        DnsForwarder   = '10.0.10.1'
    }

    Client = @{
        ComputerName   = 'WS01'
        InterfaceAlias = 'Ethernet'
        DnsServer      = '10.0.10.10'
    }

    # OU paths elsewhere in this file are relative to Root
    OUs = @{
        Root      = 'LAB'
        Children  = @('Users', 'Groups', 'Workstations', 'Servers')
        Computers = 'Workstations'   # default container for newly joined computers
        Users     = 'Users'
        Groups    = 'Groups'
    }

    # Group name = members (sAMAccountNames). Users that don't exist are created in the Users OU.
    Groups = @{
        'GG_IT'    = @('it.user1')
        'GG_Sales' = @('sales.user1', 'sales.user2')
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
