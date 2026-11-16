#!/bin/bash
# Customize repo templates from stock example.com defaults to local site values.
# Must be run from the repository root (directory containing this scripts/ folder).
set -euo pipefail

RT_HOST_DEFAULT=rt.example.com
SMTP_HOST_DEFAULT=smtp.example.com
MARIADB_USER_DEFAULT=rt_user
MARIADB_PASS_DEFAULT=rt_pass
MARIADB_ROOTPW_DEFAULT=changeme_root
SERVICE_USER_DEFAULT=service-user

RT_HOST=""
SMTP_HOST=""
MARIADB_USER=""
MARIADB_PASS=""
MARIADB_ROOTPW=""
SERVICE_USER=""

UPDATES=()

usage() {
    cat <<'EOF'
Usage: scripts/customize.sh [OPTIONS]

Run from the repository root. Replaces stock template values in config, host
config, quadlet, cron, and documentation files.

Options:
  -h, --help              Show this help
  -r, --rt-host HOST      RT web/mail hostname (default: rt.example.com)
  -s, --smtp-host HOST    Outbound SMTP relay for exim (default: smtp.example.com)
  -u, --mariadb-user USER MariaDB application user (default: rt_user)
  -p, --mariadb-pass PASS MariaDB application password (default: rt_pass)
  -R, --mariadb-rootpw PASS MariaDB root password (default: changeme_root)
  -U, --service-user USER Local rootless quadlet account (default: service-user)

Examples:
  scripts/customize.sh -r rt.myorg.edu -s smtp.myorg.edu
  scripts/customize.sh -u rt_user -p 'secret' -U service-user

After running, copy config/ and host_config/ to the host and reinstall quadlets
as documented in README.md.
EOF
}

require_repo_root() {
    if [[ ! -f README.md || ! -d quadlet || ! -d config ]]; then
        echo "Error: run this script from the repository root." >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -r|--rt-host)
            RT_HOST=$2
            shift 2
            ;;
        -s|--smtp-host)
            SMTP_HOST=$2
            shift 2
            ;;
        -u|--mariadb-user)
            MARIADB_USER=$2
            shift 2
            ;;
        -p|--mariadb-pass)
            MARIADB_PASS=$2
            shift 2
            ;;
        -R|--mariadb-rootpw|--maraidb-rootpw)
            MARIADB_ROOTPW=$2
            shift 2
            ;;
        -U|--service-user)
            SERVICE_USER=$2
            shift 2
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_repo_root

if [[ -z "$RT_HOST" && -z "$SMTP_HOST" && -z "$MARIADB_USER" && -z "$MARIADB_PASS" && -z "$MARIADB_ROOTPW" && -z "$SERVICE_USER" ]]; then
    echo "Error: specify at least one option to customize." >&2
    usage >&2
    exit 1
fi

replace_in_files() {
    local old=$1
    local new=$2
    local field=$3
    local -a files=("$@")
    files=("${files[@]:3}")
    for file in "${files[@]}"; do
        if [[ -f "$file" ]] && grep -qF "$old" "$file"; then
            perl -pi -e 'BEGIN { $o = shift; $n = shift } s/\Q$o\E/$n/g' "$old" "$new" "$file"
            UPDATES+=("$file: $field: $old -> $new")
        fi
    done
}

RT_HOST_FILES=(
    config/RT_SiteConfig.pm
    config/RT_SiteConfig.pm.test
    config/msmtprc
    config/exim.conf
    host_config/apache/rt5-proxy.conf
    host_config/postfix/transport
    host_config/postfix/virtual
    host_config/README.md
    host_config/apache/README.md
    cron/Readme.md
    README.md
)

SMTP_HOST_FILES=(
    config/exim.conf
    README.md
)

MARIADB_USER_FILES=(
    config/RT_SiteConfig.pm
    config/RT_SiteConfig.pm.test
    cron/backup-database.sh
    cron/Readme.md
    podman-rt/test-image.sh
    quadlet/mariadb.container
    README.md
)

MARIADB_PASS_FILES=(
    config/RT_SiteConfig.pm
    config/RT_SiteConfig.pm.test
    cron/backup-database.sh
    cron/Readme.md
    podman-rt/test-image.sh
    quadlet/mariadb.container
    README.md
)

MARIADB_ROOTPW_FILES=(
    quadlet/mariadb.container
    README.md
)

SERVICE_USER_FILES=(
    README.md
    host_config/apache/README.md
    cron/Readme.md
)

if [[ -n "$RT_HOST" ]]; then
    replace_in_files "$RT_HOST_DEFAULT" "$RT_HOST" "rt-host" "${RT_HOST_FILES[@]}"
fi

if [[ -n "$SMTP_HOST" ]]; then
    replace_in_files "$SMTP_HOST_DEFAULT" "$SMTP_HOST" "smtp-host" "${SMTP_HOST_FILES[@]}"
fi

if [[ -n "$MARIADB_USER" ]]; then
    replace_in_files "$MARIADB_USER_DEFAULT" "$MARIADB_USER" "mariadb-user" "${MARIADB_USER_FILES[@]}"
fi

if [[ -n "$MARIADB_PASS" ]]; then
    replace_in_files "$MARIADB_PASS_DEFAULT" "$MARIADB_PASS" "mariadb-pass" "${MARIADB_PASS_FILES[@]}"
fi

if [[ -n "$MARIADB_ROOTPW" ]]; then
    replace_in_files "$MARIADB_ROOTPW_DEFAULT" "$MARIADB_ROOTPW" "mariadb-rootpw" "${MARIADB_ROOTPW_FILES[@]}"
fi

if [[ -n "$SERVICE_USER" ]]; then
    replace_in_files "$SERVICE_USER_DEFAULT" "$SERVICE_USER" "service-user" "${SERVICE_USER_FILES[@]}"
fi

echo "Customization complete."
if [[ ${#UPDATES[@]} -eq 0 ]]; then
    echo "No matching default values found to replace (files may already be customized)."
else
    echo ""
    echo "Updated files and values:"
    for entry in "${UPDATES[@]}"; do
        echo "  - $entry"
    done
fi
