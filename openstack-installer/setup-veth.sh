#!/bin/bash

# Crear un par de interfaces veth
ip link add veth0 type veth peer name veth1

# Activar las interfaces veth
ip link set dev veth0 up
ip link set dev veth1 up

# Crear un puente de red
brctl addbr uplinkbridge

# Añadir la interfaz veth0 al puente
brctl addif uplinkbridge veth0

# Activar el puente
ip link set dev uplinkbridge up

# Asignar dirección IP al puente
ip address add 10.0.2.1/24 dev uplinkbridge

# Configurar NAT con iptables para permitir el enmascarado
#iptables -t nat -I POSTROUTING -o ens33 -s 10.0.2.0/24 -j MASQUERADE

# Permitir el reenvío de tráfico desde la subred 10.0.2.0/24
#iptables -I FORWARD -s 10.0.2.0/24 -j ACCEPT


iptables -t nat -C POSTROUTING -o ens33 -s 10.0.2.0/24 -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING -o ens33 -s 10.0.2.0/24 -j MASQUERADE

iptables -C FORWARD -s 10.0.2.0/24 -j ACCEPT 2>/dev/null || \
iptables -I FORWARD -s 10.0.2.0/24 -j ACCEPT
