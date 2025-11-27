#!/bin/bash

INSTANCE="$1"
IP="$2"
USER="$3"

echo "🔥 Instalando Snort 3 en $INSTANCE ($IP)..."

ssh -o StrictHostKeyChecking=no "$USER@$IP" << 'EOF'
sudo apt update -y
sudo apt install -y snort
EOF

echo "✔ Snort instalado correctamente en $INSTANCE"
