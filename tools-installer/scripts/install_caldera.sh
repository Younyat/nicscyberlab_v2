#!/usr/bin/env bash
#
# ============================================================
#  MITRE Caldera Installer — Idempotent + Floating IP Support
# ============================================================
set -euo pipefail
trap 'echo "❌ ERROR en línea ${LINENO}" >&2' ERR

CALDERA_DIR="$HOME/caldera"
LOG_FILE="$CALDERA_DIR/caldera.log"
START_TIME=$(date +%s)

format_time() {
    local t=$1
    printf "%dm %ds\n" $((t/60)) $((t%60))
}

echo "===================================================="
echo "🚀 Instalador de MITRE Caldera"
echo "===================================================="

# -----------------------------------------------------
# 💠 IP recibida desde el master installer
# -----------------------------------------------------
FINAL_IP="${1:-}"

if [[ -n "$FINAL_IP" ]]; then
    echo "🌍 IP recibida desde el master installer: $FINAL_IP"
else
    echo "⚠️ No se recibió IP como parámetro. Usando IP interna..."
    FINAL_IP=$(hostname -I | awk '{print $1}')
fi

echo "🌐 IP final para Dashboard: $FINAL_IP"
echo "----------------------------------------------------"


# -----------------------------------------------------
# 🧠 DETECCIÓN: ¿Caldera ya está instalado?
# -----------------------------------------------------
ALREADY=false

# 1) ¿Existe carpeta?
if [[ -d "$CALDERA_DIR" ]]; then
    echo "✔ Detectada instalación previa: $CALDERA_DIR"
    ALREADY=true
fi

# 2) ¿Proceso activo?
if pgrep -f "server.py" >/dev/null 2>&1; then
    echo "✔ Proceso Caldera ya ejecutándose"
    ALREADY=true
fi

# 3) ¿Puerto en uso?
if ss -tunlp | grep -q ":8888"; then
    echo "✔ Puerto 8888 activo"
    ALREADY=true
fi

# --------------------------------------
# SI YA ESTÁ INSTALADO → MOSTRAR Y SALIR
# --------------------------------------
if $ALREADY; then
    echo "===================================================="
    echo "🎉 MITRE Caldera YA ESTÁ INSTALADO"
    echo "===================================================="
    echo "🌍 URL      : http://$FINAL_IP:8888"
    echo "🔑 Usuario  : admin"
    echo "🔑 Password : admin (por defecto)"
    echo "📁 Carpeta  : $CALDERA_DIR"
    echo
    echo "⚙ Si necesitas forzar reinstalación:"
    echo "   rm -rf $CALDERA_DIR"
    echo "   sudo pkill -f server.py 2>/dev/null"
    echo "   sudo systemctl stop caldera 2>/dev/null"
    echo "===================================================="
    exit 0
fi


# -----------------------------------------------------
# 🚧 INSTALACIÓN NUEVA
# -----------------------------------------------------
echo
echo "🆕 No detectada instalación previa. Instalando Caldera..."
export DEBIAN_FRONTEND=noninteractive

echo "[1/7] 🔄 Actualizando sistema..."
sudo apt-get update -y >/dev/null
sudo apt-get upgrade -y >/dev/null
sudo apt-get autoremove --purge -y >/dev/null
sudo apt-get autoclean -y >/dev/null

echo "[2/7] 🔧 Dependencias..."
sudo apt-get install -y python3 python3-pip curl git build-essential >/dev/null

echo "[3/7] 💻 Instalando Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null
sudo apt-get install -y nodejs >/dev/null

echo "[4/7] 📦 Clonando Caldera..."
git clone https://github.com/mitre/caldera.git --recursive "$CALDERA_DIR" >/dev/null

echo "[5/7] 🎨 Instalando dependencias de Plugin Magma..."
MAGMA_DIR="$CALDERA_DIR/plugins/magma"
if [[ -d "$MAGMA_DIR" ]]; then
    cd "$MAGMA_DIR"
    rm -rf node_modules package-lock.json >/dev/null 2>&1 || true
    npm install \
        vite@2.9.15 \
        @vitejs/plugin-vue@2.3.4 \
        vue@3.2.45 \
        --legacy-peer-deps \
        >/dev/null
fi

echo "[6/7] 🐍 Instalando requirements Python..."
cd "$CALDERA_DIR"
sudo pip3 install --break-system-packages -r requirements.txt >/dev/null

echo "[7/7] 🚀 Arrancando servidor..."
nohup python3 server.py --insecure --build > "$LOG_FILE" 2>&1 &

END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))


# --------------------------------------
# SALIDA FINAL
# --------------------------------------
echo
echo "===================================================="
echo "🎉 Instalación de MITRE Caldera COMPLETADA"
echo "⏱ Tiempo total: $(format_time $TOTAL)"
echo "===================================================="
echo "🌍 URL              : http://$FINAL_IP:8888"
echo "🔑 Usuario          : admin"
echo "🔑 Password         : admin (por defecto)"
echo "📁 Directorio       : $CALDERA_DIR"
echo "📄 Log del servidor : $LOG_FILE"
echo "===================================================="
