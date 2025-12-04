#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)
FLOATING_IP="${1:-$(hostname -I | awk '{print $1}')}"
RULES_DIR=""
LOG_DIR="/var/log/suricata"

echo "===================================================="
echo "🚀 Instalador de Suricata (PRO)"
echo "===================================================="
echo "🌍 IP final: $FLOATING_IP"


# -----------------------------------------
# Detectar interfaz
# -----------------------------------------
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
[[ -z "$INTERFACE" ]] && INTERFACE=$(ls /sys/class/net | grep -v lo | head -n1)

echo "📡 Interfaz detectada: $INTERFACE"


# -----------------------------------------
# Detectar instalación previa
# -----------------------------------------
is_installed() {
    command -v suricata >/dev/null || return 1
    [[ -f /etc/suricata/suricata.yaml ]] || return 1
    systemctl is-active --quiet suricata || return 1
    pgrep -f suricata >/dev/null || return 1
}

if is_installed; then
    echo "🎉 Suricata YA instalado y operativo."
    exit 0
fi


# -----------------------------------------
# Instalación limpia
# -----------------------------------------
echo "🆕 Instalando..."
apt update -y
apt install -y suricata suricata-update jq net-tools

systemctl enable suricata
systemctl stop suricata


# -----------------------------------------
# Detectar rutas
# -----------------------------------------
for D in /etc/suricata /usr/local/etc/suricata; do
    [[ -d "$D" ]] && RULES_DIR="$D" && break
done

[[ -z "$RULES_DIR" ]] && RULES_DIR="/etc/suricata"

echo "[+] YAML: $RULES_DIR/suricata.yaml"


# -----------------------------------------
# Configurar interfaz
# -----------------------------------------
yq eval ".af-packet[0].interface = \"$INTERFACE\"" -i "$RULES_DIR/suricata.yaml" 2>/dev/null || true


# -----------------------------------------
# Reglas locales
# -----------------------------------------
mkdir -p "$RULES_DIR/rules"
cat > "$RULES_DIR/rules/local.rules" <<EOF
alert icmp any any -> any any (msg:"ICMP detectado por Suricata"; sid:1000001; rev:1;)
EOF


# -----------------------------------------
# Descargar reglas oficiales
# -----------------------------------------
suricata-update
suricata-update list-sources || true


# -----------------------------------------
# Test config
# -----------------------------------------
echo "🧪 Validando configuracion..."
suricata -T -c "$RULES_DIR/suricata.yaml"


# -----------------------------------------
# Arranque servicio
# -----------------------------------------
systemctl restart suricata
sleep 3

# -----------------------------------------
# Validación real
# -----------------------------------------
echo "🔎 Validación final..."

check() {
    echo "❌ ERROR: $1"; exit 1
}

command -v suricata >/dev/null || check "Binario no cargado"
systemctl is-active --quiet suricata || check "Servicio no activo"
pgrep -f suricata >/dev/null || check "Proceso no ejecutándose"

[[ -f "$LOG_DIR/eve.json" ]] || check "No existe eve.json"

grep -q "ICMP" "$RULES_DIR/rules/local.rules" || check "Regla ICMP no configurada"

echo "✔ Todo correcto"


END_TIME=$(date +%s)
TOTAL=$((END_TIME - START_TIME))

echo
echo "===================================================="
echo "🎉 Suricata INSTALADO con éxito"
echo "⏱ Tiempo: ${TOTAL}s"
echo "===================================================="
echo "🌍 IP instancia: $FLOATING_IP"
echo "🧩 Interfaz: $INTERFACE"
echo
echo "🚨 Ejecutar IDS:"
echo " sudo systemctl restart suricata"
echo " sudo tail -f $LOG_DIR/eve.json"
echo "===================================================="
