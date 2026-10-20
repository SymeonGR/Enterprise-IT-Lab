# Windows LAPS: schema, permissions and reader group. Run on DC01, elevated.
# The GPO "WS - LAPS" is configured in GPMC (see docs/07-windows-laps.md).

$ou = "OU=Workstations,OU=LAB,DC=corp,DC=internal"

# One-time and irreversible: back up the DC first
Update-LapsADSchema -Verbose

New-ADGroup -Name "GG_LAPS_Readers" -GroupScope Global -Path "OU=Groups,OU=LAB,DC=corp,DC=internal"
Add-ADGroupMember GG_LAPS_Readers -Members GG_IT, "Domain Admins"

Set-LapsADComputerSelfPermission -Identity $ou
Set-LapsADReadPasswordPermission -Identity $ou -AllowedPrincipals "CORP\GG_LAPS_Readers"
Find-LapsADExtendedRights -Identity $ou

# Verify after the GPO has applied on WS01 (does not reveal the password):
# Get-LapsADPassword -Identity WS01 | Format-List
