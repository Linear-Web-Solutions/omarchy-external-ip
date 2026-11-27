# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-26

### Added

- Bar widget showing the public IPv4 address, using Omarchy's own widget
  components so it follows the theme, font and text size.
- Tooltip with:
  - the public IPv4 address
  - the local IPv4 address, interface and gateway
  - VPN status (WireGuard, OpenVPN, PPP, IPsec and other tunnels, policy
    routing included)
  - the last refresh time
- Left click copies the address with a notification; right click looks it up
  again.
- Lookups happen every 60 seconds (configurable from 15 to 3600 with the
  `interval` setting) and 2.5 seconds after IPv4 route or rule changes.
- One shared service for all monitors.
- HTTPS lookups that try api.ipify.org, then icanhazip.com, then
  checkip.amazonaws.com. Responses are strictly validated as a public IPv4
  address.
- If lookups fail, the last known address stays on screen in the theme's
  attention colour (stale), or the widget shows "Offline" when no address is
  known yet.
- Cache on tmpfs, written atomically. Lookups are serialised with `flock`.
- Command-line helper (`bin/bar-external-ip`) and shell IPC target
  (`lws.external-ip`).
- Offline test suite (`tests/run.sh`).

[1.0.0]: https://github.com/Linear-Web-Solutions/omarchy-external-ip/releases/tag/v1.0.0
