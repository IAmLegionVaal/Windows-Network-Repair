# Windows Network Repair

Single-run PowerShell diagnostics and repair for Windows IP, DNS, DHCP, adapters, Winsock and TCP/IP.

> **Testing note:** This was tested by me to be working. User experience may vary.

## One-click use

1. Download and extract the repository.
2. Double-click `Run-OneClick.bat`.
3. Approve the Windows administrator prompt.
4. The launcher runs DNS and DHCP refresh repair directly—there is no menu.
5. Review the displayed exit code and logs in `C:\ProgramData\WindowsNetworkRepair\Logs`.

The one-click action does not restart adapters or perform the full Winsock/TCP-IP reset because those options can interrupt remote sessions and require a deliberate choice.

## Included

`Repair-WindowsNetwork.ps1`

## PowerShell usage

```powershell
.\Repair-WindowsNetwork.ps1
.\Repair-WindowsNetwork.ps1 -Repair
.\Repair-WindowsNetwork.ps1 -RestartAdapters
.\Repair-WindowsNetwork.ps1 -Repair -FullReset
.\Repair-WindowsNetwork.ps1 -Repair -WhatIf
```

The default run records adapter, IP, gateway, DNS, route, proxy and connectivity evidence. Repair refreshes DNS and DHCP. Optional switches restart adapters or reset Winsock and TCP/IP. A Windows restart is recommended after a full reset.

Exit code `0` means success, `1` means a fatal error and `2` means the run completed with warnings.

Network interruptions can occur during DHCP renewal, adapter restart or a full reset. Results vary by adapter, VPN, firewall, policy and Windows version.

MIT License.
