# Request Tracker 5 on Podman Quadlets

This repository contains Containerfiles, quadlet units, and configuration templates to run Request Tracker (RT) 5 on a RHEL 9 (or compatible Fedora/RHEL-family) host using rootless Podman and systemd quadlets.

Three containers share a custom Podman network (`rt5-net`) with embedded DNS enabled. Host Postfix receives Internet mail and relays RT addresses to the exim container. Host Apache terminates HTTPS and proxies to the rt5 container. RT outbound mail flows through exim to your site relay.

**Do not use the built-in `podman` network for these services.** That default network has `dns_enabled=false`, so containers get the host OS nameservers in `/etc/resolv.conf` and cannot resolve container names such as `mariadb`.

## Architecture

```
                         Internet / LAN
                               |
                    SMTP :25 ($myhostname)
                               |
                    +----------+----------+
                    |  Host Postfix       |
                    |  (RHEL 9 system)    |
                    |                     |
                    |  transport map:     |
                    |   rt@rt.example.com |
                    |   rt-comment@...    |
                    |        |            |
                    |        v            |
                    |  relay to           |
                    |  127.0.0.1:2525     |
                    +--------+------------+
                             |
    Host published ports     |     podman network "rt5-net" (DNS on)
    =================        |     ========================
                             |
    127.0.0.1:2525 <-------->|-------->  [ exim ] :25
                             |           rt-mailgate
                             |           image: colonwq/rt-mailgate:510-4
                             |                |
                             |                | HTTP rt-mailgate
                             |                v
    https://rt.example.com <--- host Apache (HTTPS reverse proxy)
    localhost:8080 <-------->|-------->  [ rt5 ] :8080  (Apache + RT)
                             |           image: colonwq/rt5:510-5
                             |                |
                             |                | MySQL :3306
                             |                v
    localhost:3306 <-------->|-------->  [ mariadb ] :3306
                             |           image: mariadb:lts-ubi
                             |
                             +---------------------------+

Outbound mail (RT notifications):
  rt5 --msmtp--> exim:25 (podman net) --SMTP--> smtp.example.com
```

### Container roles

| Container | Image | Host port | Podman network name | Role |
|-----------|-------|-----------|---------------------|------|
| `mariadb` | `docker.io/mariadb:lts-ubi` | `3306` | `mariadb:3306` | RT database |
| `rt5` | `docker.io/colonwq/rt5:510-5` | `8080` | `rt5:8080` | RT web UI (Apache httpd) |
| `exim` | `docker.io/colonwq/rt-mailgate:510-4` | `127.0.0.1:2525` → container `:25` | `exim:25` | Mail ingress + `rt-mailgate` + outbound relay |

Host Postfix listens on port 25 (system default `inet_interfaces`). The exim quadlet publishes `127.0.0.1:2525` on the host so rootless Podman can bind without privileged ports. Postfix forwards RT addresses to that loopback port via `transport`. See [host_config/postfix/README.md](host_config/postfix/README.md).

Public users reach RT at `https://rt.example.com` through host Apache, which proxies to `http://127.0.0.1:8080`. See [host_config/apache/README.md](host_config/apache/README.md).

## Repository layout

| Path | Description |
|------|-------------|
| [config](config) | Runtime templates copied to `/store/config` on the host |
| [cron](cron) | Maintenance scripts (backups, attachment externalization) |
| [host_config](host_config) | Host Postfix and Apache snippets ([postfix](host_config/postfix/README.md), [apache](host_config/apache/README.md)) |
| [podman-rt](podman-rt) | Multi-stage Containerfile for the RT web container |
| [podman-exim](podman-exim) | Multi-stage Containerfile for exim + `rt-mailgate` |
| [quadlet](quadlet) | Quadlet `.container`, `.network`, and `.build` units |
| [scripts](scripts) | [customize.sh](scripts/customize.sh) — replace template hostnames and credentials before deploy |

## RHEL 9 setup with `service-user`

The following assumes a fresh RHEL 9, AlmaLinux 9, Rocky Linux 9, or Fedora host. All Podman quadlets run as an unprivileged account named `service-user`.

### 1. Install packages

```bash
sudo dnf install -y podman postfix httpd mod_ssl container-selinux
```

### 2. Create `service-user`

```bash
sudo useradd -m -s /bin/bash service-user
sudo loginctl enable-linger service-user
```

`enable-linger` lets user systemd services start at boot without an interactive login.

Confirm subuid/subgid entries exist (RHEL creates them by default):

```bash
grep service-user /etc/subuid /etc/subgid
```

### 3. Storage and site configuration

```bash
sudo mkdir -p /store/config /store/db /store/attachments /store/rt5-podman
sudo chown -R service-user:service-user /store
```

Clone or copy this repository to `/store/rt5-podman`:

```bash
sudo cp -a rt5-podman /store/
sudo chown -R service-user:service-user /store/rt5-podman
```

Optional: customize template values before copying (hostname, SMTP relay, database credentials, service user). Run from the repo root:

```bash
cd /store/rt5-podman
./scripts/customize.sh -r rt.myorg.edu -s smtp.myorg.edu \
  -u rt_user -p 'rt-db-pass' -R 'mariadb-root-pass' -U service-user
```

See [scripts/README.md](scripts/README.md).

Copy configuration templates to the runtime path:

```bash
sudo cp /store/rt5-podman/config/* /store/config/
sudo chown service-user:service-user /store/config/*
```

Review `/store/config/RT_SiteConfig.pm` and `/store/config/exim.conf` if you did not use `customize.sh`.

Initialize the MariaDB data directory (first run only):

```bash
sudo chown -R service-user:service-user /store/db
```

### 4. Install quadlet units

Quadlet files define the Podman network, MariaDB, RT, and exim containers as user systemd services.

Install units for `service-user`:

```bash
sudo -u service-user mkdir -p /home/service-user/.config/containers/systemd
sudo cp /store/rt5-podman/quadlet/*.container /store/rt5-podman/quadlet/*.network \
  /home/service-user/.config/containers/systemd/
sudo chown service-user:service-user /home/service-user/.config/containers/systemd/*
```

Optional: set MariaDB credentials in `mariadb.container` before copying, or add a systemd drop-in. Example values matching `config/RT_SiteConfig.pm`:

```ini
Environment=MARIADB_ROOT_PASSWORD=changeme_root
Environment=MARIADB_DATABASE=rt5
Environment=MARIADB_USER=rt_user
Environment=MARIADB_PASSWORD=rt_pass
```

Reload user systemd and start services (network first, then database, RT, and exim):

```bash
sudo -u service-user XDG_RUNTIME_DIR=/run/user/$(id -u service-user) \
  systemctl --user daemon-reload

sudo -u service-user XDG_RUNTIME_DIR=/run/user/$(id -u service-user) \
  systemctl --user enable --now rt5-network.service mariadb.service rt5.service exim.service
```

Check status:

```bash
sudo -u service-user XDG_RUNTIME_DIR=/run/user/$(id -u service-user) \
  systemctl --user status rt5-network mariadb rt5 exim
```

After MariaDB is running, initialize RT (once):

```bash
sudo -u service-user podman exec rt5 /opt/rt5/sbin/rt-setup-database \
  --action init --skip-create
```

Containers must attach to `rt5-net` (from `rt5.network`), not the built-in `podman` network, so embedded DNS resolves `mariadb` and `exim`.

#### Health probes and restart on failure

`mariadb`, `rt5`, and `exim` quadlets define Podman liveness probes and restart when a probe failure kills the container:

| Container | Probe | Start grace period |
|-----------|-------|-------------------|
| `mariadb` | `mariadb-admin ping -h localhost --silent` | 60s |
| `rt5` | `curl -sf` to `http://127.0.0.1:8080/` | 90s |
| `exim` | `exim -bP primary_hostname` | 30s |

Shared timing: `HealthInterval=60s`, `HealthTimeout` 5–10s, `HealthRetries=3`. Failures during the start grace period do not count toward unhealthy.

When **three consecutive** checks fail after the grace period, Podman marks the container **unhealthy**. With `HealthOnFailure=kill`, Podman stops the container; the generated systemd unit has `Restart=on-failure`, so **systemd starts a new container**.

Check probe status:

```bash
podman inspect mariadb --format '{{.State.Health.Status}}'
podman inspect rt5 --format '{{.State.Health.Status}}'
podman inspect exim --format '{{.State.Health.Status}}'
podman healthcheck run rt5
```

After changing quadlet files, copy them to `~/.config/containers/systemd/`, run `systemctl --user daemon-reload`, and restart the affected services.

### 5. Configure host Postfix

Host Postfix accepts mail for RT addresses and relays to exim on `127.0.0.1:2525`.

Follow **[host_config/postfix/README.md](host_config/postfix/README.md)** for:

- Copying `virtual` and `transport` maps to `/etc/postfix/`
- Required `main.cf` settings (`virtual_alias_maps`, `transport_maps`)
- Matching exim `aliases` in `/store/config/aliases`
- Verification and troubleshooting

### 6. Configure host Apache httpd

Host Apache terminates HTTPS and reverse-proxies to the rt5 quadlet on `127.0.0.1:8080`.

Follow **[host_config/apache/README.md](host_config/apache/README.md)** for:

- Installing `rt5-proxy.conf` under `/etc/httpd/conf.d/`
- TLS certificate paths and SELinux (`httpd_can_network_connect`)
- RT `SiteConfig` web settings (included in the default `config/RT_SiteConfig.pm`)
- Login-loop troubleshooting behind a reverse proxy

### 7. Verify

| Check | Command |
|-------|---------|
| RT web UI (direct) | `curl -sI http://localhost:8080/` |
| RT web UI (proxy) | `curl -skI https://rt.example.com/` |
| Exim on loopback | `nc -zv 127.0.0.1 2525` |
| Container network | `sudo -u service-user podman exec exim nc -zv rt5 8080` |
| Database DNS | `sudo -u service-user podman exec rt5 getent hosts mariadb` then `podman exec rt5 nc -zv mariadb 3306` |

### DNS / `Unknown MySQL server host 'mariadb'`

Inside `rt5`, check `/etc/resolv.conf`. With `rt5-net`, the nameserver should be the network gateway (for example `10.89.0.1`), not your site or ISP DNS.

```bash
podman network inspect rt5-net --format '{{.DNSEnabled}}'   # expect true
podman exec rt5 cat /etc/resolv.conf
podman exec rt5 getent hosts mariadb
```

If `resolv.conf` still shows host DNS, the container is on the wrong network. Reinstall the quadlet units from this repo, reload systemd, stop the services, and start them again so they attach to `rt5-net`.

## Building images locally

Images are published as `docker.io/colonwq/rt5:510-5` and `docker.io/colonwq/rt-mailgate:510-4`. To build locally:

```bash
podman build -f /store/rt5-podman/podman-rt/Containerfile \
  -t docker.io/colonwq/rt5:510-5 /store/rt5-podman/podman-rt

podman build -f /store/rt5-podman/podman-exim/Containerfile \
  -t docker.io/colonwq/rt-mailgate:510-4 /store/rt5-podman/podman-exim
```

Or install the `.build` quadlet units and run `systemctl --user start rt5-build.service` (unit name depends on the installed file name).

## Maintenance

See [cron/Readme.md](cron/Readme.md) for backup and attachment maintenance scripts. Schedule them in `service-user`'s crontab or a system cron job that runs as `service-user` when Podman access is required.

Database restore and RT schema upgrades: [scripts/README.md](scripts/README.md) (`restore-database.sh`, `upgrade-database.sh`).
