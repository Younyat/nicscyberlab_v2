#!/bin/bash
set -euo pipefail

# ===========================================================
# 🌐 Configuración de red virtual para OpenStack (Kolla)
# Autor: Younes Assouyat
# ===========================================================

BRIDGE="uplinkbridge"
VETH0="veth0"
VETH1="veth1"
SUBNET="192.168.0.0/24"
GATEWAY="192.168.0.1"
EXT_IF="ens33"

echo "🔧 Configurando red virtual para OpenStack (modo Kolla)..."
sleep 1

# -----------------------------------------------------------
# 1️⃣ Instalar dependencias necesarias
# -----------------------------------------------------------
sudo apt update -y
sudo apt install -y iproute2 net-tools bridge-utils

# -----------------------------------------------------------
# 2️⃣ Eliminar configuraciones previas si existen
# -----------------------------------------------------------
for iface in "$BRIDGE" "$VETH0" "$VETH1"; do
  if ip link show "$iface" &>/dev/null; then
    echo "⚠️  Eliminando interfaz existente: $iface"
    ip link set "$iface" down || true
    ip link del "$iface" type veth &>/dev/null || true
  fi
done

# -----------------------------------------------------------
# 3️⃣ Crear par veth y bridge uplinkbridge
# -----------------------------------------------------------
echo "🔹 Creando veth pair y bridge $BRIDGE..."
ip link add "$VETH0" type veth peer name "$VETH1"
ip link set "$VETH0" up
ip link set "$VETH1" up

brctl addbr "$BRIDGE"
brctl addif "$BRIDGE" "$VETH0"
ip addr add "$GATEWAY/24" dev "$BRIDGE"
ip link set "$BRIDGE" up

echo "✅ Bridge $BRIDGE creado con IP $GATEWAY"
echo "✅ Par veth ($VETH0 <-> $VETH1) operativo"

# -----------------------------------------------------------
# 4️⃣ Configurar NAT y forwarding
# -----------------------------------------------------------
echo "🌍 Configurando NAT y reenvío de tráfico..."
iptables -t nat -C POSTROUTING -o "$EXT_IF" -s "$SUBNET" -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING -o "$EXT_IF" -s "$SUBNET" -j MASQUERADE

iptables -C FORWARD -s "$SUBNET" -j ACCEPT 2>/dev/null || \
iptables -I FORWARD -s "$SUBNET" -j ACCEPT

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# -----------------------------------------------------------
# 5️⃣ Resultado final
# -----------------------------------------------------------
echo ""
echo "✅ Red configurada correctamente para OpenStack:"
echo "   🔸 uplinkbridge: $GATEWAY/24"
echo "   🔸 veth0 agregado al uplinkbridge"
echo "   🔸 veth1 quedará conectado a br-ex (por Kolla)"
echo "   🔸 NAT activado hacia $EXT_IF"
echo ""
echo "Puedes verificar con:"
echo "   ip addr show $BRIDGE"
echo "   ip addr show $VETH1"
echo ""







