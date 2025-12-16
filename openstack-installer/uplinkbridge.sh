#!/bin/bash
set -e

SERVICE_NAME="uplinkbridge.service"

# =========================
# Directorio base del script
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SRC="$SCRIPT_DIR/setup-veth.sh"
SCRIPT_DST="/usr/local/sbin/setup-veth.sh"
SERVICE_DST="/etc/systemd/system/$SERVICE_NAME"

# =========================
# Verificar ejecución como root
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "[✖] Ejecuta este script como root"
  exit 1
fi

# =========================
# Verificar existencia del script
# =========================
if [ ! -f "$SCRIPT_SRC" ]; then
  echo "[✖] No se encuentra setup-veth.sh en $SCRIPT_DIR"
  exit 1
fi

# =========================
# Instalar script de red
# =========================
echo "[*] Instalando script de red..."
cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"

# =========================
# Crear servicio systemd
# =========================
echo "[*] Creando servicio systemd..."

cat << EOF > "$SERVICE_DST"
[Unit]
Description=Uplink Bridge + veth + NAT
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DST
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# =========================
# Activar servicio
# =========================
echo "[*] Activando servicio..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo ""
echo "======================================"
echo " ✔ Servicio uplinkbridge instalado"
echo "======================================"
echo " Estado:"
systemctl status "$SERVICE_NAME" --no-pager
echo ""
