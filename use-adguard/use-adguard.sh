#!/bin/bash
# Switch system DNS to AdGuard over DNS-over-TLS.
# Plain DNS on port 53 is intercepted on this network, so DoT is required.
# Any DNS pill in the Omarchy Wi-Fi panel rewrites resolved.conf; run this again after.

set -euo pipefail

SERVERS="94.140.14.14#dns.adguard-dns.com 94.140.15.15#dns.adguard-dns.com"

# sudo needs a terminal for its password prompt; fall back to polkit without one.
if [[ -t 0 ]]; then elevate=sudo; else elevate=pkexec; fi

printf '%s\n' "$SERVERS" | omarchy-dns Custom >/dev/null
$elevate sh -c 'sed -i "/^DNSOverTLS=/d" /etc/systemd/resolved.conf &&
  echo "DNSOverTLS=yes" >> /etc/systemd/resolved.conf &&
  systemctl restart systemd-resolved'

sleep 2
resolvectl flush-caches
answer=$(resolvectl query ad.doubleclick.net 2>&1 | head -1 | awk '{print $2}')
if [[ $answer == "::" || $answer == "0.0.0.0" ]]; then
  echo "AdGuard DNS over TLS is active (ad.doubleclick.net -> $answer)."
else
  echo "Warning: ad.doubleclick.net resolved to '$answer'; AdGuard is not filtering." >&2
  echo "If DNS is down, select DHCP in the Wi-Fi panel." >&2
  exit 1
fi
