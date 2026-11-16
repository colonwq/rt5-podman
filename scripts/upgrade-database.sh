#!/bin/bash
# Upgrade RT database schema and data to match the installed RT version in the rt5 container.
# Run on the host as the quadlet user (service-user). Upgrade runs inside rt5.
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

RT_CONTAINER="${RT_CONTAINER:-rt5}"
SITE_CONFIG="${RT_SITE_CONFIG:-/store/config/RT_SiteConfig.pm}"

UPGRADE_FROM=""
DBA_USER="${MARIADB_DBA_USER:-root}"
DBA_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"

usage() {
    cat <<'EOF'
Usage: scripts/upgrade-database.sh [OPTIONS]

Apply RT schema and data upgrades using rt-setup-database inside the running rt5
container. Use after restoring an older RT database or upgrading the RT container
image to a newer version.

Run on the host as the rootless Podman user (for example service-user). Take a
full database backup before upgrading.

Options:
  -h, --help              Show this help
  --upgrade-from VERSION  RT version currently in the database (for example 5.0.10).
                          If omitted, rt-setup-database prompts interactively
                          (requires a TTY: podman exec -it).

Environment:
  MARIADB_ROOT_PASSWORD   MariaDB root (DBA) password for schema changes
  MARIADB_DBA_USER        DBA account (default: root)
  RT_CONTAINER            RT container name (default: rt5)
  RT_SITE_CONFIG          Path to RT_SiteConfig.pm (default: /store/config/RT_SiteConfig.pm)

Examples:
  scripts/upgrade-database.sh --upgrade-from 5.0.10
  MARIADB_ROOT_PASSWORD=changeme_root scripts/upgrade-database.sh --upgrade-from 5.0.4

For an interactive upgrade (prompts for version and DBA password):

  podman exec -it rt5 /opt/rt5/sbin/rt-setup-database --action upgrade \
    --prompt-for-dba-password
EOF
}

read_root_password() {
    if [[ -z "$DBA_PASSWORD" && -f /store/rt5-podman/quadlet/mariadb.container ]]; then
        DBA_PASSWORD=$(grep -E '^Environment=MARIADB_ROOT_PASSWORD=' \
            /store/rt5-podman/quadlet/mariadb.container \
            | sed 's/^Environment=MARIADB_ROOT_PASSWORD=//' | head -1)
    fi
    if [[ -z "$DBA_PASSWORD" && -f "${HOME}/.config/containers/systemd/mariadb.container" ]]; then
        DBA_PASSWORD=$(grep -E '^Environment=MARIADB_ROOT_PASSWORD=' \
            "${HOME}/.config/containers/systemd/mariadb.container" \
            | sed 's/^Environment=MARIADB_ROOT_PASSWORD=//' | head -1)
    fi
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
        --upgrade-from)
            UPGRADE_FROM=$2
            shift 2
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_container
read_root_password

RT_SETUP=/opt/rt5/sbin/rt-setup-database
ARGS=(--action upgrade)

if [[ -n "$UPGRADE_FROM" ]]; then
    ARGS+=(--upgrade-from "$UPGRADE_FROM")
fi

if [[ -n "$DBA_PASSWORD" ]]; then
    ARGS+=(--dba "$DBA_USER" --dba-password "$DBA_PASSWORD")
else
    ARGS+=(--prompt-for-dba-password)
    echo "Warning: MARIADB_ROOT_PASSWORD not set; upgrade may prompt for DBA password." >&2
    echo "Warning: non-interactive runs should set MARIADB_ROOT_PASSWORD or use podman exec -it." >&2
fi

echo "Running rt-setup-database --action upgrade in '${RT_CONTAINER}'..."
podman exec "$RT_CONTAINER" "$RT_SETUP" "${ARGS[@]}"

echo "Database upgrade finished. Verify RT in the web UI and check container logs if needed."
