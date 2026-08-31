#!/bin/bash
# Backup RT database from the mariadb quadlet (rt5-net; container name mariadb).
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
BACKUP_DIR=/store/backups
BACKUP_PATTERN='rt-*.sql.gz'
KEEP_BEFORE_BACKUP=2
DB_USER=rt_user
DB_PASS=rt_pass
DB_NAME=rt5

prune_old_backups() {
    local -a files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "$BACKUP_PATTERN" -type f -printf '%T@ %p\n' \
        | sort -n | awk '{print $2}')

    local count=${#files[@]}
    if (( count > KEEP_BEFORE_BACKUP )); then
        local delete_count=$((count - KEEP_BEFORE_BACKUP))
        for (( i=0; i<delete_count; i++ )); do
            echo "Removing old database backup: ${files[i]}"
            rm -f "${files[i]}"
        done
    fi
}

verify_backup_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo "Error: database backup file was not created: $file" >&2
        exit 1
    fi
    if [[ ! -s "$file" ]]; then
        echo "Error: database backup file is empty (0 bytes): $file" >&2
        rm -f "$file"
        exit 1
    fi
}

mkdir -p "$BACKUP_DIR"
prune_old_backups

OUTPUT="${BACKUP_DIR}/rt-$(date +%s).sql.gz"

/usr/bin/podman exec mariadb bash -c "(
  mysqldump -u${DB_USER} -p${DB_PASS} --default-character-set=utf8mb4 ${DB_NAME} \
    --tables sessions --no-data --single-transaction
  mysqldump -u${DB_USER} -p${DB_PASS} --default-character-set=utf8mb4 ${DB_NAME} \
    --ignore-table=${DB_NAME}.sessions --single-transaction
)" | gzip > "$OUTPUT"

verify_backup_file "$OUTPUT"
echo "Database backup complete: $OUTPUT"
