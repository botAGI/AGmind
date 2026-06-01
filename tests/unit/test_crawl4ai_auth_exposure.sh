#!/usr/bin/env bash
# test_crawl4ai_auth_exposure.sh — ensure Crawl4AI is not exposed unauthenticated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONFIG_SH="${REPO_ROOT}/lib/config.sh"
NGINX_TEMPLATE="${REPO_ROOT}/templates/nginx.conf.template"
COMPOSE_TEMPLATE="${REPO_ROOT}/templates/docker-compose.yml"
ENV_TEMPLATE="${REPO_ROOT}/templates/env.lan.template"
REGISTRY_INDEX="${REPO_ROOT}/lib/_registry.indexed.sh"
REGISTRY_YAML="${REPO_ROOT}/templates/services/registry.yaml"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

echo "## test_crawl4ai_auth_exposure"

rg -q 'ENABLE_CRAWL4AI:-false.*ENABLE_AUTHELIA:-false' "${CONFIG_SH}" \
    || fail "Crawl4AI nginx block must only activate when Authelia is enabled"

crawl_auth_count="$(rg -c '#__CRAWL4AI__\s+#__AUTHELIA__auth_request /authelia-auth;' "${NGINX_TEMPLATE}" || true)"
[[ "${crawl_auth_count}" -ge 2 ]] \
    || fail "both Crawl4AI nginx locations must require Authelia auth_request"

crawl_auth_endpoint_count="$(rg -c '#__CRAWL4AI__\s+#__AUTHELIA__location = /authelia-auth' "${NGINX_TEMPLATE}" || true)"
[[ "${crawl_auth_endpoint_count}" -ge 2 ]] \
    || fail "both Crawl4AI nginx server blocks must define an Authelia auth endpoint"

rg -q '#__CRAWL4AI__\s+location = /health' "${NGINX_TEMPLATE}" \
    || fail "Crawl4AI mDNS vhost must keep an explicit health location"
rg -A4 '#__CRAWL4AI__\s+location = /health' "${NGINX_TEMPLATE}" | rg -q '#__AUTHELIA__auth_request /authelia-auth;' \
    || fail "Crawl4AI mDNS health endpoint must require Authelia"

# shellcheck disable=SC2016  # literal docker-compose variable syntax in regex
rg -q '\$\{CRAWL4AI_BIND_ADDR:-127\.0\.0\.1\}:\$\{EXPOSE_CRAWL4AI_PORT:-11235\}:11235' "${COMPOSE_TEMPLATE}" \
    || fail "nginx Crawl4AI port must bind to loopback by default"

rg -q '^CRAWL4AI_BIND_ADDR=127\.0\.0\.1$' "${ENV_TEMPLATE}" \
    || fail "default env must pin Crawl4AI host bind to loopback"

rg -q 'ENABLE_CRAWL4AI:-false.*ENABLE_AUTHELIA:-false.*names\+=\("agmind-crawl"\)' "${CONFIG_SH}" \
    || fail "mDNS must not advertise agmind-crawl.local unless the authenticated nginx vhost is active"

rg -q 'ENABLE_CRAWL4AI:-false.*ENABLE_AUTHELIA:-false.*wizard.summary.crawl4ai' "${REPO_ROOT}/lib/wizard.sh" \
    || fail "wizard summary must not advertise agmind-crawl.local unless the authenticated nginx vhost is active"

rg -q '\[agents\]="[^"]*ENABLE_AUTHELIA=true[^"]*ENABLE_CRAWL4AI=true' "${REGISTRY_INDEX}" \
    || fail "agents profile must force Authelia when it enables Crawl4AI"

rg -q 'agents: ".*ENABLE_AUTHELIA=true.*ENABLE_CRAWL4AI=true' "${REGISTRY_YAML}" \
    || fail "registry source must force Authelia when agents profile enables Crawl4AI"

rg -q 'ENABLE_CRAWL4AI:-false.*== "true"' "${REPO_ROOT}/lib/wizard.sh" \
    || fail "wizard must enforce Authelia for custom Crawl4AI selections"

echo "PASS: Crawl4AI exposure requires Authelia and defaults to loopback"
