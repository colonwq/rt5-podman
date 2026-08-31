# System maintenance cron jobs

Routine tasks for the RT5 quadlet stack. Scripts assume:

- Rootless Podman quadlets run as `service-user` with linger enabled
- Container names: `rt5`, `mariadb`, `exim` on network `rt5-net`
- Database host inside RT is `mariadb` (not a legacy external `db.example.com`)
- Public web URL: `https://rt.example.com` (Apache proxy to `127.0.0.1:8080`)
- Backups written to `/store/backups`

| Script | Purpose |
|--------|---------|
| `externalize-attachement.sh` | Move ticket attachments from DB to `/attachments` |
| `backup-attachments.sh` | Tar backup of `/attachments` from `rt5` |
| `backup-database.sh` | `mysqldump` of `rt5` database from `mariadb` container |

## Crontab for `service-user`

Install as `service-user` (`crontab -e`). `XDG_RUNTIME_DIR` is set inside each script for rootless Podman.

```cron
# RT maintenance (quadlet containers rt5 / mariadb on rt5-net)
10 12 * * * /store/rt5-podman/cron/externalize-attachement.sh
10 15 * * * /store/rt5-podman/cron/backup-attachments.sh
10 15 * * * /store/rt5-podman/cron/backup-database.sh
```

Ensure `/store/backups` exists:

```bash
mkdir -p /store/backups
```

## Manual checks before scheduling

```bash
# Containers running
systemctl --user status rt5 mariadb

# DB reachable from rt5 (DNS on rt5-net)
podman exec rt5 getent hosts mariadb
podman exec rt5 nc -zv mariadb 3306

# Web UI (direct or via proxy)
curl -sI http://127.0.0.1:8080/
curl -skI https://rt.example.com/
```

## Restore notes

- Database: `gunzip -c rt-*.sql.gz | podman exec -i mariadb mariadb -urt_user -prt_pass rt5`
- Attachments: `tar -xzf attachments-*.tgz -C /path/to/restore`
