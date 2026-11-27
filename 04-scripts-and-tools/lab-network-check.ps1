<#
.SYNOPSIS
    Audits Layer 3 routing, WinNAT state, and TCP reachability across the Hybrid SOC Home Lab.

.DESCRIPTION
    Inspects the active routing path to the Proxmox subnet (10.10.10.0/24), validates
    whether WinNAT matches the current operational mode (disabled on-campus for pure L3
    routing; enabled off-campus alongside the metric-5 override route via rocky-hyper),
    and performs fast TCP port reachability checks across all lab gateways and VMs.

.EXAMPLE
    .\lab-network-check.ps1

.NOTES
    Prerequisites:
      - Run from an elevated (Administrator) PowerShell session so Get-NetNat can inspect
        Hyper-V NAT state.

    Installation (Windows PowerShell):
      1. Copy this script to your user profile (or keep it in your scripts directory):
         Copy-Item .\lab-network-check.ps1 "$env:USERPROFILE\lab-network-check.ps1"

      2. (Optional) Create a global 'check-lab' command shim in WindowsApps (already in PATH):
         $bin = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
         '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\lab-network-check.ps1"' | Set-Content "$bin\check-lab.cmd" -Encoding Ascii
#>

$Targets = @(
    @{ Name = "Cudy Router (Gateway)"; IP = "192.168.0.1"; Port = 80; Scope = "LAN" },
    @{ Name = "Proxmox VE Host"; IP = "192.168.0.2"; Port = 22; Scope = "LAN" },
    @{ Name = "rocky-pve (Target)"; IP = "10.10.10.10"; Port = 22; Scope = "Lab" },
    @{ Name = "winser (AD DS/DNS)"; IP = "10.10.10.20"; Port = 3389; Scope = "Lab" },
    @{ Name = "rocky-hyper (Wazuh)"; IP = "10.10.20.10"; Port = 22; Scope = "Lab" },
    @{ Name = "win11 (Workstation)"; IP = "10.10.20.20"; Port = 3389; Scope = "Lab" }
)

function Test-TcpPort {
    param(
        [string]$Ip,
        [int]$Port,
        [int]$TimeoutMs = 1000
    )
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($Ip, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        $tcp.Close()
    }
}

Write-Host "`n=== 1. Active L3 Route & WinNAT State ===" -ForegroundColor Cyan

$activeRoute = Get-NetRoute -DestinationPrefix "10.10.10.0/24" -ErrorAction SilentlyContinue |
Sort-Object RouteMetric | Select-Object -First 1

$isRemoteMode = ($activeRoute -and $activeRoute.NextHop -eq "10.10.20.10")

if ($activeRoute) {
    Write-Host "[INFO] Active route to 10.10.10.0/24 -> NextHop: $($activeRoute.NextHop) (Metric: $($activeRoute.RouteMetric))" -ForegroundColor Gray
}
else {
    Write-Warning "No route to 10.10.10.0/24 found in the Windows routing table!"
}

try {
    $nat = Get-NetNat -ErrorAction Stop
    if ($isRemoteMode) {
        if ($nat) {
            Write-Host "[OK] Remote L3 Tunnel mode active; WinNAT ($($nat.Name)) is enabled for VM WAN access." -ForegroundColor Green
        }
        else {
            Write-Warning "Remote L3 route is active, but WinNAT is disabled (Hyper-V VMs may lack outbound WAN/Cloudflare access)."
        }
    }
    else {
        if ($nat) {
            Write-Warning "Active WinNAT detected ($($nat.Name)) while in On-Campus LAN mode! Inbound traffic from 10.10.10.0/24 will be blocked."
        }
        else {
            Write-Host "[OK] No active WinNAT rules. Pure On-Campus L3 routing mode active." -ForegroundColor Green
        }
    }
}
catch {
    Write-Warning "Unable to query Get-NetNat (run PowerShell as Administrator to inspect WinNAT state)."
}

Write-Host "`n=== 2. Testing TCP Reachability Across Subnets ===" -ForegroundColor Cyan
foreach ($t in $Targets) {
    $res = Test-TcpPort -Ip $t.IP -Port $t.Port
    $label = "$($t.Name.PadRight(24)) ($($t.IP):$($t.Port))"
    if ($res) {
        Write-Host "[UP]   $label" -ForegroundColor Green
    }
    elseif ($isRemoteMode -and $t.Scope -eq "LAN") {
        Write-Host "[SKIP] $label (Dorm LAN only)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[DOWN] $label" -ForegroundColor Red
    }
}