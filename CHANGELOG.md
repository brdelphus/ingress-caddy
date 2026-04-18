# Changelog

## [1.0.11] - 2026-04-18

### Bug Fixes

- **Duplicate `@id` on config reload eliminated** — when Caddy performs an in-place config reload, the old and new `k8s_ingress` module instances overlap. Both would see the same ingress and race to upsert its route, producing `duplicate ID found at routes/1 and routes/2`. Fixed by tying all admin API calls in `handleAdd`/`handleDelete` to a `context.Context` that is cancelled when `Stop()` is called on the old instance, so in-flight calls from the dying instance are aborted before the new instance starts.

### New Features

- **Structured annotation logging** — on every ingress sync (startup, reload, create, annotation update), caddy-k8s now logs:
  - `k8s_ingress: syncing ingress` with `ingress`, `hosts`, and `class` — emitted unconditionally so restarts and reloads are always visible.
  - `k8s_ingress: ingress annotations` listing every non-default annotation value (WAF mode, rate limit, CORS origins, whitelist/blocklist, basic auth realm, rewrite target, request/response header keys, TLS handler, body size limit, proxy timeouts, etc.). Only emitted when at least one annotation is set.

### Helm chart: 0.9.13

---

## [1.0.10] - 2026-04-18

### Bug Fixes

- **WAF annotation no longer fails with unmarshal error** — `coraza-caddy` expects `directives` as a single newline-joined string; we were passing a `[]string`, causing `cannot unmarshal array into Go struct field corazaModule.directives of type string` and rejecting the entire route. Fixed by joining the directive slice with `\n` before serialising.
- **`upsertRoute` retries after admin API restart** — an in-place Caddy config reload (triggered by every admin API write) briefly takes the admin API offline. The subsequent POST to re-add the route would fail, leaving the ingress without a route until the next annotation change. Fixed by retrying up to 3 times with 0 / 500 ms / 1 s backoff.

### Helm chart: 0.9.12

---

## [1.0.9] - 2026-04-18

### Bug Fixes

- **Concurrent `handleAdd` race eliminated** — during Caddy config reloads, the old and new module instances overlap. Both would see no existing route (404) and race to POST it, producing a `duplicate @id` error and leaving a stale route behind after the loser's DELETE. Fixed by adding a per-Ingress mutex via `sync.Map` in `App`; `handleAdd` and `handleDelete` now serialize per `namespace/name` key across concurrent instances.

### Helm chart: 0.9.11

---

## [1.0.8] - 2026-04-18

### Chore

- **Bump Go 1.26.1 → 1.26.2** — resolves govulncheck CVEs GO-2026-4863/4864/4865/4866/4867 in the Go standard library (`crypto/tls`, `crypto/x509`, `html/template`).

### Helm chart: 0.9.10

---

## [1.0.7] - 2026-04-18

### Bug Fixes

- **Route upsert no longer fails with duplicate `@id` error** — `PUT /id/<id>` momentarily indexes both the old and new route entries before removing the old one, causing Caddy to reject the update with `duplicate ID found at routes/1 and routes/2`. Fixed by switching to DELETE + POST, which removes the existing route atomically before re-adding the updated one.
- **`X-Real-IP` / `X-Forwarded-For` headers now carry the real client IP** — the `{client_ip}` Caddyfile shorthand is not a raw JSON placeholder; `{http.vars.client_ip}` is the correct form in the admin-API JSON config. Changed `injectRealIP` to use `{http.vars.client_ip}` so the headers expand to the trusted-proxy-aware client IP instead of the literal string `{client_ip}`.

### Helm chart: 0.9.9

- **Placeholder `:80` / `:443` blocks now carry a `respond /healthz 200` route** — empty server blocks leave the `routes` field as `null` in Caddy's JSON config. When `k8s_ingress` tries to POST a new route to a null array, Caddy returns `cannot unmarshal object into RouteList`. The placeholder routes initialise the array so dynamic route injection works on a fresh pod.

---

## [1.0.6] - 2026-04-17

### Bug Fixes

- **`http_server_name` Caddyfile directive now recognized** — `UnmarshalCaddyfile` was missing the `http_server_name` case, causing a parse error when `k8sIngress.httpServerName` was set via helm values.

### Helm chart: 0.9.8

---

## [1.0.5] - 2026-04-17

### Bug Fixes

- **k8s_ingress deadlock fixed at root** — server name discovery moved from `Start()` to `Provision()` using `ctx.App("http")` (in-process Go API). `Provision()` is called before Caddy acquires the config write-lock, so accessing the HTTP app's `Servers` map is safe. `Start()` no longer calls the admin API at all; the goroutine fallback polls with retry only if `Provision()` couldn't discover names.

### Helm chart: 0.9.7

---

## [1.0.4] - 2026-04-17

### Bug Fixes

- **k8s_ingress now starts and watches Ingress resources** — `Start()` was calling `GET /config/apps/http/servers` while Caddy held the config write-lock, causing a permanent deadlock: the admin API read blocked forever, `Start()` never returned, and no Ingress routes were ever injected. Fixed by spawning the server-name resolution + informer in a goroutine so `Start()` returns immediately. `resolveServerName` now retries with a 5-second timeout per attempt.
- **Placeholder `:443` block no longer fails to parse** — bare `tls` directive is invalid in a port-based site block; changed to `tls {}` (block form), then removed entirely since the placeholder only needs to anchor the server for k8s_ingress discovery (the deadlock fix above makes this moot anyway).
- **k8s_ingress server names now configured explicitly** — added `server_name` / `http_server_name` to the `k8s_ingress` Caddyfile block (values: `serverName`, `httpServerName`) to bypass auto-discovery and avoid the admin API call even in edge cases where the goroutine fix might race.

### Helm chart: 0.9.6

---

## [1.0.3] - 2026-04-16

### Bug Fixes

- **Caddy container no longer exits immediately on startup** — Dockerfile was missing `CMD`; the binary printed help text and exited. Added `CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]` to the Dockerfile and matching `args` to the DaemonSet template so both the image default and the chart are self-consistent.
- **Liveness/readiness probes now reach the admin API** — `admin` was bound to `localhost` and probes used `host: localhost`, which the kubelet resolves to the *node's* loopback rather than the pod's. Changed `admin.host` default to `""` (binds `0.0.0.0`) and removed the `host:` override from both probes. Affected all deployments using `hostPorts` (non-`hostNetwork`); pods were killed after ~70 s by the failing liveness probe.

### Helm chart: 0.9.5

---

## [1.0.2] - 2026-04-02

### New Features

- **`caddy.ingress/auth-policy` annotation** — reference a ConfigMap (same namespace) whose `handler` key contains raw Caddy handler JSON. Injected into the route after the WAF and before the reverse_proxy, enabling caddy-security authorization policies without editing the Caddyfile directly.

### Helm chart: 0.9.4

- **`imagePullSecrets`** — support private container registries
- **`affinity`** — pod affinity/anti-affinity rules
- **`podSecurityContext`** — pod-level security context
- **`securityContext`** — container-level security context; defaults to `NET_BIND_SERVICE` + drop all other capabilities
- **`service.labels`** — extra labels on the LoadBalancer Service
- **Bug fix:** `podAnnotations` was applied to DaemonSet metadata instead of the pod template

---

## [1.0.2] - 2026-04-02

### Security

- **Base image switched from Alpine 3.23 to Chainguard static (Wolfi)** — eliminates all OS-level CVEs (16 found by Grype on Alpine: 3 High, 10 Medium, 3 Low in `curl`, `libcrypto3`, `nghttp2-libs`, `busybox`). Chainguard images are rebuilt daily with automated patching.
- **Binary now built with `CGO_ENABLED=0`** — fully static binary, no libc dependency, runs on any Linux kernel.

### Helm chart: 0.9.3

---

## [1.0.1] - 2026-04-01

### Security

- **CVE-2026-30836 (CRITICAL)** — upgraded `github.com/smallstep/certificates` from `v0.30.0-rc3` to `v0.30.0` — unauthenticated certificate issuance via SCEP Update Request
- **CVE-2026-33186 (CRITICAL)** — upgraded `google.golang.org/grpc` from `v1.79.1` to `v1.79.3` — authorization bypass via improper HTTP/2 path validation
- **CVE-2026-22184 (HIGH)** — added `apk upgrade --no-cache` in Docker final stage to patch `zlib 1.3.1-r2` → `1.3.2-r0` (buffer overflow in untgz utility)

### Helm chart: 0.9.2

---

## [1.0.1] - 2026-03-31

### Bug Fixes

- **WAF: OWASP CRS rules were never loaded** — `wafHandler()` in caddy-k8s was missing the three mandatory `Include` directives (`@coraza.conf-recommended`, `@crs-setup.conf.example`, `@owasp_crs/*.conf`). `load_owasp_crs: true` only makes the virtual paths available; without the Includes, zero CRS rules were evaluated on any Ingress with `caddy.ingress/waf: on`.
- **WAF: `SecRuleEngine` ordering fixed** — In both caddy-k8s and the Helm Caddyfile snippet, `SecRuleEngine` was placed before the CRS Includes. Since `@coraza.conf-recommended` resets it to `DetectionOnly`, our `On` override must come *after* all Includes.

### Helm chart: 0.9.1

---

Versions track the `ingress-caddy` image. The Helm chart version is independent
but its `appVersion` always matches the image version.

## [1.0.0] - 2026-04-01

### Breaking Changes

- Image versioning switched from Caddy version (`2.11.2`) to ingress-caddy version (`1.0.0`).
  Update `image.tag` in your `values.yaml` if overriding it.

### Changes

- First versioned release under the `ingress-caddy` name (formerly `caddy-custom`)
- Image: `ghcr.io/brdelphus/ingress-caddy:1.0.0`
- Built on Caddy `2.11.2`
- Module updates: coraza-caddy `v2.4.0`, caddy-maxmind-geolocation `v1.0.2`, caddy-security pinned to `v1.1.59`

### Helm chart: 0.9.0

---

## [0.8.2] - 2026-04-01

### Fixes

- `.cr-config.yaml`: chart-releaser now correctly targets `ingress-caddy` repo
- `docker/build.sh`: default image name updated to `ingress-caddy`
- README: corrected `ingressClassName` examples (`caddy`, not `ingress-caddy`)

---

## [0.8.1] - 2026-03-31

### Changes

- Repo renamed from `caddy-custom` to `ingress-caddy`
- Image renamed to `ghcr.io/brdelphus/ingress-caddy`
- Default `IngressClass` changed from `caddy-custom` to `caddy` — update `spec.ingressClassName` in existing Ingress resources

---

## [0.8.0] - 2026-03-31

### New Features

- **HTTP access logging** — enable server-wide access logging with `k8sIngress.accessLog: true` in Helm values (or `access_log on` in the Caddyfile). Logs are written to stderr in JSON format. Requires the Caddy logging subsystem to be initialised; caddy-k8s sets this up automatically on startup.
- **Per-Ingress access log opt-out** (`caddy.ingress/access-log: "false"`) — suppress access logs for specific Ingresses while keeping global logging enabled. Caddy's `skip_hosts` is rebuilt incrementally as Ingresses are added or removed.
- **Per-Ingress request header manipulation** (`caddy.ingress/request-headers`) — set or delete HTTP request headers before they are forwarded upstream. Format: `Header=Value,-DeleteMe`. Caddy placeholders (e.g. `{client_ip}`) are supported.
- **Per-Ingress response header manipulation** (`caddy.ingress/response-headers`) — set or delete HTTP response headers before they reach the client. Runs after global security headers, so per-Ingress annotations can override them.

### Helm

- New value `k8sIngress.accessLog` (default `false`) — controls `access_log on/off` in the `k8s_ingress` Caddyfile block.

---

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
