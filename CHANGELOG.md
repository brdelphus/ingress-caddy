# Changelog

## [0.7.0] - 2026-03-31

### Breaking Changes

- **`caddy.ingress/plain-http` annotation removed** — Ingresses without `spec.tls` are now plain HTTP automatically. No annotation needed; remove it from existing Ingresses.
- **`k8sIngress.enabled` removed** — the chart is the ingress controller; the flag no longer exists. Remove it from your `values.yaml`.
- **Global `:80 → https` redirect removed** from the Caddyfile template — it conflicted with HTTP-only Ingresses. Add an explicit `ssl-redirect` annotation per Ingress if needed.

### TLS Model Overhaul

The TLS model has been completely redesigned around `spec.tls` as the authoritative signal:

- **`spec.tls` is required for HTTPS.** Ingresses without it are served over plain HTTP. There is no automatic TLS.
- New **`caddy.ingress/tls`** annotation declares which handler manages the certificate:
  - `certmagic` — CertMagic issues the cert via ACME proactively (within seconds of Ingress creation, no `secretName` needed)
  - `cert-manager` — cert-manager creates the Secret in `spec.tls.secretName`; caddy-k8s loads and watches it
- TLS Secrets must exist in the **same namespace as the Ingress**.

### New Features

- **Per-Ingress on-demand TLS** (`caddy.ingress/tls-ondemand: "true"`) — issue the cert on the first TLS connection instead of proactively. Requires `caddy.ingress/tls: certmagic`. Global `ask` URL and rate limits (configured in Helm values) still apply.
- **Per-Ingress custom CA** (`caddy.ingress/tls-ca: "<url>"`) — use a different ACME CA for a specific Ingress (e.g. ZeroSSL, Google Trust Services) while others use the global default.
- **Per-Ingress EAB credentials** (`caddy.ingress/tls-ca-secret: "<name>"`) — reference a K8s Secret (same namespace) containing `key_id` and `mac_key` for CAs that require External Account Binding.

### Improvements

- WAF setup clarified: `plugins.coraza.enabled: true` loads the Coraza module and configures the OWASP ruleset; `k8sIngress.security.waf: true` injects the handler into every Ingress route. Both are required. Per-route override via `caddy.ingress/waf: "off"|"on"|"detection"`.
- New example files: `cert-manager.yaml`, `certmagic.yaml`, `ondemand-tls.yaml`, `zerossl.yaml` — each explains both global and per-Ingress usage.
- All app examples (`nextcloud`, `mailu`, `gitea`, `grafana`, `jellyfin`, `vaultwarden`, `authelia`, `azuracast`) updated with `cert-manager.io/cluster-issuer` annotation and `spec.tls.secretName`.

---

## [0.6.0] - 2026-02-xx

### New Features

- Built-in config reloader (`k8s_config_reloader`) — watches the Caddyfile ConfigMap and calls `POST /load` on change; no pod restart needed.
- Optional Redis store for persistent Ingress → route ID tracking across Caddy restarts.
- `spec.tls` support — caddy-k8s loads `kubernetes.io/tls` Secrets and watches them for renewals.
- `caddy.ingress/plain-http` annotation for HTTP-only Ingresses (superseded in 0.7.0).
- CertMagic ACME with on-demand TLS, EAB, and DNS-01 challenge support added to Helm values.
- `caddy-security` plugin for authentication and SSO.
- `caddyfile.extraGlobalOptions` escape hatch for custom global Caddyfile directives.
- `caddy-kubernetes-storage` and `caddy-storage-redis` for CertMagic cert persistence.
