#!/usr/bin/env bash
# ============================================================
#   Wazuh Single-Node Installer (Ubuntu 22.04, OpenStack)
#   100% Idempotente y Autoconfigurado
# ============================================================
set -euo pipefail

START_TIME=$(date +%s)
ADMIN_PASS_FILE="/tmp/wazuh-admin-password"
WAZUH_DIR="/var/ossec"

# -------------------------------
# Pretty Print
# -------------------------------
ok()   { echo -e "  \e[32m✔\e[0m $1"; }
warn() { echo -e "  \e[33m⚠\e[0m $1"; }
err()  { echo -e "  \e[31m✖ $1\e[0m"; }

# -------------------------------
# Floating IP detection
# -------------------------------
detect_ip() {
    echo "🔎 Detectando Floating IP desde OpenStack metadata"

    META=$(curl -s http://169.254.169.254/openstack/latest/meta_data.json || true)

    if [[ -n "$META" ]]; then
        INSTANCE_ID=$(echo "$META" | grep '"uuid"' | awk -F'"' '{print $4}')
        ADDR=$(openstack server show "$INSTANCE_ID" -c addresses -f value 2>/dev/null || true)
        FLOATING=$(echo "$ADDR" | sed 's/.*=//' | awk -F',' '{print $NF}' | tr -d ' ')
    fi

    if [[ -n "$FLOATING" ]]; then
        IP="$FLOATING"
        ok "Floating IP detectada: $IP"
        return
    fi

    warn "No fue posible detectar Floating IP → usar IP interna"
    IP=$(hostname -I | awk '{print $1}')
}
detect_ip

echo "🌍 Dashboard previsto: https://$IP"
echo


# -------------------------------
# Idempotencia real
# -------------------------------
is_ok() {
    systemctl is-active --quiet wazuh-indexer.service &&
    systemctl is-active --quiet wazuh-manager.service &&
    systemctl is-active --quiet wazuh-dashboard.service
}

if is_ok; then
    ok "Wazuh YA está instalado y activo"
    PASS=$(cat "$ADMIN_PASS_FILE" 2>/dev/null || echo "<No detectada>")
    echo "🌐 URL: https://$IP"
    echo "🔑 Admin password: $PASS"
    exit 0
fi


echo "🆕 Wazuh NO detectado → instalación nueva"
echo "[1/5] 🔄 Preparando sistema..."
sudo apt-get update -y
sudo apt-get install -y curl lsb-release net-tools jq


echo "[2/5] 📥 Descargando instalador oficial Wazuh..."
sudo curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh


echo "[3/5] 🏗 Ejecutando instalación oficial con auto-configuración..."
sudo bash ./wazuh-install.sh -a > /tmp/wazuh-install.log 2>&1 || true


echo "[4/5] 🔑 Extrayendo contraseña admin real..."
if [[ -f wazuh-install-files.tar ]]; then
    PASS=$(sudo tar -axf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -O \
        | grep -P "'admin'" -A1 \
        | tail -n1 \
        | awk -F"'" '{print $2}')

    echo "$PASS" | sudo tee "$ADMIN_PASS_FILE" >/dev/null
else
    warn "No se pudo extraer automáticamente → usar tar manual"
    PASS="<No detectada>"
fi


echo "[5/5] 🚀 Activando y arrancando servicios..."
sudo systemctl daemon-reload || true
sudo systemctl enable wazuh-indexer.service || true
sudo systemctl enable wazuh-manager.service || true
sudo systemctl enable wazuh-dashboard.service || true

sudo systemctl restart wazuh-indexer.service || true
sudo systemctl restart wazuh-manager.service || true
sudo systemctl restart wazuh-dashboard.service || true

sleep 6


# -------------------------------
# Validación final
# -------------------------------
echo
echo "🧪 Validando instalación real Wazuh..."
FAILED=false

systemctl is-active --quiet wazuh-indexer.service || FAILED=true
systemctl is-active --quiet wazuh-manager.service || FAILED=true
systemctl is-active --quiet wazuh-dashboard.service || FAILED=true

if sudo curl -k --max-time 5 "https://$IP" >/dev/null 2>&1; then
    ok "Dashboard responde HTTPS"
else
    warn "Dashboard NO responde HTTPS"
    FAILED=true
fi

if $FAILED; then
    err "❌ Instalación incompleta o servicios no levantaron"
    echo "📄 Log oficial: /tmp/wazuh-install.log"
    exit 1
fi


# -------------------------------
# Instalación correcta
# -------------------------------
END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))

echo
echo "===================================================="
echo "🎉 Wazuh INSTALADO y FUNCIONANDO correctamente"
echo "⏱ Tiempo total: $((TOTAL / 60))m $((TOTAL % 60))s"
echo "===================================================="
echo "🌐 Dashboard: https://$IP"
echo "🔐 Usuario: admin"
echo "🔑 Password: $PASS"
echo
echo "📄 Log instalación: /tmp/wazuh-install.log"
echo "===================================================="
