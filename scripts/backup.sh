#!/usr/bin/env bash
# Erstellt ein komprimiertes Postgres-Backup aus dem db-Container
# und behält die letzten 14 Backups.
#
# Beispiel-Cronjob (täglich um 03:30 Uhr):
#   30 3 * * * /pfad/zu/umami-analytics/scripts/backup.sh >> /var/log/umami-backup.log 2>&1
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$REPO_DIR/backups"
KEEP=14

mkdir -p "$BACKUP_DIR"

FILE="$BACKUP_DIR/umami-$(date +%F_%H%M).sql.gz"

# -T: kein TTY (wichtig für cron); pg_dump läuft im Container als User umami
docker compose -f "$REPO_DIR/docker-compose.yml" exec -T db \
  pg_dump -U umami umami | gzip > "$FILE"

echo "Backup erstellt: $FILE ($(du -h "$FILE" | cut -f1))"

# Alte Backups löschen — nur die neuesten $KEEP behalten
ls -1t "$BACKUP_DIR"/umami-*.sql.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -- "$old"
  echo "Gelöscht: $old"
done
