#!/bin/bash

INSTANCE="$1"
IP="$2"
USER="$3"

echo "🔥 Instalando Suricata en $INSTANCE ($IP)..."

ssh -o StrictHostKeyChecking=no "$USER@$IP" << 'EOF'
sudo apt update -y
sudo apt install -y suricata

sudo systemctl enable suricata
sudo systemctl start suricata
EOF

echo "✔ Suricata instalado correctamente en $INSTANCE"
