#!/bin/bash
# Backup RT database from the mariadb quadlet (rt5-net; container name mariadb).
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
BACKUP_DIR=/store/backups
mkdir -p "$BACKUP_DIR"

/usr/bin/podman exec mariadb bash -c '(
  mysqldump -urt_user -prt_pass --default-character-set=utf8mb4 rt5 \
    --tables sessions --no-data --single-transaction
  mysqldump -urt_user -prt_pass --default-character-set=utf8mb4 rt5 \
    --ignore-table=rt5.sessions --single-transaction
)' | gzip > "${BACKUP_DIR}/rt-$(date +%s).sql.gz"
