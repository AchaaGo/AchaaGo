#!/bin/sh
# Daily PostgreSQL backups (docker-compose.yml "backup" service).
# Writes a pg_dump custom-format file to ./.data/backups on the host, keeps
# BACKUP_KEEP_DAYS days of them, and runs once at start-up, then every
# BACKUP_INTERVAL_SECONDS. Restoring is described in README "Production".
# These copies sit on the same disk as the database: also copy the folder
# off the server now and then.
set -eu
keep_days="${BACKUP_KEEP_DAYS:-14}"
interval="${BACKUP_INTERVAL_SECONDS:-86400}"
mkdir -p /backups
while true; do
  target="/backups/achaago-$(date -u +%Y%m%d-%H%M%S).dump"
  # Write to a temporary name first, so a half-written file never looks like a backup.
  if pg_dump --format=custom --file="$target.partial"; then
    mv "$target.partial" "$target"
    echo "backup: wrote $target ($(du -h "$target" | cut -f1))"
  else
    rm -f "$target.partial"
    echo "backup: FAILED, keeping the previous backups" >&2
  fi
  find /backups -name 'achaago-*.dump' -mtime +"$keep_days" -delete
  sleep "$interval"
done
