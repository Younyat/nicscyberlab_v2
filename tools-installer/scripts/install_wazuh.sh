#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo "🚀 Instalando Wazuh Manager dentro de la instancia"
echo "===================================================="

START_TIME=$(date +%s)

# -------------------------------
# Actualizar repos y paquetes
# -------------------------------
echo "[+] Actualizando sistema..."
sudo apt-get update -y >/dev/null
sudo apt-get upgrade -y >/dev/null

# -------------------------------
# Instalar dependencias
# -------------------------------
echo "[+] Instalando dependencias necesarias..."
sudo apt-get install -y curl net-tools >/dev/null

# -------------------------------
# Descargar Wazuh
# -------------------------------
cd /tmp
echo "[+] Descargando instalador oficial de Wazuh..."
sudo curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh

# -------------------------------
# Ejecutar instalación
# -------------------------------
echo "[+] Ejecutando instalador automático..."
sudo bash ./wazuh-install.sh -a >/tmp/wazuh-install.log 2>&1 || true

# -------------------------------
# Extraer contraseña admin
# -------------------------------
echo "[+] Obteniendo contraseña admin..."

ADMIN_PASS=""

if [ -f wazuh-install-files.tar ]; then
    ADMIN_PASS=$(sudo tar -axf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -O \
        | grep -P "'admin'" -A 1 \
        | tail -n 1 \
        | awk -F"'" '{print $2}')
    
    echo "$ADMIN_PASS" | sudo tee /tmp/wazuh-admin-password >/dev/null
fi

# -------------------------------
# Verificar servicio
# -------------------------------
echo "[+] Comprobando estado del servicio wazuh-manager..."
if sudo systemctl status wazuh-manager.service --no-pager >/dev/null 2>&1; then
    echo "✔ Servicio wazuh-manager activo."
else
    echo "❌ Advertencia: wazuh-manager no parece estar activo."
fi

# -------------------------------
# Check puerto 1515
# -------------------------------
echo "[+] Comprobando puerto 1515..."
if sudo netstat -tuln | grep 1515 >/dev/null; then
    echo "✔ Puerto 1515 abierto correctamente."
else
    echo "❌ Puerto 1515 NO está abierto. Verifica configuración."
fi

END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))

echo "===================================================="
echo "🎉 Instalación de Wazuh completada"
echo "⏱ Tiempo total: ${TOTAL}s"
echo "===================================================="

if [[ -n "$ADMIN_PASS" ]]; then
    MY_IP=$(hostname -I | awk '{print $1}')

    echo "🔑 Credenciales para Panel Web:"
    echo "URL       : https://$MY_IP"
    echo "Usuario   : admin"
    echo "Password  : $ADMIN_PASS"
else
    echo "⚠ No se pudo obtener la contraseña admin automáticamente."
    echo "   Ejecútalo dentro de la instancia:"
    echo "   sudo tar -O -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"
fi

