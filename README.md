# Windows Network Repair

Single-run PowerShell diagnostics and repair for Windows IP, DNS, DHCP, adapters, Winsock and TCP/IP.

> **Testing note:** This was tested by me to be working. User experience may vary.

## Included

`Repair-WindowsNetwork.ps1`

## Usage

Diagnostics only:

```powershell
.\Repair-WindowsNetwork.ps1
```

Refresh DNS and DHCP:

```powershell
.\Repair-WindowsNetwork.ps1 -Repair
```

Restart active adapters:

```powershell
.\Repair-WindowsNetwork.ps1 -RestartAdapters
```

Run the full reset:

```powershell
.\Repair-WindowsNetwork.ps1 -Repair -FullReset
```

Preview changes with `-WhatIf`. Repair actions require an elevated PowerShell window. A Windows restart is recommended after a full Winsock and TCP/IP reset.

Logs are stored in `C:\ProgramData\WindowsNetworkRepair\Logs`.

Exit code `0` means success, `1` means a fatal error and `2` means the run completed with warnings.

## Disclaimer

Use this project at your own risk. Network interruptions can occur during DHCP renewal, adapter restart or a full reset. Results vary by adapter, VPN, firewall, policy and Windows version.

## License

MIT
