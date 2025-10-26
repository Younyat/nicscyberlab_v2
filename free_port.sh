#!/usr/bin/env bash
# =============================================
# 🔧 Script para liberar un puerto TCP ocupado
# =============================================

PORT=${1:-5001}  # Puerto por defecto = 5001
PIDS=$(sudo lsof -t -i:$PORT)

if [ -z "$PIDS" ]; then
  echo "✅ El puerto $PORT está libre."
else
  echo "⚠️ Procesos usando el puerto $PORT:"
  sudo lsof -i:$PORT
  echo
  echo "🧹 Matando procesos..."
  sudo kill -9 $PIDS 2>/dev/null

  sleep 1
  if sudo lsof -i:$PORT > /dev/null 2>&1; then
    echo "❌ Error: no se pudieron eliminar todos los procesos en el puerto $PORT."
  else
    echo "✅ Puerto $PORT liberado correctamente."
  fi
fi
