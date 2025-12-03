#!/usr/bin/env bash
#
# ============================================================
#      Snort 3 Installer - Idempotente, Limpio y Validado
# ============================================================
set -euo pipefail

START_TIME=$(date +%s)
FLOATING_IP="${1:-}"

format_time() {
    local t=$1
    printf "%dm %ds\n" $((t/60)) $((t%60))
}

echo "===================================================="
echo "🚀 Instalador de Snort 3"
echo "===================================================="

# -----------------------------------------------------
# 🌍 Floating IP opcional
# -----------------------------------------------------
if [[ -z "$FLOATING_IP" ]]; then
    FLOATING_IP=$(hostname -I | awk '{print $1}')
    echo "⚠️ No se pasó Floating IP → usando IP: $FLOATING_IP"
else
    echo "🌍 Floating IP recibida: $FLOATING_IP"
fi

# -----------------------------------------------------
# 🌐 Detectar interfaz activa
# -----------------------------------------------------
INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[[ -z "${INTERFACE:-}" ]] && INTERFACE=$(ip -o link show | awk -F': ' '!/lo/ {print $2; exit}')
echo "📡 Interfaz detectada: $INTERFACE"


# -----------------------------------------------------
# 🔍 Rutas dinámicas
# -----------------------------------------------------
SNORT_BIN=$(command -v snort || true)

SNORT_DIR=""
for DIR in "/usr/local/snort3" "/opt/snort" "/etc/snort"; do
    [[ -d "$DIR" ]] && SNORT_DIR="$DIR" && break
done
SNORT_DIR="${SNORT_DIR:-/usr/local/snort3}"

if [[ -d "/usr/local/snort3/etc/snort" ]]; then
    SNORT_RULES="/usr/local/snort3/etc/snort"
elif [[ -d "/etc/snort" ]]; then
    SNORT_RULES="/etc/snort"
else
    SNORT_RULES="/etc/snort"
fi

LOG_DIR="/var/log/snort"


# ============================================================
# 🧠 Función VALIDACIÓN
# ============================================================
validate_snort() {
    echo
    echo "===================================================="
    echo "🧪 Validación completa de Snort 3"
    echo "===================================================="

    # Binario
    if [[ -z "$SNORT_BIN" ]]; then
        echo "❌ ERROR: No se encontró binario Snort tras la instalación"
        exit 1
    fi

    echo "✔ Binario: $SNORT_BIN"

    echo
    echo "📦 Versión detectada:"
    snort -V || {
        echo "❌ ERROR: Snort corrupto o instalación incompleta"
        exit 1
    }

    # Config
    echo
    echo "🔍 Localizando snort.lua..."

    SNORT_CONF=""
    for P in \
        "/usr/local/snort3/etc/snort/snort.lua" \
        "/usr/local/etc/snort/snort.lua" \
        "/etc/snort/snort.lua"
    do
        [[ -f "$P" ]] && SNORT_CONF="$P" && break
    done

    if [[ -z "$SNORT_CONF" ]]; then
        echo "❌ ERROR: No se encontró snort.lua"
        exit 1
    fi

    echo "✔ Configuración: $SNORT_CONF"

    # Reglas locales
    echo
    echo "🧮 Reglas activas:"
    RULE_COUNT=$(grep -Ei '^(alert|drop|reject)' "$SNORT_RULES/rules/local.rules" 2>/dev/null | wc -l || echo 0)
    echo "   $RULE_COUNT reglas activas"

    # Validación con -T
    echo
    echo "🧪 Test de configuración:"
    sudo snort -T -c "$SNORT_CONF" > /tmp/snort_validation.log 2>&1

    if grep -q "Snort successfully validated the configuration" /tmp/snort_validation.log; then
        echo "✨ VALIDACIÓN OK - Configuración correcta"
    else
        echo "❌ ERROR en validación de configuración"
        cat /tmp/snort_validation.log
        exit 1
    fi
}

# ============================================================
# 🎉 Banner Final
# ============================================================
show_banner() {
    END_TIME=$(date +%s)
    TOTAL=$((END_TIME - START_TIME))

    echo
    echo "===================================================="
    echo "🎉 Snort 3 operativo y validado"
    echo "⏱ Tiempo total: $(format_time $TOTAL)"
    echo "===================================================="
    echo "🌍 IP:        $FLOATING_IP"
    echo "🧩 Interfaz:  $INTERFACE"
    echo "----------------------------------------------------"
    echo "🚨 Ejecutar Snort:"
    echo "sudo snort -i $INTERFACE -c $SNORT_CONF -A alert_fast -k none -l $LOG_DIR"
    echo
    echo "📡 Logs tiempo real:"
    echo "sudo tail -f $LOG_DIR/alert_fast.txt"
    echo "===================================================="
}


# ============================================================
# 🧠 DETECCIÓN PREVIA
# ============================================================
ALREADY=false

[[ -n "$SNORT_BIN" ]] && ALREADY=true
[[ -f "$SNORT_RULES/snort.lua" ]] && ALREADY=true

if $ALREADY; then
    echo
    echo "===================================================="
    echo "🎉 Snort 3 YA está instalado en este sistema"
    echo "===================================================="
    validate_snort
    show_banner
    exit 0
fi


# ============================================================
# 🆕 INSTALACIÓN NUEVA
# ============================================================
echo
echo "🆕 No detectado Snort → Instalando..."
export DEBIAN_FRONTEND=noninteractive

echo "[1/6] 🔄 Apt update"
sudo apt update -y >/dev/null
sudo apt upgrade -y >/dev/null

echo "[2/6] 📦 Dependencias..."
sudo apt install -y \
    build-essential cmake pkg-config autoconf automake libtool \
    bison flex git libpcap-dev libpcre3 libpcre3-dev libpcre2-dev \
    libdumbnet-dev zlib1g-dev liblzma-dev openssl libssl-dev \
    libluajit-5.1-dev luajit libtirpc-dev libnghttp2-dev libhwloc-dev >/dev/null

echo "[3/6] ⚙️ Compilando libdaq..."
cd /tmp
git clone https://github.com/snort3/libdaq.git >/dev/null
cd libdaq
./bootstrap >/dev/null
./configure >/dev/null
make -j"$(nproc)" >/dev/null
sudo make install >/dev/null
sudo ldconfig >/dev/null

echo "[4/6] ⚙️ Compilando Snort 3..."
cd /tmp
git clone https://github.com/snort3/snort3.git >/dev/null
cd snort3
./configure_cmake.sh --prefix=/usr/local/snort3 >/dev/null
cd build
make -j"$(nproc)" >/dev/null
sudo make install >/dev/null
sudo ldconfig >/dev/null
sudo ln -sf /usr/local/snort3/bin/snort /usr/local/bin/snort

echo "[5/6] 📜 Reglas..."
sudo mkdir -p "$SNORT_RULES/rules"
sudo cp -r /usr/local/snort3/etc/snort/* "$SNORT_RULES/" || true

sudo tee "$SNORT_RULES/snort.lua" >/dev/null <<EOF
RULE_PATH = "$SNORT_RULES/rules"
LOCAL_RULES = RULE_PATH .. "/local.rules"
daq = { modules = { { name = "afpacket" } } }
ips = { enable_builtin_rules = false, include = { LOCAL_RULES } }
alert_fast = { file = true }
outputs = { alert_fast }
EOF

sudo tee "$SNORT_RULES/rules/local.rules" >/dev/null <<EOF
alert icmp any any -> any any (msg:"Intento ICMP detectado"; sid:1000010; rev:1;)
EOF

echo "[6/6] 📝 Logs..."
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_DIR/alert_fast.txt"
sudo chmod -R 755 "$LOG_DIR"
sudo ip link set $INTERFACE promisc on


if $ALREADY; then
    echo
    echo "===================================================="
    echo "🎉 Snort 3 YA está instalado en esta máquina"
    echo "===================================================="

    validate_snort
    show_banner

    # Solo termina este bloque sin matar la shell ni Flask
    return 0 2>/dev/null || true
fi
