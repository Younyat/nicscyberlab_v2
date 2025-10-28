#!/bin/bash
# ============================================================
# 🌐 Configuración de red virtual para OpenStack
# Crea un par de interfaces veth y un puente uplinkbridge
# para conectar la red externa (10.0.2.0/24) con el host.
# ============================================================

set -euo pipefail

echo "🔧 Creando interfaces virtuales y puente uplinkbridge..."

# Crear una interfaz virtual con 2 extremos (veth0 y veth1)
ip link add veth0 type veth peer name veth1

# Activar las dos interfaces veth
ip link set dev veth0 up
ip link set dev veth1 up

# Crear un puente llamado uplinkbridge y conectarlo a veth0
brctl addbr uplinkbridge
brctl addif uplinkbridge veth0
ip link set dev uplinkbridge up

# Asignar una IP al puente
ip addr add 10.0.2.1/24 dev uplinkbridge

# Configurar reglas con iptables para dar acceso a internet
iptables -t nat -A POSTROUTING -o ens33 -s 10.0.2.0/24 -j MASQUERADE
iptables -A FORWARD -s 10.0.2.0/24 -j ACCEPT

# Activar reenvío de paquetes a nivel de kernel
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "✅ uplinkbridge configurado correctamente con IP 10.0.2.1"
echo "✅ NAT activo y tráfico 10.0.2.0/24 permitido hacia ens33"

