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
        NtpServer      = 'time.windows.com'   # external time source for the PDC emulator
    }

    Client = @{
        ComputerName   = 'WS01'
        InterfaceAlias = 'Ethernet'
        DnsServer      = '10.0.10.10'
        JoinAccount    = 'CONTOSO\svc-domainjoin'   # delegated in step 08
    }

    # OU paths elsewhere in this file are relative to Root
    OUs = @{
        Root      = 'LAB'
        Children  = @('Users', 'Groups', 'Workstations', 'Servers', 'Service Accounts')
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
        TargetOU          = 'Workstations'
        # AGDLP: the group holding the permission is Domain Local; people come in via global groups
        ReaderGroup       = 'DL_LAPS_Readers'
        ReaderMembers     = @('GG_IT', 'Domain Admins')
        # Step 08 converts this pre-AGDLP Global group to ReaderGroup in place (same SID)
        LegacyReaderGroup = 'GG_LAPS_Readers'

        # WS - LAPS policy values, set by step 08
        Policy = @{
            GpoName                      = 'WS - LAPS'
            PasswordLength               = 20
            PasswordComplexity           = 4    # large + small letters + numbers + specials
            PasswordAgeDays              = 30
            PostAuthenticationResetDelay = 8    # hours after the managed account is used
            PostAuthenticationActions    = 3    # reset password and sign out
            ManagedAccountName           = 'lapsadmin'   # automatic account management (Windows 11 24H2+)
        }
    }

    JoinDelegation = @{
        Account             = 'svc-domainjoin'
        AccountOU           = 'Service Accounts'
        TargetOU            = 'Workstations'   # the only OU the account may create computers in
        MachineAccountQuota = 0                # ordinary users can't join computers
    }
}
