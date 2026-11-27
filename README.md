# SOC Learning Log & Blue Team Journal

> **Hands-on documentation tracking my progression toward a SOC Analyst (Tier 1) role** — covering multi-hypervisor homelab engineering, Wazuh SIEM detection, TryHackMe defensive paths, and Cisco CCNA networking.

![Focus: SOC Tier 1](https://img.shields.io/badge/Focus-SOC_Tier_1-94D2BD?style=flat-square)
![SIEM: Wazuh](https://img.shields.io/badge/SIEM-Wazuh-005F73?style=flat-square)
![Networking: CCNA Prep](https://img.shields.io/badge/Networking-CCNA_Prep-0A9396?style=flat-square)
![Labs: TryHackMe](https://img.shields.io/badge/Labs-TryHackMe-2A9D8F?style=flat-square)

---

## 🎯 Purpose

This repository serves as a structured technical journal and portfolio. Instead of keeping raw scratchpads, every entry here is a curated write-up focusing on **network architecture, log analysis methodology, alert triage, and reproducible lab configurations**.

---

## 📂 Repository Structure

```text
soc-learning-log/
├── 01-homelab-and-siem/      # Proxmox VE, Hyper-V, Rocky Linux, Windows Server (AD), Wazuh & Sysmon
├── 02-tryhackme-labs/        # SOC Level 1 path write-ups (investigation methodology, no flag spoilers)
├── 03-networking-and-certs/  # Cisco CCNA study notes, packet captures (Wireshark), subnetting & routing
├── 04-scripts-and-tools/     # Python & Bash utility scripts for log parsing and system checks
├── assets/                   # Network diagrams and sanitized alert screenshots
└── README.md                 # Repository index
```

---

## 📑 Contents & Lab Index

### 01. Homelab & SIEM Infrastructure
| Document                                                                                                 | Focus Area                                                                            | Status          |
| :------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------ | :-------------- |
| [SOC Home Lab — Network & Infrastructure Architecture (v2)](01-homelab-and-siem/network-architecture.md) | Hybrid Dual-Mode L3 Routing, Proxmox VE, Hyper-V, Site-to-Site `tun0` over Cloudflare | ✅ Completed     |
| [SOC Home Lab — Network Architecture v1 (Legacy)](01-homelab-and-siem/network-architecture-v1-legacy.md) | Initial LAN Static Routing & SSH `ProxyJump` / `LocalForward` Design                  | 🗄️ Archived    |
| [SOC Home Lab — Services, SIEM & Telemetry Deployment](01-homelab-and-siem/soc-services-deployment.md)   | Wazuh SIEM/XDR, Active Directory (AD DS/DNS), Sysmon, Wazuh Agents                    | 🛠️ In Progress |

### 02. TryHackMe Defensive Labs
Entries are added progressively as rooms in the SOC Level 1 learning path are completed.

### 03. Networking & Certifications (CCNA)
Study notes, routing labs, and Wireshark traffic analysis are currently in preparation.

### 04. Scripts & Automation
| Script | Language | Purpose |
| :--- | :--- | :--- |
| [soc-lab.ps1](04-scripts-and-tools/soc-lab.ps1) | PowerShell | Context-aware lab orchestrator (`start` / `stop` / `status`) managing VM states, `WinNAT`, route metrics, and L3 tunnel lifecycle |
| [tunel-lab.sh](04-scripts-and-tools/tunel-lab.sh) | Bash | Establishes and tears down the on-demand Site-to-Site Layer 3 tunnel (`tun0`, `10.10.99.0/30`) over Cloudflare Zero Trust |
| [lab-network-check.ps1](04-scripts-and-tools/lab-network-check.ps1) | PowerShell | Audits active L3 routes, `WinNAT` state, and TCP port reachability across all lab subnets |
| [proxmox-auto-shutdown.sh](04-scripts-and-tools/proxmox-auto-shutdown.sh) | Bash | Automates daily hypervisor shutdown (`23:00`) via cron with calendar exception support and syslog logging |

---

## 🛡️ Documentation & Privacy Standards

In line with **Privacy by Design** and platform guidelines:
* **Sanitized Configurations:** All IP addresses documented in this repository belong to private RFC 1918 ranges (`10.10.x.x`, `192.168.0.x`), and all credentials, keys, or personal domains are stripped.
* **No Spoilers:** TryHackMe write-ups focus strictly on tooling, filtering syntax, and analytical reasoning without exposing direct answers or flags.

---

[← Back to GitHub Profile](https://github.com/Beanshie)