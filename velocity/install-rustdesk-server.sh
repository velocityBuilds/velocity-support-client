#!/usr/bin/env bash
# VelocitySupport - RustDesk self-hosted server installer
# For Oracle Cloud Free Tier, Ubuntu 22.04/24.04 (Ampere ARM or AMD).
# Usage on the VM:  curl -fsSL <raw-url> | sudo bash     (or: sudo bash install-rustdesk-server.sh)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo"; exit 1; fi

echo "==> Installing Docker"
apt-get update -y
if ! command -v docker >/dev/null; then
  apt-get install -y docker.io || curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y docker-compose-v2 || apt-get install -y docker-compose-plugin
fi
systemctl enable --now docker

echo "==> Opening firewall ports on the VM (Oracle images block them by default)"
apt-get install -y iptables-persistent netfilter-persistent >/dev/null 2>&1 || true
open_port() { # proto port
  iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 5 -p "$1" -m state --state NEW --dport "$2" -j ACCEPT
}
for p in 21114 21115 21116 21117 21118 21119; do open_port tcp $p; done
open_port udp 21116
netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4

echo "==> Starting RustDesk server (hbbs + hbbr)"
mkdir -p /opt/rustdesk-server/data
cat > /opt/rustdesk-server/docker-compose.yml <<'YML'
services:
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server:latest
    command: hbbs
    volumes:
      - ./data:/root
    network_mode: host
    depends_on:
      - hbbr
    restart: unless-stopped
  hbbr:
    container_name: hbbr
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    volumes:
      - ./data:/root
    network_mode: host
    restart: unless-stopped
YML
cd /opt/rustdesk-server
docker compose pull
docker compose up -d

echo "==> Waiting for key to be generated"
for i in $(seq 1 30); do [ -s data/id_ed25519.pub ] && break; sleep 1; done

IP=$(curl -fsS -4 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
echo
echo "=============================================================="
echo " RustDesk server is running."
echo
echo "  VELOCITY_SERVER = $IP"
echo "  VELOCITY_KEY    = $(cat data/id_ed25519.pub)"
echo
echo " Put both values in GitHub: Settings > Secrets and variables >"
echo " Actions > Variables, then re-run the build."
echo " BACK UP /opt/rustdesk-server/data/id_ed25519* - if you lose"
echo " them, every customer client must be rebuilt."
echo "=============================================================="
