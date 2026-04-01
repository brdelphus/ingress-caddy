# Examples

## Caddy deployment scenarios

| File | Use case |
|---|---|
| [caddy/baremetal.yaml](caddy/baremetal.yaml) | DaemonSet + hostPorts for bare-metal k3s |
| [caddy/loadbalancer.yaml](caddy/loadbalancer.yaml) | Deployment + LoadBalancer for MetalLB / cloud |
| [caddy/mail.yaml](caddy/mail.yaml) | L4 TCP passthrough for SMTP / IMAP (combine with the above) |
| [caddy/full.yaml](caddy/full.yaml) | All optional plugins enabled (WAF, CrowdSec, GeoIP, etc.) |
| [caddy/cert-manager.yaml](caddy/cert-manager.yaml) | TLS via cert-manager — Certificate CR + spec.tls Ingress pattern |
| [caddy/certmagic.yaml](caddy/certmagic.yaml) | TLS via CertMagic built-in ACME (no cert-manager needed) |
| [caddy/ondemand-tls.yaml](caddy/ondemand-tls.yaml) | CertMagic On-Demand TLS — issue certs dynamically on first request |
| [caddy/zerossl.yaml](caddy/zerossl.yaml) | CertMagic with ZeroSSL / External Account Binding (EAB) |
| [caddy/security.yaml](caddy/security.yaml) | Built-in authentication with caddy-security (OAuth2/OIDC/SAML) |

Combine files with multiple `-f` flags:

```bash
# Bare-metal, certs via cert-manager
helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml
# Then apply your ClusterIssuer + Certificate resources — see cert-manager.yaml

# Bare-metal, certs via CertMagic built-in ACME (no cert-manager needed)
helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/certmagic.yaml

# Bare-metal with mail passthrough
helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/mail.yaml

# MetalLB with full security stack
helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/loadbalancer.yaml \
  -f examples/caddy/full.yaml

# On-Demand TLS — issue certs dynamically on first request
helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/ondemand-tls.yaml

# ZeroSSL instead of Let's Encrypt
helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/zerossl.yaml
```

## App values

Each file is a drop-in values override for the app's official Helm chart.
Set `ingressClassName: caddy` and the relevant `caddy.ingress/` annotations.

| File | Chart | Helm repo |
|---|---|---|
| [apps/nextcloud.yaml](apps/nextcloud.yaml) | `nextcloud/nextcloud` | `https://nextcloud.github.io/helm` |
| [apps/mailu.yaml](apps/mailu.yaml) | `mailu/mailu` | `https://mailu.github.io/helm-charts` |
| [apps/gitea.yaml](apps/gitea.yaml) | `gitea-charts/gitea` | `https://dl.gitea.com/charts` |
| [apps/grafana.yaml](apps/grafana.yaml) | `grafana/grafana` | `https://grafana.github.io/helm-charts` |
| [apps/vaultwarden.yaml](apps/vaultwarden.yaml) | `vaultwarden/vaultwarden` | `https://guerzon.github.io/vaultwarden` |
| [apps/jellyfin.yaml](apps/jellyfin.yaml) | `jellyfin/jellyfin` | `https://jellyfin.github.io/jellyfin-helm` |
| [apps/authelia.yaml](apps/authelia.yaml) | `authelia/authelia` | `https://charts.authelia.com` |
| [apps/azuracast.yaml](apps/azuracast.yaml) | manual Ingress | — |

### Usage pattern

```bash
# 1. Add the chart repo
helm repo add nextcloud https://nextcloud.github.io/helm
helm repo update

# 2. Install with the example values as a base, then override what you need
helm install nextcloud nextcloud/nextcloud \
  -n nextcloud --create-namespace \
  -f examples/apps/nextcloud.yaml \
  --set nextcloud.host=cloud.yourdomain.com \
  --set nextcloud.password=changeme
```

> These examples are starting points — review and adjust hostnames, resource limits,
> and storage settings for your environment before deploying.

## TLS quick reference

### cert-manager (recommended)

Issue and renew certs automatically. Each app gets its own `Certificate` resource pointing to a `kubernetes.io/tls` Secret. The Ingress `spec.tls.secretName` tells caddy-k8s which Secret to load. See [cert-manager.yaml](caddy/cert-manager.yaml) for the full pattern including ClusterIssuer, wildcard, and DNS-01 examples.

### CertMagic built-in ACME

No cert-manager needed. Configure CertMagic globally via [certmagic.yaml](caddy/certmagic.yaml) and set `spec.tls` on Ingresses without a `secretName` — CertMagic issues and manages the cert for each hostname automatically.

### On-Demand TLS

Issue certs dynamically on first request — no Certificate resources needed. See [ondemand-tls.yaml](caddy/ondemand-tls.yaml). Always configure the `ask` validation URL in production.

### ZeroSSL / alternative ACME CAs

Use ZeroSSL, Google Trust Services, or any EAB-capable CA instead of Let's Encrypt. See [zerossl.yaml](caddy/zerossl.yaml).

## Built-in Authentication (caddy-security)

Native SSO without external dependencies. See [security.yaml](caddy/security.yaml).

```bash
kubectl create secret generic caddy-security-creds \
  --from-literal=GOOGLE_CLIENT_ID=xxx \
  --from-literal=GOOGLE_CLIENT_SECRET=xxx \
  --from-literal=JWT_SHARED_KEY=$(openssl rand -hex 32) \
  -n caddy

helm install caddy ingress-caddy/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/security.yaml
```
