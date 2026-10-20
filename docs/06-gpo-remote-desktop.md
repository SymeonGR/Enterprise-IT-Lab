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

## What went wrong on the way

| Symptom | Cause | Fix |
|---|---|---|
| `gpresult` showed the GPO as **Not Applied (Empty)** | Computer side of the GPO had no saved settings yet | Checked *Settings → show all* and *Details → Computer version*; completed the settings and clicked **OK** (Cancel/X discards) |
| Group name `remote`, member `GG_IT` with empty SID | Names typed by hand | Picked the built-in group from the dropdown; re-added the member via browse so it resolved to `CORP\GG_IT` with a SID |

Lesson: in GPO editors never type names by hand. With *Update*, a mistyped group name silently **creates a new local group** on every machine.
