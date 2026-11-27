# SOC Home Lab — Network & Infrastructure Architecture

**Project Status:** Phase 1 (Network Architecture, Layer 3 Routing & Remote Access) — **COMPLETED & VERIFIED (100% all-to-all + WAN connectivity)**.  
**Next Phase:** Deployment and configuration of SOC services (Wazuh SIEM, Active Directory + DNS, Sysmon, and Wazuh agents).

---

## 1. Topology & Network Architecture (Pure L3 Routing)

The lab environment runs across two hypervisors interconnected via a local home network (`192.168.0.0/24`) using pure Layer 3 static routing (avoiding double NAT within the LAN). This ensures full, bidirectional visibility across all virtual machines using their actual IP addresses.

```text
                      [ Internet / WAN ]
                              │
                   [ Router Cudy TR3000 ]
                    LAN: 192.168.0.1/24
          (Static Route: 10.10.20.0/24 -> 192.168.0.4)
               ┌──────────────┴──────────────┐
               ▼                             ▼
   [ HP ProDesk — Proxmox VE ]   [ Laptop — Windows 11 + Hyper-V ]
       vmbr0: 192.168.0.2/24          Wi-Fi: 192.168.0.4/24
   (Route: 10.10.20.0/24 -> .4)    (Route: 10.10.10.0/24 -> .2)
               │                             │
       vmbr1: 10.10.10.1/24          vEthernet (LabNAT): 10.10.20.1/24
               │                             │
      ┌────────┴────────┐           ┌────────┴────────┐
      ▼                 ▼           ▼                 ▼
 [rocky-pve]       [winser]   [rocky-hyper]        [win11]
 10.10.10.10      10.10.10.20  10.10.20.10       10.10.20.20
 (Target/App)     (AD DS/DNS)  (Wazuh SIEM)     (Workstation)
```

---

## 2. Node & Virtual Machine Inventory

| Hostname / Alias    | Host / Hypervisor       | Operating System     | IP Address / Subnet                                     | Default Gateway | DNS             | Role in SOC Lab                                    |
| :------------------ | :---------------------- | :------------------- | :------------------------------------------------------ | :-------------- | :-------------- | :------------------------------------------------- |
| **Cudy Router**     | Hardware (TR3000)       | CudyOS               | `192.168.0.1/24`                                        | ISP WAN         | ISP / `1.1.1.1` | Main gateway, outbound NAT, DHCP, LAN routing      |
| **proxmox (`pve`)** | HP ProDesk (Bare-metal) | Proxmox VE           | `192.168.0.2/24` (`vmbr0`)<br>`10.10.10.1/24` (`vmbr1`) | `192.168.0.1`   | `1.1.1.1`       | Server hypervisor, L3 gateway for `10.10.10.0/24`  |
| **Laptop Host**     | Physical (Windows 11)   | Windows 11 + Hyper-V | `192.168.0.4/24` (LAN)<br>`10.10.20.1/24` (`LabNAT`)    | `192.168.0.1`   | `1.1.1.1`       | Operator workstation, L3 router, client hypervisor |
| **rocky-pve**       | Proxmox (`VM 101`)      | Rocky Linux          | `10.10.10.10/24`                                        | `10.10.10.1`    | `1.1.1.1`       | Application server / Attack Target + Wazuh Agent   |
| **winser**          | Proxmox (VM)            | Windows Server       | `10.10.10.20/24`                                        | `10.10.10.1`    | `127.0.0.1`     | Active Directory Domain Controller (AD DS) + DNS   |
| **rocky-hyper**     | Hyper-V (Laptop)        | Rocky Linux          | `10.10.20.10/24`                                        | `10.10.20.1`    | `1.1.1.1`       | Central SIEM: Wazuh Manager, Indexer, Dashboard    |
| **win11**           | Hyper-V (Laptop)        | Windows 11           | `10.10.20.20/24`                                        | `10.10.20.1`    | `10.10.10.20`   | Domain-joined workstation + Sysmon + Wazuh Agent   |

---

## 3. Routing & Network Configuration Details

### Cudy TR3000 Router (`192.168.0.1`)
* **DHCP Static Leases:**
  * Proxmox VE: `192.168.0.2`
  * Laptop Host: `192.168.0.4`
* **Static Route (`LAN` Interface):**
  * Destination Network: `10.10.20.0` | Netmask: `255.255.255.0` | Gateway: `192.168.0.4`

### Proxmox VE (`192.168.0.2`)
* Enabled IPv4 packet forwarding (`net.ipv4.ip_forward=1`).
* `/etc/network/interfaces` configuration:
  * `vmbr0` (`192.168.0.2/24`, gateway `192.168.0.1`) with persistent route:
    `up ip route add 10.10.20.0/24 via 192.168.0.4`
  * `vmbr1` (`10.10.10.1/24`) — isolated internal bridge without a physical NIC attached.

### Laptop Host (`192.168.0.4`)
* Enabled IP forwarding (`Forwarding: Enabled`) on both the physical LAN/Wi-Fi adapter and the `vEthernet (LabNAT)` virtual switch.
* Persistent static route to the Proxmox internal subnet:
  `route -p add 10.10.10.0 mask 255.255.255.0 192.168.0.2`
* Removed default `WinNAT` (`LabNATNetwork`) while on the home LAN to prevent NAT from blocking inbound connections originating from `10.10.10.0/24`.

---

## 4. Remote Access (LAN SSH & Cloudflare Zero Trust Tunnel)

Passwordless SSH authentication is enforced across all Linux nodes and Windows Server (`C:\ProgramData\ssh\administrators_authorized_keys`) using **Ed25519** cryptographic keys. External WAN access is secured via a **Cloudflare Zero Trust Tunnel (`cloudflared`)** without exposing any ports on the home router.

### Sanitized `~/.ssh/config` Template

```text
Host *
    UpdateHostKeys no

# === PROXMOX HOST ===
Host proxmox
    HostName 192.168.0.2
    User root
    IdentityFile ~/.ssh/id_ed25519

Host proxmox-wan
    HostName pve.<YOUR_CLOUDFLARE_DOMAIN>
    User root
    IdentityFile ~/.ssh/id_ed25519
    ProxyCommand cloudflared access ssh --hostname %h

# === ROCKY LINUX ON PROXMOX (10.10.10.10) ===
Host rocky-pve
    HostName 10.10.10.10
    User root
    IdentityFile ~/.ssh/id_ed25519

Host rocky-pve-wan
    HostName 10.10.10.10
    User root
    IdentityFile ~/.ssh/id_ed25519
    ProxyJump proxmox-wan

# === WINDOWS SERVER ON PROXMOX (10.10.10.20) ===
Host winser
    HostName 10.10.10.20
    User Administrator
    IdentityFile ~/.ssh/id_ed25519

Host winser-wan
    HostName 10.10.10.20
    User Administrator
    IdentityFile ~/.ssh/id_ed25519
    ProxyJump proxmox-wan

# === WAN PORT FORWARDING FOR RDP (WIN SERVER) & PROXMOX WEB GUI ===
Host tunel-wan
    HostName pve.<YOUR_CLOUDFLARE_DOMAIN>
    User root
    IdentityFile ~/.ssh/id_ed25519
    ProxyCommand cloudflared access ssh --hostname %h
    LocalForward 13389 10.10.10.20:3389
    LocalForward 8006 127.0.0.1:8006

# === HYPER-V ON LAPTOP (LOCAL) ===
Host rocky-hyper
    HostName 10.10.20.10
    User root
    IdentityFile ~/.ssh/id_ed25519
```

---

## 5. Operational Runbook & Troubleshooting Notes

1. **Mobile / On-Campus Operation (Outside Home LAN):**
   * When operating outside the Cudy router's network, Hyper-V VMs (`10.10.20.0/24`) lose their upstream NAT gateway. To restore internet access on the go (run PowerShell as Administrator):
```powershell
New-NetNat -Name "LabNATNetwork" -InternalIPInterfaceAddressPrefix "10.10.20.0/24"
```
   * Upon returning to the home LAN, remove `LabNATNetwork` to restore bidirectional L3 routing with Proxmox:
```powershell
Remove-NetNat -Name "LabNATNetwork" -Confirm:$false
```

2. **External GUI Access (RDP / Proxmox Web UI over WAN):**
   * Start the background SSH tunnel: `ssh -N tunel-wan`
   * Connect to Windows Server via RDP (`mstsc`): `localhost:13389`
   * Access Proxmox Web GUI: `https://localhost:8006`

3. **Proxmox Emergency Console & Guest Agent Notes:**
   * For Rocky Linux (`VM 101`), use the graphical **noVNC** console (the default `xterm.js` serial console requires manual `getty` binding to `ttyS0`).
   * On Rocky Linux, the `qemu-guest-agent` service disables the `guest-exec` command by default in `/etc/sysconfig/qemu-ga`.

---

## 6. Phase 2 Roadmap (SOC Services Deployment)

- **Wazuh SIEM (`10.10.20.10`):** Audit core services (`wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard`) and verify Web UI access (`https://10.10.20.10`).
- **Active Directory (`10.10.10.20`):** Install AD DS and DNS roles, promote the domain controller, and configure Organizational Units (OUs) and test user accounts.
- **Domain Integration (`10.10.20.20`):** Join the Windows 11 workstation to the Active Directory domain.
- **Telemetry & Agents:** Deploy Sysmon (using SwiftOnSecurity / Olaf Hartong modular configs) and enroll Wazuh agents across `winser`, `win11`, and `rocky-pve`.