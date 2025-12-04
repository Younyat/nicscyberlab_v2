#!/usr/bin/env bash
set -euo pipefail

INSTANCE="$1"
IP_PRIV="$2"
IP_FLOAT="$3"
USER="$4"

IP="${IP_FLOAT:-$IP_PRIV}"

echo "❎ Desinstalando Wazuh en $INSTANCE ($IP)..."

# ---------------------------------------------------------
# Detectar key SSH
# ---------------------------------------------------------
SSH_KEY=""
for K in "$HOME/.ssh/"*; do
    [[ -f "$K" ]] && grep -q "PRIVATE KEY" "$K" && SSH_KEY="$K" && break
done

if [[ -z "$SSH_KEY" ]]; then
    echo "❌ ERROR: No se encontró ninguna key privada SSH"
    exit 1
fi

chmod 600 "$SSH_KEY"

# ==========================================================
# TODA la limpieza + validación se hace REMOTAMENTE
# ==========================================================
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$IP" bash <<'EOF'
set -euo pipefail

echo "🧹 Eliminando servicios..."
sudo systemctl stop wazuh-manager 2>/dev/null || true
sudo systemctl disable wazuh-manager 2>/dev/null || true

sudo systemctl stop filebeat 2>/dev/null || true
sudo systemctl disable filebeat 2>/dev/null || true

echo "🧹 Purga de paquetes..."
sudo apt purge -y wazuh* filebeat 2>/dev/null || true

echo "🧹 Eliminando directorios residuales..."
sudo rm -rf /var/ossec /etc/ossec* /opt/wazuh* 2>/dev/null || true

# =======================================
# VALIDACIÓN FINAL DENTRO DE LA INSTANCIA
# =======================================
HAS_WAZUH=false

# servicios
systemctl list-units | grep -q "wazuh" && HAS_WAZUH=true

# paquetes
dpkg -l | grep -q "wazuh" && HAS_WAZUH=true

# carpetas
[[ -d "/var/ossec" ]] && HAS_WAZUH=true

# binarios
command -v wazuh-control >/dev/null 2>&1 && HAS_WAZUH=true

# puertos
ss -tunlp | grep -q ":1515" && HAS_WAZUH=true

echo "🧽 Validando eliminación de Wazuh..."

if [[ "$HAS_WAZUH" == false ]]; then
    echo "✔ LIMPIEZA CORRECTA: No quedan rastros de Wazuh."
    exit 0
else
    echo "❌ VALIDACIÓN FALLIDA: Aún quedan restos."
    exit 3
fi
EOF
