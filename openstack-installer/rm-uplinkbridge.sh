#!/bin/bash
set -e

SERVICE_NAME="uplinkbridge.service"
SCRIPT_DST="/usr/local/sbin/setup-veth.sh"
SERVICE_DST="/etc/systemd/system/$SERVICE_NAME"

echo "=============================================="
echo " Limpieza completa de uplinkbridge"
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "[✖] Ejecuta este script como root"
  exit 1
fi

# -------------------------------
# 1. Parar y eliminar servicio
# -------------------------------
if systemctl is-active --quiet "$SERVICE_NAME"; then
  systemctl stop "$SERVICE_NAME"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME"; then
  systemctl disable "$SERVICE_NAME"
fi

rm -f "$SERVICE_DST"
systemctl daemon-reload

# -------------------------------
# 2. Eliminar bridge y veth
# -------------------------------
echo "[*] Eliminando bridge y veth..."
ip link del veth0 2>/dev/null || true
ip link del veth1 2>/dev/null || true
ip link set uplinkbridge down 2>/dev/null || true
brctl delbr uplinkbridge 2>/dev/null || true

# -------------------------------
# 3. Eliminar reglas iptables
# -------------------------------
echo "[*] Restaurando iptables..."
iptables -t nat -D POSTROUTING -s 10.0.2.0/24 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 192.168.250.0/24 -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -s 10.0.2.0/24 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 192.168.250.0/24 -j ACCEPT 2>/dev/null || true

# ⚠️ Política FORWARD no se toca (por seguridad)

# -------------------------------
# 4. Restaurar forwarding IPv4
# -------------------------------
echo "[*] Restaurando forwarding IPv4..."
sysctl -w net.ipv4.conf.all.forwarding=0 >/dev/null

sed -i '/^net.ipv4.conf.all.forwarding=1/d' /etc/sysctl.conf
sysctl -p >/dev/null

# -------------------------------
# 5. Eliminar script instalado
# -------------------------------
rm -f "$SCRIPT_DST"

echo ""
echo "=============================================="
echo " ✔ Sistema limpio"
echo " - SIN servicio"
echo " - SIN bridge"
echo " - SIN veth"
echo " - SIN NAT"
echo " - Forwarding restaurado"
echo "=============================================="
echo ""
