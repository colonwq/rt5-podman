# Adding an email alias for an RT queue

This guide walks through routing mail sent to **rt-security@rt.example.com** into the RT queue named **Security**. The same steps apply to any additional address and queue.

Mail path:

```
Internet → host Postfix (:25) → exim container (127.0.0.1:2525) → rt-mailgate → RT queue
```

Three places must agree on the address:

| Layer | File | What you set |
|-------|------|----------------|
| Host Postfix | `/etc/postfix/virtual` | Accept the recipient at RCPT time |
| Host Postfix | `/etc/postfix/transport` | Relay to exim on loopback |
| Exim container | `/store/config/aliases` | Pipe to `rt-mailgate` with `--queue` |

The **local part** before `@` must match in Postfix maps and exim `aliases` (for example `rt-security`).

## Prerequisites

### 1. Create the RT queue

In the RT web UI (**Admin → Queues**), create a queue named **Security** (name must match the `--queue` value passed to `rt-mailgate` exactly).

Confirm the queue exists and that users who should work security tickets have rights to it.

### 2. Choose the address

This example uses:

- **Email address:** `rt-security@rt.example.com`
- **Local part:** `rt-security`
- **RT queue:** `Security`

Replace `rt.example.com` with your site domain if you customized templates with [scripts/customize.sh](../scripts/customize.sh).

## Step 1 — Host Postfix `virtual` map

Edit `/etc/postfix/virtual` (or add to the repo copy under `host_config/postfix/virtual` before copying):

```text
rt-security@rt.example.com rt-security@rt.example.com
```

Without this entry, Postfix rejects the recipient with `550 User unknown in local recipient table` before delivery.

## Step 2 — Host Postfix `transport` map

Edit `/etc/postfix/transport`:

```text
rt-security@rt.example.com smtp:[127.0.0.1]:2525
```

This forwards the message to the exim quadlet (host port **2525** → container port **25**).

## Step 3 — Exim `aliases`

Edit `/store/config/aliases` on the host (mounted into the exim container as `/etc/aliases`):

```text
rt-security: |/opt/rt5/bin/rt-mailgate-wrap.sh --no-verify-ssl --queue Security --action correspond --url http://rt5:8080/
```

| Flag | Purpose |
|------|---------|
| `--queue Security` | Create or update tickets in the **Security** queue |
| `--action correspond` | Treat inbound mail as a new ticket or reply (same as the main `rt` alias) |
| `--url http://rt5:8080/` | RT base URL on the podman network (not the public HTTPS URL) |

For a **comment-only** address (like `rt-comment`), use `--action comment` instead.

Exim matches the local part `rt-security` when mail arrives for `rt-security@rt.example.com`. The domain `rt.example.com` is already listed in `config/exim.conf` (`local_domains`); no exim.conf change is required for a new local part on an existing domain.

## Step 4 — Apply changes

Rebuild Postfix LMDB maps and reload:

```bash
sudo postmap /etc/postfix/virtual
sudo postmap /etc/postfix/transport
sudo postfix check
sudo systemctl reload postfix
```

Restart exim so it reloads `/etc/aliases`:

```bash
sudo -u service-user XDG_RUNTIME_DIR=/run/user/$(id -u service-user) \
  systemctl --user restart exim.service
```

## Step 5 — Verify

Check Postfix maps:

```bash
sudo postmap -q rt-security@rt.example.com lmdb:/etc/postfix/virtual
sudo postmap -q rt-security@rt.example.com lmdb:/etc/postfix/transport
```

Confirm exim is listening:

```bash
nc -zv 127.0.0.1 2525
```

Send a test message:

```bash
echo "Security queue test" | mail -s "RT security alias test" rt-security@rt.example.com
```

Watch logs:

```bash
sudo tail -f /var/log/maillog
sudo -u service-user podman logs -f exim
```

In RT, confirm a new ticket appears in the **Security** queue.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `550 User unknown in local recipient table` | `virtual` map entry and `postmap` / reload |
| Postfix accepts mail but nothing in RT | `transport` map, exim running, `aliases` local part spelling |
| Exim delivers but RT rejects | Queue name in RT Admin matches `--queue Security`; RT URL reachable from exim (`podman exec exim curl -sI http://rt5:8080/`) |
| Ticket in wrong queue | `--queue` value in `aliases` |

## Optional: comment alias for the same queue

To accept ticket comments on a separate address (mirroring `rt-comment@`):

```text
# Postfix virtual + transport
rt-security-comment@rt.example.com rt-security-comment@rt.example.com
rt-security-comment@rt.example.com smtp:[127.0.0.1]:2525

# /store/config/aliases
rt-security-comment: |/opt/rt5/bin/rt-mailgate-wrap.sh --no-verify-ssl --queue Security --action comment --url http://rt5:8080/
```

## Related documentation

- [host_config/postfix/README.md](../host_config/postfix/README.md) — Postfix install and map overview
- [config/aliases](../config/aliases) — default `rt` and `rt-comment` aliases
- [README.md](../README.md) — mail architecture diagram
