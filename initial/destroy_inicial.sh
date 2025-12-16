



#!/usr/bin/env bash
set -euo pipefail



# Inicializar Terraform si es necesario
if [ ! -d ".terraform" ]; then
  echo "  Ejecutando 'terraform init'..."
  terraform init -input=false
fi
terraform init -upgrade
# Destruir todos los recursos
echo " Ejecutando 'terraform destroy'..."
terraform destroy -auto-approve -parallelism=4

echo " Recursos Terraform destruidos correctamente."





# Limpieza opcional de archivos residuales
echo " Eliminando archivos temporales..."
rm -rf .terraform terraform.tfstate terraform.tfstate.backup terraform.lock.hcl terraform_outputs.json


echo " Limpieza completa. Entorno restaurado."
