# USR - Sales Restrictions: block Control Panel / Settings for GG_Sales only. Run on DC01.

$gpo = "USR - Sales Restrictions"

New-GPO -Name $gpo | New-GPLink -Target "OU=Users,OU=LAB,DC=corp,DC=internal"

Set-GPRegistryValue -Name $gpo `
  -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
  -ValueName "NoControlPanel" -Type DWord -Value 1

# Security filtering: GG_Sales gets Apply; Authenticated Users keep Read only (MS16-072)
Set-GPPermission -Name $gpo -TargetName "GG_Sales" -TargetType Group -PermissionLevel GpoApply
Set-GPPermission -Name $gpo -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoRead -Replace

# Verify: expect GG_Sales = GpoApply, Authenticated Users = GpoRead
Get-GPPermission -Name $gpo -All | Select-Object Trustee, Permission
