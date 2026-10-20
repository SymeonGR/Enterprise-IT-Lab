# 04 — GPO: Logon banner (computer policy, GUI)

| | |
|---|---|
| Name | `WS - Logon Banner` |
| Linked to | `OU=Workstations,OU=LAB` |
| Type | Computer |
| Method | Group Policy Management Console |

## Steps

1. Server Manager → Tools → **Group Policy Management**.
2. Forest → Domains → `corp.internal` → `LAB`.
3. Right-click **Workstations** → *Create a GPO in this domain, and Link it here…* → `WS - Logon Banner`.
4. Right-click the GPO → **Edit**.
5. *Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → Security Options*
   - **Interactive logon: Message title for users attempting to log on** → `CORP Lab`
   - **Interactive logon: Message text for users attempting to log on** → `Authorized users only.`
6. Close the editor (changes save automatically).

## Test on WS01

From an **elevated** prompt (`CORP\Administrator`):
```powershell
gpupdate /force
gpresult /r /scope computer
```
`WS - Logon Banner` appears under *Applied Group Policy Objects*.
Restart, then the banner appears before the logon screen.

## Lessons

- A computer policy is linked to the OU containing the **computer** object. Linking it to a user OU is a common reason a policy "doesn't work".
- As a standard user, `gpresult /r /scope computer` returns **Access denied**, and plain `gpresult /r` only shows user settings. Computer policies are always checked elevated.
- Some security settings only take effect at boot — a restart was needed for the banner to show.
