#!/bin/bash
# Restore a database backup into MariaDB via the rt5 container.
# Run on the host as the quadlet user (service-user). Import runs inside rt5.
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

RT_CONTAINER="${RT_CONTAINER:-rt5}"
MARIADB_HOST="${MARIADB_HOST:-mariadb}"
SITE_CONFIG="${RT_SITE_CONFIG:-/store/config/RT_SiteConfig.pm}"

FILE=""
DATABASE="rt5"

usage() {
    cat <<'EOF'
Usage: scripts/restore-database.sh [OPTIONS]

Restore a SQL dump into MariaDB. The archive or dump is copied into the running
rt5 container; mariadb client inside rt5 connects to the mariadb container on
rt5-net.

Run on the host as the rootless Podman user (for example service-user).

Options:
  -h, --help              Show this help
  -f, --file PATH         Backup file (.tgz, .tar.gz, .sql.gz, or plain .sql)
  -d, --database NAME     Target database name (default: rt5)

Environment:
  MARIADB_USER            Database user (default: from RT_SiteConfig.pm or rt_user)
  MARIADB_PASSWORD        Database password (default: from RT_SiteConfig.pm or rt_pass)
  RT_SITE_CONFIG          Path to RT_SiteConfig.pm (default: /store/config/RT_SiteConfig.pm)
  RT_CONTAINER            RT container name (default: rt5)

Examples:
  scripts/restore-database.sh -f /store/backups/rt-1725123456.sql.gz
  scripts/restore-database.sh --file /store/backups/rt-dump.tgz --database rt5

Supports backups from cron/backup-database.sh (.sql.gz) and tar archives (.tgz)
containing a .sql or .sql.gz file.
EOF
}

read_db_creds() {
    if [[ -z "${MARIADB_USER:-}" && -f "$SITE_CONFIG" ]]; then
        MARIADB_USER=$(grep -E 'Set\(\s*\$DatabaseUser' "$SITE_CONFIG" \
            | sed -n "s/.*'\\([^']*\\)'.*/\1/p" | head -1)
    fi
    if [[ -z "${MARIADB_PASSWORD:-}" && -f "$SITE_CONFIG" ]]; then
        MARIADB_PASSWORD=$(grep -E 'Set\(\s*\$DatabasePassword' "$SITE_CONFIG" \
            | sed -n "s/.*'\\([^']*\\)'.*/\1/p" | head -1)
    fi
    MARIADB_USER="${MARIADB_USER:-rt_user}"
    MARIADB_PASSWORD="${MARIADB_PASSWORD:-rt_pass}"
}

require_container() {
    if ! podman container exists "$RT_CONTAINER" 2>/dev/null; then
        echo "Error: container '$RT_CONTAINER' does not exist." >&2
        exit 1
    fi
    if [[ "$(podman inspect -f '{{.State.Running}}' "$RT_CONTAINER")" != "true" ]]; then
        echo "Error: container '$RT_CONTAINER' is not running." >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--file)
            FILE=$2
            shift 2
            ;;
        -d|--database)
            DATABASE=$2
            shift 2
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$FILE" ]]; then
    echo "Error: --file is required." >&2
    usage >&2
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    echo "Error: backup file not found: $FILE" >&2
    exit 1
fi

read_db_creds
require_container

ARCHIVE_PATH="/tmp/rt-restore-$$"
REMOTE_ARCHIVE="${ARCHIVE_PATH}/input"
REMOTE_WORK="${ARCHIVE_PATH}/work"

podman exec "$RT_CONTAINER" mkdir -p "$ARCHIVE_PATH" "$REMOTE_WORK"

case "$FILE" in
    *.tgz|*.tar.gz)
        podman cp "$FILE" "${RT_CONTAINER}:${REMOTE_ARCHIVE}.tgz"
        podman exec "$RT_CONTAINER" bash -c "
set -euo pipefail
tar xzf '${REMOTE_ARCHIVE}.tgz' -C '${REMOTE_WORK}'
sql=\$(find '${REMOTE_WORK}' -type f \( -name '*.sql' -o -name '*.sql.gz' \) | head -1)
if [[ -z \"\$sql\" ]]; then
    echo 'Error: no .sql or .sql.gz file found in archive.' >&2
    exit 1
fi
if [[ \"\$sql\" == *.gz ]]; then
    gunzip -c \"\$sql\" | mariadb -h '${MARIADB_HOST}' -u'${MARIADB_USER}' -p'${MARIADB_PASSWORD}' '${DATABASE}'
else
    mariadb -h '${MARIADB_HOST}' -u'${MARIADB_USER}' -p'${MARIADB_PASSWORD}' '${DATABASE}' < \"\$sql\"
fi
"
        ;;
    *.sql.gz|*.gz)
        gunzip -c "$FILE" | podman exec -i "$RT_CONTAINER" \
            mariadb -h "$MARIADB_HOST" -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$DATABASE"
        ;;
    *.sql)
        podman exec -i "$RT_CONTAINER" \
            mariadb -h "$MARIADB_HOST" -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$DATABASE" < "$FILE"
        ;;
    *)
        echo "Error: unsupported file type (use .tgz, .tar.gz, .sql.gz, or .sql): $FILE" >&2
        exit 1
        ;;
esac

podman exec "$RT_CONTAINER" rm -rf "$ARCHIVE_PATH"

echo "Restore complete: imported into database '${DATABASE}' on '${MARIADB_HOST}'."
