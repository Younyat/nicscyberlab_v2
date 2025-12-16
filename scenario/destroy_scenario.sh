#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
#  Script: destroy_scenario.sh
#  Ubicación: /scenario/
#  Destruye todos los recursos Terraform generados en /tf_out/
# ==========================================================
# Autor: Younes Assouyat
# ======================================================
# Uso:
#   bash destroy_scenario.sh 2>&1 | tee log_destroy_scenario.log
# ======================================================

# Directorio base del script actual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../tf_out"
SCENARIO_FILE="${SCRIPT_DIR}/scenario_file.json"

echo "==============================================="
echo " Iniciando destrucción del escenario Terraform"
echo " Directorio esperado: $TF_DIR"
echo "==============================================="

# ----------------------------------------------------------
#  Comprobación de existencia del directorio tf_out
# ----------------------------------------------------------
if [ ! -d "$TF_DIR" ]; then
  echo "  No se encontró el directorio tf_out."
  echo "  No hay recursos Terraform que destruir. Saliendo sin error."
else
  # ----------------------------------------------------------
  #  Entrar en el directorio tf_out
  # ----------------------------------------------------------
  cd "$TF_DIR" || {
    echo "  No se pudo acceder al directorio tf_out."
    echo "  Saliendo sin error."
    exit 0
  }

  # ----------------------------------------------------------
  #  Inicializar Terraform si es necesario
  # ----------------------------------------------------------
  if [ ! -d ".terraform" ]; then
    echo "  Ejecutando 'terraform init'..."
    terraform init -input=false
  fi

  # ----------------------------------------------------------
  #  Ejecutar 'terraform destroy' y capturar el resultado
  # ----------------------------------------------------------
  echo " Ejecutando 'terraform destroy'..."
  if terraform destroy -auto-approve -parallelism=4; then
    echo " Recursos Terraform destruidos correctamente."

    # ------------------------------------------------------
    #  Limpieza de archivos temporales y directorio completo
    # ------------------------------------------------------
    echo " Eliminando archivos temporales..."
    rm -rf .terraform terraform.tfstate terraform.tfstate.backup terraform.lock.hcl terraform_outputs.json

    echo "  Eliminando carpeta tf_out completa..."
    cd ..
    rm -rf "$TF_DIR"
    echo " Carpeta tf_out eliminada con éxito. Entorno restaurado."
  else
    echo "  Error: Terraform destroy no se completó correctamente."
    echo " La carpeta tf_out se conserva para revisión manual."
    exit 1
  fi
fi

# ----------------------------------------------------------
#  Verificar y eliminar scenario_file.json
# ----------------------------------------------------------
echo "-----------------------------------------------"
echo " Verificando archivo de escenario..."
if [ -f "$SCENARIO_FILE" ]; then
  echo "  Eliminando archivo de escenario: $SCENARIO_FILE"
  rm -f "$SCENARIO_FILE"
  echo " Archivo scenario_file.json eliminado correctamente."
else
  echo "  No se encontró el archivo scenario_file.json."
fi

echo "==============================================="
echo " Proceso de destrucción completado."
echo "==============================================="
