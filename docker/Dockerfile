FROM caddy:2.11.2-builder AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN xcaddy build \
    # WAF — OWASP Core Rule Set (built against Caddy v2.11.2)
    --with github.com/corazawaf/coraza-caddy/v2@v2.3.0 \
    # Layer 4 TCP/UDP routing (built against Caddy v2.11.2)
    --with github.com/mholt/caddy-l4@v0.1.0 \
    # Rate limiting — no formal release, pin to latest master commit
    # targets Caddy v2.8.0; verify no regressions before upgrading Caddy
    --with github.com/mholt/caddy-ratelimit@b8d8c9a9d99e \
    # RFC 7234 HTTP cache (targets Caddy v2.10.0, compat with v2.11.2)
    --with github.com/caddyserver/cache-handler@v0.16.0 \
    # GeoIP country blocking (v1.0.0 had checksum mismatch, v1.0.2 is phantom — use v1.0.1)
    --with github.com/porech/caddy-maxmind-geolocation@v1.0.1 \
    # CrowdSec IP reputation + AppSec (targets Caddy v2.10.2, compat with v2.11.2)
    --with github.com/hslatman/caddy-crowdsec-bouncer@v0.10.1 \
    # AI scraper / cloud datacenter IP blocker — module path differs from GitHub repo path
    --with pkg.jsn.cam/caddy-defender=github.com/jasonlovesdoggo/caddy-defender@v0.10.0 \
    # Kubernetes Ingress controller — watches ingressClassName: caddy-custom
    --with github.com/brdelphus/caddy-k8s

FROM caddy:2.11.2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

LABEL org.opencontainers.image.description="Caddy with WAF, L4, rate limiting, cache, GeoIP, CrowdSec, defender, k8s-ingress"
