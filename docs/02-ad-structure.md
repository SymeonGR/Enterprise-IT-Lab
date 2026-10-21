# 02 — AD Structure: OUs, users, groups

Script: [`scripts/02-ad-structure.ps1`](../scripts/02-ad-structure.ps1) — skips objects that already exist, so it can be re-run against the lab.

Real environments don't leave objects in the default `Users` / `Computers` containers — GPOs can't be linked to containers, only to OUs.

## OUs

```powershell
New-ADOrganizationalUnit -Name "LAB" -Path "DC=corp,DC=internal"
"Users","Groups","Workstations","Servers" | ForEach-Object {
    New-ADOrganizationalUnit -Name $_ -Path "OU=LAB,DC=corp,DC=internal"
}
```

## Redirect new computers

New computer accounts land in `OU=Workstations` instead of `CN=Computers`, so they receive workstation GPOs from the first boot.

```powershell
redircmp "OU=Workstations,OU=LAB,DC=corp,DC=internal"
```

## Users

```powershell
$pw = Read-Host "Password for lab users" -AsSecureString
"nikos","maria","giorgos" | ForEach-Object {
    New-ADUser -Name $_ -SamAccountName $_ -UserPrincipalName "$_@corp.internal" `
      -Path "OU=Users,OU=LAB,DC=corp,DC=internal" -AccountPassword $pw -Enabled $true
}
```

The password must meet the default complexity policy (8+ characters, mixed case, digit or symbol).

No `-ChangePasswordAtLogon`: the test users sign in over RDP with Network Level Authentication, which can't change an expired password, so a forced change would lock them out of RDP. In production, new accounts get a unique initial password and must change it at first sign-in.

## Groups

```powershell
New-ADGroup -Name "GG_IT"    -GroupScope Global -Path "OU=Groups,OU=LAB,DC=corp,DC=internal"
New-ADGroup -Name "GG_Sales" -GroupScope Global -Path "OU=Groups,OU=LAB,DC=corp,DC=internal"
Add-ADGroupMember GG_IT    -Members nikos
Add-ADGroupMember GG_Sales -Members maria,giorgos
```

## Verify

```powershell
Get-ADUser -Filter * -SearchBase "OU=LAB,DC=corp,DC=internal" | Select-Object Name, Enabled
Get-ADGroupMember GG_Sales | Select-Object Name
Get-ADGroupMember GG_IT    | Select-Object Name
Get-ADUser nikos -Properties MemberOf | Select-Object -ExpandProperty MemberOf
```

Expected: three enabled users; `maria`, `giorgos` in `GG_Sales`; `nikos` in `GG_IT`.
