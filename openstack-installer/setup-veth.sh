#!/bin/bash
set -euo pipefail

# ============================================================
# 🌐 Configuración de red virtual para OpenStack (con OVS)
# ============================================================

BRIDGE="uplinkbridge"
VETH0="veth0"
VETH1="veth1"
SUBNET="10.0.2.0/24"
GATEWAY="10.0.2.1"
EXT_IF="ens33"
BR_EX="br-ex"

echo "🔧 Configurando red virtual para OpenStack..."

# ============================================================
# 1️⃣ Instalar dependencias necesarias
# ============================================================
sudo apt update -y
sudo apt install -y iproute2 net-tools bridge-utils openvswitch-switch

# Asegurar que OVS está activo
sudo systemctl start openvswitch-switch || sudo systemctl restart openvswitch-switch


# ============================================================
# 2️⃣ Eliminar configuración previa
# ============================================================
for iface in "$BRIDGE" "$BR_EX"; do
  if ip link show "$iface" &>/dev/null; then
    echo "⚠️  Eliminando bridge existente $iface..."
    ip link set "$iface" down || true
    brctl delbr "$iface" 2>/dev/null || sudo ovs-vsctl del-br "$iface" || true
  fi
done
ip link del "$VETH0" type veth &>/dev/null || true
ip link del "$VETH1" type veth &>/dev/null || true

# ============================================================
# 3️⃣ Crear par veth y bridge clásico (uplinkbridge)
# ============================================================
ip link add "$VETH0" type veth peer name "$VETH1"
ip link set "$VETH0" up
ip link set "$VETH1" up

brctl addbr "$BRIDGE"
brctl addif "$BRIDGE" "$VETH0"
ip addr add "$GATEWAY/24" dev "$BRIDGE"
ip link set "$BRIDGE" up

# ============================================================
# 4️⃣ Crear br-ex con Open vSwitch y conectarlo a veth1
# ============================================================
echo "🔗 Creando bridge externo br-ex (OVS) y conectando veth1..."
# sudo ovs-vsctl add-br "$BR_EX"
# sudo ip link set "$BR_EX" up
# sudo ovs-vsctl add-port "$BR_EX" "$VETH1"



# Limpiar reglas NAT duplicadas o anteriores
iptables -t nat -D POSTROUTING -o "$EXT_IF" -s "$SUBNET" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -s "$SUBNET" -j ACCEPT 2>/dev/null || true


# ============================================================
# 5️⃣ Configurar NAT y forwarding
# ============================================================
iptables -t nat -A POSTROUTING -o "$EXT_IF" -s "$SUBNET" -j MASQUERADE
iptables -A FORWARD -s "$SUBNET" -j ACCEPT



