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
        NtpServer      = 'time.windows.com'   # external time source for the PDC emulator
    }

    Client = @{
        ComputerName   = 'WS01'
        InterfaceAlias = 'Ethernet'
        DnsServer      = '192.168.64.10'
        JoinAccount    = 'CORP\svc-domainjoin'   # delegated in step 08
    }

    OUs = @{
        Root      = 'LAB'
        Children  = @('Users', 'Groups', 'Workstations', 'Servers', 'Service Accounts')
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
