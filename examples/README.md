# Examples

## Caddy deployment scenarios

| File | Use case |
|---|---|
| [caddy/baremetal.yaml](caddy/baremetal.yaml) | DaemonSet + hostPorts for bare-metal k3s |
| [caddy/loadbalancer.yaml](caddy/loadbalancer.yaml) | Deployment + LoadBalancer for MetalLB / cloud |
| [caddy/mail.yaml](caddy/mail.yaml) | L4 TCP passthrough for SMTP / IMAP (combine with the above) |
| [caddy/full.yaml](caddy/full.yaml) | All optional plugins enabled (WAF, CrowdSec, GeoIP, etc.) |
| [caddy/security.yaml](caddy/security.yaml) | Built-in authentication with caddy-security (OAuth2/OIDC/SAML) |
| [caddy/ondemand-tls.yaml](caddy/ondemand-tls.yaml) | On-Demand TLS — issue certs dynamically on first request |
| [caddy/zerossl.yaml](caddy/zerossl.yaml) | ZeroSSL with External Account Binding (EAB) |

Combine files with multiple `-f` flags:

```bash
# Bare-metal with mail passthrough
helm install caddy caddy-custom/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/mail.yaml

# MetalLB with full security stack
helm install caddy caddy-custom/caddy -n caddy --create-namespace \
  -f examples/caddy/loadbalancer.yaml \
  -f examples/caddy/full.yaml

# Bare-metal with built-in authentication (caddy-security)
helm install caddy caddy-custom/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/security.yaml

# On-Demand TLS (no cert-manager needed)
helm install caddy caddy-custom/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/ondemand-tls.yaml

# ZeroSSL instead of Let's Encrypt
helm install caddy caddy-custom/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/zerossl.yaml
```

## App values

Each file is a drop-in values override for the app's official Helm chart.
Set `ingressClassName: caddy-custom` and the relevant `caddy.ingress/` annotations.

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

## New in v0.6.0

### Built-in Authentication (caddy-security)

Native SSO without external dependencies. See [security.yaml](caddy/security.yaml).

```bash
# Create credentials secret
kubectl create secret generic caddy-security-creds \
  --from-literal=GOOGLE_CLIENT_ID=xxx \
  --from-literal=GOOGLE_CLIENT_SECRET=xxx \
  --from-literal=JWT_SHARED_KEY=$(openssl rand -hex 32) \
  -n caddy

# Deploy with authentication
helm install caddy caddy-custom/caddy -n caddy --create-namespace \
  -f examples/caddy/baremetal.yaml \
  -f examples/caddy/security.yaml
```

### On-Demand TLS

Issue certificates dynamically on first request. See [ondemand-tls.yaml](caddy/ondemand-tls.yaml).

### ZeroSSL / EAB

Use alternative ACME CAs with External Account Binding. See [zerossl.yaml](caddy/zerossl.yaml).

### Pod Disruption Budget

Enabled by default in [full.yaml](caddy/full.yaml) for graceful upgrades.

### Namespace Filtering

Watch Ingress resources in specific namespace only — useful for multi-tenant clusters.
