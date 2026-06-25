# Windows Network Diagnostics and Repair

A PowerShell utility for Windows IP, DNS, DHCP, adapter, Winsock and TCP/IP diagnostics. Repair actions are opt-in and potentially disruptive adapter actions require exact adapter names.

## One-click behavior

`Run-OneClick.bat` runs **diagnostics only**. It does not request elevation, release DHCP leases, restart adapters or reset the network stack.

Logs are written under:

```text
C:\ProgramData\WindowsNetworkRepair\Logs
```

## Usage

Diagnostics only:

```powershell
.\Repair-WindowsNetwork.ps1
```

Flush the DNS cache and register DNS records:

```powershell
.\Repair-WindowsNetwork.ps1 -Repair
```

Renew DHCP on one explicitly selected adapter:

```powershell
.\Repair-WindowsNetwork.ps1 -RenewDhcp -AdapterName 'Ethernet'
```

Restart one explicitly selected adapter:

```powershell
.\Repair-WindowsNetwork.ps1 -RestartAdapters -AdapterName 'Ethernet'
```

Select multiple exact adapters:

```powershell
.\Repair-WindowsNetwork.ps1 `
    -RestartAdapters `
    -AdapterName 'Ethernet','Wi-Fi'
```

Perform a full Winsock and TCP/IP reset:

```powershell
.\Repair-WindowsNetwork.ps1 -Repair -FullReset
```

Preview repair actions:

```powershell
.\Repair-WindowsNetwork.ps1 -Repair -WhatIf
.\Repair-WindowsNetwork.ps1 -RenewDhcp -AdapterName 'Ethernet' -WhatIf
```

## Safety controls

- `-RenewDhcp` and `-RestartAdapters` require `-AdapterName`.
- Adapter names are resolved exactly through `Get-NetAdapter`.
- Disabled adapters are rejected.
- DHCP renewal is skipped unless IPv4 DHCP is enabled and the adapter is up.
- `-FullReset` requires `-Repair`.
- Repair actions require an elevated PowerShell session.
- The one-click launcher is deliberately non-destructive.

DHCP renewal, adapter restart and a full network reset can interrupt VPN, RMM or remote desktop connectivity. Use console access or an approved maintenance window when operating remotely.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Completed without recorded warnings |
| `1` | Fatal validation or execution error |
| `2` | Completed with one or more warnings |

## Validation

A Windows GitHub Actions workflow parses every PowerShell file with the native PowerShell parser and runs PSScriptAnalyzer with error-severity findings treated as failures.

## License

MIT License.
