#!/bin/bash
# tor_persistent_iptables.sh
# Redirect only Tor Browser traffic via Tor's TransPort/DNSPort
# Works with iptables-services persistence

TOR_UID=$(id -u torbrowser)

# Flush existing NAT rules for cleanliness
sudo iptables -t nat -F

# Redirect all TCP from torbrowser user to Tor's TransPort
sudo iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -p tcp -j REDIRECT --to-ports 9040

# Redirect DNS requests from torbrowser user to Tor's DNSPort
sudo iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -p udp --dport 53 -j REDIRECT --to-ports 5353

# Save the rules so they load at boot
sudo service iptables save

# Enable iptables service for persistence
sudo systemctl enable iptables
