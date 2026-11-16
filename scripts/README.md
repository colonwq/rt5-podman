# Scripts

## `customize.sh`

Replaces stock template values in this repository with site-specific settings before you copy configs to the host and install quadlets. The repo defaults use example hostnames (`rt.example.com`, `smtp.example.com`), database credentials, and a local quadlet account name (`service-user`).

Run the script **from the repository root** (the directory that contains `scripts/`, `config/`, and `quadlet/`):

```bash
cd /path/to/rt5-podman
./scripts/customize.sh [OPTIONS]
```

After customization, follow the main [README.md](../README.md) to deploy `config/` and `host_config/` to `/store/config/` and install quadlets for your service user.

### Options

| Option | Short | Default | What it changes |
|--------|-------|---------|-----------------|
| `--help` | `-h` | — | Print usage and exit |
| `--rt-host` | `-r` | `rt.example.com` | RT web domain, mail addresses (`rt@…`, `rt-comment@…`), Apache `ServerName` and TLS cert paths, Postfix maps, exim `local_domains` |
| `--smtp-host` | `-s` | `smtp.example.com` | Outbound SMTP relay in `config/exim.conf` |
| `--mariadb-user` | `-u` | `rt_user` | RT database user in SiteConfig templates, cron scripts, test harness, and `quadlet/mariadb.container` |
| `--mariadb-pass` | `-p` | `rt_pass` | RT database password (same files as `--mariadb-user`) |
| `--mariadb-rootpw` | `-R` | `changeme_root` | MariaDB root password in `quadlet/mariadb.container` and README examples |
| `--service-user` | `-U` | `service-user` | Local rootless Podman account name and `/home/service-user` paths in documentation |

You may pass any combination of options; at least one is required (unless using `--help`).

The script prints every file and value it changes. It only replaces the literal default strings listed above. If a file was already customized, that default may no longer be present and the script will skip it.

Passwords with special characters are supported; quote them on the command line.

`podman-rt/test-image.sh` uses a separate test root password (`rootpass`) and is not updated by `--mariadb-rootpw`.

### Example (all parameters)

```bash
./scripts/customize.sh \
  --rt-host rt.myorg.edu \
  --smtp-host smtp.myorg.edu \
  --mariadb-user rt_user \
  --mariadb-pass 'rt-db-password' \
  --mariadb-rootpw 'mariadb-root-password' \
  --service-user service-user
```

Short-form equivalent:

```bash
./scripts/customize.sh \
  -r rt.myorg.edu \
  -s smtp.myorg.edu \
  -u rt_user \
  -p 'rt-db-password' \
  -R 'mariadb-root-password' \
  -U service-user
```

## `restore-database.sh`

Load a SQL backup into MariaDB. Run on the host as the quadlet user (`service-user`). The dump is imported from inside the **rt5** container using `mariadb` against the **mariadb** container on `rt5-net`.

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--help` | `-h` | — | Print usage and exit |
| `--file` | `-f` | — | Backup path (`.tgz`, `.tar.gz`, `.sql.gz`, or `.sql`) |
| `--database` | `-d` | `rt5` | Target database name |

Credentials default from `/store/config/RT_SiteConfig.pm`, or set `MARIADB_USER` and `MARIADB_PASSWORD`.

Example:

```bash
/store/rt5-podman/scripts/restore-database.sh \
  -f /store/backups/rt-1725123456.sql.gz \
  -d rt5
```

Tar archive example (`.tgz` containing a `.sql` or `.sql.gz` file):

```bash
/store/rt5-podman/scripts/restore-database.sh \
  --file /store/backups/rt-dump.tgz \
  --database rt5
```

After restoring an older database, run `upgrade-database.sh` so the schema matches the RT version in the container image.

## `upgrade-database.sh`

Upgrade RT database schema and data to the version installed in the **rt5** container (`/opt/rt5/sbin/rt-setup-database --action upgrade`). Run on the host as the quadlet user.

| Option | Description |
|--------|-------------|
| `--help`, `-h` | Print usage and exit |
| `--upgrade-from VERSION` | RT version in the database (for example `5.0.10`). Omit to prompt interactively (`podman exec -it` required). |

Set `MARIADB_ROOT_PASSWORD` (DBA password) for non-interactive upgrades. The script also reads `MARIADB_ROOT_PASSWORD` from the installed `mariadb.container` quadlet when unset.

**Back up the database before upgrading.**

Example:

```bash
MARIADB_ROOT_PASSWORD=changeme_root \
  /store/rt5-podman/scripts/upgrade-database.sh --upgrade-from 5.0.10
```

Interactive upgrade (prompts for version and DBA password):

```bash
podman exec -it rt5 /opt/rt5/sbin/rt-setup-database --action upgrade \
  --prompt-for-dba-password
```
