# Troubleshooting log

Problems hit while building the lab, and how each was solved.

## UTM / macOS

**Server display went black after installing UTM guest tools**
- Cause: SPICE / QXL display driver on Windows Server (x86, emulated).
- Workaround: stopped relying on the UTM console and managed the server over RDP instead. Options if the console is needed: a simpler emulated display card (`VGA` / `bochs-display`, no GPU acceleration) and removing the guest display driver.
- Lesson: avoid guest display drivers on the emulated server; manage it over RDP instead.

**Copy/paste between macOS and VMs**
- Instead of the UTM console and its drivers, both VMs are managed via **RDP** (Windows App) with *Devices & Audio → Clipboard* enabled.
- Long pasted commands sometimes got truncated — keep one command per line, or save them as a `.ps1` and run it.

**VM had an IP but no internet**
- Ruled out a subnet clash between the home LAN and the UTM network (`192.168.64.x`).
- Cause: macOS NAT for UTM Shared Network stuck after network changes.
- First fix to try: restart the Mac; test with `curl -I https://www.microsoft.com` from the VM.

**UTM Clone writes to the internal disk**
- Backups made by copying the `.utm` bundle in Finder to the external drive instead.

**x86 emulation is very slow**
- Reboots (e.g. after DC promotion) are very slow. Use `nc -vz <ip> 3389` from macOS to know when RDP is up.

## Active Directory

**`nslookup` shows `DNS request timed out` / `Server: UnKnown`**
- No reverse lookup zone; harmless if the name still resolves.

**`dcdiag` fails DFSREvent and SystemLog on a new DC**
- Those tests count recent event-log errors; not a functional failure.

**Output of the last command missing when copying from the console**
- Press Enter once after the output so a fresh prompt appears, then copy.

## Domain join

**"The specified domain either does not exist or could not be contacted"**
- Cause: the client's DNS did not point to DC01 (the earlier successful SRV lookup used `-Server 192.168.64.10` explicitly).
- Checks: `Get-DnsClientServerAddress`, `Resolve-DnsName _ldap._tcp.dc._msdcs.corp.internal -Type SRV`, `nltest /dsgetdc:corp.internal`.
- Fix: set client DNS to `192.168.64.10`, clear the cache, retry.
- A reboot after `Add-Computer` doesn't prove the join worked — the rename alone also reboots. Verify with `PartOfDomain`.

## Windows LAPS

**`DecryptionStatus : Unauthorized` even as Domain Admin**
- Cause: the authorized decryptor was set to a single group (`GG_IT`), which replaces Domain Admins; the decryptor is fixed at encryption time.
- Fix: dedicated `GG_LAPS_Readers` group (GG_IT + Domain Admins), then `Reset-LapsPassword`. See [07](07-windows-laps.md).

**"Requires elevation" in a prompt started as Administrator**
- *Run as different user* ≠ *Run as administrator*. Use `Start-Process powershell -Verb RunAs`.

**RSAT not found on Windows 11 ARM64**
- No Features on Demand on Arm64. On 25H2 use *Turn Windows features on or off* → *RSAT: Server Manager Tools* → AD DS tools.

**Added to a group but still no access**
- The logon token is stale. Sign out (not just close RDP) and sign back in, or `klist purge`.

## Group Policy

See the "What went wrong" sections in [04](04-gpo-logon-banner.md), [05](05-gpo-sales-restrictions.md) and [06](06-gpo-remote-desktop.md).

Quick checklist when a GPO "doesn't apply":
1. Is the object (user or computer) in the OU the GPO is linked to?
2. Is it a computer policy checked from a non-elevated prompt?
3. Does `gpresult` list it as *filtered out*? Read the reason (Security, WMI, Empty).
4. Security filtering: target has **Apply**, *Authenticated Users* still has **Read**.
5. Settings actually saved (*Settings → show all*, version ≠ 0)?
6. Does it need a logoff or reboot?
