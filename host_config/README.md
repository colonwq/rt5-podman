# Host configuration

Configuration for services on the RHEL host that work with the RT quadlet stack (not files mounted into containers).

| Directory | Guide | Role |
|-----------|-------|------|
| [apache/](apache/) | [apache/README.md](apache/README.md) | HTTPS reverse proxy to `rt5` on `127.0.0.1:8080` |
| [postfix/](postfix/) | [postfix/README.md](postfix/README.md) | Inbound SMTP on port 25 → exim on `127.0.0.1:2525` |

Install quadlets and copy `config/` to `/store/config/` first (see the main [README.md](../README.md)), then configure Postfix and Apache using the guides above.
