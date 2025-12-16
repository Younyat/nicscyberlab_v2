#!/bin/bash
# ==========================================
#  Descripción: Despliega una instancia
#  Debian 12 en OpenStack e instala Wazuh
# ==========================================

# ===== Timer global del script =====
SCRIPT_START=$(date +%s)

# Convertir segundos → "X minutos y Y segundos"
format_time() {
    local total=$1
    local minutes=$((total / 60))
    local seconds=$((total % 60))
    echo "${minutes} minutos y ${seconds} segundos"
}

echo "============================================="
echo "    Despliega una instancia en OpenStack:    "
echo "           Debian 12 + Wazuh Manager         "
echo "============================================="

# ===== Activar entorno virtual =====
echo " Activando entorno virtual de OpenStack..."
step_start=$(date +%s)
if [[ -d "openstack-installer/openstack_venv" ]]; then
    source openstack-installer/openstack_venv/bin/activate
    echo "[] Entorno virtual 'openstack_venv' activado correctamente."
else
    echo "[] No se encontró el entorno 'openstack_venv'. Ejecuta primero openstack-recursos.sh"
    exit 1
fi
step_end=$(date +%s)
echo "-------------------------------------------"
sleep 1

# ===== Cargar variables de entorno OpenStack =====
if [[ -f "admin-openrc.sh" ]]; then
    echo "[+] Cargando variables del entorno OpenStack (admin-openrc.sh)..."
    source admin-openrc.sh
    echo "[] Variables cargadas correctamente."
    echo "-------------------------------------------"
    sleep 1
else
    echo "[] No se encontró 'admin-openrc.sh'. Ejecuta primero openstack-recursos.sh"
    exit 1
fi

# =========================
# CONFIGURACIÓN GENERAL
# =========================
IMAGE_NAME="debian-12"
FLAVOR="S_2CPU_4GB"
KEY_NAME="my_key"
SEC_GROUP="sg_basic"

NETWORK_PRIVATE="net_private_01"
SUBNET_PRIVATE="subnet_net_private_01"
NETWORK_EXTERNAL="net_external_01"
ROUTER_NAME="router_private_01"

INSTANCE_NAME="wazuh-manager"
SSH_USER="debian"
SSH_KEY_PATH="$HOME/nics-cyberlab-A/my_key.pem"
USERDATA_FILE="$HOME/nics-cyberlab-A/set-password.yml"
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"

# =========================
# VERIFICACIÓN DE RECURSOS
# =========================
echo " Verificando recursos necesarios..."

if ! openstack image list -f value -c Name | grep -qw "$IMAGE_NAME"; then
    echo "[!] Falta la imagen '$IMAGE_NAME'. Ejecuta openstack-recursos.sh"; exit 1
fi
if ! openstack flavor list -f value -c Name | grep -qw "$FLAVOR"; then
    echo "[!] Falta el flavor '$FLAVOR'. Ejecuta openstack-recursos.sh"; exit 1
fi
if ! openstack keypair list -f value -c Name | grep -qw "$KEY_NAME"; then
    echo "[!] Falta el keypair '$KEY_NAME'. Ejecuta openstack-recursos.sh"; exit 1
fi
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "[!] No se encuentra la clave privada '$SSH_KEY_PATH'."; exit 1
fi
if ! openstack security group list -f value -c Name | grep -qw "$SEC_GROUP"; then
    echo "[!] Falta el grupo de seguridad '$SEC_GROUP'. Ejecuta openstack-recursos.sh"; exit 1
fi
if ! openstack network list -f value -c Name | grep -qw "$NETWORK_PRIVATE"; then
    echo "[!] Falta la red privada '$NETWORK_PRIVATE'."; exit 1
fi
if ! openstack subnet list -f value -c Name | grep -qw "$SUBNET_PRIVATE"; then
    echo "[!] Falta la subred privada '$SUBNET_PRIVATE'."; exit 1
fi
if ! openstack router list -f value -c Name | grep -qw "$ROUTER_NAME"; then
    echo "[!] Falta el router '$ROUTER_NAME'."; exit 1
fi
if [[ ! -f "$USERDATA_FILE" ]]; then
    echo "[!] No se encuentra '$USERDATA_FILE'."; exit 1
fi

echo "[] Todos los recursos necesarios existen."
echo "-------------------------------------------"

# =========================
# ELIMINAR INSTANCIA PREVIA
# =========================
EXISTING=$(openstack server list -f value -c Name | grep -w "$INSTANCE_NAME" || true)
if [[ -n "$EXISTING" ]]; then
    echo "[!] Existe una instancia '$INSTANCE_NAME'. Eliminando..."
    for s in $EXISTING; do openstack server delete "$s"; done

    until ! openstack server list -f value -c Name | grep -qw "$INSTANCE_NAME"; do
        sleep 5
        echo -n "."
    done
    echo
    echo "[] Instancia '$INSTANCE_NAME' eliminada."
fi

# =========================
# CREACIÓN DE LA INSTANCIA
# =========================
echo " Creando instancia '$INSTANCE_NAME'..."
openstack server create \
  --image "$IMAGE_NAME" \
  --flavor "$FLAVOR" \
  --key-name "$KEY_NAME" \
  --security-group "$SEC_GROUP" \
  --network "$NETWORK_PRIVATE" \
  --user-data "$USERDATA_FILE" \
  "$INSTANCE_NAME"

echo "[+] Esperando que la instancia esté ACTIVE..."
until [[ "$(openstack server show "$INSTANCE_NAME" -f value -c status)" == "ACTIVE" ]]; do
    sleep 5
    echo -n "."
done
echo
echo "[] Instancia '$INSTANCE_NAME' activa."

# =========================
# IP FLOTANTE
# =========================
FLOATING_IP=$(openstack floating ip list -f value -c "Floating IP Address" -c "Fixed IP Address" | awk '$2=="None"{print $1; exit}')
if [[ -z "$FLOATING_IP" ]]; then
    FLOATING_IP=$(openstack floating ip create "$NETWORK_EXTERNAL" -f value -c floating_ip_address)
fi

ssh-keygen -f "$KNOWN_HOSTS_FILE" -R "$FLOATING_IP" >/dev/null 2>&1
openstack server add floating ip "$INSTANCE_NAME" "$FLOATING_IP"

# =========================
# ESPERA SSH (1 MINUTO)
# =========================
echo "[+] Esperando conexión SSH (timeout 1 min)..."
SSH_TIMEOUT=60
SSH_START=$(date +%s)

until ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" $SSH_USER@"$FLOATING_IP" "echo ok" >/dev/null 2>&1; do
    sleep 5
    echo -n "."
    NOW=$(date +%s)
    if (( NOW - SSH_START > SSH_TIMEOUT )); then
        echo
        echo "[] Timeout al intentar conectar por SSH"
        exit 1
    fi
done

echo
echo "[] SSH disponible en $FLOATING_IP"

# ===========================================
# INSTALACIÓN DE WAZUH MANAGER (CON TIMER)
# ===========================================
INSTALL_START=$(date +%s)

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" $SSH_USER@"$FLOATING_IP" <<'EOF'
set -e

echo "[+] Actualizando el sistema..."
sudo apt-get update && sudo apt-get upgrade -y

echo "[+] Instalando dependencias (curl, net-tools)..."
sudo apt-get install -y curl net-tools

echo "[+] Descargando e instalando Wazuh (wazuh-install.sh -a)..."
cd "$HOME"
sudo curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
sudo bash ./wazuh-install.sh -a

echo "[+] Extrayendo contraseña del usuario 'admin' de wazuh-passwords.txt..."
if [ -f wazuh-install-files.tar ]; then
  sudo tar -axf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt -O \
    | grep -P "'admin'" -A 1 \
    | tail -n 1 \
    | awk -F"'" '{print $2}' \
    | sudo tee /tmp/wazuh-admin-password >/dev/null || true
else
  echo "[!] No se ha encontrado 'wazuh-install-files.tar', no se puede extraer la contraseña automáticamente."
fi

echo "[+] Comprobando estado del servicio wazuh-manager..."
sudo systemctl status wazuh-manager.service --no-pager || true

echo "[+] Comprobando que el puerto 1515 está en escucha..."
sudo netstat -tuln | grep 1515 || echo "[!] puerto 1515 no encontrado en escucha (comprueba manualmente)."

EOF

# Recuperar contraseña admin desde la instancia
ADMIN_PASSWORD=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" $SSH_USER@"$FLOATING_IP" 'sudo cat /tmp/wazuh-admin-password 2>/dev/null || true')

INSTALL_END=$(date +%s)
INSTALL_TIME=$((INSTALL_END - INSTALL_START))

if [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD="<NO_DETECTADA_EN_SCRIPT>"
    echo "[!] No se ha podido obtener automáticamente la contraseña de 'admin'."
    echo "    Dentro de la instancia puedes ejecutar:"
    echo "    sudo tar -O -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"
fi

echo "[] Wazuh Manager instalado y configurado."
echo "[] Tiempo de instalación de Wazuh: $(format_time $INSTALL_TIME)"
echo "[] IP flotante asignada: $FLOATING_IP"

# ========================================
# TIEMPO TOTAL DEL SCRIPT
# ========================================
SCRIPT_END=$(date +%s)
SCRIPT_TIME=$((SCRIPT_END - SCRIPT_START))

echo "===================================================="
echo "[] Tiempo TOTAL del script: $(format_time $SCRIPT_TIME)"
echo "===================================================="

echo
echo "Acceso SSH a la instancia Wazuh Manager:"
echo "[] ssh -i $SSH_KEY_PATH $SSH_USER@$FLOATING_IP"
echo "-----------------------------------------------"
echo
echo "Acceso al Wazuh Dashboard:"
echo "  URL      : https://$FLOATING_IP"
echo "  Usuario  : admin"
echo "  Password : $ADMIN_PASSWORD"
echo
echo "Recuerda que el acceso es vía HTTPS y el certificado será autofirmado (tendrás que aceptar la excepción en el navegador)."