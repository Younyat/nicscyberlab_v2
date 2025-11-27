#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$BASE_DIR/tools-installer-tmp"

echo "📂 Buscando archivos JSON en: $TOOLS_DIR"
echo "----------------------------------------------------"

cd "$TOOLS_DIR" || exit 1

# ====================================================
# 🔍 BUSCAR CLAVE SSH EN ~/.ssh
# ====================================================
SSH_KEY=""
for KEY in "$HOME/.ssh/"*.pem "$HOME/.ssh/"*key "$HOME/.ssh/id_rsa"; do
    if [[ -f "$KEY" ]]; then
        SSH_KEY="$KEY"
        break
    fi
done

if [[ -z "$SSH_KEY" ]]; then
    echo "❌ ERROR: No existe ninguna clave válida en ~/.ssh/"
    exit 1
fi

echo "🔑 Usando identity SSH: $SSH_KEY"
chmod 600 "$SSH_KEY"

# ====================================================
# 🚀 PROCESO PRINCIPAL
# ====================================================
for FILE in *_tools.json; do
    [ -f "$FILE" ] || continue

    echo "===================================================="
    echo "📄 Archivo detectado: $FILE"

    INSTANCE=$(jq -r '.name' "$FILE")
    TOOLS=$(jq -r '.tools[]' "$FILE")

    echo "🖥 Instancia: $INSTANCE"

    FLOATING_IP=$(jq -r '.ip_floating // empty' "$FILE")
    PRIVATE_IP=$(jq -r '.ip_private // empty' "$FILE")

    IP="$FLOATING_IP"
    [[ -z "$IP" ]] && IP="$PRIVATE_IP"

    echo "🌐 IP detectada: $IP"

    echo "🔍 Consultando imagen de OpenStack..."
    RAW_IMAGE=$(openstack server show "$INSTANCE" -f json | jq -r '.image')

    if echo "$RAW_IMAGE" | jq empty 2>/dev/null; then
        IMAGE_NAME=$(echo "$RAW_IMAGE" | jq -r '.name')
    else
        IMAGE_NAME="$RAW_IMAGE"
    fi

    echo "🧩 Imagen detectada: $IMAGE_NAME"

    # Determinar usuario
    if echo "$IMAGE_NAME" | grep -qi "ubuntu"; then
        POSSIBLE_USERS=("ubuntu" "debian")
    elif echo "$IMAGE_NAME" | grep -qi "debian"; then
        POSSIBLE_USERS=("debian" "ubuntu")
    else
        POSSIBLE_USERS=("debian" "ubuntu")
    fi

    echo "🔍 Detectando usuario SSH..."
    USER=""
    for u in "${POSSIBLE_USERS[@]}"; do
        if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" $u@"$IP" "echo ok" >/dev/null 2>&1; then
            USER="$u"
            break
        fi
    done

    if [[ -z "$USER" ]]; then
        echo "❌ No fue posible autenticar vía SSH."
        continue
    fi

    echo "👤 Usuario SSH detectado: $USER"
    echo "🌐 Conectando a IP: $IP"

    # ====================================================
    # 🔥 INSTALAR CADA TOOL + VERIFICAR INSTALACIÓN
    # ====================================================
    for TOOL in $TOOLS; do
        echo "▶ Instalando $TOOL en $INSTANCE..."

        SCRIPT="$BASE_DIR/tools-installer/scripts/install_${TOOL}.sh"

        if [[ ! -f "$SCRIPT" ]]; then
            echo "❌ Script no encontrado: $SCRIPT"
            continue
        fi

        echo "📦 Subiendo script..."
        scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SCRIPT" $USER@"$IP":/tmp/

        echo "🚀 Ejecutando script vía SSH..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" $USER@"$IP" "sudo bash /tmp/install_${TOOL}.sh"

        echo "✔ Instalación de $TOOL completada."

        # ====================================================
        # 🔍 VERIFICACIÓN REAL DE INSTALACIÓN
        # ====================================================
        echo "🔎 Verificando instalación de $TOOL en $INSTANCE..."

        case "$TOOL" in
            suricata)
                CHECK_CMD="suricata -V"
                ;;
            snort)
                CHECK_CMD="snort -V"
                ;;
            wazuh)
                CHECK_CMD="systemctl status wazuh-agent"
                ;;
            *)
                CHECK_CMD="which $TOOL"
                ;;
        esac

        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" $USER@"$IP" "$CHECK_CMD" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            echo "✅ Verificado: $TOOL está instalado en $INSTANCE"
        else
            echo "❌ ERROR: $TOOL NO aparece instalado en $INSTANCE"
        fi

        echo "----------------------------------------------------"
    done

done

echo "🎉 PROCESO COMPLETO FINALIZADO"
