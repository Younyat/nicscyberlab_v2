#!/bin/bash
# ============================================================
# Ejecutar escenario OpenStack leyendo un JSON de configuración
# Descarga imágenes, crea claves, redes, router, flavors, etc.
# ============================================================

set -euo pipefail

# ==========================================
# 🔍 Detectar ruta raíz del proyecto
# ==========================================
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Paths automáticos
JSON_FILE="${1:-$BASE_DIR/initial/configs/scenario_config.json}"
VENV_PATH="$BASE_DIR/openstack-installer/openstack_venv"
ADMIN_OPENRC="$BASE_DIR/admin-openrc.sh"

# Carpeta de imágenes
IMAGES_DIR="$HOME/openstack_images"
mkdir -p "$IMAGES_DIR"

UBUNTU_IMG="$IMAGES_DIR/ubuntu-22.04.qcow2"
DEBIAN_IMG="$IMAGES_DIR/debian-12.qcow2"

UBUNTU_IMG_NAME="ubuntu-22.04"
DEBIAN_IMG_NAME="debian-12"

SSH_KEY_NAME="cyberlab-key"
SSH_KEY_FILE="$HOME/.ssh/cyberlab-key"

EXTERNAL_NET_NAME="external-net"
EXTERNAL_SUBNET_NAME="external-subnet"
PRIVATE_NET_NAME="private-net"
PRIVATE_SUBNET_NAME="private-subnet"
ROUTER_NAME="router-cyberlab"
SECGRP_NAME="allow-ssh-icmp"

# ============================================================
# 🔧 Verificación entorno virtual
# ============================================================
if [ ! -f "$VENV_PATH/bin/activate" ]; then
    echo "[ERROR] ❌ No se encontró el entorno virtual en:"
    echo "   $VENV_PATH/bin/activate"
    exit 1
fi

source "$VENV_PATH/bin/activate"
echo "[INFO] 🟢 Entorno virtual activado."

# ============================================================
# 🔧 Verificar y cargar admin-openrc
# ============================================================
if [ ! -f "$ADMIN_OPENRC" ]; then
    echo "[ERROR] ❌ admin-openrc.sh no encontrado en:"
    echo "    $ADMIN_OPENRC"
    exit 1
fi

source "$ADMIN_OPENRC"
echo "[INFO] 🔐 Credenciales OpenStack cargadas."

# ============================================================
# Validación cliente OpenStack
# ============================================================
if ! command -v openstack >/dev/null 2>&1; then
    echo "[ERROR] ❌ No existe el comando 'openstack' en el entorno actual."
    exit 1
fi

# ============================================================
# ✔ Confirmar login API
# ============================================================
if ! openstack token issue >/dev/null 2>&1; then
    echo "[ERROR] ❌ No se pudo emitir token. Credenciales o API incorrectos."
    exit 1
fi

echo "[INFO] 🟢 Token OpenStack generado correctamente (API OK)"
echo "[INFO] 📂 BASE_DIR detectado: $BASE_DIR"

# ============================================================
# Función de log
# ============================================================
log() { echo -e "[LOG] $*"; }

# ============================================================
# Validar jq
# ============================================================
if ! command -v jq >/dev/null; then
    echo "[ERROR] ❌ Falta jq. Instala con: sudo apt install jq"
    exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
    echo "[ERROR] ❌ No existe el JSON: $JSON_FILE"
    exit 1
fi

log "📄 JSON encontrado correctamente."

# --------- LEER JSON ----------------------------------------
CLEANUP=$(jq -r '.cleanup' "$JSON_FILE")
IMAGE_CHOICE=$(jq -r '.image_choice' "$JSON_FILE")
RED_EXTERNA=$(jq -r '.red_externa' "$JSON_FILE")
RED_PRIVADA=$(jq -r '.red_privada' "$JSON_FILE")
DNS1=$(jq -r '.dns' "$JSON_FILE" | cut -d',' -f1 | xargs)
DNS2=$(jq -r '.dns' "$JSON_FILE" | cut -d',' -f2 | xargs)

# ============================================================
# Funciones
# ============================================================

download_images() {

    if [ "$IMAGE_CHOICE" != "ambas" ]; then
        log "⏭ No descargo imágenes (image_choice != ambas)"
        return
    fi

    log "📥 Descargando imágenes cloud..."

    if [ ! -f "$UBUNTU_IMG" ]; then
        log "⬇ Ubuntu 22.04"
        wget -O "$UBUNTU_IMG" \
            https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
    else
        log "✔ Ubuntu ya descargado"
    fi

    if [ ! -f "$DEBIAN_IMG" ]; then
        log "⬇ Debian 12"
        wget -O "$DEBIAN_IMG" \
            https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
    else
        log "✔ Debian ya descargado"
    fi
}

create_ssh_key() {
    if openstack keypair show "$SSH_KEY_NAME" >/dev/null 2>&1; then
        log "🔑 Keypair ya existe."
        return
    fi

    log "🔑 Creando clave SSH..."

    mkdir -p "$HOME/.ssh"

    if [ ! -f "$SSH_KEY_FILE" ]; then
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_FILE" -N ""
    fi

    openstack keypair create --public-key "${SSH_KEY_FILE}.pub" "$SSH_KEY_NAME"

    log "✔ Keypair lista: $SSH_KEY_NAME"
}

upload_images() {

    if [ "$IMAGE_CHOICE" != "ambas" ]; then
        log "⏭ No subo imágenes (image_choice != ambas)"
        return
    fi

    if ! openstack image show "$UBUNTU_IMG_NAME" >/dev/null 2>&1; then
        log "⬆ Subiendo Ubuntu 22.04 a Glance..."
        openstack image create "$UBUNTU_IMG_NAME" \
            --disk-format qcow2 \
            --container-format bare \
            --file "$UBUNTU_IMG" \
            --public
    else
        log "✔ Ubuntu ya está en Glance"
    fi

    if ! openstack image show "$DEBIAN_IMG_NAME" >/dev/null 2>&1; then
        log "⬆ Subiendo Debian 12 a Glance..."
        openstack image create "$DEBIAN_IMG_NAME" \
            --disk-format qcow2 \
            --container-format bare \
            --file "$DEBIAN_IMG" \
            --public
    else
        log "✔ Debian ya está en Glance"
    fi
}

create_networking() {

    log "🌐 Configurando redes..."

    if ! openstack network show "$EXTERNAL_NET_NAME" >/dev/null 2>&1; then
        openstack network create --external \
            --provider-network-type flat \
            --provider-physical-network physnet1 \
            "$EXTERNAL_NET_NAME"
    fi

    if ! openstack subnet show "$EXTERNAL_SUBNET_NAME" >/dev/null 2>&1; then
        openstack subnet create --network "$EXTERNAL_NET_NAME" \
            --subnet-range "$RED_EXTERNA" \
            --no-dhcp \
            "$EXTERNAL_SUBNET_NAME"
    fi

    if ! openstack network show "$PRIVATE_NET_NAME" >/dev/null 2>&1; then
        openstack network create "$PRIVATE_NET_NAME"
    fi

    if ! openstack subnet show "$PRIVATE_SUBNET_NAME" >/dev/null 2>&1; then
        openstack subnet create --network "$PRIVATE_NET_NAME" \
            --subnet-range "$RED_PRIVADA" \
            --dns-nameserver "$DNS1" \
            --dns-nameserver "$DNS2" \
            "$PRIVATE_SUBNET_NAME"
    fi

    if ! openstack router show "$ROUTER_NAME" >/dev/null 2>&1; then
        openstack router create "$ROUTER_NAME"
    fi

    openstack router set "$ROUTER_NAME" --external-gateway "$EXTERNAL_NET_NAME" || true
    openstack router add subnet "$ROUTER_NAME" "$PRIVATE_SUBNET_NAME" || true

    log "✔ Redes listas."
}

create_security_group() {
    if openstack security group show "$SECGRP_NAME" >/dev/null 2>&1; then
        log "✔ Security group ya existente."
        return
    fi

    log "🔐 Configurando reglas ICMP + SSH+.Wazuh+.Caldera"

    openstack security group create "$SECGRP_NAME"
    openstack security group rule create --proto icmp "$SECGRP_NAME"
    # ICMP
    openstack security group rule create --proto icmp "$SECGRP_NAME"

    # SSH
    openstack security group rule create --proto tcp --dst-port 22 "$SECGRP_NAME"

    # Wazuh
    openstack security group rule create --proto tcp --dst-port 1515 "$SECGRP_NAME"
    openstack security group rule create --proto udp --dst-port 1514 "$SECGRP_NAME"
    openstack security group rule create --proto tcp --dst-port 55000 "$SECGRP_NAME"
    openstack security group rule create --proto tcp --dst-port 5601 "$SECGRP_NAME"
    openstack security group rule create --proto tcp --dst-port 443 "$SECGRP_NAME"

    # Caldera
    openstack security group rule create --proto tcp --dst-port 8888 "$SECGRP_NAME"


}

create_flavors() {
    log "💠 Creando flavours..."

    openstack flavor create tiny   --vcpus 1 --ram 512  --disk 5  || true
    openstack flavor create small  --vcpus 1 --ram 1024 --disk 10 || true
    openstack flavor create medium --vcpus 2 --ram 2048 --disk 20 || true
    openstack flavor create large  --vcpus 4 --ram 4096 --disk 40 || true

    log "✔ Flavors listos."
}

# ============================================================
# EJECUCIÓN
# ============================================================

log "🧩 JSON cargado. Preparando todo..."

if [ "$CLEANUP" = "true" ]; then
    log "🧹 Cleanup activado (pendiente implementar)."
fi

download_images
create_ssh_key
upload_images
create_networking
create_security_group
create_flavors

log "🎉 ESCENARIO LISTO"

echo "
Puedes lanzar instancias así:

openstack server create \\
  --image ubuntu-22.04 \\
  --flavor tiny \\
  --network private-net \\
  --security-group allow-ssh-icmp \\
  --key-name $SSH_KEY_NAME \\
  ubuntu-test-1
"

