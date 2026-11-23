<#
.SYNOPSIS
    Audits Layer 3 routing, WinNAT state, and reachability across the SOC Home Lab.
#>

$Targets = @(
    @{ Name = "Cudy Router (Gateway)"; IP = "192.168.0.1"; Port = 80 },
    @{ Name = "Proxmox VE Host"; IP = "192.168.0.2"; Port = 22 },
    @{ Name = "rocky-pve (Target)"; IP = "10.10.10.10"; Port = 22 },
    @{ Name = "winser (AD DS/DNS)"; IP = "10.10.10.20"; Port = 3389 },
    @{ Name = "rocky-hyper (Wazuh)"; IP = "10.10.20.10"; Port = 22 },
    @{ Name = "win11 (Workstation)"; IP = "10.10.20.20"; Port = 3389 }
)

Write-Host "`n=== 1. Checking WinNAT Status (Must be empty on Home LAN) ===" -ForegroundColor Cyan
$nat = Get-NetNat
if ($nat) {
    Write-Warning "Active WinNAT detected ($($nat.Name)). Inbound traffic from 10.10.10.0/24 will be blocked!"
}
else {
    Write-Host "[OK] No active WinNAT rules. Pure L3 routing mode active." -ForegroundColor Green
}

Write-Host "`n=== 2. Testing TCP Reachability Across Subnets ===" -ForegroundColor Cyan
foreach ($t in $Targets) {
    $res = Test-NetConnection -ComputerName $t.IP -Port $t.Port -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($res) {
        Write-Host "[UP]   $($t.Name.PadRight(24)) ($($t.IP):$($t.Port))" -ForegroundColor Green
    }
    else {
        Write-Host "[DOWN] $($t.Name.PadRight(24)) ($($t.IP):$($t.Port))" -ForegroundColor Red
    }
}