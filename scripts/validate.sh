#!/usr/bin/env bash
# =============================================================================
# validate.sh — Prove the Tailscale home-lab connectivity works
# =============================================================================
# Run this from any node that is on the tailnet.
# Edit the variables below to match your node names and domain.
#
# Usage:
#   chmod +x scripts/validate.sh
#   ./scripts/validate.sh
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
TAILNET="YOUR-TAILNET"                  # Tailscale MagicDNS network name
DOMAIN="yourdomain.com"                 # Your custom domain
N8N_NODE="n8n"                          # Tailscale MagicDNS node name
DOCKER_NODE="docker-server"             # Tailscale MagicDNS node name
POSTGRES_NODE="postgres"

PASS="\033[0;32m✓\033[0m"
FAIL="\033[0;31m✗\033[0m"
INFO="\033[0;34m→\033[0m"

check() {
  local description="$1"
  local command="$2"
  printf "  %-60s" "$description"
  if eval "$command" &>/dev/null; then
    echo -e "$PASS"
  else
    echo -e "$FAIL"
    return 1
  fi
}

# --- 1. Tailscale daemon ------------------------------------------------------
echo ""
echo "1. Tailscale daemon"
check "tailscale is running" "tailscale status"

# --- 2. Node reachability via MagicDNS ping -----------------------------------
echo ""
echo "2. Peer connectivity (MagicDNS ping)"
check "ping $DOCKER_NODE"    "tailscale ping --c=1 $DOCKER_NODE"
check "ping $N8N_NODE"       "tailscale ping --c=1 $N8N_NODE"
check "ping $POSTGRES_NODE"  "tailscale ping --c=1 $POSTGRES_NODE"

# --- 3. SSH via MagicDNS (checks TCP port 22, no full auth required) ----------
echo ""
echo "3. SSH reachability via MagicDNS"
ssh_check() {
  # nc -z = TCP port scan, no data sent; timeout 3s
  nc -z -w3 "$1" 22
}
check "SSH port open on $N8N_NODE"      "ssh_check $N8N_NODE"
check "SSH port open on $POSTGRES_NODE" "ssh_check $POSTGRES_NODE"

# --- 4. Tailscale Serve (n8n public endpoint) ---------------------------------
echo ""
echo "4. Tailscale Serve — n8n public endpoint"
N8N_URL="https://${N8N_NODE}.${TAILNET}.ts.net"
check "HTTPS cert valid on $N8N_URL" \
  "curl -sf --max-time 5 -o /dev/null '$N8N_URL'"
check "n8n health endpoint returns 200" \
  "curl -sf --max-time 5 -o /dev/null -w '%{http_code}' '${N8N_URL}/healthz' | grep -q 200"

# --- 5. Domain → Tailscale → NPM → service chain -----------------------------
echo ""
echo "5. Domain chain (Cloudflare → Tailscale → NPM → service)"
check "Nextcloud responds at cloud.$DOMAIN" \
  "curl -skL --max-time 5 -o /dev/null -w '%{http_code}' 'https://cloud.$DOMAIN' | grep -qE '2[0-9][0-9]|30[12]'"
check "Home Assistant responds at ha.$DOMAIN" \
  "curl -skL --max-time 5 -o /dev/null -w '%{http_code}' 'https://ha.$DOMAIN' | grep -qE '2[0-9][0-9]|30[12]'"

# --- 6. DNS resolution check --------------------------------------------------
echo ""
echo "6. DNS resolves *.${DOMAIN} to Tailscale IP (100.x.x.x)"
RESOLVED_IP=$(dig +short "cloud.$DOMAIN" | tail -1)
if [[ "$RESOLVED_IP" == 100.* ]]; then
  echo -e "  cloud.$DOMAIN resolves to $RESOLVED_IP   $PASS"
else
  echo -e "  cloud.$DOMAIN resolved to $RESOLVED_IP — expected 100.x.x.x  $FAIL"
fi

# --- Summary ------------------------------------------------------------------
echo ""
echo "Done. Review any ✗ failures above."
echo -e "${INFO} For full Tailscale node list: tailscale status"
echo -e "${INFO} For Serve config on n8n LXC: ssh $N8N_NODE 'tailscale serve status'"
