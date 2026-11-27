<#
.SYNOPSIS
    Context-aware lifecycle orchestrator for the Hybrid SOC Home Lab (Hyper-V + Proxmox VE).

.DESCRIPTION
    Automatically detects whether the operator laptop is connected to the local dorm/home LAN
    (direct TCP 22 reachability to Proxmox VE) or operating remotely off-campus, and manages
    VM power states, Windows NAT (WinNAT), static route metrics, and the Site-to-Site L3
    tunnel (/root/tunel-lab.sh on rocky-hyper).

.PARAMETER Action
    Specifies the lifecycle operation to perform:
      - start  : Brings up all lab VMs in dependency order and configures L3 routing/tunneling.
      - stop   : Gracefully shuts down all VMs, tears down tun0, and cleans up temporary host NAT/routes.
      - status : Displays current power states across both Hyper-V and Proxmox VE.

.EXAMPLE
    .\soc-lab.ps1 -Action start
    .\soc-lab.ps1 -Action status
    .\soc-lab.ps1 -Action stop

.NOTES
    Installation & Global Alias Setup (Windows PowerShell as Administrator):
      1. Copy this script to your user profile:
         Copy-Item .\soc-lab.ps1 "$env:USERPROFILE\soc-lab.ps1"

      2. (Optional) Create global command shims in WindowsApps (already in system PATH)
         to run 'start-lab', 'stop-lab', and 'status-lab' from any CMD or PowerShell tab:
         $bin = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
         '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\soc-lab.ps1" -Action start'  | Set-Content "$bin\start-lab.cmd"  -Encoding Ascii
         '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\soc-lab.ps1" -Action stop'   | Set-Content "$bin\stop-lab.cmd"   -Encoding Ascii
         '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\soc-lab.ps1" -Action status' | Set-Content "$bin\status-lab.cmd" -Encoding Ascii
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action
)

$ErrorActionPreference = "SilentlyContinue"

# === LAB CONFIGURATION ===
$ProxmoxLanIp = "192.168.0.2"
$LabVms = @("Rocky-Linux", "windows 11")
$Win11SshTarget = "<WINDOWS_USER>@10.10.20.20"
$NatName = "LabNATNetwork"
$HyperVSubnet = "10.10.20.0/24"
$PveSubnet = "10.10.10.0"
$PveMask = "255.255.255.0"
$VpnGatewayIp = "10.10.20.10"

function Test-DormLan {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($ProxmoxLanIp, 22, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(1500, $false)
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

function Wait-SshHost {
    param(
        [string]$Target,
        [int]$MaxAttempts = 30
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        ssh -o BatchMode=yes -o ConnectTimeout=2 $Target "exit" 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

$IsDorm = Test-DormLan
$ModeLabel = if ($IsDorm) { "ON-CAMPUS LAN (Native L3 via Cudy Router)" } else { "REMOTE / OFF-CAMPUS (Site-to-Site L3 Tunnel via Cloudflare)" }

Write-Host "`n=== SOC LAB [$($Action.ToUpper())] | Mode: $ModeLabel ===" -ForegroundColor Cyan

switch ($Action) {
    "start" {
        if ($IsDorm) {
            # Ensure remote NAT and override routes are disabled on local LAN
            route delete $PveSubnet $VpnGatewayIp 2>$null | Out-Null
            Remove-NetNat -Name $NatName -Confirm:$false 2>$null | Out-Null

            Write-Host "[1/4] Starting Proxmox VE virtual machines..."
            ssh proxmox 'qm list | grep stopped | while read vmid rest; do qm start $vmid; sleep 4; done'

            Write-Host "[2/4] Starting Hyper-V lab virtual machines ($($LabVms -join ', '))..."
            Get-VM -Name $LabVms | Where-Object { $_.State -ne 'Running' } | Start-VM

            Write-Host "[3/4] Waiting for rocky-hyper SSH and verifying clean LAN routing..."
            if (Wait-SshHost -Target "rocky-hyper" -MaxAttempts 25) {
                ssh rocky-hyper "/root/tunel-lab.sh stop" 2>$null | Out-Null
            }

            Write-Host "[4/4] Lab startup complete (On-Campus Mode)." -ForegroundColor Green
        }
        else {
            Write-Host "[1/5] Enabling WinNAT and metric-5 route via rocky-hyper ($VpnGatewayIp)..."
            if (-not (Get-NetNat -Name $NatName)) {
                New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $HyperVSubnet | Out-Null
            }
            route delete $PveSubnet $VpnGatewayIp 2>$null | Out-Null
            route add $PveSubnet mask $PveMask $VpnGatewayIp metric 5 | Out-Null

            Write-Host "[2/5] Starting SIEM / L3 VPN edge gateway (Rocky-Linux) in Hyper-V..."
            $rockyVm = Get-VM -Name "Rocky-Linux"
            if ($rockyVm -and $rockyVm.State -ne 'Running') { Start-VM -VM $rockyVm }

            Write-Host "[3/5] Waiting for rocky-hyper SSH and establishing Site-to-Site L3 tunnel (tun0)..."
            if (Wait-SshHost -Target "rocky-hyper" -MaxAttempts 30) {
                ssh rocky-hyper "/root/tunel-lab.sh start"
            }
            else {
                Write-Host "[ERROR] rocky-hyper did not respond over SSH within timeout." -ForegroundColor Red
                exit 1
            }

            Write-Host "[4/5] Starting Proxmox VE virtual machines through L3 tunnel..."
            ssh proxmox-wan 'qm list | grep stopped | while read vmid rest; do qm start $vmid; sleep 4; done'

            Write-Host "[5/5] Starting Windows 11 workstation in Hyper-V..."
            $winVm = Get-VM -Name "windows 11"
            if ($winVm -and $winVm.State -ne 'Running') { Start-VM -VM $winVm }

            Write-Host "Lab startup complete (Remote L3 Tunnel Mode)." -ForegroundColor Green
        }
    }

    "stop" {
        Write-Host "[1/4] Shutting down Windows 11 workstation..."
        ssh -o BatchMode=yes -o ConnectTimeout=2 $Win11SshTarget "shutdown /s /t 0" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Get-VM -Name "windows 11" | Where-Object { $_.State -eq 'Running' } | Stop-VM
        }

        Write-Host "[2/4] Shutting down Proxmox VE VMs (rocky-pve, winser)..."
        ssh -o BatchMode=yes -o ConnectTimeout=3 rocky-pve "poweroff" 2>$null
        ssh -o BatchMode=yes -o ConnectTimeout=3 winser "shutdown /s /t 0" 2>$null

        Write-Host "[3/4] Tearing down L3 tunnel and shutting down rocky-hyper..."
        ssh -o BatchMode=yes -o ConnectTimeout=3 rocky-hyper "/root/tunel-lab.sh stop 2>/dev/null; poweroff" 2>$null

        Write-Host "[4/4] Cleaning up temporary host routes and WinNAT..."
        route delete $PveSubnet $VpnGatewayIp 2>$null | Out-Null
        Remove-NetNat -Name $NatName -Confirm:$false 2>$null | Out-Null

        Write-Host "All lab VMs have been safely shut down." -ForegroundColor Green
    }

    "status" {
        Write-Host "--- Hyper-V (Laptop Host) ---"
        Get-VM -Name $LabVms | Format-Table Name, State, Uptime -AutoSize

        Write-Host "--- Proxmox VE ---"
        $pveTarget = if ($IsDorm) { "proxmox" } else { "proxmox-wan" }
        ssh -o BatchMode=yes -o ConnectTimeout=3 $pveTarget "qm list"
    }
}