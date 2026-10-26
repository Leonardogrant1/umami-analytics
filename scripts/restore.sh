#!/usr/bin/env bash
# Spielt ein Backup wieder ein (überschreibt die aktuelle Datenbank!).
# Nutzung: ./scripts/restore.sh backups/umami-2026-10-26_0330.sql.gz
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Nutzung: $0 <backup-datei.sql.gz>" >&2
  exit 1
fi
BACKUP_FILE="$1"

echo "ACHTUNG: Die aktuelle Umami-Datenbank wird gelöscht und durch"
echo "         $BACKUP_FILE ersetzt."
read -r -p "Fortfahren? [ja/NEIN] " answer
[ "$answer" = "ja" ] || { echo "Abgebrochen."; exit 1; }

compose() { docker compose -f "$REPO_DIR/docker-compose.yml" "$@"; }

# Umami stoppen, damit keine offenen Verbindungen das Restore blockieren
compose stop umami

# Schema leeren, dann Backup einspielen
compose exec -T db psql -U umami -d umami \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
gunzip -c "$BACKUP_FILE" | compose exec -T db psql -U umami -d umami

compose start umami
echo "Restore abgeschlossen."
