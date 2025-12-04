#!/usr/bin/env bash
#   este codigo se usará para configutras Sort 3.10.0.0 y tmabien lnzara un regla basica y la comprobacion de deteccion 
# ====================================================================
#           Snort++ 3 Smart Config & ICMP Detection Test
# ====================================================================
#  - Respeta configuración existente
#  - Solo modifica si falta algo esencial
#  - Realiza test real ICMP y muestra alertas
#
# 100% compatible con Snort++ 3.10
# ====================================================================
set -euo pipefail

# --------------------------
# Paths
# --------------------------
SNORT_ETC="/usr/local/snort3/etc"
RULES_DIR="$SNORT_ETC/rules"
RULES_FILE="$RULES_DIR/local.rules"
SNORT_LUA="$SNORT_ETC/snort/snort.lua"
TMP_OUTPUT="/tmp/snort_sniff_test.log"

# --------------------------
# Pretty printing
# --------------------------
ok()   { echo -e "  \e[32m✔\e[0m $1"; }
warn() { echo -e "  \e[33m⚠\e[0m $1"; }
err()  { echo -e "  \e[31m✖ $1\e[0m"; }

echo "=================================================="
echo " 🧠 Snort++ 3 Smart Checker"
echo "=================================================="

# ==================================================
# Detect interface
# ==================================================
echo "🔎 Detectando interfaz activa..."
INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5;exit}')

if [[ -z "${INTERFACE}" ]]; then
    # fallback: interfaz UP con IP
    INTERFACE=$(ip -4 addr | awk '/state UP/ {iface=$2} /inet / {print iface; exit}' | sed 's/://')
fi

if [[ -z "${INTERFACE}" ]]; then
    err "No se pudo detectar interfaz de red activa."
    exit 1
fi

ok "Interfaz detectada: $INTERFACE"

# ==================================================
# Detect HOME_NET
# ==================================================
CIDR=$(ip -4 addr show "$INTERFACE" | awk '/inet /{print $2}')
if [[ -z "${CIDR}" ]]; then
    err "No se pudo obtener CIDR desde interfaz $INTERFACE"
    exit 1
fi

ok "HOME_NET detectado: $CIDR"
echo

# ==================================================
# Ensure rules folder
# ==================================================
if [[ ! -d "$RULES_DIR" ]]; then
    warn "Directorio de reglas no existe: creando..."
    sudo mkdir -p "$RULES_DIR"
else
    ok "Carpeta de reglas encontrada"
fi

# ==================================================
# Ensure local.rules
# ==================================================
if [[ ! -f "$RULES_FILE" ]]; then
    warn "local.rules no encontrado: creándolo..."
    sudo tee "$RULES_FILE" >/dev/null <<EOF
alert icmp any any -> any any (msg:"ICMP Ping detectado"; sid:100001; rev:1)
EOF
    ok "local.rules creado"
else
    ok "local.rules encontrado"
fi

# Rule correction check
if ! grep -q "ICMP Ping detectado" "$RULES_FILE"; then
    warn "Regla ICMP no presente, agregando..."
    echo 'alert icmp any any -> any any (msg:"ICMP Ping detectado"; sid:100001; rev:1)' | sudo tee -a "$RULES_FILE" >/dev/null
else
    ok "Regla ICMP confirmada"
fi
echo

# ==================================================
# Check IPS block in snort.lua
# ==================================================
REQUIRED="include $RULES_FILE"
if grep -q "$REQUIRED" "$SNORT_LUA" && grep -q "^ips =" "$SNORT_LUA"; then
    ok "Bloque IPS existente y correcto en snort.lua"
else
    warn "Bloque IPS incorrecto o ausente. Ajustando snort.lua..."

    sudo sed -i '/^ips = {/,/}/d' "$SNORT_LUA"

    sudo tee -a "$SNORT_LUA" >/dev/null <<EOF

-----------------------------------------------------
-- Auto IPS Block (snort3-smart-check)
-----------------------------------------------------
HOME_NET = '$CIDR'

ips =
{
    enable_builtin_rules = true,
    variables = default_variables,

    rules = [[
        include $RULES_FILE
    ]],
}
EOF

    ok "Bloque IPS corregido"
fi
echo

# ==================================================
# Validate snort config
# ==================================================
echo "🧪 Validando configuración Snort..."
if sudo snort -T -c "$SNORT_ETC/snort/snort.lua" >/dev/null; then
    ok "Snort validado sin errores"
else
    err "Validación fallida. Revisa configuración."
    exit 1
fi
echo

# ==================================================
# Detection test
# ==================================================
echo "🚀 Ejecutando test ICMP real en $INTERFACE"
echo "--------------------------------------------------"

rm -f "$TMP_OUTPUT"

sudo timeout 7 snort -c "$SNORT_ETC/snort/snort.lua" -i "$INTERFACE" \
     -A alert_fast > "$TMP_OUTPUT" 2>/dev/null &

sleep 2

ping -c 3 8.8.8.8 >/dev/null 2>&1 || true

sleep 3
sudo pkill snort >/dev/null 2>&1 || true

echo

# ==================================================
# Parse detection result
# ==================================================
echo "📄 RESULTADO DE LA PRUEBA:"
echo "--------------------------------------------------"

sleep 1
sync

if grep -q "ICMP Ping detectado" "$TMP_OUTPUT"; then
    echo "  🟢 ALERTAS DETECTADAS:"
    grep "ICMP Ping detectado" "$TMP_OUTPUT" | sed 's/^/   /'
    echo "--------------------------------------------------"
    ok "TEST SUPERADO: regla activada correctamente"
else
    warn "No se detectó alerta ICMP"
    echo "   - Comprueba interfaz y ruta del tráfico"
fi
