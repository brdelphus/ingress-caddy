# caddy-custom

> **Status: working, not yet battle-tested.**
> Core functionality is operational and runs in a personal k3s cluster, but this project is still early. More real-world testing, edge case coverage, and community feedback is needed before it can be considered stable for general use. Contributions and issue reports are very welcome.

A custom [Caddy](https://caddyserver.com) image for Kubernetes, built to replace Traefik or nginx-ingress. Ships with a Helm chart that makes every feature toggleable.

TLS is opt-in per Ingress: add `spec.tls` with a `secretName` and the module loads the certificate from the Kubernetes Secret automatically. Ingresses without `spec.tls` are HTTP only.

Includes a built-in Kubernetes Ingress controller — apps set `ingressClassName: caddy-custom` and routes appear in Caddy automatically, no manual config editing required.

Supports two deployment modes:
- **DaemonSet + hostPorts** — runs on every node, binds ports directly. Ideal for bare-metal k3s.
- **Deployment + LoadBalancer** — fixed replica count behind MetalLB or a cloud LB (AWS NLB, GCE, etc.).

Created after migrating from ingress-nginx (deprecated) to Traefik, finding Traefik lacking, discovering Caddy, and realising there was no proper Kubernetes ingress support for it — so I built one.

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
| [caddy-security](https://github.com/greenpau/caddy-security) | [Paul Greenberg](https://github.com/greenpau) | Authentication (OAuth2/OIDC/SAML/LDAP) + Authorization |
| [caddy-k8s](https://github.com/brdelphus/caddy-k8s) | [brdelphus](https://github.com/brdelphus) | Kubernetes Ingress controller |
| [caddy-kubernetes-storage](https://github.com/brdelphus/caddy-kubernetes-storage) | [brdelphus](https://github.com/brdelphus) | TLS storage backend using Kubernetes Secrets |
| [caddy-storage-redis](https://github.com/pberkel/caddy-storage-redis) | [Peter Berkel](https://github.com/pberkel) | TLS storage backend using Redis |

All plugins are compiled into a single binary via [xcaddy](https://github.com/caddyserver/xcaddy). Multi-arch image: `linux/amd64` + `linux/arm64`, built natively (no QEMU).

---

## Architecture

**Bare-metal / k3s (DaemonSet + hostPorts)**

```
                  ┌─────────────────────────────────┐
                  │         k3s cluster             │
                  │                                 │
Internet ──80/443─▶  Caddy DaemonSet (hostPort)     │
          ──L4────▶  (all nodes, incl. control-     │
                  │   plane via tolerations)        │
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

**Cloud / MetalLB (Deployment + LoadBalancer)**

```
                  ┌─────────────────────────────────┐
                  │         cluster                 │
                  │                                 │
Internet ──80/443─▶  LoadBalancer (MetalLB / cloud) │
          ──L4────▶        │                        │
                  │  Caddy Deployment (N replicas)  │
                  │        │                        │
                  │  [same WAF / Ingress pipeline]  │
                  │        │                        │
                  │   backend services              │
                  └─────────────────────────────────┘
```

TLS is opt-in per Ingress via `spec.tls` — the caddy-k8s module loads certificates from Kubernetes Secrets and watches them for renewals. See the [TLS section](#tls) for details.

---

## Quick start

### 1. Prerequisites

No hard dependencies. TLS certificates are loaded per-Ingress from Kubernetes Secrets — create them manually or use cert-manager to issue and renew them automatically:

```bash
helm install cert-manager jetstack/cert-manager -n cert-manager --set crds.enabled=true
```

cert-manager stores issued certificates in Secrets. Point `spec.tls[].secretName` in your Ingress to the same Secret name and caddy-k8s will pick it up. Renewals are applied automatically without a restart.

**Config hot-reload is built in.** The `k8s_config_reloader` module (enabled by default) watches the Caddyfile ConfigMap and calls Caddy's admin API when it changes — no pod restart ever needed, not even for Helm upgrades that modify the Caddyfile.

Stakater Reloader is **not needed** and is disabled by default. If you prefer pod restarts over in-place reloads, set `configReloader.enabled: false` and `reloader.enabled: true` and install it separately:

```bash
helm install reloader stakater/reloader -n kube-system
```

### 2. Install

```bash
helm repo add caddy-custom https://brdelphus.github.io/caddy-custom
helm repo update

helm install caddy caddy-custom/caddy \
  --namespace caddy \
  --create-namespace \
  --values values.local.yaml
```

Or from source (after `helm dependency update helm/`):

```bash
helm install caddy ./helm \
  --namespace caddy \
  --create-namespace \
  --values helm/values.local.yaml
```

### 3. Minimal `values.local.yaml`

```yaml
k8sIngress:
  ingressClass: caddy-custom

realIP:
  trustedProxies:
    - 10.42.0.0/16   # k3s pod CIDR
    - 127.0.0.1/32
```

TLS is configured per Ingress via `spec.tls` — no global TLS backend needed. See the [TLS section](#tls) for details.

### 4. Point your apps at Caddy

Create an `Ingress` resource pointing at your service. Add `spec.tls` to serve HTTPS and declare which TLS handler manages the cert:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
  annotations:
    caddy.ingress/tls: cert-manager          # cert-manager provisions the Secret
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: caddy-custom
  tls:
    - hosts:
        - app.example.com
      secretName: myapp-tls                  # cert-manager creates this
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

Routes appear in Caddy within seconds — no restart, no manual Caddyfile editing.

- No `spec.tls` → plain HTTP.
- `caddy.ingress/tls: certmagic` → CertMagic issues the cert via ACME (`spec.tls` with hosts, no `secretName`).
- `caddy.ingress/tls: cert-manager` → cert-manager creates the Secret in `spec.tls.secretName`.

Per-route behaviour (redirects, auth, CORS, rate limiting, etc.) is controlled via annotations — see the [annotation reference](#kubernetes-ingress-controller).

See [`examples/`](examples/) for ready-to-use values files for common apps (Nextcloud, Mailu, Gitea, Grafana, Jellyfin, Vaultwarden, Authelia, AzuraCast).

---

## Helm values reference

### Workload type

```yaml
# Bare-metal k3s — runs on every node, binds ports directly on the host network
workloadType: DaemonSet
hostPorts:
  enabled: true
  http: 80
  https: 443

# Cloud / MetalLB — fixed replica Deployment behind a LoadBalancer Service
workloadType: Deployment
replicaCount: 2
hostPorts:
  enabled: false   # disable to avoid conflicts with the LB
service:
  enabled: true
  type: LoadBalancer
  loadBalancerIP: ""            # request a specific IP from your LB provider
  externalTrafficPolicy: Local  # preserves real client IP, recommended
  annotations: {}
  # MetalLB:    metallb.universe.tf/address-pool: production
  # AWS NLB:    service.beta.kubernetes.io/aws-load-balancer-type: nlb
  # GCE LB:     cloud.google.com/load-balancer-type: Internal
```

L4 ports declared in `l4.hostPorts` are automatically added to the LoadBalancer Service — no duplication needed.

### Kubernetes Ingress controller

```yaml
k8sIngress:
  ingressClass: caddy-custom   # matches spec.ingressClassName
  isDefaultClass: false        # set true to make this the cluster default
  security:
    waf: false                 # inject Coraza WAF handler into every Ingress route (requires plugins.coraza.enabled: true)
    wafMode: Detection         # Detection (log only) | On (block)
    securityHeaders: true      # HSTS, X-Content-Type-Options, X-Frame-Options, etc.
    injectRealIP: true         # X-Real-IP + X-Forwarded-* to upstream
```

`k8sIngress.security.waf` controls whether the WAF handler is injected into each auto-generated route. To actually enable WAF, you also need `plugins.coraza.enabled: true` which loads the Coraza module and configures the ruleset — see the [WAF section](#waf-coraza--owasp-crs).

Per-Ingress behaviour is controlled via `caddy.ingress/` annotations on individual Ingress resources:

| Annotation | Description |
|---|---|
| `caddy.ingress/tls: "certmagic"` | CertMagic issues the cert via ACME (`spec.tls` required, no `secretName`) |
| `caddy.ingress/tls: "cert-manager"` | cert-manager provisions the cert into `spec.tls.secretName`; caddy-k8s loads it |
| `caddy.ingress/tls-ondemand: "true"` | Issue cert on first TLS connection instead of proactively (certmagic only) |
| `caddy.ingress/tls-ca: "https://..."` | ACME CA URL for this Ingress, e.g. ZeroSSL (certmagic only) |
| `caddy.ingress/tls-ca-secret: "<name>"` | K8s Secret (same namespace) with EAB keys `key_id` and `mac_key` for the CA above |
| `caddy.ingress/ssl-redirect: "true"` | Redirect HTTP → HTTPS with 301 |
| `caddy.ingress/permanent-redirect: "https://..."` | 301-redirect all paths to a fixed URL |
| `caddy.ingress/temporal-redirect: "https://..."` | 302-redirect all paths to a fixed URL |
| `caddy.ingress/redirect-code: "308"` | Override status code for either redirect type |
| `caddy.ingress/rewrite-target: "/"` | Rewrite request URI before proxying |
| `caddy.ingress/server-alias` | Additional hostnames (comma-separated) |
| `caddy.ingress/backend-protocol: HTTPS` | Enable TLS on the upstream transport |
| `caddy.ingress/backend-tls-insecure-skip-verify: "true"` | Skip upstream TLS verification (self-signed certs) |
| `caddy.ingress/upstream-vhost` | Override `Host` header sent to upstream |
| `caddy.ingress/x-forwarded-prefix` | Set `X-Forwarded-Prefix` upstream header |
| `caddy.ingress/proxy-http-version: "1.1"` | Force HTTP/1.1 to upstream (streaming backends) |
| `caddy.ingress/proxy-next-upstream-tries` | Retry failed upstream requests N times |
| `caddy.ingress/proxy-read-timeout` / `proxy-send-timeout` / `proxy-connect-timeout` | Per-route proxy timeouts (seconds) |
| `caddy.ingress/proxy-body-size` | Max request body size (`0` = unlimited) |
| `caddy.ingress/enable-cors: "true"` | Enable CORS (preflight OPTIONS handled automatically) |
| `caddy.ingress/cors-allow-origin` | `*` or comma-separated specific origins |
| `caddy.ingress/cors-allow-methods` / `cors-allow-headers` / `cors-expose-headers` | CORS header overrides |
| `caddy.ingress/cors-allow-credentials: "true"` | Allow credentials (incompatible with `*` origin) |
| `caddy.ingress/cors-max-age` | Preflight cache duration in seconds |
| `caddy.ingress/limit-rps` | Max requests/second per client IP |
| `caddy.ingress/waf: "off"\|"on"\|"detection"` | Per-route WAF override |
| `caddy.ingress/whitelist-source-range` | CIDRs to allow; all others 403 |
| `caddy.ingress/blocklist-source-range` | CIDRs to deny; all others pass |
| `caddy.ingress/basic-auth-secret` | Secret with `auth` htpasswd key |

Full annotation reference and examples: [caddy-k8s](https://github.com/brdelphus/caddy-k8s#annotations)

### Redis (bundled, optional)

The Helm chart can deploy a Redis pod alongside Caddy using the [Bitnami Redis](https://github.com/bitnami/charts/tree/main/bitnami/redis) sub-chart. When enabled, caddy-k8s uses Redis to persist the Ingress → route ID mapping across Caddy restarts, preventing stale routes from accumulating when Ingresses are deleted while Caddy is down.

```yaml
redis:
  enabled: true
  architecture: standalone   # standalone | replication
  auth:
    enabled: false           # set true and provide password for production
  master:
    persistence:
      enabled: true          # survive pod restarts
      size: 1Gi
```

All `redis.*` values are passed through to the Bitnami Redis sub-chart. The address is wired into caddy-k8s automatically — no manual configuration needed.

To use an **external** Redis instead, leave `redis.enabled: false` and configure the address directly in the Caddyfile via the `k8s_ingress` global block.

### Built-in config reloader

The `k8s_config_reloader` Caddy module watches the Caddyfile ConfigMap and reloads Caddy in-place via `POST /load` when it changes. No pod restart, no Stakater Reloader dependency.

```yaml
configReloader:
  enabled: true         # default — hot-reloads Caddyfile on ConfigMap change
  # configmap: ""       # defaults to <release>-caddyfile
  # key: Caddyfile      # key inside ConfigMap.data
  # adminAPI: ""        # defaults to localhost:2019
```

When enabled, Helm upgrades that modify the Caddyfile will no longer cause a rolling restart — Caddy picks up the new config within seconds.

### WAF (Coraza / OWASP CRS)

`plugins.coraza` loads the Coraza module and configures the OWASP ruleset — this is always required if WAF is used anywhere. `k8sIngress.security.waf` sets the default for every Ingress route; the `caddy.ingress/waf` annotation overrides it per-Ingress.

**WAF on all routes, opt-out per Ingress:**

```yaml
plugins:
  coraza:
    enabled: true
    ruleEngine: DetectionOnly   # DetectionOnly | On | Off
    customRules: []
    # - "SecRule REQUEST_URI \"@contains /wp-admin\" \"id:9001,phase:1,deny,status:403\""

k8sIngress:
  security:
    waf: true
    wafMode: Detection
```

```yaml
# Disable WAF for this specific Ingress
metadata:
  annotations:
    caddy.ingress/waf: "off"
```

**WAF on one specific Ingress only:**

```yaml
plugins:
  coraza:
    enabled: true
    ruleEngine: DetectionOnly

k8sIngress:
  security:
    waf: false   # off by default

# Enable WAF only on this Ingress
metadata:
  annotations:
    caddy.ingress/waf: "on"
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

### Authentication & SSO (caddy-security)

Built-in authentication portal supporting OAuth2, OIDC, SAML, LDAP with MFA. Replaces the need for Authelia/OAuth2-proxy for simple SSO use cases.

```yaml
plugins:
  security:
    enabled: true

    # Identity providers — configure one or more
    identityProviders:
      - name: google
        driver: google
        realm: google
        clientId: "{env.GOOGLE_CLIENT_ID}"
        clientSecret: "{env.GOOGLE_CLIENT_SECRET}"
        scopes: [openid, email, profile]

      - name: keycloak                    # Generic OIDC (Keycloak, Authentik, etc.)
        driver: generic
        realm: keycloak
        clientId: "{env.KEYCLOAK_CLIENT_ID}"
        clientSecret: "{env.KEYCLOAK_CLIENT_SECRET}"
        scopes: [openid, email, profile]
        metadataUrl: "https://keycloak.example.com/realms/master/.well-known/openid-configuration"

    # Authentication portal settings
    portal:
      name: myportal
      tokenLifetime: 86400               # 24 hours
      cryptoKey: "{env.JWT_SHARED_KEY}"  # MUST set in production
      enableProviders: [google, keycloak]
      cookie:
        domain: example.com              # for cross-subdomain SSO
        insecure: false
        sameSite: lax

    # Map users to roles based on identity provider claims
    transforms:
      - match:
          realm: google
          email: admin@example.com
        action: add role authp/admin
      - match:
          realm: google
        action: add role authp/user

    # Authorization policies — apply to routes
    policies:
      - name: users
        authUrl: /auth/oauth2/google
        allowRoles: [authp/admin, authp/user]
        injectHeaders: true

    # Secret containing OAuth credentials as env vars
    credentialsSecret: caddy-security-creds
```

Create the credentials secret:

```bash
kubectl create secret generic caddy-security-creds \
  --from-literal=GOOGLE_CLIENT_ID=xxx \
  --from-literal=GOOGLE_CLIENT_SECRET=xxx \
  --from-literal=JWT_SHARED_KEY=$(openssl rand -hex 32) \
  -n caddy
```

To protect a route, import the authorization policy in your route file:

```caddyfile
app.example.com {
  import authorize-users
  reverse_proxy app.default.svc.cluster.local:8080
}
```

The authentication portal is served at `/auth/*` and handles OAuth callbacks automatically.

Documentation: [docs.authcrunch.com](https://docs.authcrunch.com)

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

TLS is configured per Ingress via `spec.tls`. Add a `spec.tls` block referencing a `kubernetes.io/tls` Secret and the caddy-k8s module loads the certificate into Caddy automatically. The secret is watched — renewals are applied without a restart. Ingresses without `spec.tls` are served over HTTP only.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
  annotations:
    caddy.ingress/tls: cert-manager               # cert-manager provisions the Secret
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: caddy-custom
  tls:
    - hosts:
        - app.example.com
      secretName: myapp-tls                       # cert-manager creates this in namespace myapp
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 8080
```

The Secret must exist in the **same namespace as the Ingress**. Use `caddy.ingress/tls: certmagic` instead to let CertMagic issue the cert via ACME — omit `secretName` in that case. See [`examples/caddy/cert-manager.yaml`](examples/caddy/cert-manager.yaml) and [`examples/caddy/certmagic.yaml`](examples/caddy/certmagic.yaml).

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

### Namespace filtering

Watch Ingress resources only in specific namespace(s) — useful for multi-tenant clusters:

```yaml
k8sIngress:
  watchNamespace: "production"   # empty = watch all namespaces (default)
```

### Pod Disruption Budget

Ensures minimum availability during voluntary disruptions (node drains, upgrades):

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1        # or use maxUnavailable: 1
```

### IP Dual Stack (IPv4 + IPv6)

Enable dual-stack support for the LoadBalancer service (requires K8s 1.23+):

```yaml
service:
  enabled: true
  type: LoadBalancer
  ipDualStack:
    enabled: true
    ipFamilies:
      - IPv4
      - IPv6
    ipFamilyPolicy: PreferDualStack   # or RequireDualStack
```

---

## Examples

Ready-to-use values files are in [`examples/`](examples/):

| File | Description |
|---|---|
| [`caddy/baremetal.yaml`](examples/caddy/baremetal.yaml) | DaemonSet + hostPorts for bare-metal k3s |
| [`caddy/loadbalancer.yaml`](examples/caddy/loadbalancer.yaml) | Deployment + LoadBalancer for MetalLB / cloud |
| [`caddy/mail.yaml`](examples/caddy/mail.yaml) | L4 TCP passthrough for SMTP / IMAP (stack on top of either above) |
| [`caddy/full.yaml`](examples/caddy/full.yaml) | All optional plugins enabled |
| [`caddy/cert-manager.yaml`](examples/caddy/cert-manager.yaml) | TLS via cert-manager — ClusterIssuer + Certificate + spec.tls pattern |
| [`caddy/certmagic.yaml`](examples/caddy/certmagic.yaml) | TLS via CertMagic built-in ACME (no cert-manager needed) |
| [`caddy/ondemand-tls.yaml`](examples/caddy/ondemand-tls.yaml) | CertMagic On-Demand TLS — issue certs on first request |
| [`caddy/zerossl.yaml`](examples/caddy/zerossl.yaml) | CertMagic with ZeroSSL / External Account Binding |
| [`apps/nextcloud.yaml`](examples/apps/nextcloud.yaml) | Nextcloud values override |
| [`apps/mailu.yaml`](examples/apps/mailu.yaml) | Mailu values override |
| [`apps/gitea.yaml`](examples/apps/gitea.yaml) | Gitea values override |
| [`apps/grafana.yaml`](examples/apps/grafana.yaml) | Grafana values override |
| [`apps/jellyfin.yaml`](examples/apps/jellyfin.yaml) | Jellyfin values override |
| [`apps/vaultwarden.yaml`](examples/apps/vaultwarden.yaml) | Vaultwarden values override |
| [`apps/authelia.yaml`](examples/apps/authelia.yaml) | Authelia values override |
| [`apps/azuracast.yaml`](examples/apps/azuracast.yaml) | AzuraCast Ingress manifest |

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
- [Bitnami Redis](https://github.com/bitnami/charts/tree/main/bitnami/redis) chart for the optional bundled Redis
- All plugin authors listed in the [What's inside](#whats-inside) table above

---

## License

MIT
