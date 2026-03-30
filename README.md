# caddy-custom

> **Status: working, not yet battle-tested.**
> Core functionality is operational and runs in a personal k3s cluster, but this project is still early. More real-world testing, edge case coverage, and community feedback is needed before it can be considered stable for general use. Contributions and issue reports are very welcome.

A custom [Caddy](https://caddyserver.com) image for Kubernetes, built to replace Traefik or nginx-ingress. Handles TLS via cert-manager CSI and ships with a Helm chart that makes every feature toggleable.

Includes a built-in Kubernetes Ingress controller — apps set `ingressClassName: caddy-custom` and routes appear in Caddy automatically, no manual config editing required.

Supports two deployment modes:
- **DaemonSet + hostPorts** — runs on every node, binds ports directly. Ideal for bare-metal k3s.
- **Deployment + LoadBalancer** — fixed replica count behind MetalLB or a cloud LB (AWS NLB, GCE, etc.).

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

With cert-manager CSI:

```yaml
k8sIngress:
  enabled: true
  ingressClass: caddy-custom

tls:
  certManagerCSI:
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer

realIP:
  trustedProxies:
    - 10.42.0.0/16   # k3s pod CIDR
    - 127.0.0.1/32
```

With CertMagic built-in ACME (no cert-manager needed):

```yaml
k8sIngress:
  enabled: true
  ingressClass: caddy-custom

tls:
  certManagerCSI:
    enabled: false
  acme:
    enabled: true
    email: admin@example.com
    challenge: dns
    storage: kubernetes      # certs stored as K8s Secrets, no PVC needed
    dns:
      provider: cloudflare
      config: |
        api_token {env.CF_API_TOKEN}
      credentialsSecret: caddy-dns-creds

realIP:
  trustedProxies:
    - 10.42.0.0/16
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

Three mutually exclusive backends — enable exactly one.

**Option 1 — cert-manager CSI** (external dependency):

```yaml
tls:
  certManagerCSI:
    enabled: true
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer
```

Requires cert-manager + cert-manager-csi-driver. Certificates are mounted as real files; Caddy's fsnotify handles rotation automatically.

**Option 2 — CertMagic built-in ACME** (no external dependency):

Caddy handles issuance and renewal automatically. Domains are discovered from Ingress resources as apps are deployed — no need to pre-list them.

Three challenge types:

```yaml
tls:
  certManagerCSI:
    enabled: false
  acme:
    enabled: true
    email: admin@example.com
    ca: ""   # empty = Let's Encrypt production; set staging URL for testing

    # HTTP-01 — default, no extra config needed, port 80 must be reachable
    challenge: http

    # TLS-ALPN-01 — port 443, no extra config needed, useful when port 80 is blocked
    challenge: tls-alpn

    # DNS-01 — required for wildcards and private clusters not reachable from internet
    # The DNS provider module must be compiled into the image (DNS_PROVIDER build arg)
    # See https://github.com/caddy-dns for available providers
    challenge: dns
    dns:
      provider: cloudflare           # provider module name
      config: |
        api_token {env.CF_API_TOKEN} # raw Caddyfile block, use {env.X} for secrets
      credentialsSecret: caddy-dns-creds  # all keys exposed as env vars to Caddy
```

Three storage backends for issued certificates:

```yaml
    # filesystem — default, /data/caddy/ inside the pod
    # Requires persistence.enabled to survive restarts and avoid rate limits
    storage: filesystem

    # kubernetes — stores certs as Kubernetes Secrets in the release namespace
    # No PVC needed; certs survive restarts naturally
    # RBAC is automatically extended to allow secret create/update/delete
    storage: kubernetes

    # redis — uses bundled Redis when redis.enabled: true
    # Best for multi-replica Deployments sharing cert state across pods
    storage: redis
```

Persistence (only needed with `storage: filesystem`):

```yaml
persistence:
  enabled: true
  hostPath: /var/lib/caddy   # recommended for DaemonSet
  # storageClass: longhorn   # for Deployment mode with dynamic provisioning
```

**Option 3 — existing TLS secret**:

```yaml
tls:
  certManagerCSI:
    enabled: false
  existingSecret: my-tls-secret
```

**Building with a DNS provider**

To use DNS-01 challenge, build the image with the `DNS_PROVIDER` build arg:

```bash
docker build \
  --build-arg DNS_PROVIDER=github.com/caddy-dns/cloudflare \
  -t ghcr.io/brdelphus/caddy-custom:latest \
  docker/
```

Any provider from [github.com/caddy-dns](https://github.com/caddy-dns) works, as well as community modules (e.g. `github.com/simonvandermeer/caddy-technitium-dns-module`).

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

## Examples

Ready-to-use values files are in [`examples/`](examples/):

| File | Description |
|---|---|
| [`caddy/baremetal.yaml`](examples/caddy/baremetal.yaml) | DaemonSet + hostPorts for bare-metal k3s |
| [`caddy/loadbalancer.yaml`](examples/caddy/loadbalancer.yaml) | Deployment + LoadBalancer for MetalLB / cloud |
| [`caddy/mail.yaml`](examples/caddy/mail.yaml) | L4 TCP passthrough for SMTP / IMAP (stack on top of either above) |
| [`caddy/full.yaml`](examples/caddy/full.yaml) | All optional plugins enabled |
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
