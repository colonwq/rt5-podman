# Host Postfix for RT mail ingress

Host Postfix receives Internet mail on port 25 and relays RT ticket addresses to the **exim** quadlet on `127.0.0.1:2525`. The exim container runs `rt-mailgate` and forwards parsed messages into RT.

```
Internet / LAN
      |
 SMTP :25 (host Postfix, $myhostname)
      |
 virtual map  — accept RT addresses at RCPT
      |
 transport map — relay to smtp:[127.0.0.1]:2525
      |
 exim container :25 (published as host 127.0.0.1:2525)
      |
 rt-mailgate → RT
```

Rootless Podman cannot bind host port 25, so exim is published on loopback **2525** while Postfix keeps the normal system listener on **25**. There is no port conflict.

## Files

| File | Install path | Purpose |
|------|--------------|---------|
| `virtual` | `/etc/postfix/virtual` | Mark RT addresses as valid recipients (checked at RCPT time) |
| `transport` | `/etc/postfix/transport` | Relay those addresses to `smtp:[127.0.0.1]:2525` |

Postfix uses the system default `inet_interfaces` (no `main.cf` snippet in this repo).

## Install

Copy the maps from this repository:

```bash
sudo cp /store/rt5-podman/host_config/postfix/virtual /etc/postfix/virtual
sudo cp /store/rt5-podman/host_config/postfix/transport /etc/postfix/transport
```

Edit addresses to match your RT hostname (defaults use `rt@rt.example.com` and `rt-comment@rt.example.com`). Use [scripts/customize.sh](../../scripts/customize.sh) before copying if you customized the repo templates.

Ensure `/etc/postfix/main.cf` references both maps:

```conf
virtual_alias_maps = hash:/etc/postfix/virtual
transport_maps = hash:/etc/postfix/transport
```

Build the hash databases and reload:

```bash
sudo postmap /etc/postfix/virtual
sudo postmap /etc/postfix/transport
sudo postfix check
sudo systemctl reload postfix
```

Set `myhostname` in `main.cf` to the real server hostname (not `localhost`) so inbound mail routing and logs are correct.

## Why both `virtual` and `transport`?

| Map | When Postfix uses it | Without it |
|-----|----------------------|------------|
| `virtual` | RCPT — is this recipient allowed? | `550 User unknown in local recipient table` |
| `transport` | Delivery — how to deliver accepted mail | Default local delivery (wrong for RT) |

`transport_maps` only applies **after** Postfix accepts the recipient. You need `virtual` (or another recipient validation mechanism) first.

## Exim aliases (container)

For each RT address in Postfix, add a matching **local part** in `/store/config/aliases` (mounted into the exim container). The domain in Postfix maps is the full address; exim aliases use the part before `@`:

```text
rt:           "|/usr/local/bin/rt-mailgate-wrap.sh --queue ..."
rt-comment:   "|/usr/local/bin/rt-mailgate-wrap.sh --queue ..."
```

See `config/aliases` in the repository. After editing aliases on the host, restart exim:

```bash
sudo -u service-user XDG_RUNTIME_DIR=/run/user/$(id -u service-user) \
  systemctl --user restart exim.service
```

Keep Postfix `virtual`/`transport`, exim `aliases`, and `config/RT_SiteConfig.pm` mail addresses in sync.

## Verify

Exim must be running and listening on loopback 2525:

```bash
nc -zv 127.0.0.1 2525
```

Send a test message (adjust address and hostname):

```bash
echo "test body" | mail -s "RT test" rt@rt.example.com
sudo tail -f /var/log/maillog
```

Check exim logs via the container:

```bash
sudo -u service-user podman logs exim
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| `550 User unknown in local recipient table` | Missing or stale `virtual` map | Install `virtual`, run `postmap`, reload Postfix |
| Mail accepted but never reaches RT | Wrong `transport` or exim not on 2525 | Check `transport`, `nc -zv 127.0.0.1 2525`, exim service status |
| RT address works in Postfix but exim rejects | Mismatched `aliases` local part | Align `config/aliases` with Postfix addresses |
| Nothing on port 25 | Postfix not running or `inet_interfaces` | `systemctl status postfix`, review `main.cf` |

Diagnose Postfix:

```bash
sudo postfix check
sudo postmap -q rt@rt.example.com hash:/etc/postfix/virtual
sudo postmap -q rt@rt.example.com hash:/etc/postfix/transport
```
