#!/usr/bin/env bash
set -euo pipefail

##############################################################
#      DESTRUCCIÓN COMPLETA DEL ESCENARIO CREADO EN FASE 2  #
#  - Elimina instancias, FIPs, puertos                       #
#  - Elimina keypair cyberlab-key                            #
#  - Elimina claves locales                                  #
#  - Elimina summary.json y escenario original               #
#  - Limpia OUTDIR                                           #
##############################################################

ADMIN_OPENRC="$HOME/Escritorio/cyber-range-v1/admin-openrc.sh"

DEFAULT_KEYPAIR="cyberlab-key"
LOCAL_KEYFILE="$HOME/.ssh/cyberlab-key"

# ============================================================
# 1. Cargar credenciales OpenStack
# ============================================================

if [ -f "$ADMIN_OPENRC" ]; then
    source "$ADMIN_OPENRC"
    echo "🔐 Credenciales OpenStack cargadas."
else
    echo "❌ ERROR: No se encontró admin-openrc en: $ADMIN_OPENRC"
    exit 1
fi

# ============================================================
# 2. Validación de parámetros
# ============================================================

if [ "$#" -lt 2 ]; then
    echo "Uso: $0 escenario.json output_dir"
    exit 1
fi

SCENARIO_JSON="$1"
OUTDIR="$2"
SUMMARY_JSON="$OUTDIR/summary.json"

if [ ! -f "$SCENARIO_JSON" ]; then
    echo "❌ ERROR: No existe archivo de escenario: $SCENARIO_JSON"
    exit 1
fi

if [ ! -f "$SUMMARY_JSON" ]; then
    echo "❌ ERROR: No existe summary.json: $SUMMARY_JSON"
    exit 1
fi

echo ""
echo "📄 Escenario: $SCENARIO_JSON"
echo "📄 Summary:   $SUMMARY_JSON"
echo "📂 Output dir: $OUTDIR"
echo "------------------------------------------------------------"

# ============================================================
# 3. Eliminar recursos según summary.json
# ============================================================

while read -r node; do

    id=$(echo "$node" | jq -r '.id')
    name=$(echo "$node" | jq -r '.name')
    fip=$(echo "$node" | jq -r '.floating_ip')

    SAFE_ID=$(echo "$id" | tr -c '[:alnum:]' '_')
    PORT_NAME="${SAFE_ID}-port"

    echo ""
    echo "🔥 Eliminando nodo → $name"
    echo "------------------------------------------------------------"

    # === 1) Floating IP =================================================

    if [ -n "$fip" ] && openstack floating ip show "$fip" >/dev/null 2>&1; then
        echo "🌍 Eliminando Floating IP: $fip"
        openstack floating ip delete "$fip" || true
    else
        echo "✔ No se encontró Floating IP."
    fi

    # === 2) Instancia ===================================================

    if openstack server show "$name" >/dev/null 2>&1; then
        echo "🖥 Eliminando instancia: $name"
        openstack server delete "$name" || true
    else
        echo "✔ Instancia ya eliminada."
    fi

    # Esperar eliminación real
    for i in {1..20}; do
        if ! openstack server show "$name" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    # === 3) Puerto ======================================================

    if openstack port show "$PORT_NAME" >/dev/null 2>&1; then
        echo "🌐 Eliminando puerto: $PORT_NAME"
        openstack port delete "$PORT_NAME" || true
    else
        echo "✔ Puerto ya eliminado o no existe."
    fi

    echo "✔ Nodo $name eliminado."
    echo "------------------------------------------------------------"

done < <(jq -c '.[]' "$SUMMARY_JSON")


# ============================================================
# 4. Eliminar Keypair y claves locales
# ============================================================

echo ""
echo "🔑 Eliminando keypair y claves locales..."

if openstack keypair show "$DEFAULT_KEYPAIR" >/dev/null 2>&1; then
    echo "🗑 Eliminando keypair OpenStack: $DEFAULT_KEYPAIR"
    openstack keypair delete "$DEFAULT_KEYPAIR" || true
else
    echo "✔ Keypair $DEFAULT_KEYPAIR no existe."
fi

if [ -f "$LOCAL_KEYFILE" ] || [ -f "${LOCAL_KEYFILE}.pub" ]; then
    echo "🗑 Eliminando claves locales: $LOCAL_KEYFILE*"
    rm -f "$LOCAL_KEYFILE" "${LOCAL_KEYFILE}.pub" || true
else
    echo "✔ No se encontraron claves locales."
fi

# ============================================================
# 5. Limpiar output_dir
# ============================================================

echo ""
echo "🧹 Limpiando directorio de salida: $OUTDIR"
rm -rf "${OUTDIR:?}/"* || true

# ============================================================
# 6. Eliminar escenario.json original
# ============================================================

echo "🗑 Eliminando archivo del escenario: $SCENARIO_JSON"
rm -f "$SCENARIO_JSON" || true


echo ""
echo "=================================================================="
echo "🎉 ESCENARIO COMPLETO ELIMINADO"
echo "🧽 OUTDIR limpiado: $OUTDIR"
echo "🗑 Escenario JSON eliminado: $SCENARIO_JSON"
echo "🔑 Claves y keypair eliminadas"
echo "=================================================================="
