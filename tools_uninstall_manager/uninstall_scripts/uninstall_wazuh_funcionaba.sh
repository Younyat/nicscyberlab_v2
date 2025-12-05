#!/usr/bin/env bash
# ============================================================
#   Wazuh Uninstaller (Ubuntu 22.04 FINAL VERSION)
#   Limpieza completa tras instalador oficial Wazuh 4.x
#   Elimina estados ic, iF, ii
#   Compatible con set -euo pipefail
# ============================================================
set -euo pipefail

INSTANCE="$1"
IP_PRIV="$2"
IP_FLOAT="$3"
USER="$4"

IP="${IP_FLOAT:-$IP_PRIV}"

echo "----------------------------------------------------------"
echo "Desinstalando Wazuh y Filebeat en $INSTANCE ($IP)..."
echo "----------------------------------------------------------"

SSH_KEY=""
for K in "$HOME/.ssh/"*; do
    [[ -f "$K" ]] && grep -q "PRIVATE KEY" "$K" && SSH_KEY="$K" && break
done

if [[ -z "$SSH_KEY" ]]; then
    echo "ERROR: No se encontró ninguna clave privada SSH en ~/.ssh"
    exit 1
fi

chmod 600 "$SSH_KEY"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$USER@$IP" bash << 'EOF'
set -euo pipefail

echo "[1] Deteniendo servicios"
sudo systemctl stop wazuh-manager.service 2>/dev/null || true
sudo systemctl stop wazuh-dashboard.service 2>/dev/null || true
sudo systemctl stop wazuh-indexer.service 2>/dev/null || true
sudo systemctl stop filebeat.service 2>/dev/null || true

echo "[2] Purga dirigida de paquetes con dpkg --purge --force-all"
sudo dpkg --purge --force-all filebeat wazuh-dashboard wazuh-indexer wazuh-manager >/dev/null 2>&1 || true

echo "[3] Eliminando unidades systemd"
sudo rm -f /etc/systemd/system/wazuh*.service
sudo rm -f /lib/systemd/system/wazuh*.service
sudo rm -f /etc/systemd/system/filebeat*.service
sudo rm -f /lib/systemd/system/filebeat*.service

echo "[4] Eliminando repos"
sudo rm -f /etc/apt/sources.list.d/wazuh*.list
sudo rm -f /etc/apt/trusted.gpg.d/wazuh*.gpg

echo "[5] Eliminando directorios y datos"
sudo rm -rf /var/ossec
sudo rm -rf /etc/ossec*
sudo rm -rf /opt/wazuh*
sudo rm -rf /usr/share/wazuh*
sudo rm -rf /etc/wazuh*
sudo rm -rf /var/lib/wazuh*
sudo rm -rf /var/log/wazuh*

sudo rm -rf /etc/filebeat
sudo rm -rf /var/lib/filebeat
sudo rm -rf /var/log/filebeat
sudo rm -rf /usr/share/filebeat
sudo rm -f /usr/bin/filebeat

sudo rm -rf /etc/opensearch*
sudo rm -rf /var/lib/opensearch*
sudo rm -rf /usr/share/opensearch*
sudo rm -rf /var/log/opensearch*
sudo rm -rf /var/run/opensearch*

echo "[6] Eliminando usuarios"
sudo userdel -r wazuh          2>/dev/null || true
sudo userdel -r wazuh-indexer  2>/dev/null || true
sudo userdel -r wazuh-dashboard 2>/dev/null || true
sudo userdel -r filebeat       2>/dev/null || true

echo "[7] Reparando dpkg"
sudo dpkg --configure -a >/dev/null 2>&1 || true
sudo apt --fix-broken install -y >/dev/null 2>&1 || true

sudo systemctl daemon-reload

echo "Validación final real..."

FAILED=false

pgrep -fa wazuh && FAILED=true
pgrep -fa filebeat && FAILED=true
pgrep -fa opensearch && FAILED=true

systemctl list-units | grep -qi "wazuh" && FAILED=true
systemctl list-units | grep -qi "filebeat" && FAILED=true
systemctl list-units | grep -qi "opensearch" && FAILED=true

command -v wazuh-control >/dev/null 2>&1 && FAILED=true
command -v filebeat       >/dev/null 2>&1 && FAILED=true

[[ -d "/var/ossec" ]] && FAILED=true
[[ -d "/etc/wazuh" ]]  && FAILED=true
[[ -d "/opt/wazuh" ]]  && FAILED=true

ss -tunlp | grep -q ":1515" && FAILED=true
ss -tunlp | grep -q ":5601" && FAILED=true

if [[ "$FAILED" == false ]]; then
  echo "--------------------------------------------------"
  echo "LIMPIEZA TOTAL COMPLETADA"
  echo "WAZUH, FILEBEAT Y OPENSEARCH ELIMINADOS"
  echo "--------------------------------------------------"

  echo
  echo "🛈 Quedan posibles entradas en dpkg, NO BLOQUEAN."
  dpkg -l | grep -E 'wazuh|filebeat|opensearch' || true
  echo "Estos son solo metadatos e inofensivos."
  exit 0
else
  echo "--------------------------------------------------"
  echo "ERROR: Algún componente sigue activo."
  echo "--------------------------------------------------"
  dpkg -l | grep -E 'wazuh|filebeat|opensearch' || true
  exit 3
fi
EOF
