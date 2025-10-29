#!/usr/bin/env bash
set -euo pipefail


###############################################
#  Configuración de Credenciales de OpenStack
# =============================================
# Reemplaza las siguientes variables con la información
# obtenida del archivo `app-cred-app-openrc.sh`
# descargado desde el Dashboard de OpenStack.
###############################################

# URL de autenticación del servicio Keystone
#export OS_AUTH_URL=http://192.168.0.10:5000

# Nombre del proyecto o tenant asociado
#export OS_PROJECT_NAME=admin

# Dominio del proyecto (por defecto: Default)
#export OS_PROJECT_DOMAIN_NAME=Default

# Nombre de usuario administrador
#export OS_USERNAME=admin

# Dominio del usuario (por defecto: Default)
#export OS_USER_DOMAIN_NAME=Default

# Contraseña asociada al usuario o credencial
#export OS_PASSWORD=JE6663lP1THXJqP8zVCWz3OQxqyXzu74b7Cd0Z7s

# Interfaz de acceso (public, internal o admin)
#export OS_INTERFACE=public

# Versión de la API de identidad (normalmente 3)
#export OS_IDENTITY_API_VERSION=3

###############################################


# Clave privada RSA para SSH
PRIVATE_KEY="tf_out/nueva_clave_wazuh"

# Usuario con el que conectar a la instancia
SSH_USER="ubuntu"

# ==========================
# FUNCIONES
# ==========================

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 <nombre_de_instancia>"
  exit 1
fi

INSTANCE_NAME="$1"

echo "🔍 Buscando instancia '$INSTANCE_NAME'..."
INSTANCE_ID=$(openstack server list -f value -c ID -c Name | grep -w "$INSTANCE_NAME" | awk '{print $1}')

if [ -z "$INSTANCE_ID" ]; then
  echo "No se encontró una instancia con el nombre '$INSTANCE_NAME'"
  exit 1
fi

echo "Instancia encontrada: $INSTANCE_ID"



# Obtener URL de la consola
echo "📡 Obteniendo URL de consola VNC..."
CONSOLE_URL=$(openstack console url show "$INSTANCE_NAME" -f value -c url)

if [ -z "$CONSOLE_URL" ]; then
  echo "No se pudo obtener la URL de consola."
  exit 1
fi

echo "---------------------------------------"
echo " URL de consola para $INSTANCE_NAME:"
echo "$CONSOLE_URL"
echo "---------------------------------------"
