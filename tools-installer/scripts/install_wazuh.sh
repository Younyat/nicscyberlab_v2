#!/usr/bin/env bash
#
# ============================================================
#       Wazuh Manager Installer (Idempotent + Floating IP)
# ============================================================
set -euo pipefail

START_TIME=$(date +%s)
WAZUH_PASS_FILE="/tmp/wazuh-admin-password"
WAZUH_DIR="/var/ossec"
ADMIN_PASS=""

format_time() {
    local t=$1
    printf "%dm %ds\n" $((t/60)) $((t%60))
}

echo "===================================================="
echo "🚀 Instalador de Wazuh Manager"
echo "===================================================="

# -----------------------------------------------------
# 💠 IP Floating recibida como parámetro
# -----------------------------------------------------
FLOATING_IP=""

if [[ $# -ge 1 ]]; then
    FLOATING_IP="$1"
    echo "🌍 Floating IP recibida desde el master installer: $FLOATING_IP"
fi

# -----------------------------------------------------
# 📌 Función fallback: obtener Floating IP desde OpenStack
# -----------------------------------------------------
get_floating_ip() {
    local instance_name="$1"
    openstack server show "$instance_name" -f json \
        | jq -r '.addresses' \
        | grep -oP '((?:[0-9]{1,3}\.){3}[0-9]{1,3})' \
        | tail -n1
}

if [[ -z "$FLOATING_IP" ]]; then
    echo "⚠️ No se recibió Floating IP como parámetro."
    echo "   🧪 Intentando detectarla automáticamente usando OpenStack..."
    INSTANCE_NAME=$(hostname)

    if command -v openstack >/dev/null 2>&1; then
        FLOATING_IP=$(get_floating_ip "$INSTANCE_NAME" || true)
    fi

    if [[ -z "$FLOATING_IP" ]]; then
        echo "❌ No pude detectar Floating IP. Se usará IP interna."
        FLOATING_IP=$(hostname -I | awk '{print $1}')
    fi
fi

echo "🌐 IP final detectada para Dashboard: $FLOATING_IP"
echo "----------------------------------------------------"


# -----------------------------------------------------
# 🧠 DETECCIÓN: ¿Ya está instalado Wazuh?
# -----------------------------------------------------
ALREADY=false

# 1) Detectar estructura de instalación
if [[ -d "$WAZUH_DIR" ]]; then
    echo "✔ Instalación existente detectada: $WAZUH_DIR"
    ALREADY=true
fi

# 2) Servicio corriendo
if systemctl is-active --quiet wazuh-manager.service; then
    echo "✔ Servicio wazuh-manager activo"
    ALREADY=true
fi

# 3) Puertos de Wazuh
if ss -tunlp | grep -Eq ":1515|:55000"; then
    echo "✔ Puertos Wazuh detectados"
    ALREADY=true
fi

# 4) Password previa
if [[ -f "$WAZUH_PASS_FILE" ]]; then
    ADMIN_PASS=$(cat "$WAZUH_PASS_FILE")
fi


# -----------------------------------------------------
# 🔸 SI YA ESTÁ INSTALADO → SALIR
# -----------------------------------------------------
if $ALREADY; then
    echo
    echo "===================================================="
    echo "🎉 Wazuh ya está instalado en esta máquina"
    echo "===================================================="

    echo "🌍 Dashboard: https://$FLOATING_IP"
    echo "🔑 Usuario: admin"

    if [[ -n "$ADMIN_PASS" ]]; then
        echo "🔑 Password: $ADMIN_PASS"
    else
        echo "⚠ No se detectó password."
        echo "   Puedes recuperarla así:"
        echo "   sudo tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"
    fi

    echo "✔ Instalación confirmada. EXIT."
    exit 0
fi


# -----------------------------------------------------
# 🚧 INSTALACIÓN NUEVA
# -----------------------------------------------------
echo
echo "🆕 No detectada instalación previa. Instalando Wazuh Manager..."
export DEBIAN_FRONTEND=noninteractive

echo "[1/6] 🔄 Actualizando sistema..."
sudo apt-get update -y >/dev/null
sudo apt-get upgrade -y >/dev/null

echo "[2/6] 🔧 Instalando dependencias..."
sudo apt-get install -y curl net-tools >/dev/null

echo "[3/6] 📥 Descargando instalador oficial..."
cd /tmp
sudo curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh

echo "[4/6] 🧩 Ejecutando instalador..."
sudo bash ./wazuh-install.sh -a >/tmp/wazuh-install.log 2>&1 || true

echo "[5/6] 🔑 Extrayendo contraseña..."
if [[ -f wazuh-install-files.tar ]]; then
    ADMIN_PASS=$(sudo tar -axf wazuh-install-files.tar \
        wazuh-install-files/wazuh-passwords.txt -O \
        | grep -P "'admin'" -A 1 \
        | tail -n 1 \
        | awk -F"'" '{print $2}')

    echo "$ADMIN_PASS" | sudo tee "$WAZUH_PASS_FILE" >/dev/null
fi

echo "[6/6] 🔍 Comprobando servicio..."
if systemctl is-active --quiet wazuh-manager.service; then
    echo "✔ Servicio ACTIVO"
else
    echo "❌ ADVERTENCIA: wazuh-manager no parece estar activo"
fi

echo "[+] Verificando puerto 1515..."
if ss -tunlp | grep -q ":1515"; then
    echo "✔ Puerto 1515 abierto"
else
    echo "❌ Puerto 1515 NO está abierto"
fi


# -----------------------------------------------------
# 🎉 FIN INSTALACIÓN
# -----------------------------------------------------
END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))

echo
echo "===================================================="
echo "🎉 Instalación completa de Wazuh Manager"
echo "⏱ Tiempo total: $(format_time $TOTAL)"
echo "===================================================="

echo "🌍 URL Dashboard:"
echo "    https://$FLOATING_IP"
echo
echo "🔑 Credenciales:"
echo "    Usuario : admin"
echo "    Password: ${ADMIN_PASS:-<NO DETECTADA>}"
echo
echo "📄 Log instalación: /tmp/wazuh-install.log"
echo
