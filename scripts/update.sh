#!/usr/bin/env bash
# Zieht die neuesten Images, startet die Container neu und räumt alte Images auf.
# Tipp: vorher ein Backup machen (./scripts/backup.sh).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

docker compose pull
docker compose up -d --force-recreate
docker image prune -f

echo "Update abgeschlossen. Status:"
docker compose ps
