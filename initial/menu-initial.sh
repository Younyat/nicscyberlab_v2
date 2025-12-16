#!/bin/bash
# ======================================================
#  Generador principal de archivos Terraform
# Incluye:
#   - Limpieza total del entorno OpenStack (opcional)
#   - Provider dinámico (desde /etc/kolla/clouds.yaml)
#   - Generación de imágenes, redes y flavors
# Autor: Younes Assouyat
# ======================================================

set -euo pipefail

# ------------------------------------------------------
#  Detectar ruta del script y entorno virtual
# ------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
PROVIDER_FILE="$BASE_DIR/provider.tf"
GEN_PROVIDER_SCRIPT="$BASE_DIR/generate_provider_from_clouds.sh"
CLEAN_SCRIPT="$BASE_DIR/openstack_full_cleanup.sh"
USER_NAME=$(whoami)

# Activar entorno virtual local
VENV_PATH="$SCRIPT_DIR/../openstack-installer/openstack_venv"
if [[ -d "$VENV_PATH" ]]; then
  source "$VENV_PATH/bin/activate"
  export PATH="$VENV_PATH/bin:$PATH"
  echo " Entorno virtual activado: $(which python)"
else
  echo "  No se encontró el entorno virtual en $VENV_PATH"
  echo "    Ejecuta primero el instalador de OpenStack:"
  echo "     bash ../openstack-installer/openstack-installer.sh"
  exit 1
fi

alias sudo='sudo -E'  # Mantener entorno al usar sudo

echo "==============================================="
echo " Iniciando generador principal de Terraform"
echo "==============================================="

# ------------------------------------------------------
#  0⃣ Limpieza de scripts y permisos de ejecución
# ------------------------------------------------------
echo " Verificando y corrigiendo scripts locales..."
for script in generate_provider_from_clouds.sh debian-linux.sh ubuntu-linux.sh flavors.sh network_generator.sh openstack_full_cleanup.sh; do
  if [[ -f "$BASE_DIR/$script" ]]; then
    echo " Corrigiendo $script ..."
    sudo chown "$USER_NAME:$USER_NAME" "$BASE_DIR/$script"
    chmod +x "$BASE_DIR/$script"
    sed -i '1s/^\xEF\xBB\xBF//' "$BASE_DIR/$script" 2>/dev/null
    sed -i 's/\r$//' "$BASE_DIR/$script" 2>/dev/null
  fi
done
echo " Scripts corregidos y permisos aplicados."
echo ""

# ------------------------------------------------------
#  0.1⃣ Corregir permisos de archivos sensibles
# ------------------------------------------------------
echo " Corrigiendo permisos en archivos críticos..."
if [[ -f "/etc/kolla/clouds.yaml" ]]; then
  sudo chown "$USER_NAME:$USER_NAME" /etc/kolla/clouds.yaml
  sudo chmod 644 /etc/kolla/clouds.yaml
  echo " clouds.yaml corregido."
fi

if [[ -d "/etc/kolla" ]]; then
  sudo chown -R "$USER_NAME:$USER_NAME" /etc/kolla
  sudo chmod -R 755 /etc/kolla
  echo " /etc/kolla corregido."
fi

sudo rm -f /tmp/clouds.json
touch /tmp/clouds.json
sudo chown "$USER_NAME:$USER_NAME" /tmp/clouds.json
chmod 644 /tmp/clouds.json
echo " Archivo temporal /tmp/clouds.json preparado."
echo ""

# ------------------------------------------------------
#  0.5⃣ Preguntar si se desea limpiar OpenStack antes
# ------------------------------------------------------
if [[ -f "$CLEAN_SCRIPT" ]]; then
  echo "  Antes de generar los archivos Terraform, puedes limpiar completamente tu entorno OpenStack."
  read -p "¿Deseas ejecutar el script de limpieza total (y/n)? " confirm_cleanup
  if [[ "$confirm_cleanup" =~ ^[Yy]$ ]]; then
    echo " Ejecutando limpieza completa de OpenStack..."
    bash "$CLEAN_SCRIPT"   #  SIN sudo — mantiene entorno virtual
    echo " Limpieza completada."
  else
    echo "  Limpieza omitida. Continuando..."
  fi
else
  echo "  Script de limpieza ($CLEAN_SCRIPT) no encontrado. Se omitirá este paso."
fi

# ------------------------------------------------------
# 1⃣ Comprobar si existe clouds.yaml y script generador
# ------------------------------------------------------
if [[ -f "/etc/kolla/clouds.yaml" && -f "$GEN_PROVIDER_SCRIPT" ]]; then
    echo " Detectado clouds.yaml en /etc/kolla y script generador."
    echo " Ejecutando $GEN_PROVIDER_SCRIPT ..."
    bash "$GEN_PROVIDER_SCRIPT"
else
    echo " No se encontró /etc/kolla/clouds.yaml o el script $GEN_PROVIDER_SCRIPT."
    echo " No se generará provider.tf hasta que existan ambos archivos."
    echo ""
    echo "    Asegúrate de tener:"
    echo "     - /etc/kolla/clouds.yaml"
    echo "     - generate_provider_from_clouds.sh"
    echo ""
    echo "   Luego vuelve a ejecutar:"
    echo "     bash $(basename "$0")"
    echo ""
    deactivate
    exit 1
fi

# ------------------------------------------------------
# 2⃣ Menú de generación de imágenes, redes y sabores
# ------------------------------------------------------
echo ""
echo "=== Seleccione las imágenes que desea crear ==="
echo "1) Solo Debian"
echo "2) Solo Ubuntu"
echo "3) Ambas (Debian y Ubuntu)"
read -p "Ingrese su opción [1-3]: " image_choice

read -p "¿Desea crear los ficheros de redes interna/externa? [s/n]: " network_choice
read -p "¿Desea crear los ficheros de sabores (flavors)? [s/n]: " flavors_choice
echo "---"

# ------------------------------------------------------
# 3⃣ Ejecutar scripts según la elección
# ------------------------------------------------------
if [[ "$image_choice" == "1" || "$image_choice" == "3" ]]; then
  [[ -f "$BASE_DIR/debian-linux.sh" ]] && ./debian-linux.sh || echo " Script debian-linux.sh no encontrado."
fi

if [[ "$image_choice" == "2" || "$image_choice" == "3" ]]; then
  [[ -f "$BASE_DIR/ubuntu-linux.sh" ]] && ./ubuntu-linux.sh || echo " Script ubuntu-linux.sh no encontrado."
fi

if [[ "$flavors_choice" =~ ^[Ss]$ ]]; then
  [[ -f "$BASE_DIR/flavors.sh" ]] && ./flavors.sh || echo " Script flavors.sh no encontrado."
fi

if [[ "$network_choice" =~ ^[Ss]$ ]]; then
  [[ -f "$BASE_DIR/network_generator.sh" ]] && ./network_generator.sh || echo " Script network_generator.sh no encontrado."
fi

# ------------------------------------------------------
# 4⃣ Finalización
# ------------------------------------------------------
echo "---"
echo " Proceso completado."
echo " Archivos Terraform generados según su selección."
echo " Ahora puede ejecutar:"
echo "   terraform init"
echo "   terraform apply"
echo "   terraform apply -auto-approve -parallelism=4"
echo "para aplicar los cambios en OpenStack."

# Salir del entorno virtual
deactivate

