#!/bin/bash
set -euo pipefail

echo "==============================================="
echo "🧹 INICIO limpiar_inicial.sh"
echo "==============================================="

# aquí pones tu limpieza real:
bash openstack_full_cleanup.sh <<< "y"

echo "✅ Limpieza completa."
exit 0
