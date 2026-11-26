#!/usr/bin/env bash
# Manages the on-demand Site-to-Site Layer 3 IP tunnel (tun0) between
# the Hyper-V SIEM edge router (10.10.20.10) and Proxmox VE (192.168.0.2)
# encapsulated inside Cloudflare Zero Trust (TCP 443).

set -euo pipefail

REMOTE_HOST="proxmox-wan"
TUN_LOCAL="10.10.99.2"
TUN_REMOTE="10.10.99.1"
PVE_SUBNET="10.10.10.0/24"
HYPER_SUBNET="10.10.20.0/24"
DORM_LAPTOP_IP="192.168.0.4"

case "${1:-}" in
  start)
    echo "[1/4] Cleaning up previous tunnel session..."
    pkill -f "ssh .* -w 0:0 .* ${REMOTE_HOST}" 2>/dev/null || true
    ip link del tun0 2>/dev/null || true

    echo "[2/4] Establishing Layer 3 tunnel (tun0) over Cloudflare..."
    ssh -f -N -w 0:0 \
      -o BatchMode=yes \
      -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=3 \
      -o ExitOnForwardFailure=yes \
      "${REMOTE_HOST}"

    for i in {1..15}; do
      ip link show tun0 >/dev/null 2>&1 && break
      sleep 0.5
    done

    echo "[3/4] Configuring tun0, firewall zone, and route on rocky-hyper..."
    ip link set tun0 mtu 1300 up
    firewall-cmd --zone=trusted --add-interface=tun0 >/dev/null 2>&1 || true
    ip addr replace "${TUN_LOCAL}/30" peer "${TUN_REMOTE}" dev tun0
    ip route replace "${PVE_SUBNET}" via "${TUN_REMOTE}" dev tun0

    echo "[4/4] Configuring tun0 and return route on Proxmox..."
    ssh -o BatchMode=yes "${REMOTE_HOST}" "
      ip link set tun0 mtu 1300 up &&
      ip addr replace ${TUN_REMOTE}/30 peer ${TUN_LOCAL} dev tun0 &&
      ip route replace ${HYPER_SUBNET} via ${TUN_LOCAL} dev tun0
    "

    echo "=== L3 TUNNEL VERIFICATION ==="
    ping -c 2 -W 2 "${TUN_REMOTE}" >/dev/null && echo "[OK] Point-to-point tun0 (${TUN_REMOTE})"
    ping -c 2 -W 2 10.10.10.10 >/dev/null && echo "[OK] rocky-hyper -> rocky-pve (10.10.10.10)"
    ;;

  stop)
    echo "[1/2] Restoring dorm route on Proxmox and removing tun0..."
    ssh -o BatchMode=yes "${REMOTE_HOST}" "
      ip route replace ${HYPER_SUBNET} via ${DORM_LAPTOP_IP} 2>/dev/null || true
      ip link del tun0 2>/dev/null || true
    " 2>/dev/null || true

    echo "[2/2] Closing local tunnel on rocky-hyper..."
    pkill -f "ssh .* -w 0:0 .* ${REMOTE_HOST}" 2>/dev/null || true
    ip route del "${PVE_SUBNET}" 2>/dev/null || true
    ip link del tun0 2>/dev/null || true
    echo "[OK] Remote L3 tunnel closed."
    ;;

  status)
    ip addr show tun0 2>/dev/null || echo "tun0: inactive"
    ip route show "${PVE_SUBNET}" || true
    ;;

  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac