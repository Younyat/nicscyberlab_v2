#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$BASE_DIR/tools-installer-tmp"

echo "📂 Buscando archivos JSON en $TOOLS_DIR"

cd "$TOOLS_DIR" || exit 1

for FILE in *_tools.json; do
    [ -f "$FILE" ] || continue

    echo "============================================="
    echo "📄 Archivo: $FILE"

    INSTANCE=$(jq -r '.instance' "$FILE")
    TOOLS=$(jq -r '.tools[]' "$FILE")

    echo "🖥 Instancia detectada: $INSTANCE"

    # -------------------------------------------
    # 🔥 OBTENER IP DESDE OPENSTACK
    # -------------------------------------------
    FLOATING_IP=$(openstack server show "$INSTANCE" -f json | jq -r '.addresses' | sed 's/,//g' | awk '{print $2}')
    PRIVATE_IP=$(openstack server show "$INSTANCE" -f json | jq -r '.addresses' | sed 's/,//g' | awk '{print $1}')

    # Si la IP flotante existe, usarla. Si no, usar IP privada.
    IP="$FLOATING_IP"
    if [[ "$IP" == "null" || -z "$IP" ]]; then
        IP="$PRIVATE_IP"
    fi

    echo "🌐 IP encontrada: $IP"
    echo "============================================="

    # -------------------------------------------
    # 🔥 Determinar usuario SSH (Ubuntu por defecto)
    # -------------------------------------------
    USER="ubuntu"

    # -------------------------------------------
    # 🔥 Ejecutar instalación por cada herramienta
    # -------------------------------------------
    for TOOL in $TOOLS; do
        echo "▶ Instalando $TOOL en $INSTANCE..."

        SCRIPT="$BASE_DIR/tools-installer/scripts/install_${TOOL}.sh"

        if [ -f "$SCRIPT" ]; then
            chmod +x "$SCRIPT"
            bash "$SCRIPT" "$INSTANCE" "$IP" "$USER"
        else
            echo "❌ Script de instalación no encontrado: install_${TOOL}.sh"
        fi

        echo "---------------------------------------------"
    done

done

echo "🎉 PROCESO GLOBAL COMPLETADO"
