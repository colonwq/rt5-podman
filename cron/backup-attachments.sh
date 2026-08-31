#!/bin/bash
# Backup RT attachment files from the rt5 quadlet volume mount (/attachments).
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
BACKUP_DIR=/store/backups
BACKUP_PATTERN='attachments-*.tgz'
KEEP_BEFORE_BACKUP=2

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
            echo "Removing old attachment backup: ${files[i]}"
            rm -f "${files[i]}"
        done
    fi
}

verify_backup_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo "Error: attachment backup file was not created: $file" >&2
        exit 1
    fi
    if [[ ! -s "$file" ]]; then
        echo "Error: attachment backup file is empty (0 bytes): $file" >&2
        rm -f "$file"
        exit 1
    fi
}

mkdir -p "$BACKUP_DIR"
prune_old_backups

OUTPUT="${BACKUP_DIR}/attachments-$(date +%s).tgz"

/usr/bin/podman exec -i rt5 bash -c '(cd /attachments/ && tar -czf - .)' > "$OUTPUT"

verify_backup_file "$OUTPUT"
echo "Attachment backup complete: $OUTPUT"
