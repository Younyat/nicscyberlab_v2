#!/bin/bash
# ======================================================
# 🧩 Archivo de credenciales para OpenStack
# Generado automáticamente desde /etc/kolla/clouds.yaml
# Cloud seleccionado: kolla-admin
# ======================================================

# ------------------------------------------------------
# 🧹 Limpiar variables previas del entorno
# ------------------------------------------------------
unset OS_AUTH_TYPE
unset OS_AUTH_URL
unset OS_USERNAME
unset OS_PASSWORD
unset OS_USER_DOMAIN_NAME
unset OS_PROJECT_NAME
unset OS_PROJECT_DOMAIN_NAME
unset OS_REGION_NAME
unset OS_APPLICATION_CREDENTIAL_ID
unset OS_APPLICATION_CREDENTIAL_SECRET
unset OS_APPLICATION_CREDENTIAL_NAME

# ------------------------------------------------------
# 🔐 Configuración de credenciales
# ------------------------------------------------------
export OS_AUTH_URL=http://192.168.5.12:5000
export OS_PROJECT_NAME=admin
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USERNAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PASSWORD=Bi36tQolQDNlbKCARZmO9z31SUOduiBfCIaJTolj
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=RegionOne

echo "✅ Credenciales OpenStack cargadas para $OS_PROJECT_NAME ($OS_USERNAME)"
