#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="tools-installer"
TOOL_NAME="wazuh"
TOOL_DIR="${BASE_DIR}/${TOOL_NAME}"
INSTALLER="${TOOL_DIR}/installer.sh"

echo "🛠️ Preparando entorno para wazuh..."

mkdir -p "$TOOL_DIR"

if [ ! -f "$INSTALLER" ]; then
    cat << 'EOF' > "$INSTALLER"
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Instalando Caldera..."
# TODO: añadir comandos de instalación real
EOF

    chmod +x "$INSTALLER"

    echo "✔ installer.sh creado para Caldera."

    # ============================================
    # 🚀 Ejecutar el installer inmediatamente
    # ============================================
    echo "🏁 Ejecutando installer.sh..."
    bash "$INSTALLER"

else
    echo "⚠️ installer.sh ya existe para Caldera."
    echo "ℹ️ Ejecútalo manualmente si quieres:"
    echo "   bash \"$INSTALLER\""
fi

echo "📂 Directorio: $TOOL_DIR"
