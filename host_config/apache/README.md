# Host Apache reverse proxy for RT

Terminate HTTPS on the RHEL host and proxy to the rootless **rt5** quadlet on `127.0.0.1:8080`.

## Files

| File | Purpose |
|------|---------|
| `rt5-proxy.conf` | `https://rt.example.com:443` → `http://127.0.0.1:8080` |

## Install

```bash
sudo cp rt5-proxy.conf /etc/httpd/conf.d/
# Edit SSLCertificateFile / SSLCertificateKeyFile paths if needed
sudo dnf install -y httpd mod_ssl
sudo setsebool -P httpd_can_network_connect on
sudo apachectl configtest
sudo systemctl enable --now httpd
sudo systemctl reload httpd
```

## RT SiteConfig (required for proxy)

Login succeeds in the RT log but the browser returns to the login form (or redirects to `:8080`) when `RT_SiteConfig.pm` still describes the **backend** URL (`http`, port `8080`, wrong hostname) instead of the public HTTPS URL.

The repo template `config/RT_SiteConfig.pm` already includes reverse-proxy web settings. Copy it with the other config files and edit site-specific values (database, mail, domain):

```bash
sudo cp /store/rt5-podman/config/RT_SiteConfig.pm /store/config/
sudo chown service-user:service-user /store/config/RT_SiteConfig.pm
```

Minimum web settings for `https://rt.example.com` (included in the default template):

```perl
Set( $WebDomain, 'rt.example.com' );
Set( $WebPort, '443' );
Set( $WebPath, '' );
Set( $WebSecureCookies, 1 );
Set( $CanonicalizeRedirectURLs, 1 );
Set( $CanonicalizeURLsInFeeds, 1 );
```

`CanonicalizeRedirectURLs` is the usual fix for reverse-proxy login loops: RT uses `$WebURL` for redirects instead of guessing from the proxied `http://127.0.0.1:8080` environment.

Also ensure the mounted container Apache config includes `SetEnvIf` for forwarded HTTPS (see `config/rt5.conf` in this repo). Reload after changes:

```bash
sudo -u service-user XDG_RUNTIME_DIR=/run/user/$(id -u service-user) \
  systemctl --user restart rt5.service
```

Clear browser cookies for the site after changing `WebDomain` or cookie settings.

### Login loop checklist

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| Redirect to `http://…:8080` after login | RT using backend URL from `%ENV` | `CanonicalizeRedirectURLs = 1`, correct `WebDomain` / `WebPort` |
| Back at login; log shows successful auth | Session cookie not sent (wrong domain or `Secure` mismatch) | `WebDomain` = public hostname; `WebSecureCookies = 1` for HTTPS |
| Works on `http://localhost:8080` only | SiteConfig still set for direct access | Use proxy web settings (`WebPort` `443`, `CanonicalizeRedirectURLs`) |

## SELinux

With SELinux enforcing, **httpd cannot open outbound TCP connections by default**. A reverse proxy to `127.0.0.1:8080` needs an explicit policy change.

Typical AVC (from `/var/log/audit/audit.log`):

```text
type=AVC ... avc: denied { name_connect } for comm="httpd" dest=8080
  scontext=system_u:system_r:httpd_t:s0
  tcontext=system_u:object_r:port_t:s0 tclass=tcp_socket
```

Apache error log may show `(13)Permission denied` on `proxy: HTTP: attempt to connect to 127.0.0.1:8080`.

### Required boolean (reverse proxy)

Allow httpd to connect to network backends (including `127.0.0.1:8080`):

```bash
sudo setsebool -P httpd_can_network_connect on
sudo getsebool httpd_can_network_connect
# httpd_can_network_connect --> on
```

`-P` makes the change persistent across reboots.

This is the standard fix for Apache `ProxyPass` / `mod_proxy` on RHEL. You do **not** need `httpd_can_network_relay` for a simple reverse proxy to a single HTTP backend.

### Optional: allow only port 8080 (narrower)

If you prefer not to enable broad outbound connects, label TCP **8080** as an HTTP port httpd may use:

```bash
sudo dnf install -y policycoreutils-python-utils
sudo semanage port -a -t http_port_t -p tcp 8080
# If the port is already defined, modify instead:
# sudo semanage port -m -t http_port_t -p tcp 8080
```

Verify:

```bash
semanage port -l | grep http_port_t
```

Use this **instead of** or **in addition to** `httpd_can_network_connect` depending on site policy. On many RHEL systems, `httpd_can_network_connect on` alone is sufficient and is the usual choice for reverse proxies.

### Not needed for this setup

| Boolean | Why |
|---------|-----|
| `httpd_can_network_relay` | Proxy relay between multiple backends; not required for RT → `127.0.0.1:8080` |
| `httpd_can_network_connect_db` | Database ports only |
| `httpd_graceful_shutdown` | Shutdown behavior, not proxy connectivity |

### Diagnose denials

```bash
sudo ausearch -m AVC -ts recent | grep httpd
sudo ausearch -m AVC -ts recent | audit2why
```

After fixing policy, reload httpd and retest:

```bash
curl -sI https://rt.example.com/
```

## Verify proxy path

```bash
curl -sI http://127.0.0.1:8080/          # rt5 quadlet directly
curl -skI https://rt.example.com/   # through Apache
```

After login, the browser location bar should stay on `https://rt.example.com/` with no `:8080` in the URL.
