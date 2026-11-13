<#
.SYNOPSIS
  Read-only health check for a Windows/IIS application host.
.DESCRIPTION
  Checks DNS resolution, TCP reachability, optional HTTPS response,
  Windows services, local IIS sites/application pools, and local machine
  certificates approaching expiry. Writes a JSON report under .\reports.
  Designed as a learning/portfolio tool; it does not change server settings.
.PARAMETER ComputerName
  Host to check for DNS/TCP reachability and remote Windows service status.
.PARAMETER WebsiteUrl
  Optional HTTP/HTTPS URL to request from this machine.
.PARAMETER SqlHost
  Optional SQL Server host to check on the configured SqlPort.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ComputerName = $env:COMPUTERNAME,
    [Parameter()]
    [string]$DnsName,
    [Parameter()]
    [string]$WebsiteUrl,
    [Parameter()]
    [int]$WebPort = 443,
    [Parameter()]
    [string]$SqlHost,
    [Parameter()]
    [int]$SqlPort = 1433,
    [Parameter()]
    [int]$CertificateWarningDays = 30
)

$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Name, [string]$Target, [string]$Status, [string]$Details)
    $checks.Add([pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Name = $Name
        Target = $Target
        Status = $Status
        Details = $Details
    })
}

$dnsTarget = if ($DnsName) { $DnsName } else { $ComputerName }
try {
    $addresses = [System.Net.Dns]::GetHostAddresses($dnsTarget) |
        ForEach-Object { $_.IPAddressToString }
    Add-Check 'DNS resolution' $dnsTarget 'PASS' ($addresses -join ', ')
} catch {
    Add-Check 'DNS resolution' $dnsTarget 'FAIL' $_.Exception.Message
}

$ports = @()
if ($ComputerName -and $WebPort -gt 0) {
    $ports += [pscustomobject]@{ Host = $ComputerName; Port = $WebPort; Label = 'Web TCP' }
}
if ($SqlHost -and $SqlPort -gt 0) {
    $ports += [pscustomobject]@{ Host = $SqlHost; Port = $SqlPort; Label = 'SQL TCP' }
}
foreach ($item in $ports) {
    try {
        $result = Test-NetConnection -ComputerName $item.Host -Port $item.Port -WarningAction SilentlyContinue
        $status = if ($result.TcpTestSucceeded) { 'PASS' } else { 'FAIL' }
        Add-Check $item.Label "$($item.Host):$($item.Port)" $status "TcpTestSucceeded=$($result.TcpTestSucceeded)"
    } catch {
        Add-Check $item.Label "$($item.Host):$($item.Port)" 'ERROR' $_.Exception.Message
    }
}

if ($WebsiteUrl) {
    try {
        $response = Invoke-WebRequest -Uri $WebsiteUrl -UseBasicParsing -TimeoutSec 20
        Add-Check 'HTTP response' $WebsiteUrl 'PASS' "StatusCode=$([int]$response.StatusCode)"
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        $detail = if ($statusCode) { "StatusCode=$statusCode; $($_.Exception.Message)" } else { $_.Exception.Message }
        Add-Check 'HTTP response' $WebsiteUrl 'FAIL' $detail
    }
}

try {
    $services = Get-Service -ComputerName $ComputerName -Name 'W3SVC','WAS' -ErrorAction Stop
    foreach ($service in $services) {
        $status = if ($service.Status -eq 'Running') { 'PASS' } else { 'WARN' }
        Add-Check 'Windows service' "$ComputerName/$($service.Name)" $status "Status=$($service.Status)"
    }
} catch {
    Add-Check 'Windows services' $ComputerName 'ERROR' "Could not query W3SVC/WAS. Check permissions and remote service access. $($_.Exception.Message)"
}

if ($ComputerName -eq $env:COMPUTERNAME -or $ComputerName -eq 'localhost' -or $ComputerName -eq '.') {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $sites = Get-Website
        if ($sites.Count -eq 0) {
            Add-Check 'IIS websites' $ComputerName 'WARN' 'No IIS websites were found.'
        } else {
            foreach ($site in $sites) {
                $status = if ($site.State -eq 'Started') { 'PASS' } else { 'WARN' }
                Add-Check 'IIS website' $site.Name $status "State=$($site.State); PhysicalPath=$($site.PhysicalPath)"
            }
        }
        foreach ($pool in Get-ChildItem IIS:\AppPools) {
            $state = (Get-WebAppPoolState -Name $pool.Name).Value
            $status = if ($state -eq 'Started') { 'PASS' } else { 'WARN' }
            Add-Check 'IIS application pool' $pool.Name $status "State=$state; IdentityType=$($pool.processModel.identityType)"
        }
    } catch {
        Add-Check 'IIS inventory' $ComputerName 'ERROR' "Run locally on an IIS server with WebAdministration available. $($_.Exception.Message)"
    }

    try {
        $cutoff = (Get-Date).AddDays($CertificateWarningDays)
        $certificates = Get-ChildItem Cert:\LocalMachine\My
        $nearExpiry = @($certificates | Where-Object { $_.NotAfter -le $cutoff } | Sort-Object NotAfter)
        if ($nearExpiry.Count -eq 0) {
            Add-Check 'Local machine certificates' 'Cert:\LocalMachine\My' 'PASS' "No certificates expire within $CertificateWarningDays days."
        } else {
            foreach ($cert in $nearExpiry) {
                $status = if ($cert.NotAfter -lt (Get-Date)) { 'FAIL' } else { 'WARN' }
                Add-Check 'Certificate expiry' $cert.Subject $status "Thumbprint=$($cert.Thumbprint); Expires=$($cert.NotAfter.ToString('o'))"
            }
        }
    } catch {
        Add-Check 'Local machine certificates' 'Cert:\LocalMachine\My' 'ERROR' $_.Exception.Message
    }
}

$report = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    ComputerName = $ComputerName
    Checks = @($checks)
    Summary = [pscustomobject]@{
        Pass = @($checks | Where-Object Status -eq 'PASS').Count
        Warning = @($checks | Where-Object Status -eq 'WARN').Count
        Fail = @($checks | Where-Object Status -eq 'FAIL').Count
        Error = @($checks | Where-Object Status -eq 'ERROR').Count
    }
}

$reportDirectory = Join-Path $PSScriptRoot '..\reports'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$reportPath = Join-Path $reportDirectory ("health-check-{0}-{1}.json" -f ($ComputerName -replace '[^A-Za-z0-9._-]', '_'), (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8
$report.Checks | Format-Table -AutoSize
Write-Host "`nSummary: PASS=$($report.Summary.Pass) WARN=$($report.Summary.Warning) FAIL=$($report.Summary.Fail) ERROR=$($report.Summary.Error)"
Write-Host "Report saved to: $reportPath"
