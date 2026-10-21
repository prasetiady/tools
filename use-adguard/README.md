# Use AdGuard DNS

A script that switches system DNS on [Omarchy](https://omarchy.org/) to [AdGuard DNS](https://adguard-dns.io/en/public-dns.html) over DNS over TLS (DoT). AdGuard DNS blocks ad and tracker domains.

DoT is required on networks that intercept plain DNS on port 53. On those networks, plain AdGuard DNS settings have no effect, because the network answers the queries instead of AdGuard.

## Requirements

- Omarchy (the script calls `omarchy-dns`)
- `systemd-resolved`
- `sudo` when you run the script in a terminal, or `pkexec` when you run it without one
- Port 853 open to `94.140.14.14` and `94.140.15.15`

## Usage

To switch to AdGuard DNS, run the script:

```bash
./use-adguard.sh
```

The script does these steps:

1. Sets the two AdGuard IPv4 servers with `omarchy-dns Custom`.
2. Sets `DNSOverTLS=yes` in `/etc/systemd/resolved.conf` and restarts `systemd-resolved`.
3. Checks that `ad.doubleclick.net` resolves to `::` or `0.0.0.0`. If it does not, the script prints a warning and exits with code 1.

You can run the script more than once. It replaces any earlier `DNSOverTLS=` line.

To run the script from anywhere, copy it to a directory on your `PATH`:

```bash
cp use-adguard.sh ~/.local/bin/use-adguard
```

## Limitations

- When you select a DNS provider in the Omarchy Wi-Fi panel or run `omarchy-dns`, `/etc/systemd/resolved.conf` is rewritten and the DoT setting is removed. Run the script again after you do this.
- DoT is in strict mode. If a network blocks port 853, DNS stops working. To restore DNS, select **DHCP** in the Wi-Fi panel.
- The script uses IPv4 servers only. The AdGuard TLS certificate does not list the IPv6 server addresses.
