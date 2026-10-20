# 06 — GPO: Remote Desktop for IT (computer policy, GUI)

| | |
|---|---|
| Name | `WS - Remote Desktop` |
| Linked to | `OU=Workstations,OU=LAB` |
| Type | Computer |
| Effect | Enable RDP, open firewall for the lab subnet, add `GG_IT` to local *Remote Desktop Users* |

## Settings (all under Computer Configuration)

**1. Enable RDP**
*Policies → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Session Host → Connections*
→ **Allow users to connect remotely by using Remote Desktop Services** = Enabled

**2. Firewall**
*Policies → Administrative Templates → Network → Network Connections → Windows Defender Firewall → Domain Profile*
→ **Allow inbound Remote Desktop exceptions** = Enabled, allowed from `192.168.64.0/24`

**3. Local group membership**
*Preferences → Control Panel Settings → Local Users and Groups* → New → Local Group
- Action: **Update**
- Group name: **Remote Desktop Users (built-in)** — chosen from the dropdown
- Members → Add → browse (`…`) → `GG_IT` → Check Names → Action **Add to this group**
- Result: `CORP\GG_IT` listed **with a SID**
- *Delete all member users / groups* left **unchecked**

### Why Preferences and not Restricted Groups
Restricted Groups **replaces** the group's membership, wiping existing members on every machine. GPP *Update* only **adds**.

## Test

On WS01, elevated:
```powershell
gpupdate /force
gpresult /r /scope computer
net localgroup "Remote Desktop Users"
```
`WS - Remote Desktop` applied; `CORP\GG_IT` listed.

From macOS (Windows App) to WS01:
- `CORP\nikos` → connects
- `CORP\maria` → denied

## Issues and resolutions

| Symptom | Cause | Fix |
|---|---|---|
| `gpresult`: **Not Applied (Empty)** | Computer side of the GPO had no saved settings (version 0) | Confirmed via *Settings → show all* and *Details → Computer version*; completed and saved the settings |
| Preference item with no SID on the member | Group and member entered as free text | Selected the built-in group from the list and resolved the member to `CORP\GG_IT` (SID bound) |

With *Update*, an unresolved local group name creates a **new local group** on every targeted machine — caught at review, before it reached clients.
