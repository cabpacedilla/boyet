#!/bin/bash

# Option 2: Custom user (safer than using claiveapa)
# Create a dedicated account:
#
# bash
# Copy
# Edit
# sudo useradd --system --no-create-home --shell /bin/false torproxy
# Update torrc:
#
# sql
# Copy
# Edit
# User torproxy
# Fix permissions:
#
# bash
# Copy
# Edit
# sudo chown -R torproxy:torproxy /var/lib/tor /var/log/tor
# Restart service.

set -euo pipefail
IFS=$'\n'

# Nobara Tor Browser Network Isolation Script (Firewalld Version)
# Author: Claive + ChatGPT
# Date: 2025-08-10
# Description:
#   Isolates Tor Browser in its own user account and routes its traffic through Tor
#   using Firewalld rich rules. Applies AppArmor profile for extra sandboxing.

TOR_USER="torbrowser"
TOR_SERVICE_NAME="tor"
TOR_TRANSPORT_PORT=9040
TOR_DNS_PORT=5353
APPARMOR_PROFILE="/etc/apparmor.d/torbrowser"

echo "This script will:
 - Install Tor, Firejail, AppArmor utils, and Tor Browser Launcher (if available)
 - Create system user: ${TOR_USER}
 - Configure /etc/tor/torrc with TransPort=${TOR_TRANSPORT_PORT} and DNSPort=${TOR_DNS_PORT}
 - Add Firewalld rules to force Tor Browser traffic through Tor
 - Create AppArmor profile for Tor Browser
 - Create launcher: /usr/local/bin/torbrowser-sandbox
Before continuing: ensure you have console access if running remotely.
Type 'yes' to continue:"
read -r CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo "==> Installing packages..."
sudo dnf -y update
sudo dnf -y install tor torsocks firejail apparmor apparmor-utils apparmor-profiles firewalld torbrowser-launcher || true

echo "==> Enabling Tor service..."
sudo systemctl enable --now "${TOR_SERVICE_NAME}"

echo "==> Creating Tor Browser user..."
if ! id "${TOR_USER}" >/dev/null 2>&1; then
    sudo useradd -m -s /usr/sbin/nologin "${TOR_USER}"
fi

echo "==> Configuring Tor..."
sudo bash -c "cat > /etc/tor/torrc" <<EOF
Log notice file /var/log/tor/notices.log
RunAsDaemon 1
User ${TOR_USER}
TransPort 127.0.0.1:${TOR_TRANSPORT_PORT}
DNSPort 127.0.0.1:${TOR_DNS_PORT}
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
EOF
sudo systemctl restart "${TOR_SERVICE_NAME}"

echo "==> Configuring Firewalld rules..."
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --new-zone=torbrowser
sudo firewall-cmd --permanent --zone=torbrowser --add-source=127.0.0.1
sudo firewall-cmd --permanent --zone=torbrowser --add-port=${TOR_TRANSPORT_PORT}/tcp
sudo firewall-cmd --permanent --zone=torbrowser --add-port=${TOR_DNS_PORT}/udp
sudo firewall-cmd --permanent --zone=torbrowser --add-rich-rule="rule family='ipv4' source address='0.0.0.0/0' reject"
sudo firewall-cmd --reload

echo "==> Creating AppArmor profile..."
sudo bash -c "cat > ${APPARMOR_PROFILE}" <<EOF
#include <tunables/global>
profile torbrowser /usr/bin/torbrowser-launcher {
  #include <abstractions/base>
  #include <abstractions/X>
  network inet tcp,
  network inet udp,
  deny network raw,
}
EOF
sudo apparmor_parser -r "${APPARMOR_PROFILE}"

echo "==> Creating sandbox launcher..."
sudo bash -c "cat > /usr/local/bin/torbrowser-sandbox" <<'EOF'
#!/bin/bash
set -e
TOR_USER="torbrowser"
firejail --apparmor --noprofile --net=torbrowser --dns=127.0.0.1 torbrowser-launcher
EOF
sudo chmod +x /usr/local/bin/torbrowser-sandbox

echo "==> Done!"
echo "Run Tor Browser with: torbrowser-sandbox"
