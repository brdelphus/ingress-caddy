# caddy-custom

A production-ready [Caddy](https://caddyserver.com) image for Kubernetes, built to fully replace Traefik or nginx-ingress. Runs as a DaemonSet with hostPorts, handles TLS via cert-manager CSI, and ships with a Helm chart that makes every feature toggleable.

Includes a built-in Kubernetes Ingress controller — apps set `ingressClassName: caddy-custom` and routes appear in Caddy automatically, no manual config editing required.

**Image:** `ghcr.io/brdelphus/caddy-custom`

---

## What's inside

| Plugin | Author | Purpose |
|---|---|---|
| [coraza-caddy](https://github.com/corazawaf/coraza-caddy) | [Coraza](https://github.com/corazawaf) / [jcchavezs](https://github.com/jcchavezs) | OWASP Core Rule Set WAF |
| [caddy-l4](https://github.com/mholt/caddy-l4) | [Matt Holt](https://github.com/mholt) | Layer 4 TCP/UDP routing |
| [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) | [Matt Holt](https://github.com/mholt) | Sliding-window rate limiting |
| [cache-handler](https://github.com/caddyserver/cache-handler) | [Caddy](https://github.com/caddyserver) / [Sylvain Combraque](https://github.com/darkweak) | RFC 7234 HTTP response cache (Souin) |
| [caddy-maxmind-geolocation](https://github.com/porech/caddy-maxmind-geolocation) | [Massimiliano Porrini](https://github.com/porech) | GeoIP country-level blocking |
| [caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer) | [Herman Slatman](https://github.com/hslatman) | CrowdSec IP reputation + AppSec |
| [caddy-defender](https://github.com/jasonlovesdoggo/caddy-defender) | [Jason Cameron](https://github.com/jasonlovesdoggo) | AI scraper / cloud datacenter IP blocker |
| [caddy-k8s](https://github.com/brdelphus/caddy-k8s) | [brdelphus](https://github.com/brdelphus) | Kubernetes Ingress controller |

All plugins are compiled into a single binary via [xcaddy](https://github.com/caddyserver/xcaddy). Multi-arch image: `linux/amd64` + `linux/arm64`, built natively (no QEMU).

---

## Architecture

```
                  ┌─────────────────────────────────┐
                  │         k3s cluster             │
                  │                                 │
Internet ──80/443─▶  Caddy DaemonSet (hostPort)     │
          ──L4────▶  (all nodes, including          │
                  │   control-plane)                │
                  │         │                       │
                  │    ┌────▼─────────────────┐     │
                  │    │  Coraza WAF (OWASP)  │     │
                  │    │  Security headers    │     │
                  │    │  Rate limiting       │     │
                  │    │  GeoIP / CrowdSec    │     │
                  │    └────────────┬─────────┘     │
                  │                 │               │
                  │    ┌────────────▼─────────┐     │
                  │    │  Routes from         │     │
                  │    │  Ingress resources   │     │
                  │    │  (caddy-k8s module)  │     │
                  │    └────────────┬─────────┘     │
                  │                 │               │
                  │         backend services        │
                  └─────────────────────────────────┘
```

TLS is handled by [cert-manager CSI driver](https://cert-manager.io/docs/usage/csi-driver/) — certs are mounted as real files and Caddy's fsnotify detects rotation natively. No sidecar, no restart needed.

---

## Quick start

### 1. Prerequisites

```bash
# cert-manager + CSI driver
helm install cert-manager jetstack/cert-manager -n cert-manager --set crds.enabled=true
helm install cert-manager-csi-driver jetstack/cert-manager-csi-driver -n cert-manager

# Stakater Reloader (triggers rolling restart on ConfigMap changes)
helm install reloader stakater/reloader -n kube-system
```

### 2. Install

```bash
helm install caddy ./helm \
  --namespace caddy \
  --create-namespace \
  --values helm/values.yaml \
  --values helm/values.local.yaml   # your overrides (gitignored)
```

### 3. Minimal `values.local.yaml`

```yaml
tls:
  certManagerCSI:
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer
    dnsNames:
      - "*.example.com"
      - "example.com"

realIP:
  trustedProxies:
    - 10.42.0.0/16   # k3s pod CIDR
    - 127.0.0.1/32
```

### 4. Point your apps at Caddy

In any Helm chart that creates an `Ingress` resource:

```yaml
ingress:
  enabled: true
  className: caddy-custom
  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix
```

Routes appear in Caddy within seconds — no restart, no manual Caddyfile editing.

---

## Helm values reference

### Kubernetes Ingress controller

```yaml
k8sIngress:
  enabled: true
  ingressClass: caddy-custom   # matches spec.ingressClassName
  isDefaultClass: false        # set true to make this the cluster default
  security:
    waf: false                 # Coraza WAF per route (on | off)
    wafMode: Detection         # Detection (log only) | On (block)
    securityHeaders: true      # HSTS, X-Content-Type-Options, X-Frame-Options, etc.
    injectRealIP: true         # X-Real-IP + X-Forwarded-* to upstream
```

Per-Ingress behaviour is controlled via `caddy.ingress/` annotations on individual Ingress resources:

| Annotation | Description |
|---|---|
| `caddy.ingress/backend-protocol: HTTPS` | Enable TLS on the upstream transport (for HTTPS backends like Mailu) |
| `caddy.ingress/backend-tls-insecure-skip-verify: "true"` | Skip upstream TLS verification (use with self-signed backend certs) |
| `caddy.ingress/permanent-redirect: "https://..."` | 301-redirect all paths in this Ingress to a fixed URL (e.g. `.well-known` → `/remote.php/dav`) |
| `caddy.ingress/proxy-http-version: "1.1"` | Force HTTP/1.1 to upstream — required for streaming and WebSocket backends |
| `caddy.ingress/proxy-read-timeout` / `proxy-send-timeout` / `proxy-connect-timeout` | Per-route proxy timeouts (seconds) |
| `caddy.ingress/proxy-body-size` | Max request body size (`0` = unlimited, supports `k`/`m`/`g`) |
| `caddy.ingress/ssl-redirect: "true"` | Redirect HTTP → HTTPS with 301 |
| `caddy.ingress/whitelist-source-range` | Comma-separated CIDRs to allow; all others get 403 |
| `caddy.ingress/blocklist-source-range` | Comma-separated CIDRs to deny; all others pass |
| `caddy.ingress/basic-auth-secret` | Secret name (same namespace) with `auth` htpasswd key |

Full annotation reference and examples: [caddy-k8s](https://github.com/brdelphus/caddy-k8s#annotations)

### WAF (Coraza / OWASP CRS)

```yaml
plugins:
  coraza:
    enabled: true
    ruleEngine: DetectionOnly   # DetectionOnly | On | Off
    customRules: []
    # - "SecRule REQUEST_URI \"@contains /wp-admin\" \"id:9001,phase:1,deny,status:403\""
```

### CrowdSec

```yaml
plugins:
  crowdsec:
    enabled: true
    lapiUrl: http://crowdsec-lapi.crowdsec.svc.cluster.local:8080
    existingSecret: crowdsec-bouncer-secret   # key: api-key
    tickerInterval: 15s
    appSec:
      enabled: false
      host: crowdsec-lapi.crowdsec.svc.cluster.local
      port: 7422
```

### Rate limiting

```yaml
plugins:
  rateLimit:
    enabled: true
    window: 1m
    maxEvents: 100
    key: "{client_ip}"
```

### HTTP cache

```yaml
plugins:
  cache:
    enabled: true
    ttl: 1h
    backend: memory   # memory | redis
    redis:
      address: redis.redis.svc.cluster.local:6379
```

### GeoIP blocking

```yaml
plugins:
  geoip:
    enabled: true
    dbPath: /data/geoip/GeoLite2-Country.mmdb
    deniedCountries: ["CN", "RU", "KP", "IR"]
    updater:
      enabled: true
      existingSecret: maxmind-secret   # keys: account-id, license-key
```

### AI scraper / cloud IP blocking

```yaml
plugins:
  defender:
    enabled: true
    action: block   # block | tarpit | garbage
```

### Layer 4 TCP/UDP routing

For protocols that can't go through HTTP (SMTP, IMAP, DNS, game servers, etc.):

```yaml
l4:
  enabled: true
  hostPorts:
    - port: 25
      protocol: TCP
    - port: 465
      protocol: TCP
    - port: 993
      protocol: TCP
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
  routes:
    - address: ":25"
      upstream: "tcp/mailu-front.mail.svc.cluster.local:25"
      proxyProtocol: v2   # sends PROXY protocol v2 — backend recovers real client IP
    - address: ":465"
      upstream: "tcp/mailu-front.mail.svc.cluster.local:465"
      proxyProtocol: v2
    - address: ":993"
      upstream: "tcp/mailu-front.mail.svc.cluster.local:993"
      proxyProtocol: v2
    - address: ":53"
      upstream: "udp/kube-dns.kube-system.svc.cluster.local:53"
    - address: ":53"
      upstream: "tcp/kube-dns.kube-system.svc.cluster.local:53"
```

### TLS

```yaml
tls:
  certManagerCSI:
    enabled: true
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer
    dnsNames:
      - "*.example.com"
      - "example.com"
  # Alternative: use an existing TLS secret
  existingSecret: ""
  mountPath: /certs
```

### Forward auth (Authelia / authentik)

```yaml
forwardAuth:
  enabled: true
  url: http://authelia.authelia.svc.cluster.local:9091
  uri: /api/authz/forward-auth
  copyHeaders:
    - Remote-User
    - Remote-Groups
    - Remote-Email
    - Remote-Name
```

### Observability

```yaml
metrics:
  enabled: true
  port: 2019
  serviceMonitor:
    enabled: true        # Prometheus Operator
    namespace: monitoring
    interval: 30s

tracing:
  enabled: true
  endpoint: otel-collector.monitoring.svc.cluster.local:4317
```

---

## CI / Image build

Images are built on GitHub Actions using native runners (no QEMU):

| Platform | Runner |
|---|---|
| `linux/amd64` | `ubuntu-latest` |
| `linux/arm64` | `ubuntu-24.04-arm` |

Both jobs build simultaneously, then a merge job creates the multi-arch manifest.

Tags pushed on every merge to `main`:
- `latest`
- `2.11.2` (Caddy version from Dockerfile)
- `sha-<short>` (commit SHA)

---

## Acknowledgements

Built on top of:

- [Caddy](https://github.com/caddyserver/caddy) by [Matt Holt](https://github.com/mholt) and contributors
- [xcaddy](https://github.com/caddyserver/xcaddy) by the Caddy team
- All plugin authors listed in the [What's inside](#whats-inside) table above

---

## License

MIT
