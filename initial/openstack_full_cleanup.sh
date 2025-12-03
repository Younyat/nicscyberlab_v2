#!/usr/bin/env bash
# ======================================================
# 🧹 Limpieza total de recursos en OpenStack
# Elimina: instancias, volúmenes, routers, redes, subredes,
# grupos de seguridad, imágenes y sabores.
# Autor: Younes Assouyat
# ======================================================

set -euo pipefail

echo "==============================================="
echo "  LIMPIEZA COMPLETA DE OPENSTACK"
echo "==============================================="
read -p "¿Seguro que deseas eliminar TODO (y/n)? " confirm
if [[ "$confirm" != "y" ]]; then
  echo "🚫 Operación cancelada."
  exit 0
fi

echo ""
echo " Eliminando instancias (servers)..."
for id in $(openstack server list -f value -c ID); do
  echo "🗑️ Eliminando instancia: $id"
  openstack server delete "$id" || true
done

echo ""
echo " Eliminando volúmenes..."
for id in $(openstack volume list -f value -c ID); do
  echo "🗑️ Eliminando volumen: $id"
  openstack volume delete "$id" || true
done

echo ""
echo " Eliminando routers..."
for id in $(openstack router list -f value -c ID); do
  echo " Eliminando router: $id"
  # Desconectar interfaces antes
  for port in $(openstack port list --router "$id" -f value -c ID); do
    echo "    Quitando interfaz del router $id → puerto $port"
    openstack router remove port "$id" "$port" || true
  done
  openstack router delete "$id" || true
done

echo ""
echo " Eliminando subredes..."
for id in $(openstack subnet list -f value -c ID); do
  echo " Eliminando subred: $id"
  openstack subnet delete "$id" || true
done

echo ""
echo " Eliminando redes..."
for id in $(openstack network list -f value -c ID); do
  echo " Eliminando red: $id"
  openstack network delete "$id" || true
done

echo ""
echo " Eliminando grupos de seguridad..."
for id in $(openstack security group list -f value -c ID); do
  # Evitar eliminar el grupo "default" si no quieres perderlo:
  NAME=$(openstack security group show "$id" -f value -c name)
  if [[ "$NAME" == "default" ]]; then
    echo "  Saltando grupo default ($id)"
    continue
  fi
  echo "🗑️ Eliminando grupo de seguridad: $id ($NAME)"
  openstack security group delete "$id" || true
done

echo ""
echo " Eliminando imágenes..."
for id in $(openstack image list -f value -c ID); do
  echo " Eliminando imagen: $id"
  openstack image delete "$id" || true
done

echo ""
echo " Eliminando sabores (flavors)..."
for id in $(openstack flavor list -f value -c ID); do
  echo " Eliminando flavor: $id"
  openstack flavor delete "$id" || true
done





echo "============================================="
echo "🧹 LIMPIEZA COMPLETA OPENSTACK"
echo "============================================="


# ---------------------------------------------------------
# 1️⃣ BORRAR TODOS LOS ROUTERS
# ---------------------------------------------------------
echo
echo "🗑 Borrando routers..."

ROUTERS=$(openstack router list -f value -c ID)

if [ -z "$ROUTERS" ]; then
    echo "✔ No hay routers para borrar."
else
    for ROUTER_ID in $ROUTERS; do
        echo "-------------------------------------------------"
        echo "🗑 Procesando router: $ROUTER_ID"
        
        PORTS=$(openstack port list --router "$ROUTER_ID" -f value -c ID)

        if [ -z "$PORTS" ]; then
            echo "   No hay interfaces en este router."
        else
            echo "   Eliminando interfaces:"
            for PORT_ID in $PORTS; do
                echo "    ➤ Eliminando interfaz $PORT_ID..."
                openstack router remove port "$ROUTER_ID" "$PORT_ID" \
                    || echo "       Interfaz ya no existe, continuando..."
            done
        fi

        echo "  🗑 Borrando router..."
        openstack router delete "$ROUTER_ID" \
            && echo "  ✔ Router eliminado." \
            || echo "   No se pudo borrar (dependencias o no existe)."
    done
fi


# ---------------------------------------------------------
# 2️⃣ BORRAR TODOS LOS SECURITY GROUPS (excepto default)
# ---------------------------------------------------------
echo
echo "🛡️ Borrando Security Groups..."

SEC_GROUPS=$(openstack security group list -f value -c ID -c Name)

while IFS= read -r LINE; do
    SG_ID=$(echo "$LINE" | awk '{print $1}')
    SG_NAME=$(echo "$LINE" | awk '{print $2}')

    if [ "$SG_NAME" = "default" ]; then
        echo " Saltando security group default ($SG_ID)"
        continue
    fi

    echo "-------------------------------------------------"
    echo " Procesando Security Group: $SG_NAME ($SG_ID)"

    RULES=$(openstack security group rule list "$SG_ID" -f value -c ID)

    for RULE_ID in $RULES; do
        echo "  ➤ Eliminando regla $RULE_ID..."
        openstack security group rule delete "$RULE_ID" \
            || echo "     La regla ya no existe."
    done

    echo "  🗑 Eliminando Security Group..."
    openstack security group delete "$SG_ID" \
        && echo "  ✔ Security Group eliminado." \
        || echo "   No se pudo eliminar."
done <<< "$SEC_GROUPS"


# ---------------------------------------------------------
# 3️⃣ BORRAR TODOS LOS KEYPAIRS
# ---------------------------------------------------------
echo
echo "🗝️ Borrando todas las claves SSH..."

KEYPAIRS=$(openstack keypair list -f value -c Name)

if [ -z "$KEYPAIRS" ]; then
    echo "✔ No hay claves para borrar."
else
    for KEY in $KEYPAIRS; do
        echo "🗝️ Eliminando clave: $KEY"
        openstack keypair delete "$KEY" \
            && echo "   ✔ Clave borrada." \
            || echo "    No se pudo borrar."
    done
fi


echo
echo "============================================="
echo "✔ LIMPIEZA COMPLETADA"
echo "============================================="


echo ""
echo " Limpieza completada. Entorno OpenStack vacío."
