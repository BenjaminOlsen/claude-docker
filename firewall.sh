#!/bin/bash
# Outbound firewall for the Claude Docker container.
# Whitelists only the domains Claude needs; drops everything else.
#
# Requires NET_ADMIN capability on the container.
# Set FIREWALL_ENABLED=false to disable (default: true).
# Set FIREWALL_ALLOW_EXTRA="host1,host2" to whitelist additional domains.

set -euo pipefail

if [ "${FIREWALL_ENABLED:-true}" != "true" ]; then
    echo "  Firewall: DISABLED (FIREWALL_ENABLED=${FIREWALL_ENABLED})"
    return 0 2>/dev/null || exit 0
fi

# Resolve a domain to its IPs and add iptables rules
allow_domain() {
    local domain="$1"
    local ips
    ips=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u) || true
    for ip in $ips; do
        iptables -A OUTPUT -d "$ip" -j ACCEPT 2>/dev/null || true
    done
    echo "    + $domain ($( echo $ips | tr '\n' ' '))"
}

echo "  Firewall: configuring outbound rules..."

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true

# Allow loopback (localhost)
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established/related connections (responses to inbound SSH, etc.)
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (UDP and TCP port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# --- Required: Anthropic API ---
allow_domain "api.anthropic.com"
allow_domain "claude.ai"
allow_domain "console.anthropic.com"
allow_domain "statsig.anthropic.com"
allow_domain "sentry.io"

# --- Optional: package registries ---
# Uncomment the ones Claude needs based on your projects
allow_domain "registry.npmjs.org"
# allow_domain "pypi.org"
# allow_domain "files.pythonhosted.org"
# allow_domain "rubygems.org"
# allow_domain "proxy.golang.org"
# allow_domain "crates.io"
# allow_domain "static.crates.io"

# --- Optional: git hosts ---
# allow_domain "github.com"
# allow_domain "gitlab.com"

# --- Extra domains from environment ---
if [ -n "${FIREWALL_ALLOW_EXTRA:-}" ]; then
    IFS=',' read -ra EXTRA_DOMAINS <<< "$FIREWALL_ALLOW_EXTRA"
    for domain in "${EXTRA_DOMAINS[@]}"; do
        domain="$(echo "$domain" | xargs)"  # trim whitespace
        [ -n "$domain" ] && allow_domain "$domain"
    done
fi

# Drop everything else outbound
iptables -A OUTPUT -j DROP

echo "  Firewall: ENABLED (outbound restricted to whitelisted domains)"
echo "  Firewall: set FIREWALL_ENABLED=false or FIREWALL_ALLOW_EXTRA to adjust"
