#!/bin/bash
set -euo pipefail
trap 'echo "Error en la línea $LINENO. Abortando."; exit 1;' ERR

echo "Iniciando proceso de reversión y limpieza completa..."

# ============================================================
# 1. DESTRUCCIÓN KOLLA-ANSIBLE
# ============================================================
if command -v kolla-ansible >/dev/null 2>&1; then
    kolla-ansible destroy -i /etc/kolla/ansible/inventory/all-in-one || true
fi


# ============================================================
# 2. LIMPIEZA DOCKER: CONTENEDORES, IMÁGENES, VOLÚMENES
# ============================================================
docker ps -aq 2>/dev/null | xargs -r docker stop
docker ps -aq 2>/dev/null | xargs -r docker rm -f
docker images -aq 2>/dev/null | xargs -r docker rmi -f
docker volume ls -q 2>/dev/null | xargs -r docker volume rm -f
docker system prune -a -f --volumes || true


# ============================================================
# 3. LIMPIEZA REDES DOCKER
# ============================================================
# Eliminar todas excepto host y none
docker network ls --format "{{.Name}}" | grep -vE "host|none" | xargs -r docker network rm

# Eliminar bridges huérfanos creados por kolla y docker
for br in $(ip link show | grep -E "br-|kolla" | awk -F: '{print $2}' | tr -d ' '); do
    ip link delete "$br" || true
done

# Eliminar docker0 si existe
ip link show docker0 >/dev/null 2>&1 && ip link delete docker0 || true

# Eliminar vxlan sobrantes
for vx in $(ip link show | grep vxlan | awk -F: '{print $2}' | tr -d ' '); do
    ip link delete "$vx" || true
done

# Limpiar reglas NAT de Docker
iptables -F
iptables -t nat -F
iptables -X


# ============================================================
# 4. ELIMINACIÓN FICHEROS Y DIRECTORIOS KOLLA
# ============================================================
rm -rf /etc/kolla
rm -rf /var/lib/kolla
rm -rf /opt/kolla
rm -rf /var/log/kolla


# ============================================================
# 5. ENTORNO VIRTUAL PYTHON Y DEPENDENCIAS
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rm -rf "$SCRIPT_DIR/openstack_venv"
rm -f "$SCRIPT_DIR/requirements.txt"
rm -rf ~/.ansible
rm -rf /root/.ansible


# ============================================================
# 6. LIMPIEZA DE BASE DE DATOS LOCAL (MARIADB / GALERA)
# ============================================================
systemctl stop mariadb 2>/dev/null || true
rm -rf /var/lib/mysql
rm -rf /var/log/mysql
rm -f /root/.my.cnf


# ============================================================
# 7. DESINSTALACIÓN DOCKER COMPLETA
# ============================================================
systemctl stop docker 2>/dev/null || true
apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
apt-get autoremove -y
rm -rf /var/lib/docker
rm -rf /var/lib/containerd


# ============================================================
# 8. LIMPIEZA DE REPOSITORIOS APT AÑADIDOS
# ============================================================
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.gpg
apt-get update -y || true


# ============================================================
# 9. LIMPIEZA DE REDES Y ARTESANÍAS NETWORKING RESTANTES
# ============================================================
ip route flush cache || true
systemctl restart systemd-networkd 2>/dev/null || true


# ============================================================
# 10. FINALIZACIÓN
# ============================================================
echo "Limpieza completa finalizada."
exit 0

