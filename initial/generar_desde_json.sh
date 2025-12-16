#!/bin/bash
# ======================================================
#  Generador Terraform basado en JSON (sin entorno virtual)
# Autor: Younes Assouyat
# ======================================================

set -euo pipefail

echo "==============================================="
echo " INICIO generar_desde_json.sh (sin venv)"
echo "==============================================="

# -----------------------------
# 1⃣ Leer JSON desde argumento
# -----------------------------
if [[ $# -ne 1 ]]; then
  echo " Uso: $0 <config.json>"
  exit 1
fi

JSON_FILE="$1"

if [[ ! -f "$JSON_FILE" ]]; then
  echo " Archivo JSON no encontrado: $JSON_FILE"
  exit 1
fi

cleanup=$(jq -r '.cleanup' "$JSON_FILE")
image_choice=$(jq -r '.image_choice' "$JSON_FILE")
network=$(jq -r '.network' "$JSON_FILE")
flavors_enabled=$(jq -r '.flavors_enabled' "$JSON_FILE")

echo " JSON recibido: $JSON_FILE"
echo " cleanup=$cleanup"
echo " image_choice=$image_choice"
echo " network=$network"
echo " flavors=$flavors_enabled"

# -----------------------------
# 2⃣ Variables y rutas
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GEN_PROVIDER_SCRIPT="$SCRIPT_DIR/generate_provider_from_clouds.sh"
CLEAN_SCRIPT="$SCRIPT_DIR/openstack_full_cleanup.sh"

echo " SCRIPT_DIR=$SCRIPT_DIR"
echo " ROOT_DIR=$ROOT_DIR"

# -----------------------------
# 3⃣ Arreglar permisos
# -----------------------------
echo " Corrigiendo permisos..."
for script in generate_provider_from_clouds.sh debian-linux.sh ubuntu-linux.sh flavors.sh network_generator.sh openstack_full_cleanup.sh; do
  if [[ -f "$SCRIPT_DIR/$script" ]]; then
    chmod +x "$SCRIPT_DIR/$script"
    echo "   $script OK"
  fi
done

# -----------------------------
# 4⃣ Limpieza automática
# -----------------------------
if [[ "$cleanup" == "true" ]]; then
  echo " Ejecutando limpieza total de OpenStack..."
  bash "$CLEAN_SCRIPT" <<< "y"
fi

# -----------------------------
# 5⃣ Generar provider.tf
# -----------------------------
echo " Generando provider.tf..."
bash "$GEN_PROVIDER_SCRIPT"

# -----------------------------
# 6⃣ Ejecutar scripts según configuración JSON
# -----------------------------
echo "==============================================="
echo "  GENERANDO SEGÚN CONFIGURACIÓN DEL JSON"
echo "==============================================="

case "$image_choice" in
  debian)
    [[ -f "$SCRIPT_DIR/debian-linux.sh" ]] && "$SCRIPT_DIR/debian-linux.sh"
    ;;
  ubuntu)
    [[ -f "$SCRIPT_DIR/ubuntu-linux.sh" ]] && "$SCRIPT_DIR/ubuntu-linux.sh"
    ;;
  ambas)
    [[ -f "$SCRIPT_DIR/debian-linux.sh" ]] && "$SCRIPT_DIR/debian-linux.sh"
    [[ -f "$SCRIPT_DIR/ubuntu-linux.sh" ]] && "$SCRIPT_DIR/ubuntu-linux.sh"
    ;;
esac

if [[ "$flavors_enabled" == "true" ]]; then
  [[ -f "$SCRIPT_DIR/flavors.sh" ]] && "$SCRIPT_DIR/flavors.sh"
fi

if [[ "$network" == "true" ]]; then
  [[ -f "$SCRIPT_DIR/network_generator.sh" ]] && "$SCRIPT_DIR/network_generator.sh"
fi

echo "==============================================="
echo " Generación completada correctamente (sin venv)."
echo "==============================================="

exit 0
