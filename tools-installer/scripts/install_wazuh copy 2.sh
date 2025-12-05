#!/usr/bin/env bash
# ============================================================
#   Wazuh Single-Node Installer
#   Ubuntu 22.04 (VM OpenStack)
#   Idempotente y Autoverificado
# ============================================================
set -euo pipefail

START_TIME=$(date +%s)
ADMIN_PASS_FILE="/tmp/wazuh-admin-password"
WAZUH_DIR="/var/ossec"
LOG_FILE="/tmp/wazuh-install.log"

PASS=""

ok()   { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err()  { echo "[ERROR] $1"; }

# ------------------------------------------------------------
# Comprobar privilegios sudo
# ------------------------------------------------------------
if ! sudo -n true 2>/dev/null; then
    err "El usuario actual no tiene privilegios sudo o requiere contraseña"
    exit 1
fi

# ------------------------------------------------------------
# Floating IP
# ------------------------------------------------------------
FINAL_IP="${1:-}"

if [[ -z "$FINAL_IP" ]]; then
    echo "No se recibió IP como argumento"
    echo "Detectando IP local..."
    FINAL_IP=$(hostname -I | awk '{print $1}')
fi

echo "IP final para Dashboard: $FINAL_IP"
echo "URL prevista: https://$FINAL_IP"


# ------------------------------------------------------------
# Validación de instalación previa
# ------------------------------------------------------------
is_ok() {
    systemctl is-active --quiet wazuh-indexer.service &&
    systemctl is-active --quiet wazuh-manager.service &&
    systemctl is-active --quiet wazuh-dashboard.service &&
    curl -k --max-time 3 "https://$FINAL_IP" >/dev/null 2>&1
}

if is_ok; then
    ok "Wazuh ya está completamente instalado y operativo"
    PASS=$(cat "$ADMIN_PASS_FILE" 2>/dev/null || echo "<No detectada>")
    echo "URL: https://$FINAL_IP"
    echo "Admin password: $PASS"
    exit 0
fi




# ------------------------------------------------------------
# Sanidad de dpkg/APT antes de instalar Wazuh
# ------------------------------------------------------------
echo "[0/6] Validando estado del sistema APT/DPKG..."

# 1) Paquetes residuales en dpkg
RESIDUAL_DPKG=$(dpkg -l \
  | awk '/^rc|^pF|^iF|^ic/ && /wazuh|filebeat|opensearch/ {print $2}')

if [[ -n "${RESIDUAL_DPKG:-}" ]]; then
    warn "Se detectaron paquetes residuales en dpkg:"
    echo "$RESIDUAL_DPKG"
    echo "Aplicando purga..."

    sudo dpkg --purge $RESIDUAL_DPKG >/dev/null 2>&1 || true
fi

# 2) Reparación de dependencias
sudo dpkg --configure -a >/dev/null 2>&1 || true
sudo apt --fix-broken install -y >/dev/null 2>&1 || true

# 3) Limpieza estándar
sudo apt autoremove -y >/dev/null 2>&1 || true
sudo apt autoclean -y >/dev/null 2>&1 || true

# 4) Test real de salud
if ! sudo apt-get update -y >/dev/null 2>&1; then
    err "APT está dañado incluso tras sanear dpkg."
    echo "Se recomienda ejecutar desinstalación completa."
    exit 1
fi

ok "Sistema apt/dpkg OK. Continuando..."



# ------------------------------------------------------------
# Instalación nueva
# ------------------------------------------------------------
echo "[1/6] Preparando sistema"
sudo apt-get update -y
sudo apt-get install -y curl lsb-release net-tools jq > /dev/null

echo "[2/6] Descargando instalador oficial Wazuh"
sudo curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh

echo "[3/6] Ejecutando instalación oficial"
if ! sudo bash ./wazuh-install.sh -a > "$LOG_FILE" 2>&1; then
    err "Fallo la instalación oficial de Wazuh"
    echo "Log disponible en: $LOG_FILE"
    exit 1
fi
ok "Instalación oficial completada"


# ------------------------------------------------------------
# Extracción de contraseña
# ------------------------------------------------------------
echo "[4/6] Extrayendo contraseña admin"
if [[ -f wazuh-install-files.tar ]]; then

    PASS=$(sudo tar -axf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -O \
            | grep -P "'admin'" -A1 \
            | tail -n1 \
            | awk -F"'" '{print $2}')

    if [[ -n "$PASS" ]]; then
        echo "$PASS" | sudo tee "$ADMIN_PASS_FILE" >/dev/null
        ok "Contraseña extraída correctamente"
    else
        err "No se pudo extraer la contraseña"
        echo "Revise el archivo: wazuh-install-files.tar"
        exit 1
    fi

else
    err "No existe el archivo wazuh-install-files.tar"
    echo "Es necesario extraer manualmente la contraseña"
    echo "Log disponible en: $LOG_FILE"
    exit 1
fi


# ------------------------------------------------------------
# Activación y arranque de servicios
# ------------------------------------------------------------
echo "[5/6] Activando servicios"

sudo systemctl daemon-reload
sudo systemctl enable wazuh-indexer.service
sudo systemctl enable wazuh-manager.service
sudo systemctl enable wazuh-dashboard.service

sudo systemctl restart wazuh-indexer.service
sudo systemctl restart wazuh-manager.service
sudo systemctl restart wazuh-dashboard.service

sleep 6


# ------------------------------------------------------------
# Validación final
# ------------------------------------------------------------
echo "[6/6] Validando instalación final"
FAILED=false

systemctl is-active --quiet wazuh-indexer.service || FAILED=true
systemctl is-active --quiet wazuh-manager.service || FAILED=true
systemctl is-active --quiet wazuh-dashboard.service || FAILED=true

if ! curl -k --max-time 5 "https://$FINAL_IP" >/dev/null 2>&1; then
    warn "El dashboard HTTPS no respondió"
    FAILED=true
fi

if $FAILED; then
    err "La instalación está incompleta o algún servicio no levantó"
    echo "Revise el log: $LOG_FILE"
    exit 1
fi

ok "Wazuh está operativo"


# ------------------------------------------------------------
# Resultados finales
# ------------------------------------------------------------
END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))

echo
echo "===================================================="
echo " Wazuh instalado correctamente"
echo " Tiempo total: $((TOTAL / 60))m $((TOTAL % 60))s"
echo "===================================================="
echo "Dashboard: https://$FINAL_IP"
echo "Usuario: admin"
echo "Password: $PASS"
echo "Log instalacion: $LOG_FILE"
echo "===================================================="
