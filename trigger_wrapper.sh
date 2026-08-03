#!/usr/bin/env bash
# trigger_update.sh
# Ruft den Admin-Endpoint /admin/update-challenges mit dem WRITE_TOKEN aus der Umgebung auf

set -euo pipefail # sauber bei Fehlern abbrechen

# WRITE_TOKEN aus der Umgebung holen
: "${WRITE_TOKEN:?FEHLER: WRITE_TOKEN ist nicht gesetzt}" # bricht ab, wenn kein Token gesetzt ist

API_URL="${API_URL:-http://localhost:8000}" # Basis-URL der API, Standard localhost

echo "Trigger Admin-Update-Endpoint auf ${API_URL}/admin/update-challenges..."

curl -X POST "${API_URL}/admin/update-challenges" \
  -H "x-api-key: ${WRITE_TOKEN}" >> /var/log/cron.log 2>&1