
# Dar permisos de ejecución a todos los proveedores descargados
chmod -R +x .terraform/providers/

# Asegurarte de que pertenecen a tu usuario
sudo chown -R $USER:$USER .terraform/

echo "=== 4. Lanzando Terraform ==="

terraform init
echo "Pausando 30 segundos antes de 'init'..."
sleep 3
terraform plan
echo "Pausando 30 segundos antes de 'plan'..."
sleep 3
terraform apply -auto-approve -parallelism=4
echo "Pausando 30 segundos antes de 'apply'..."

