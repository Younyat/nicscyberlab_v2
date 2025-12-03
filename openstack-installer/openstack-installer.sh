#!/bin/bash
#bash openstack-installer.sh 2>&1 | tee nombre_del_log.log

# ============================================================
#  Script completo: Instalación OpenStack + Kolla-Ansible
# ============================================================

set -euo pipefail
set -x  # Debug mode

echo "🚀 Iniciando automatización de instalación de OpenStack..."

# ============================================================
# 1️⃣ CREAR ENTORNO VIRTUAL LOCAL (en el directorio del instalador)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="$SCRIPT_DIR/openstack_venv"

echo "🔹 Creando entorno virtual en $VENV_PATH..."
sudo apt update -y
sudo apt install -y python3.12 python3.12-venv python3.12-dev libffi-dev gcc libssl-dev

python3.12 -m venv "$VENV_PATH"

# Activar el entorno y exportar PATH
source "$VENV_PATH/bin/activate"
export PATH="$VENV_PATH/bin:$PATH"

echo "✅ Entorno virtual activado: $(which python)"
echo "📦 Entorno creado en: $VENV_PATH"


python -m ensurepip --upgrade
python -m pip install --upgrade pip setuptools wheel
#which pip
#pip --version
# ============================================================
# 2️⃣ INSTALAR DEPENDENCIAS DEL SISTEMA
# ============================================================
echo "🔹 Instalando dependencias del sistema..."
sudo apt install -y git iptables bridge-utils wget curl dbus pkg-config \
cmake build-essential libdbus-1-dev libglib2.0-dev sudo gnupg \
apt-transport-https ca-certificates software-properties-common

# ✅ Ahora ya se puede instalar dbus-python
python -m pip install dbus-python docker

# ============================================================
# 2️⃣ INSTALAR DEPENDENCIAS DEL SISTEMA
# ============================================================
echo "🔹 Instalando dependencias del sistema..."
sudo apt install -y git iptables bridge-utils wget curl dbus pkg-config \
libdbus-1-dev libglib2.0-dev sudo gnupg apt-transport-https \
ca-certificates software-properties-common

# ============================================================
# 3️⃣ CONFIGURAR DOCKER Y TERRAFORM
# ============================================================
echo "🔹 Configurando Docker y Terraform..."
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -rf /etc/apt/keyrings/docker.asc
sudo mkdir -p /usr/share/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

ARCH=$(dpkg --print-architecture)
DISTRO=$(lsb_release -cs)
echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $DISTRO stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo snap install terraform --classic || sudo apt install -y terraform

sudo systemctl enable docker --now
sudo usermod -aG docker "$USER"

# ============================================================
# 4️⃣ INSTALAR DEPENDENCIAS PYTHON Y KOLLA-ANSIBLE
# ============================================================
echo "🔹 Instalando dependencias Python y Kolla-Ansible..."
REQ_FILE="requirements.txt"
cat << 'EOF' > "$REQ_FILE"
ansible==11.5.0
ansible-core==2.18.5
autopage==0.5.2
bcrypt==4.3.0
bidict==0.23.1
blinker==1.9.0
certifi==2025.4.26
cffi==1.17.1
charset-normalizer==3.4.2
click==8.3.0
cliff==4.9.1
cmd2==2.5.11
cryptography==43.0.3
dbus-python==1.4.0
debtcollector==3.0.0
decorator==5.2.1
dnspython==2.8.0
docker==7.1.0
dogpile.cache==1.4.0
eventlet==0.40.3
Flask==3.1.2
flask-cors==6.0.1
Flask-SocketIO==5.5.1
greenlet==3.2.4
h11==0.16.0
hvac==2.3.0
idna==3.10
invoke==2.2.0
iso8601==2.1.0
itsdangerous==2.2.0
Jinja2==3.1.6
jmespath==1.0.1
jsonpatch==1.33
jsonpointer==3.0.0
keystoneauth1==5.10.0
kolla-ansible @ git+https://opendev.org/openstack/kolla-ansible@master
MarkupSafe==3.0.2
msgpack==1.1.0
netaddr==1.3.0
openstacksdk==4.5.0
os-service-types==1.7.0
osc-lib==4.0.0
oslo.config==9.7.1
oslo.i18n==6.5.1
oslo.serialization==5.7.0
oslo.utils==8.2.0
packaging==25.0
paramiko==4.0.0
passlib==1.7.4
pbr==6.1.1
platformdirs==4.3.7
prettytable==3.16.0
psutil==7.0.0
pycparser==2.22
PyNaCl==1.6.0
pyparsing==3.2.3
pyperclip==1.9.0
python-cinderclient==9.7.0
python-engineio==4.12.3
python-keystoneclient==5.6.0
python-openstackclient==8.0.0
python-socketio==5.14.1
PyYAML==6.0.2
requests==2.32.3
requestsexceptions==1.4.0
resolvelib==0.8.1
rfc3986==2.0.0
setuptools==80.4.0
simple-websocket==1.1.0
stevedore==5.4.1
typing_extensions==4.13.2
tzdata==2025.2
urllib3==1.26.20
wcwidth==0.2.13
Werkzeug==3.1.3
wrapt==1.17.2
wsproto==1.2.0
EOF

pip install -r "$REQ_FILE" --no-cache-dir

echo "✅ Dependencias Python instaladas correctamente."



# ============================================================
# 7️⃣.1 HABILITAR REENVÍO DE PAQUETES IPv4 (REQUISITO DE RED)
# ============================================================
echo "🔹 Verificando el reenvío de paquetes IPv4..."

# Habilitar temporalmente el reenvío de paquetes
sudo sysctl -w net.ipv4.conf.all.forwarding=1

# Comprobar si ya está en /etc/sysctl.conf; si no, añadirlo
if ! grep -q "^net.ipv4.conf.all.forwarding=1" /etc/sysctl.conf; then
  echo "net.ipv4.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf > /dev/null
  echo "✅ Configuración añadida a /etc/sysctl.conf"
else
  echo "ℹ️  La configuración de reenvío ya estaba habilitada en /etc/sysctl.conf"
fi

# Aplicar los cambios del archivo sysctl.conf
sudo sysctl -p

echo "✅ Reenvío de paquetes IPv4 habilitado correctamente."



# ============================================================
# 🔧 CONFIGURAR TOPOLOGÍA DE RED (DESPUÉS DEL DEPLOY)
# ============================================================
if [ -f "./setup-veth.sh" ]; then
  echo "🔹 Configurando red virtual post-deploy..."
  chmod +x ./setup-veth.sh
  sudo bash ./setup-veth.sh
  echo "✅ Red virtual configurada correctamente."
else
  echo "⚠️  No se encontró setup-veth.sh, continuando..."
fi



# ============================================================
# 5️⃣ CONFIGURAR ARCHIVOS DE KOLLA
# ============================================================
KOLLA_EXAMPLES="$VENV_PATH/share/kolla-ansible/etc_examples/kolla"
KOLLA_INVENTORY="$VENV_PATH/share/kolla-ansible/ansible/inventory"

sudo mkdir -p /etc/kolla/ansible/inventory

# Copiar TODO el contenido del directorio de ejemplos
sudo cp -r "$KOLLA_EXAMPLES"/* /etc/kolla/

# Copiar inventario de ejemplo (all-in-one)
sudo cp "$KOLLA_INVENTORY/all-in-one" /etc/kolla/ansible/inventory/

# Cambiar propietario
sudo chown -R "$USER:$USER" /etc/kolla

echo "✅ Archivos de configuración de Kolla copiados completamente."
# ============================================================
# 6️⃣ GENERAR PASSWORDS Y CONFIGURAR GLOBALS
# ============================================================

sudo chown "$USER:$USER" /etc/kolla/passwords.yml
kolla-genpwd || true


# === Detectar SUBNET automáticamente ================================
MAIN_IFACE=$(ip route | awk '/default/ {print $5; exit}')
MAIN_IP=$(ip -4 addr show "$MAIN_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
SUBNET=$(echo "$MAIN_IP" | cut -d. -f1-3)

echo "📌 Interfaz detectada: $MAIN_IFACE"
echo "📌 IP principal:       $MAIN_IP"
echo "📌 SUBNET detectada:   $SUBNET"
# ====================================================================


# === Buscar IP libre para VIP =======================================
START=10
END=50
VIP=""

echo "🔎 Buscando IP libre en rango $SUBNET.$START → $SUBNET.$END..."

for i in $(seq $START $END); do
  IP="$SUBNET.$i"
  if ! ping -c 1 -W 1 "$IP" &>/dev/null; then
    VIP="$IP"
    echo "✅ IP libre encontrada: $VIP"
    break
  fi
done

[ -z "$VIP" ] && { echo "❌ No se encontró IP libre en el rango."; exit 1; }


# === Detectar interfaz de red principal para Kolla ===================
DEFAULT_IFACE=$(ip route | awk '/default/ {print $5; exit}')

echo "🔧 network_interface detectado para Kolla: $DEFAULT_IFACE"


# === Generar archivo globals.yml =====================================
echo "📝 Generando /etc/kolla/globals.yml..."

sudo tee /etc/kolla/globals.yml > /dev/null <<EOF
kolla_base_distro: "ubuntu"
network_interface: "$DEFAULT_IFACE"
neutron_external_interface: "veth1"
kolla_internal_vip_address: "$VIP"
EOF

sudo chown "$USER:$USER" /etc/kolla/globals.yml

echo "✔ Archivo globals.yml configurado correctamente"
echo "📍 VIP final:     $VIP"
echo "📍 Interfaz:      $DEFAULT_IFACE"


# === Export PATH ======================================================
export PATH="$VENV_PATH/bin:$PATH"

# ============================================================
# 7️⃣ INSTALAR COLECCIONES DE ANSIBLE GALAXY Y FIX MODPROBE
# ============================================================
echo "🔹 Instalando colecciones de Ansible Galaxy..."
kolla-ansible install-deps

ansible-galaxy collection install \
  ansible.posix:==1.5.1 \
  community.general \
  community.docker \
  openstack.cloud --collections-path ~/.ansible/collections

# Crear módulo modprobe (faltante en posix>=2.x)
mkdir -p ~/.ansible/collections/ansible_collections/ansible/posix/plugins/modules/
cat << 'EOF' > ~/.ansible/collections/ansible_collections/ansible/posix/plugins/modules/modprobe.py
#!/usr/bin/python
from ansible.module_utils.basic import AnsibleModule
import subprocess

def main():
    module = AnsibleModule(argument_spec=dict(
        name=dict(type='str', required=True),
        state=dict(type='str', default='present', choices=['present', 'absent'])
    ))
    cmd = ['modprobe'] + (['-r'] if module.params['state'] == 'absent' else []) + [module.params['name']]
    try:
        subprocess.run(cmd, check=True)
        module.exit_json(changed=True)
    except subprocess.CalledProcessError as e:
        module.fail_json(msg=str(e))

if __name__ == '__main__':
    main()
EOF

chmod +x ~/.ansible/collections/ansible_collections/ansible/posix/plugins/modules/modprobe.py
echo "✅ Colecciones Ansible y fix de modprobe configurados."

# ============================================================
# 8️⃣ DESPLIEGUE DE OPENSTACK
# ============================================================


echo "🚀 Iniciando despliegue de OpenStack..."
kolla-ansible bootstrap-servers -i /etc/kolla/ansible/inventory/all-in-one
kolla-ansible prechecks -i /etc/kolla/ansible/inventory/all-in-one
kolla-ansible deploy -i /etc/kolla/ansible/inventory/all-in-one
kolla-ansible post-deploy


# CAMBIAR DE PERMISOS EL ENTORNO AL USUARIO LOCAL
sudo chown -R nics:nics "$VENV_PATH"

# ============================================================
# 9️⃣ CLIENTE OPENSTACK Y PERMISOS
# ============================================================
echo "🔹 Instalando cliente OpenStack..."
pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/master

# Permisos de seguridad
sudo chown -R root:root /etc/kolla
sudo chmod -R 640 /etc/kolla/*.yml

echo "✅ Instalación completada. Ejecuta:"
echo "   source /etc/kolla/admin-openrc.sh"
echo "   openstack project list"
echo "🎉 OpenStack desplegado correctamente con Kolla-Ansible."
