{{/*
Expand the name of the chart.
*/}}
{{- define "caddy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "caddy.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "caddy.labels" -}}
helm.sh/chart: {{ include "caddy.chart" . }}
{{ include "caddy.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "caddy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "caddy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "caddy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "caddy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "caddy.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
TLS cert path helpers
*/}}
{{- define "caddy.tlsCertPath" -}}
{{ .Values.tls.mountPath }}/{{ .Values.tls.certManagerCSI.certFile }}
{{- end }}

{{- define "caddy.tlsKeyPath" -}}
{{ .Values.tls.mountPath }}/{{ .Values.tls.certManagerCSI.keyFile }}
{{- end }}

{{/*
Reloader annotation — lists all ConfigMaps that should trigger a restart
*/}}
{{- define "caddy.reloaderAnnotation" -}}
{{- if .Values.reloader.enabled }}
configmap.reloader.stakater.com/reload: "{{ include "caddy.fullname" . }}-caddyfile,{{ include "caddy.fullname" . }}-routes"
{{- end }}
{{- end }}

{{/*
Redis master service address — used by caddy-k8s when redis.enabled is true.
Bitnami Redis sub-chart names the master service <release>-redis-master.
*/}}
{{- define "caddy.redisAddr" -}}
{{- printf "%s-redis-master:6379" .Release.Name }}
{{- end }}

{{/*
Generate the Caddyfile content
*/}}
{{- define "caddy.caddyfile" -}}
{
  admin {{ .Values.admin.host }}:{{ .Values.admin.port }}

  {{- if .Values.tls.acme.enabled }}

  # ── CertMagic ACME ────────────────────────────────────────────────────────────
  {{- if .Values.tls.acme.email }}
  email {{ .Values.tls.acme.email }}
  {{- end }}
  {{- if .Values.tls.acme.ca }}
  acme_ca {{ .Values.tls.acme.ca }}
  {{- end }}

  {{- if eq .Values.tls.acme.challenge "dns" }}
  acme_dns {{ .Values.tls.acme.dns.provider }} {
    {{ .Values.tls.acme.dns.config | nindent 4 | trim }}
  }
  {{- else if eq .Values.tls.acme.challenge "tls-alpn" }}
  acme_challenges {
    tls_alpn
  }
  {{- end }}
  {{- /* http challenge is Caddy's default — no explicit config needed */}}

  {{- if eq .Values.tls.acme.storage "kubernetes" }}
  storage kubernetes {
    namespace {{ .Release.Namespace }}
  }
  {{- else if eq .Values.tls.acme.storage "redis" }}
  {{- $redisAddr := include "caddy.redisAddr" . }}
  {{- $redisParts := splitList ":" $redisAddr }}
  storage redis {
    host       {{ index $redisParts 0 }}
    port       {{ index $redisParts 1 }}
    key_prefix caddy
  }
  {{- end }}
  {{- end }}

  {{- if .Values.k8sIngress.enabled }}
  k8s_ingress {
    ingress_class {{ .Values.k8sIngress.ingressClass }}
    security {
      waf              {{ if .Values.k8sIngress.security.waf }}on{{ else }}off{{ end }}
      waf_mode         {{ .Values.k8sIngress.security.wafMode }}
      security_headers {{ if .Values.k8sIngress.security.securityHeaders }}on{{ else }}off{{ end }}
      inject_real_ip   {{ if .Values.k8sIngress.security.injectRealIP }}on{{ else }}off{{ end }}
    }
    {{- if .Values.redis.enabled }}
    redis {
      address {{ include "caddy.redisAddr" . }}
      {{- if .Values.redis.auth.enabled }}
      password {{ .Values.redis.auth.password }}
      {{- end }}
    }
    {{- end }}
  }
  {{- end }}

  {{- if .Values.plugins.coraza.enabled }}
  order coraza_waf first
  {{- end }}
  {{- if and .Values.plugins.crowdsec.enabled .Values.plugins.coraza.enabled }}
  order crowdsec after coraza_waf
  {{- else if .Values.plugins.crowdsec.enabled }}
  order crowdsec first
  {{- end }}

  servers {
    {{- if .Values.realIP.enabled }}
    trusted_proxies static {{ join " " .Values.realIP.trustedProxies }}
    {{- if .Values.realIP.strict }}
    trusted_proxies_strict
    {{- end }}
    {{- end }}
    {{- if .Values.metrics.enabled }}
    metrics
    {{- end }}
  }

  {{- if .Values.plugins.crowdsec.enabled }}
  crowdsec {
    api_url {{ .Values.plugins.crowdsec.lapiUrl }}
    {{- if .Values.plugins.crowdsec.existingSecret }}
    api_key {env.CROWDSEC_API_KEY}
    {{- else }}
    api_key {{ .Values.plugins.crowdsec.apiKey }}
    {{- end }}
    ticker_interval {{ .Values.plugins.crowdsec.tickerInterval }}
    {{- if .Values.plugins.crowdsec.appSec.enabled }}
    appsec_url http://{{ .Values.plugins.crowdsec.appSec.host }}:{{ .Values.plugins.crowdsec.appSec.port }}
    {{- end }}
  }
  {{- end }}

  {{- if and .Values.l4.enabled .Values.l4.routes }}
  layer4 {
    {{- range .Values.l4.routes }}
    {{ .address }} {
      route {
        proxy {
          {{- if .proxyProtocol }}
          proxy_protocol {{ .proxyProtocol }}
          {{- end }}
          upstream {{ .upstream }}
        }
      }
    }
    {{- end }}
  }
  {{- end }}

  {{- if .Values.caddyfile.extraGlobalOptions }}

  # ── Extra global options ──────────────────────────────────────────────────────
  {{ .Values.caddyfile.extraGlobalOptions | nindent 2 | trim }}
  {{- end }}
}

# ── HTTP → HTTPS redirect ───────────────────────────────────────────────────────
:80 {
  redir https://{host}{uri} permanent
}

# ── Reusable security snippet ───────────────────────────────────────────────────
# Usage in route files:  import security
(security) {
  {{- if .Values.plugins.coraza.enabled }}
  coraza_waf {
    load_owasp_crs
    directives `
      Include @coraza.conf-recommended
      SecRuleEngine {{ .Values.plugins.coraza.ruleEngine }}
      Include @crs-setup.conf.example
      Include @owasp_crs/*.conf
      {{- range .Values.plugins.coraza.customRules }}
      {{ . }}
      {{- end }}
    `
  }
  {{- end }}

  {{- if .Values.plugins.crowdsec.enabled }}
  crowdsec
  {{- end }}

  {{- if .Values.plugins.defender.enabled }}
  defender {
    action {{ .Values.plugins.defender.action }}
  }
  {{- end }}

  {{- if .Values.plugins.geoip.enabled }}
  @geoblock maxmind_geolocation {
    db_path {{ .Values.plugins.geoip.dbPath }}
    {{- if .Values.plugins.geoip.deniedCountries }}
    deny_countries {{ join " " .Values.plugins.geoip.deniedCountries }}
    {{- end }}
  }
  respond @geoblock "Forbidden" 403
  {{- end }}

  {{- if .Values.plugins.rateLimit.enabled }}
  rate_limit {
    zone dynamic {
      key {{ .Values.plugins.rateLimit.key }}
      window {{ .Values.plugins.rateLimit.window }}
      events {{ .Values.plugins.rateLimit.maxEvents }}
    }
  }
  {{- end }}

  {{- if .Values.securityHeaders.enabled }}
  header {
    {{- if .Values.securityHeaders.hsts.enabled }}
    Strict-Transport-Security "max-age={{ .Values.securityHeaders.hsts.maxAge }}{{- if .Values.securityHeaders.hsts.includeSubDomains }}; includeSubDomains{{- end }}{{- if .Values.securityHeaders.hsts.preload }}; preload{{- end }}"
    {{- end }}
    {{- if .Values.securityHeaders.xContentTypeOptions }}
    X-Content-Type-Options "nosniff"
    {{- end }}
    {{- if .Values.securityHeaders.xFrameOptions }}
    X-Frame-Options "{{ .Values.securityHeaders.xFrameOptions }}"
    {{- end }}
    Referrer-Policy "{{ .Values.securityHeaders.referrerPolicy }}"
    {{- if .Values.securityHeaders.permissionsPolicy }}
    Permissions-Policy "{{ .Values.securityHeaders.permissionsPolicy }}"
    {{- end }}
    {{- if .Values.securityHeaders.removeServerHeader }}
    -Server
    {{- end }}
  }
  {{- end }}

  {{- if .Values.tracing.enabled }}
  tracing {
    span {{ .Values.tracing.spanName }}
  }
  {{- end }}

  {{- if .Values.forwardAuth.enabled }}
  forward_auth {{ .Values.forwardAuth.url }} {
    uri {{ .Values.forwardAuth.uri }}
    {{- range .Values.forwardAuth.copyHeaders }}
    copy_headers {{ . }}
    {{- end }}
  }
  {{- end }}

  {{- if .Values.plugins.cache.enabled }}
  cache {
    ttl {{ .Values.plugins.cache.ttl }}
  }
  {{- end }}
}

# ── Reverse proxy snippet with real-IP headers ──────────────────────────────────
# Usage:  import upstream <service>.<namespace>.svc.cluster.local:<port>
# Sets X-Real-IP and X-Forwarded-* for nginx-based backends (e.g. Mailu)
(upstream) {
  reverse_proxy {args[0]} {
    {{- if .Values.realIP.injectXRealIP }}
    header_up X-Real-IP {client_ip}
    header_up X-Forwarded-For {client_ip}
    header_up X-Forwarded-Proto https
    {{- end }}
  }
}

# ── Site routes (managed via ConfigMap caddy-routes) ───────────────────────────
import /etc/caddy/routes/*.caddy
{{- end }}
