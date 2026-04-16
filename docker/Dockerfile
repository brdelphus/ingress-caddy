FROM caddy:2.11.2-builder AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Optional: DNS provider module for CertMagic DNS-01 ACME challenge.
# Pass any caddy-dns module path at build time, e.g.:
#   --build-arg DNS_PROVIDER=github.com/caddy-dns/cloudflare
#   --build-arg DNS_PROVIDER=github.com/caddy-dns/rfc2136
#   --build-arg DNS_PROVIDER=github.com/simonvandermeer/caddy-technitium-dns-module
# Leave empty (default) to use HTTP-01 or TLS-ALPN-01 challenges only.
ARG DNS_PROVIDER=""

# Build a fully static binary so it runs on Chainguard (glibc) without depending on musl
ENV CGO_ENABLED=0

RUN set -eux; \
    xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2@v2.4.0 \
    --with github.com/mholt/caddy-l4@v0.1.0 \
    --with github.com/mholt/caddy-ratelimit@b8d8c9a9d99e \
    --with github.com/caddyserver/cache-handler@v0.16.0 \
    --with github.com/porech/caddy-maxmind-geolocation@v1.0.1 \
    --with github.com/hslatman/caddy-crowdsec-bouncer@v0.10.1 \
    --with pkg.jsn.cam/caddy-defender=github.com/jasonlovesdoggo/caddy-defender@v0.10.0 \
    --with github.com/greenpau/caddy-security@v1.1.59 \
    --with github.com/brdelphus/caddy-k8s \
    --with github.com/brdelphus/caddy-kubernetes-storage \
    --with github.com/pberkel/caddy-storage-redis \
    ${DNS_PROVIDER:+--with ${DNS_PROVIDER}}

# Chainguard static: distroless Wolfi base, 0 CVEs, daily rebuilds, Sigstore-signed
# Includes CA certificates and timezone data — no shell or package manager
FROM cgr.dev/chainguard/static:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

LABEL org.opencontainers.image.title="ingress-caddy" \
      org.opencontainers.image.description="Caddy-based Kubernetes ingress controller with WAF, L4, rate limiting, cache, GeoIP, CrowdSec, defender and SSO" \
      org.opencontainers.image.source="https://github.com/brdelphus/ingress-caddy" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.url="https://caddyserver.com" \
      org.opencontainers.image.vendor="Light Code Labs" \
      org.opencontainers.image.documentation="https://caddyserver.com/docs"

ENTRYPOINT ["/usr/bin/caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
