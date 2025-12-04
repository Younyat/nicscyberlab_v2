#!/usr/bin/env bash
# ====================================================================
#           Suricata Smart Config & ICMP Detection Test
# ====================================================================
#  - Detecta rutas reales de config
#  - Añade local.rules si falta
#  - Inserta bloque rule-files si no está
#  - Ajusta interfaz dinámica
#  - Test IDS en vivo y muestra alertas
# ====================================================================
set -euo pipefail

# --------------------------
# Pretty printing
# --------------------------
ok()   { echo -e "  \e[32m✔\e[0m $1"; }
warn() { echo -e "  \e[33m⚠\e[0m $1"; }
err()  { echo -e "  \e[31m✖ $1\e[0m"; }

echo "=================================================="
echo " 🧠 Suricata Smart Checker"
echo "=================================================="

# ==================================================
# Detect Suricata bin
# ==================================================
if command -v suricata >/dev/null 2>&1; then
    BIN=$(command -v suricata)
else
    err "Suricata NO está instalado."
    exit 1
fi
ok "Binario detectado: $BIN"

# ==================================================
# Detect config path real
# ==================================================
SURICATA_YAML=""
for f in \
    "/etc/suricata/suricata.yaml" \
    "/usr/local/etc/suricata/suricata.yaml" \
    "/opt/suricata/etc/suricata.yaml"
do
    [[ -f "$f" ]] && SURICATA_YAML="$f" && break
done

if [[ -z "$SURICATA_YAML" ]]; then
    err "No pude localizar suricata.yaml"
    echo "Busca manualmente:"
    echo "  find / -name suricata.yaml 2>/dev/null"
    exit 1
fi

CONF_DIR=$(dirname "$SURICATA_YAML")
RULES_DIR="$CONF_DIR/rules"
RULES_FILE="$RULES_DIR/local.rules"
TMP_OUT="/tmp/suricata_icmp_test.log"

ok "Archivo de configuración detectado: $SURICATA_YAML"
ok "Directorio de reglas: $RULES_DIR"

# ==================================================
# Detect INTERFACE real
# ==================================================
echo "🔎 Detectando interfaz activa..."
IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5;exit}')

if [[ -z "$IFACE" ]]; then
    IFACE=$(ip -4 addr | awk '/state UP/ {iface=$2} /inet / {print iface;exit}' | sed 's/://')
fi

if [[ -z "$IFACE" ]]; then
    err "No pude detectar interfaz activa."
    exit 1
fi
ok "Interfaz detectada: $IFACE"

CIDR=$(ip -4 addr show "$IFACE" | awk '/inet /{print $2}')
ok "HOME_NET CIDR detectado: $CIDR"

echo

# ==================================================
# Garantizar carpeta reglas
# ==================================================
if [[ ! -d "$RULES_DIR" ]]; then
    warn "No existe carpeta rules → Creando..."
    sudo mkdir -p "$RULES_DIR"
else
    ok "Carpeta rules detectada"
fi

# ==================================================
# Crear local.rules si falta
# ==================================================
if [[ ! -f "$RULES_FILE" ]]; then
    warn "local.rules no encontrado → Creándolo..."
    sudo tee "$RULES_FILE" >/dev/null <<EOF
alert icmp any any -> any any (msg:"ICMP detectado por Suricata"; sid:1000001; rev:1;)
EOF
    ok "local.rules creado"
else
    ok "local.rules presente"
fi

# Garantizar regla ICMP
if ! grep -q "ICMP detectado por Suricata" "$RULES_FILE"; then
    warn "No está la regla ICMP → agregando..."
    echo 'alert icmp any any -> any any (msg:"ICMP detectado por Suricata"; sid:1000001; rev:1;)' \
        | sudo tee -a "$RULES_FILE" >/dev/null
else
    ok "Regla ICMP confirmada"
fi
echo

# ==================================================
# Garantizar bloque rule-files
# ==================================================
if ! grep -q "rule-files:" "$SURICATA_YAML"; then
    warn "No existe bloque rule-files → agregando al final"

    sudo tee -a "$SURICATA_YAML" >/dev/null <<EOF

# ==========================================================
# Auto Inserted Rule Block (suricata-smart-check)
# ==========================================================
rule-files:
  - $(basename "$RULES_FILE")

EOF
    ok "Bloque rule-files insertado"
else
    ok "rule-files ya existe en suricata.yaml"

    # Confirmar que local.rules está referenciado
    if ! grep -q "$(basename "$RULES_FILE")" "$SURICATA_YAML"; then
        warn "local.rules no está en rule-files → añadiendo línea"
        sudo sed -i "/rule-files:/a \  - $(basename "$RULES_FILE")" "$SURICATA_YAML"
        ok "local.rules agregado a rule-files"
    fi
fi
echo

# ==================================================
# Ajustar interfaz en YAML (af-packet)
# ==================================================
if grep -q "interface:" "$SURICATA_YAML"; then
    sudo sed -i "s/interface:.*/interface: $IFACE/" "$SURICATA_YAML"
    ok "Interfaz actualizada dentro de suricata.yaml"
else
    warn "No se encontró sección interface:, añádela manualmente si es necesario"
fi
echo

# ==================================================
# Validación configuración
# ==================================================
echo "🧪 Validando configuración..."
if ! sudo "$BIN" -T -c "$SURICATA_YAML" >/dev/null 2>&1; then
    err "Configuración inválida. Detalles:"
    sudo "$BIN" -T -c "$SURICATA_YAML"
    exit 1
fi
ok "Configuración válida (test OK)"
echo

# ==================================================
# Test real IDS
# ==================================================
echo "🚀 Ejecutando test ICMP real..."
rm -f "$TMP_OUT"

sudo timeout 8 "$BIN" -c "$SURICATA_YAML" -i "$IFACE" \
    -l /var/log/suricata \
    --init-errors-fatal no \
    -k none >"$TMP_OUT" 2>&1 &

sleep 2
ping -c 3 8.8.8.8 >/dev/null 2>&1 || true
sleep 3
sudo pkill suricata >/dev/null 2>&1 || true

echo
echo "📄 RESULTADO DEL TEST"
echo "---------------------------------------------------"

if grep -q "ICMP detectado por Suricata" "$TMP_OUT"; then
    echo "  🟢 ALERTAS DETECTADAS:"
    grep "ICMP detectado por Suricata" "$TMP_OUT" | sed 's/^/   /'
    echo "---------------------------------------------------"
    ok "TEST SUPERADO: IDS activo y regla funcionando"
else
    warn "No se detectaron alertas"
    echo "   📌 Comprueba:"
    echo "   - interfaz correcta"
    echo "   - reglas activas"
    echo "   - tráfico ICMP genera visibilidad"
fi

echo
echo "Logs guardados en: $TMP_OUT"
echo "=================================================="
echo " 🟢 FINALIZADO"
echo "=================================================="
