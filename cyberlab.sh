#!/bin/bash
# ==================================================
# Script de despliegue automático de NICS | CyberLab
# ==================================================

set -e

# ======================================
# SECCIÓN DE CONFIGURACION DE LOS LOGS
# ======================================
BASE_DIR="$(pwd)"
LOG_DIR="${BASE_DIR}/log"
LOG_FILE="${LOG_DIR}/cyberlab.log"

mkdir -p "${LOG_DIR}"

if [[ -f "${LOG_FILE}" ]]; then
    mv "${LOG_FILE}" "${LOG_FILE}-$(date +%Y%m%d-%H%M).bak"
fi

exec > >(tee -a "${LOG_FILE}") 2>&1

exec 3>>"${LOG_FILE}"

# ===========================
# FUNCIONES
# ===========================
timer() {
    local start_time=$1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    printf "%02d min %02d seg\n" $((duration / 60)) $((duration % 60))
}

log_block() {
    echo "" >&3
    echo "============================================================" >&3
    echo "$1" >&3
    echo "$(date '+%Y-%m-%d | %H:%M:%S')" >&3
    echo "============================================================" >&3
    echo "" >&3
}

overall_start=$(date +%s)

log_block "INICIO DEL DESPLIEGUE DE NICS | CyberLab"
echo "🚀 Iniciando despliegue de NICS | CyberLab..."

# ===========================
# PASO 1
# ===========================
log_block "PASO 1 | Instalación de OpenStack"
step_start=$(date +%s)

bash openstack-installer/openstack-installer.sh

echo "[✔] Instalación completada en: $(timer $step_start)"
echo "------------------------------------------------------------"

# ===========================
# PASO 2
# ===========================
log_block "PASO 2 | Activación entorno virtual OpenStack"

if [[ -d "openstack-installer/openstack_venv" ]]; then
    source openstack-installer/openstack_venv/bin/activate
    echo "[✔] Entorno activado correctamente."
else
    echo "[✖] No se encontró el entorno 'openstack_venv'."
    exit 1
fi

# ===========================
# PASO 3
# ===========================
log_block "PASO 3 | Generación de credenciales"

bash generate_admin-openrc.sh
echo "[✔] Credenciales generadas."

if [[ -f "admin-openrc.sh" ]]; then
    source admin-openrc.sh
    echo "[✔] admin-openrc cargado."
fi

# ===========================
# PASO 4
# ===========================
log_block "PASO 4 | Reglas de red / iptables"
sudo bash openstack-installer/uplinkbridge.sh
echo "[✔] Reglas aplicadas."
echo "------------------------------------------------------------"

# ===========================
# PASO 5
# ===========================
log_block "PASO 5 | Configuración inicial OpenStack"
step_start=$(date +%s)

bash openstack-resources.sh
echo "[✔] Configuración completada en: $(timer $step_start)"
echo "------------------------------------------------------------"

# ===========================
# PASO 6
# ===========================
log_block "PASO 6 | Arrancando Dashboard"
step_start=$(date +%s)

DASH_LOG="${LOG_DIR}/dashboard.log"

bash start_dashboard.sh > "${DASH_LOG}" 2>&1 & 
DASH_PID=$!

echo "Accede al dashboard desde tu navegador:"
echo "[➜] http://localhost:5001"
echo
echo "[⚙️] Ejecutándose en segundo plano (PID: $DASH_PID)"
echo "Para detenerlo:"
echo "[!] kill $DASH_PID"
echo
echo "[📜] Log del dashboard: tail -f ${DASH_LOG}"
echo "------------------------------------------------------------"

# ===========================
# INFO ACCESO
# ===========================
log_block "PARÁMETROS DE ACCESO"

AUTH_URL=$(grep -m1 "auth_url:" /etc/kolla/clouds.yaml | awk '{print $2}' | sed 's/:5000//')
USERNAME=$(grep -m1 "username:" /etc/kolla/clouds.yaml | awk '{print $2}')
PASSWORD=$(grep -m1 "password:" /etc/kolla/clouds.yaml | awk '{print $2}')

echo "Dashboard: ${AUTH_URL}"
echo "Usuario:   ${USERNAME}"
echo "Password:  ${PASSWORD}"
echo "------------------------------------------------------------"

deactivate 2>/dev/null || true

log_block "FIN DEL PROCESO"

echo "[⏱] Tiempo total de despliegue: $(timer $overall_start)"
echo "[📜] Log completo registrado en: ${LOG_FILE}"
