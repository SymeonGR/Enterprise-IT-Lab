# OUs, computer redirection, users and groups for corp.internal

$base = "OU=LAB,DC=corp,DC=internal"

New-ADOrganizationalUnit -Name "LAB" -Path "DC=corp,DC=internal"
"Users","Groups","Workstations","Servers" | ForEach-Object {
    New-ADOrganizationalUnit -Name $_ -Path $base
}

redircmp "OU=Workstations,$base"

$pw = Read-Host "Password for lab users" -AsSecureString
"nikos","maria","giorgos" | ForEach-Object {
    New-ADUser -Name $_ -SamAccountName $_ -UserPrincipalName "$_@corp.internal" `
      -Path "OU=Users,$base" -AccountPassword $pw -Enabled $true
}

New-ADGroup -Name "GG_IT"    -GroupScope Global -Path "OU=Groups,$base"
New-ADGroup -Name "GG_Sales" -GroupScope Global -Path "OU=Groups,$base"
Add-ADGroupMember GG_IT    -Members nikos
Add-ADGroupMember GG_Sales -Members maria,giorgos

Get-ADUser -Filter * -SearchBase $base | Select-Object Name, Enabled
Get-ADGroupMember GG_IT    | Select-Object Name
Get-ADGroupMember GG_Sales | Select-Object Name
