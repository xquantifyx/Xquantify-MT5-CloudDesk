#!/bin/bash
# secure-firewall.sh
# Safe UFW setup: allows SSH, HTTP, HTTPS, App port 8000

set -e

echo "🔐 Configuring firewall safely..."

sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8000/tcp

# Enable with auto-confirm
echo "y" | sudo ufw enable

# Show status
sudo ufw status verbose

echo "✅ Firewall is active and secured!"
#chmod +x secure-firewall.sh
#./secure-firewall.sh
