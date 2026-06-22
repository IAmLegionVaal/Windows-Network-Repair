<#
.SYNOPSIS
Diagnoses and repairs common Windows network problems.

.DESCRIPTION
Runs read-only adapter, IP, gateway, DNS, route and proxy checks by default.
Use -Repair for DNS and DHCP refresh actions. Use -FullReset with -Repair to
also reset Winsock and TCP/IP. A restart may be required after a full reset.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Repair,
    [switch]$FullReset,
    [switch]$RestartAdapters,
    [string]$LogRoot = "$env:ProgramData\WindowsNetworkRepair\Logs"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$runPath = Join-Path $LogRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
$warnings = New-Object System.Collections.Generic.List[string]
$transcript = $false

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Run-Native {
    param([string]$Name,[string]$Command,[string[]]$Arguments)
    $log = Join-Path $runPath (($Name -replace '[^A-Za-z0-9-]','_') + '.log')
    & $Command @Arguments 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { $script:warnings.Add("$Name returned $LASTEXITCODE") }
}

function Save-Diagnostics {
    Run-Native 'IP Configuration' 'ipconfig.exe' @('/all')
    Run-Native 'Route Table' 'route.exe' @('print')
    Run-Native 'WinHTTP Proxy' 'netsh.exe' @('winhttp','show','proxy')

    Get-NetAdapter -ErrorAction SilentlyContinue |
        Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress |
        Export-Csv (Join-Path $runPath 'NetworkAdapters.csv') -NoTypeInformation

    Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,InterfaceIndex,IPv4Address,IPv4DefaultGateway,DNSServer |
        Export-Clixml (Join-Path $runPath 'IPConfiguration.xml')

    Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
        Select-Object InterfaceAlias,AddressFamily,ServerAddresses |
        Export-Clixml (Join-Path $runPath 'DnsServers.xml')

    $tests = @(
        @{Name='DNS Microsoft'; Type='Dns'; Target='www.microsoft.com'},
        @{Name='DNS GitHub'; Type='Dns'; Target='github.com'},
        @{Name='Internet IPv4'; Type='Ping'; Target='1.1.1.1'}
    )

    foreach ($test in $tests) {
        try {
            if ($test.Type -eq 'Dns') {
                Resolve-DnsName $test.Target -ErrorAction Stop | Out-File (Join-Path $runPath ($test.Name + '.txt'))
            }
            else {
                Test-Connection $test.Target -Count 2 -ErrorAction Stop | Out-File (Join-Path $runPath ($test.Name + '.txt'))
            }
        }
        catch { $warnings.Add("$($test.Name): $($_.Exception.Message)") }
    }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if (($Repair -or $FullReset -or $RestartAdapters) -and -not (Test-Admin)) {
        throw 'Run PowerShell as Administrator for repair actions.'
    }

    New-Item -Path $runPath -ItemType Directory -Force | Out-Null
    Start-Transcript -Path (Join-Path $runPath 'Transcript.txt') -Force | Out-Null
    $transcript = $true

    Save-Diagnostics

    if ($Repair -and $PSCmdlet.ShouldProcess('Windows network stack','Refresh DNS and DHCP configuration')) {
        Run-Native 'Flush DNS' 'ipconfig.exe' @('/flushdns')
        Run-Native 'Register DNS' 'ipconfig.exe' @('/registerdns')
        Run-Native 'Release DHCP' 'ipconfig.exe' @('/release')
        Run-Native 'Renew DHCP' 'ipconfig.exe' @('/renew')
    }

    if ($RestartAdapters -and $PSCmdlet.ShouldProcess('Connected network adapters','Restart adapters')) {
        Get-NetAdapter | Where-Object Status -ne 'Disabled' | ForEach-Object {
            try { Restart-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction Stop }
            catch { $warnings.Add("Adapter $($_.Name): $($_.Exception.Message)") }
        }
    }

    if ($Repair -and $FullReset -and $PSCmdlet.ShouldProcess('Winsock and TCP/IP','Perform full network reset')) {
        Run-Native 'Winsock Reset' 'netsh.exe' @('winsock','reset')
        Run-Native 'TCPIP Reset' 'netsh.exe' @('int','ip','reset')
        'A Windows restart is recommended after the full reset.' |
            Out-File (Join-Path $runPath 'RestartRecommended.txt')
    }

    $warnings | Out-File (Join-Path $runPath 'Warnings.txt') -Encoding UTF8
    if ($transcript) { Stop-Transcript | Out-Null; $transcript = $false }

    if ($warnings.Count -gt 0) {
        Write-Host "[WARN] Completed with $($warnings.Count) warning(s). Logs: $runPath" -ForegroundColor Yellow
        exit 2
    }
    Write-Host "[OK] Completed. Logs: $runPath" -ForegroundColor Green
    exit 0
}
catch {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
    Write-Error $_.Exception.Message
    exit 1
}
