#!/bin/bash

INSTANCE="$1"
IP="$2"
USER="$3"

echo "🔥 Instalando Wazuh en $INSTANCE ($IP)..."

ssh -o StrictHostKeyChecking=no "$USER@$IP" << 'EOF'
sudo apt update -y
sudo apt install -y curl gnupg apt-transport-https

curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo tee /etc/apt/trusted.gpg.d/wazuh.asc >/dev/null

echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list >/dev/null

sudo apt update -y
sudo apt install -y wazuh-agent

sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
EOF

echo "✔ Wazuh instalado correctamente en $INSTANCE"
