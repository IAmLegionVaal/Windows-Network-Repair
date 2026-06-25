#requires -Version 5.1

<#
.SYNOPSIS
Collects Windows network diagnostics and performs explicitly selected repair actions.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Repair,
    [switch]$RenewDhcp,
    [switch]$FullReset,
    [switch]$RestartAdapters,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdapterName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogRoot = "$env:ProgramData\WindowsNetworkRepair\Logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runPath = Join-Path $LogRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:TranscriptStarted = $false

function Add-RunWarning {
    param([Parameter(Mandatory)][string]$Message)
    $script:Warnings.Add($Message)
    Write-Warning $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @(),
        [int[]]$SuccessExitCodes = @(0)
    )

    $log = Join-Path $runPath (($Name -replace '[^A-Za-z0-9-]', '_') + '.log')
    & $Command @Arguments 2>&1 | Tee-Object -FilePath $log
    $exitCode = $LASTEXITCODE

    if ($exitCode -notin $SuccessExitCodes) {
        Add-RunWarning "$Name returned exit code $exitCode. Review $log"
        return $false
    }

    return $true
}

function Resolve-SelectedAdapters {
    if (-not $AdapterName -or $AdapterName.Count -eq 0) {
        throw 'Specify -AdapterName for DHCP renewal or adapter restart actions.'
    }

    $resolved = New-Object System.Collections.Generic.List[object]
    foreach ($name in $AdapterName) {
        $matches = @(Get-NetAdapter -Name $name -ErrorAction Stop)
        foreach ($adapter in $matches) {
            if ($adapter.Status -eq 'Disabled') {
                throw "Adapter '$($adapter.Name)' is disabled. Enable or select a different adapter."
            }

            $alreadyAdded = @($resolved | Where-Object { $_.ifIndex -eq $adapter.ifIndex }).Count -gt 0
            if (-not $alreadyAdded) {
                $resolved.Add($adapter)
            }
        }
    }

    return $resolved.ToArray()
}

function Save-Diagnostics {
    Invoke-NativeCommand -Name 'IP Configuration' -Command 'ipconfig.exe' -Arguments @('/all') | Out-Null
    Invoke-NativeCommand -Name 'Route Table' -Command 'route.exe' -Arguments @('print') | Out-Null
    Invoke-NativeCommand -Name 'WinHTTP Proxy' -Command 'netsh.exe' -Arguments @('winhttp','show','proxy') | Out-Null

    Get-NetAdapter -ErrorAction SilentlyContinue |
        Select-Object Name,InterfaceDescription,ifIndex,Status,LinkSpeed,MacAddress |
        Export-Csv (Join-Path $runPath 'NetworkAdapters.csv') -NoTypeInformation -Encoding UTF8

    Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,InterfaceIndex,IPv4Address,IPv4DefaultGateway,DNSServer |
        Export-Clixml (Join-Path $runPath 'IPConfiguration.xml')

    Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,InterfaceIndex,ConnectionState,Dhcp,InterfaceMetric,NlMtuBytes |
        Export-Csv (Join-Path $runPath 'IPv4Interfaces.csv') -NoTypeInformation -Encoding UTF8

    Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,ServerAddresses |
        Export-Clixml (Join-Path $runPath 'DnsServers.xml')

    foreach ($test in @(
        @{ Name = 'DNS Microsoft'; Type = 'Dns'; Target = 'www.microsoft.com' }
        @{ Name = 'DNS GitHub'; Type = 'Dns'; Target = 'github.com' }
        @{ Name = 'Internet IPv4'; Type = 'Ping'; Target = '1.1.1.1' }
    )) {
        try {
            $path = Join-Path $runPath ($test.Name + '.txt')
            if ($test.Type -eq 'Dns') {
                Resolve-DnsName -Name $test.Target -ErrorAction Stop | Out-File $path -Encoding UTF8
            }
            else {
                Test-Connection -ComputerName $test.Target -Count 2 -ErrorAction Stop | Out-File $path -Encoding UTF8
            }
        }
        catch {
            Add-RunWarning "$($test.Name): $($_.Exception.Message)"
        }
    }
}

try {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Windows is required.'
    }

    if ($FullReset -and -not $Repair) {
        throw '-FullReset requires -Repair.'
    }

    $hasMutation = $Repair -or $RenewDhcp -or $FullReset -or $RestartAdapters
    if ($hasMutation -and -not (Test-IsAdministrator)) {
        throw 'Run PowerShell as Administrator for repair actions.'
    }

    $selectedAdapters = @()
    if ($RenewDhcp -or $RestartAdapters) {
        $selectedAdapters = @(Resolve-SelectedAdapters)
    }

    New-Item -Path $runPath -ItemType Directory -Force | Out-Null
    Start-Transcript -Path (Join-Path $runPath 'Transcript.txt') -Force | Out-Null
    $script:TranscriptStarted = $true

    Save-Diagnostics

    if ($Repair -and $PSCmdlet.ShouldProcess('Windows DNS client cache', 'Flush and register DNS')) {
        Invoke-NativeCommand -Name 'Flush DNS' -Command 'ipconfig.exe' -Arguments @('/flushdns') | Out-Null
        Invoke-NativeCommand -Name 'Register DNS' -Command 'ipconfig.exe' -Arguments @('/registerdns') | Out-Null
    }

    if ($RenewDhcp) {
        foreach ($adapter in $selectedAdapters) {
            $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop
            if ($ipInterface.Dhcp -ne 'Enabled') {
                Add-RunWarning "Skipping DHCP renewal for '$($adapter.Name)' because IPv4 DHCP is not enabled."
                continue
            }
            if ($adapter.Status -ne 'Up') {
                Add-RunWarning "Skipping DHCP renewal for '$($adapter.Name)' because its status is '$($adapter.Status)'."
                continue
            }

            if ($PSCmdlet.ShouldProcess($adapter.Name, 'Release and renew the DHCP lease')) {
                $released = Invoke-NativeCommand -Name "Release DHCP $($adapter.Name)" `
                    -Command 'ipconfig.exe' -Arguments @('/release', $adapter.Name)
                if ($released) {
                    Start-Sleep -Seconds 2
                    Invoke-NativeCommand -Name "Renew DHCP $($adapter.Name)" `
                        -Command 'ipconfig.exe' -Arguments @('/renew', $adapter.Name) | Out-Null
                }
            }
        }
    }

    if ($RestartAdapters) {
        foreach ($adapter in $selectedAdapters) {
            if ($PSCmdlet.ShouldProcess($adapter.Name, 'Restart network adapter')) {
                try {
                    Restart-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                }
                catch {
                    Add-RunWarning "Adapter '$($adapter.Name)' restart failed: $($_.Exception.Message)"
                }
            }
        }
    }

    if ($Repair -and $FullReset -and $PSCmdlet.ShouldProcess('Winsock and TCP/IP', 'Perform full network reset')) {
        Invoke-NativeCommand -Name 'Winsock Reset' -Command 'netsh.exe' -Arguments @('winsock','reset') | Out-Null
        Invoke-NativeCommand -Name 'TCPIP Reset' -Command 'netsh.exe' -Arguments @('int','ip','reset') | Out-Null
        'A Windows restart is required to complete the full network reset.' |
            Out-File (Join-Path $runPath 'RestartRequired.txt') -Encoding UTF8
    }

    $script:Warnings | Out-File (Join-Path $runPath 'Warnings.txt') -Encoding UTF8

    if ($script:TranscriptStarted) {
        Stop-Transcript | Out-Null
        $script:TranscriptStarted = $false
    }

    if ($script:Warnings.Count -gt 0) {
        Write-Host "[WARN] Completed with $($script:Warnings.Count) warning(s). Logs: $runPath"
        exit 2
    }

    Write-Host "[OK] Completed. Logs: $runPath"
    exit 0
}
catch {
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
    Write-Error $_.Exception.Message
    exit 1
}
