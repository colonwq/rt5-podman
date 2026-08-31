#!/bin/bash
# Backup RT attachment files from the rt5 quadlet volume mount (/attachments).
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
BACKUP_DIR=/store/backups
mkdir -p "$BACKUP_DIR"

/usr/bin/podman exec -i rt5 bash -c '(cd /attachments/ && tar -czf - .)' \
  > "${BACKUP_DIR}/attachments-$(date +%s).tgz"
