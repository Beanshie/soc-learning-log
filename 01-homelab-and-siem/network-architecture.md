# SOC Home Lab — Hybrid Network & Site-to-Site L3 Architecture (v2)

> **Legacy Architecture Reference:** For the initial pure-LAN baseline before remote Site-to-Site L3 tunneling was introduced, see [Network Architecture v1 (Legacy)](network-architecture-v1-legacy.md).
>
> **Project Status:** Phase 1 (Hybrid Layer 3 Routing, Site-to-Site SSH L3 Tunnel & Automated Lifecycle Orchestration) — **COMPLETED & VERIFIED** (100% all-to-all VM interoperability + WAN access both on-campus and remotely).
>
> **Next Phase:** Deployment and configuration of SOC services (Wazuh SIEM audit, Active Directory + DNS, Sysmon, and Wazuh agents).

---

## 1. Architectural Evolution: Why We Migrated from v1 to v2

The v1 architecture relied exclusively on static Layer 3 routes via the local Cudy TR3000 router (`192.168.0.0/24`) paired with a basic Cloudflare SSH `ProxyJump` for individual administrative terminal sessions. While optimal inside the dorm/campus LAN, that design created critical limitations whenever the laptop operated remotely (at home, on mobile hotspot, or traveling):

1. **Subnet Isolation Off-Campus:** `ProxyJump` only forwarded single TCP sockets from the laptop host to Proxmox (`10.10.10.0/24`). The Hyper-V subnet (`10.10.20.0/24` — `rocky-hyper` SIEM and `win11` workstation) had no Layer 3 path to the Proxmox subnet (`10.10.10.0/24` — `winser` AD DS/DNS and `rocky-pve`).
2. **Enterprise Protocol Requirements:** Active Directory authentication (Kerberos, LDAP, SMB), internal DNS resolution (`10.10.10.20`), and Wazuh agent telemetry (`10.10.20.10:1514/1515`) require true bidirectional IP routing across both subnets using their native static IPs.
3. **Restrictive Upstream Firewalls:** Campus networks block inbound ports, standard UDP-based VPNs (WireGuard/OpenVPN), and external DNS resolvers (`8.8.8.8:53`), requiring all remote lab traffic to traverse outbound HTTPS (`TCP 443`).

### The v2 Hybrid Design
The lab now operates as a **context-aware, dual-mode Layer 3 network** without changing any VM IP addresses, DNS records, or agent configurations:
* **On-Campus / Dorm Mode:** Zero-overhead native Layer 3 static routing through the Cudy TR3000 router (`<1 ms` latency, no encapsulation overhead).
* **Remote / Off-Campus Mode:** An automated, on-demand Site-to-Site Layer 3 IP tunnel (`10.10.99.0/30` via `ssh -w 0:0` `tun0`) encapsulated inside Cloudflare Zero Trust (`TCP 443`). `rocky-hyper` (`10.10.20.10`) acts as both the central SIEM and the Layer 3 edge VPN gateway for `10.10.20.0/24`, peering directly with Proxmox VE (`192.168.0.2`).

---

## 2. Dual-Mode Network Topology

### Mode A: On-Campus / Dorm LAN (Native L3 Static Routing)
```text
                      [ Internet / WAN ]
                              |
                   [ Router Cudy TR3000 ]
                    LAN: 192.168.0.1/24
          (Static Route: 10.10.20.0/24 -> 192.168.0.4)
               +--------------+--------------+
               |                             |
               v                             v
   [ HP ProDesk - Proxmox VE ]   [ Laptop - Windows 11 + Hyper-V ]
       vmbr0: 192.168.0.2/24          Wi-Fi: 192.168.0.4/24
   (Route: 10.10.20.0/24 -> .4)    (Route: 10.10.10.0/24 -> .2)
               |                             |
       vmbr1: 10.10.10.1/24          vEthernet (LabNAT): 10.10.20.1/24
               |                             |
      +--------+--------+           +--------+--------+
      |                 |           |                 |
      v                 v           v                 v
 [rocky-pve]       [winser]   [rocky-hyper]        [win11]
 10.10.10.10      10.10.10.20  10.10.20.10       10.10.20.20
 (Target/App)     (AD DS/DNS)  (Wazuh SIEM)     (Workstation)
```

### Mode B: Remote / Off-Campus (Site-to-Site L3 `tun0` over Cloudflare `TCP 443`)
```text
 [win11: 10.10.20.20] --+
                        |
                        v
              [rocky-hyper: 10.10.20.10]  <-- SIEM + L3 Edge VPN Router
                        |
                        | (tun0: 10.10.99.2/30, MTU 1300)
                        v
              [SSH -w 0:0 + cloudflared]  <-- Encapsulates L3 IP in SSH
                        |
                        | (Outbound via Laptop WinNAT as HTTPS TCP 443)
                        v
          [ CLOUDFLARE ZERO TRUST EDGE ]  <-- pve.<YOUR_CLOUDFLARE_DOMAIN>
                        ^
                        | (Persistent outbound tunnel from Proxmox)
              [cloudflared + sshd]
                        |
                        | (tun0: 10.10.99.1/30, MTU 1300)
                        v
              [Proxmox VE: 192.168.0.2]   <-- L3 Gateway for 10.10.10.0/24
                 +------+------+
                 |             |
                 v             v
         [rocky-pve]       [winser]
         10.10.10.10      10.10.10.20
```

---

## 3. Node & Virtual Machine Inventory

| Hostname / Alias | Host / Hypervisor | Operating System | IP Address / Subnet | Default Gateway | DNS | Role in SOC Lab |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Cudy Router** | Hardware (TR3000) | CudyOS | `192.168.0.1/24` | Campus WAN | Campus DNS / `8.8.8.8` | Main dorm gateway, outbound NAT, DHCP, LAN routing |
| **`proxmox`** (`pve`) | HP ProDesk (Bare-metal) | Proxmox VE | `192.168.0.2/24` (`vmbr0`)<br>`10.10.10.1/24` (`vmbr1`)<br>`10.10.99.1/30` (`tun0`) | `192.168.0.1` | `1.1.1.1` | Server hypervisor, L3 gateway for `10.10.10.0/24`, remote tunnel endpoint |
| **Laptop Host** | Physical (Windows 11) | Windows 11 + Hyper-V | `192.168.0.4/24` (LAN)<br>`10.10.20.1/24` (`LabNAT`) | `192.168.0.1` (Dorm)<br>ISP/Hotspot (Away) | `1.1.1.1` | Operator workstation, L3 router, client hypervisor |
| **`rocky-pve`** | Proxmox (VM 101) | Rocky Linux 9 | `10.10.10.10/24` | `10.10.10.1` | `1.1.1.1` | Application server / Attack Target + Wazuh Agent |
| **`winser`** | Proxmox (VM 102) | Windows Server | `10.10.10.20/24` | `10.10.10.1` | `127.0.0.1` | Active Directory Domain Controller (AD DS) + DNS |
| **`rocky-hyper`** | Hyper-V (`Rocky-Linux`) | Rocky Linux 9 | `10.10.20.10/24` (`eth0`)<br>`10.10.99.2/30` (`tun0`) | `10.10.20.1` | `1.1.1.1` / `8.8.8.8`<br>(`<CAMPUS_DNS_IP>` on-campus) | Central SIEM (Wazuh Manager, Indexer, Dashboard) + L3 VPN Edge Router |
| **`win11`** | Hyper-V (`windows 11`) | Windows 11 | `10.10.20.20/24` | `10.10.20.1` | `10.10.10.20` | Domain-joined workstation + Sysmon + Wazuh Agent |

---

## 4. Infrastructure & Routing Engineering Details

### Cudy TR3000 Router (`192.168.0.1`)
* **DHCP Static Leases:** Proxmox VE (`192.168.0.2`), Laptop Host (`192.168.0.4`).
* **Static Route (LAN):** `10.10.20.0/24` via `192.168.0.4`.

### Proxmox VE (`192.168.0.2`)
* **Kernel IP Forwarding:** Persistent `net.ipv4.ip_forward = 1` configured in `/etc/sysctl.d/99-soc-tunnel.conf`.
* **SSH Layer 3 Tunneling:** Enabled `PermitTunnel point-to-point` in `/etc/ssh/sshd_config` to allow `root` to dynamically allocate `tun0` point-to-point interfaces.
* **Network Interfaces (`/etc/network/interfaces`):**
  * `vmbr0` (`192.168.0.2/24`, gateway `192.168.0.1`) with default dorm static route `up ip route add 10.10.20.0/24 via 192.168.0.4`.
  * `vmbr1` (`10.10.10.1/24`) — isolated internal bridge for Proxmox VMs.
  * `tun0` (`10.10.99.1/30` peer `10.10.99.2`, MTU `1300`) — dynamically provisioned during remote sessions.
* **Power Safeguard:** Automated daily 23:00 shutdown with calendar exemptions managed by [`proxmox-auto-shutdown.sh`](../04-scripts-and-tools/proxmox-auto-shutdown.sh).

### `rocky-hyper` SIEM & L3 Edge VPN Router (`10.10.20.10`)
* **Transport Layer:** `cloudflared` + Ed25519 key authentication establishes an outbound SSH-over-HTTPS (`TCP 443`) transport session to Proxmox.
* **MTU & Fragmentation Tuning:** Reduced interface MTU to `1350` on `eth0` and `1300` on `tun0` to prevent packet drops caused by nested encapsulation headers (Hyper-V vSwitch + Windows NAT + SSH + Cloudflare TLS).
* **Kernel & Package Manager:** Persistent `net.ipv4.ip_forward = 1` in `/etc/sysctl.d/99-soc-tunnel.conf` and `ip_resolve=4` in `/etc/dnf/dnf.conf`.
* **Firewalld Transit Policies:**
  * Because `tun0` is created dynamically at runtime, [`tunel-lab.sh`](../04-scripts-and-tools/tunel-lab.sh) binds it to the `trusted` zone upon tunnel initialization (`firewall-cmd --zone=trusted --add-interface=tun0`).
  * Bidirectional forwarding policies (`soc-tun-forward` and `soc-lan-forward`) permit unrestricted transit between `trusted` (`tun0`) and the default Hyper-V LAN zone.

### Laptop Host (`192.168.0.4`)
* **IP Forwarding:** Enabled on both the physical Wi-Fi/LAN adapter and `vEthernet (LabNAT)`.
* **Persistent Dorm Route:** `route -p add 10.10.10.0 mask 255.255.255.0 192.168.0.2`.
* **Dynamic Route Metric & WinNAT:** Managed automatically by [`soc-lab.ps1`](../04-scripts-and-tools/soc-lab.ps1). On the dorm LAN, `LabNATNetwork` (`10.10.20.0/24`) remains disabled so source IPs from `10.10.20.0/24` are not masqueraded. Off-campus, `LabNATNetwork` is enabled for outbound WAN access, and a higher-priority route (`metric 5`) directs `10.10.10.0/24` traffic to `rocky-hyper` (`10.10.20.10`).

---

## 5. Active SSH Aliases & Access Model

All nodes enforce passwordless Ed25519 key-based authentication. Because v2 provides full Layer 3 routing across both subnets in both operational modes, internal VMs are accessed via unified direct aliases regardless of physical location:

| Alias / Target | Endpoint | Authentication | Purpose & Behavior Across Modes |
| :--- | :--- | :--- | :--- |
| **`proxmox`** | `192.168.0.2` (`root`) | Ed25519 key | Direct local LAN shell to the Proxmox VE bare-metal host (on-campus only). |
| **`proxmox-wan`** | Cloudflare Edge (`TCP 443` via `cloudflared`) | Ed25519 key | Outbound HTTPS transport alias. Used by `rocky-hyper` to establish the `tun0` L3 tunnel, and by [`soc-lab.ps1`](../04-scripts-and-tools/soc-lab.ps1) to orchestrate Proxmox VMs off-campus. |
| **`rocky-pve`** | `10.10.10.10` (`root`) | Ed25519 key | Direct SSH access to the Rocky Linux target VM. Works identically on-campus (via Cudy router) and remotely (routed transparently through `rocky-hyper` and `tun0`). |
| **`winser`** | `10.10.10.20` (`Administrator`) | Ed25519 key (`administrators_authorized_keys`) | Direct SSH access to Windows Server (AD DS / DNS) across both LAN and remote L3 tunnel modes (also used for graceful `shutdown /s /t 0`). |
| **`rocky-hyper`** | `10.10.20.10` (`root`) | Ed25519 key | Local Hyper-V switch connection to the central Wazuh SIEM and L3 VPN edge router. |
| **`win11`** | `10.10.20.20` (`<WINDOWS_USER>`) | Ed25519 key (`administrators_authorized_keys`) | Local Hyper-V switch SSH access to the Windows 11 workstation for automated shutdown orchestration. |

---

## 6. Automated Lifecycle & Environment Switching

Manual route toggling, `WinNAT` management, tunnel initialization, and multi-hypervisor VM power sequencing are fully automated via [`soc-lab.ps1`](../04-scripts-and-tools/soc-lab.ps1) (exposed globally in Windows Terminal as `start-lab`, `stop-lab`, and `status-lab`) working in tandem with [`tunel-lab.sh`](../04-scripts-and-tools/tunel-lab.sh) on `rocky-hyper`.

### Single-Command Operations (Laptop Host)

```powershell
start-lab   # Auto-detects network mode, configures NAT/routes/tun0, and boots VMs in dependency order
status-lab  # Displays detected mode (On-Campus vs. Remote) and VM states across Hyper-V & Proxmox VE
stop-lab    # Gracefully shuts down all VMs, tears down tun0, and cleans up temporary host NAT/routes
```

### What Happens Under the Hood

1. **Context Detection (`Test-DormLan`):**
   * [`soc-lab.ps1`](../04-scripts-and-tools/soc-lab.ps1) probes `192.168.0.2:22` with a 1.5-second TCP socket check.
2. **On-Campus / Dorm Mode (`192.168.0.2:22` reachable):**
   * Ensures any leftover remote route (`metric 5`) and `LabNATNetwork` (`WinNAT`) are removed so `10.10.20.0/24` traffic is never masqueraded.
   * Starts Proxmox VMs (`rocky-pve`, `winser`) via `proxmox` and Hyper-V lab VMs (`Rocky-Linux`, `windows 11`).
   * Runs `/root/tunel-lab.sh stop` on `rocky-hyper` to guarantee `tun0` is closed and Proxmox routes `10.10.20.0/24` directly via `192.168.0.4`.
3. **Remote / Off-Campus Mode (`192.168.0.2:22` unreachable):**
   * Enables `LabNATNetwork` (`WinNAT`) and injects `route add 10.10.10.0 mask 255.255.255.0 10.10.20.10 metric 5` on the laptop host.
   * Boots `Rocky-Linux` (`rocky-hyper`) first, waits for SSH readiness, and executes `/root/tunel-lab.sh start` to establish `tun0` (`10.10.99.0/30`) over Cloudflare.
   * Boots Proxmox VMs via `proxmox-wan`, followed by `windows 11` in Hyper-V.
   * *(One-time prerequisite on `win11` for off-campus AD/DNS access bypassing `WinNAT`: `route -p add 10.10.10.0 mask 255.255.255.0 10.10.20.10`).*
4. **Graceful Teardown (`stop-lab`):**
   * Shuts down endpoints first (`win11`, `rocky-pve`), then Domain Controller (`winser` via `shutdown /s /t 0`), then executes `/root/tunel-lab.sh stop && poweroff` on `rocky-hyper` (restoring Proxmox's dorm return route), and finally removes `WinNAT` and `metric 5` on the laptop.

### Diagnostics & Operational Safeguards
* **Network & Routing Audit:** Run [`lab-network-check.ps1`](../04-scripts-and-tools/lab-network-check.ps1) (`check-lab`) to verify active route metrics, `WinNAT` consistency with the current mode, and TCP reachability across all 6 nodes.
* **Proxmox Auto-Shutdown:** [`proxmox-auto-shutdown.sh`](../04-scripts-and-tools/proxmox-auto-shutdown.sh) powers down the Proxmox host daily at `23:00` unless exempted (`auto-shutdown today` or date ranges).
* **Campus DNS Filtering:** Upstream campus firewalls drop `UDP 53` traffic to public resolvers (`8.8.8.8` / `1.1.1.1`) when routed directly without NAT. Off-campus behind `WinNAT`, public resolvers function normally.
* **Proxmox Console & Graceful Windows Shutdown:** For Rocky Linux (VM 101), use the graphical `noVNC` console (`xterm.js` requires manual `getty` binding to `ttyS0`). For Windows Server (VM 102), always shut down via SSH (`shutdown /s /t 0`) rather than `qm shutdown`/`qm stop` unless `virtio-win-guest-tools` is installed, preventing ACPI lock timeouts and protecting the Active Directory `NTDS.dit` database.

---

## 7. Phase 2 Roadmap (SOC Services Deployment)

* **Wazuh SIEM (`10.10.20.10`):** Audit core services (`wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard`) and verify Web UI access (`https://10.10.20.10`).
* **Active Directory (`10.10.10.20`):** Verify/harden AD DS and DNS roles, Organizational Units (OUs), GPOs, and test user accounts.
* **Domain Integration (`10.10.20.20`):** Join the Windows 11 workstation to the Active Directory domain and verify Kerberos/LDAP/DNS across both LAN and L3 tunnel modes.
* **Telemetry & Agents:** Deploy Sysmon (using SwiftOnSecurity / Olaf Hartong modular configs) and enroll Wazuh agents across `winser`, `win11`, and `rocky-pve`.