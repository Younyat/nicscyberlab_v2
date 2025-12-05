#!/usr/bin/env bash
#
# ============================================================
#       Suricata Installer (Idempotent + Floating IP)
# ============================================================
set -euo pipefail

START_TIME=$(date +%s)

FLOATING_IP="${1:-}"

format_time() {
    local t=$1
    printf "%dm %ds\n" $((t/60)) $((t%60))
}

echo "===================================================="
echo " Instalador de Suricata"
echo "===================================================="


# -----------------------------------------------------
#  Determinar IP final
# -----------------------------------------------------
if [[ -z "$FLOATING_IP" ]]; then
    FLOATING_IP=$(hostname -I | awk '{print $1}')
    echo " No se pasó Floating IP -> usando IP interna: $FLOATING_IP"
else
    echo " Floating IP recibida: $FLOATING_IP"
fi


# -----------------------------------------------------
# 🔍 Detectar interfaz activa automáticamente
# -----------------------------------------------------
INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')

if [[ -z "${INTERFACE:-}" ]]; then
    INTERFACE=$(ip -o link show | awk -F': ' '!/lo/ {print $2; exit}')
fi

echo "Interfaz activa detectada: $INTERFACE"
echo "----------------------------------------------------"


# -----------------------------------------------------
#  Detectar binario y rutas dinámicas
# -----------------------------------------------------
SURICATA_BIN=$(command -v suricata || true)

RULES_DIR=""
for R in "/etc/suricata" "/usr/local/etc/suricata"; do
    [[ -d "$R" ]] && RULES_DIR="$R" && break
done
RULES_DIR="${RULES_DIR:-/etc/suricata}"

LOG_DIR="/var/log/suricata"

echo " Binario        : ${SURICATA_BIN:-NO INSTALADO}"
echo " Configuración  : $RULES_DIR"
echo " Logs           : $LOG_DIR"
echo "----------------------------------------------------"


# -----------------------------------------------------
#  DETECCIÓN: ¿Suricata ya instalado?
# -----------------------------------------------------
ALREADY=false

# Binario existente
if command -v suricata >/dev/null 2>&1; then
    echo "✔ Suricata ya está instalado"
    ALREADY=true
fi

# Puerto estándar IDS
if ss -tunlp | grep -q ':9000'; then
    echo "✔ Puerto Suricata detectado"
    ALREADY=true
fi

# Config existente
if [[ -f "$RULES_DIR/suricata.yaml" ]]; then
    echo "✔ Configuración existente detectada"
    ALREADY=true
fi

if $ALREADY; then
    echo
    echo "===================================================="
    echo " Suricata YA está instalado"
    echo "===================================================="
    echo " IP: $FLOATING_IP"
    echo " Interfaz: $INTERFACE"
    echo
    echo " Ejecutar IDS:"
    echo "   sudo suricata -c $RULES_DIR/suricata.yaml -i $INTERFACE"
    echo
    echo " Logs:"
    echo "   sudo tail -f $LOG_DIR/fast.log"
    echo "===================================================="
    exit 0
fi


# -----------------------------------------------------
#  INSTALACIÓN NUEVA
# -----------------------------------------------------
echo
echo " Instalando Suricata..."
export DEBIAN_FRONTEND=noninteractive

echo "[1/5]  Actualizando sistema..."
sudo apt-get update -y >/dev/null
sudo apt-get upgrade -y >/dev/null

echo "[2/5]  Dependencias..."
sudo apt-get install -y \
  suricata \
  jq \
  net-tools \
  >/dev/null

echo "[3/5]  Configurando Suricata..."
sudo mkdir -p "$RULES_DIR/rules"

# regla de prueba ICMP
sudo tee "$RULES_DIR/rules/local.rules" >/dev/null <<EOF
alert icmp any any -> any any (msg:"ICMP detectado por Suricata"; sid:1000001; rev:1;)
EOF


# Ajustar interfaz en el YAML sin hardcoding
sudo sed -i "s|^ *af-packet:.*|af-packet:\n  - interface: $INTERFACE|g" "$RULES_DIR/suricata.yaml" || true


echo "[4/5]  Carpeta logs..."
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/fast.log"
sudo chmod -R 755 "$LOG_DIR"

echo "[5/5] ▶ Permitir modo promiscuo..."
sudo ip link set "$INTERFACE" promisc on




# -----------------------------------------------------
# 🔍 Verificación automática de instalación y reglas
# -----------------------------------------------------
echo
echo "🔎 Validando estado de Suricata..."

# 1) Verificar binario
if ! command -v suricata >/dev/null 2>&1; then
    echo " ERROR: No se detecta el binario 'suricata' en PATH"
    echo "   Revisa la instalación."
    exit 1
else
    echo "✔ Binario detectado: $(command -v suricata)"
fi

# 2) Validar configuración
if [[ ! -f "$RULES_DIR/suricata.yaml" ]]; then
    echo " ERROR: No existe configuración Suricata en $RULES_DIR/suricata.yaml"
    exit 1
else
    echo "✔ Configuración YAML detectada"
fi

# 3) Validar reglas cargadas
if [[ ! -f "$RULES_DIR/rules/local.rules" ]]; then
    echo " Advertencia: No se encontró archivo de reglas $RULES_DIR/rules/local.rules"
else
    RULES_COUNT=$(grep -E "^(alert|drop|reject)" "$RULES_DIR/rules/local.rules" | wc -l)
    echo "✔ Reglas cargadas: $RULES_COUNT"
    [[ "$RULES_COUNT" -eq 0 ]] && echo " No hay reglas activas, Suricata arrancará 'vacío'"
fi

# 4) Arranque en modo test para validar config
echo
echo "🧪 Probando configuración..."
if sudo suricata -T -c "$RULES_DIR/suricata.yaml" >/dev/null 2>&1; then
    echo "✔ Configuración válida (test OK)"
else
    echo " ERROR en configuración Suricata"
    sudo suricata -T -c "$RULES_DIR/suricata.yaml"
    exit 1
fi

# 5) Confirmar arranque
echo
echo "🎯 Confirmando arranque del motor IDS..."
if sudo suricata -c "$RULES_DIR/suricata.yaml" -i "$INTERFACE" >/dev/null 2>&1 & then
    sleep 2
    if ss -tunlp | grep -q "suricata"; then
        echo "✔ Motor Suricata ACTIVO en la interfaz $INTERFACE"
    else
        echo " Suricata arrancó pero no se detectan procesos escuchando"
    fi
else
    echo " ERROR: Suricata no pudo iniciar el motor IDS"
    exit 1
fi

echo "----------------------------------------------------"


END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))





# -----------------------------------------------------
# 🎉 Instalación terminada
# -----------------------------------------------------
echo
echo "===================================================="
echo " Suricata INSTALADO con éxito"
echo " Tiempo total: $(format_time $TOTAL)"
echo "===================================================="
echo " IP instancia: $FLOATING_IP"
echo " Interfaz:    $INTERFACE"
echo
echo " Ejecutar IDS:"
echo "   sudo suricata -c $RULES_DIR/suricata.yaml -i $INTERFACE"
echo
echo " Logs tiempo real:"
echo "   sudo tail -f $LOG_DIR/fast.log"
echo "===================================================="
