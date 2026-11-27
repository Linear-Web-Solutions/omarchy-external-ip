# External IP for Omarchy

[![tests](https://github.com/Linear-Web-Solutions/omarchy-external-ip/actions/workflows/tests.yml/badge.svg)](https://github.com/Linear-Web-Solutions/omarchy-external-ip/actions/workflows/tests.yml)

A bar widget for the [Omarchy](https://omarchy.org/) shell that shows your
public IPv4 address, next to the network icon:

![The widget at the right end of the Omarchy bar, showing a globe icon and an example address](docs/screenshot.png)

<sub>Example address shown. Colours and font follow your theme.</sub>

Hover for connection details, click to copy, right-click to look it up again.
When a VPN is up it shows the VPN's exit address, because it follows the route
your traffic actually takes.

- Native Omarchy shell plugin: uses the bar's own button, icon and font
  components, so it follows your theme, font and text size live, on every
  monitor.
- One lookup per minute, shared by all monitors, plus one a few seconds after
  any network change (cable, Wi-Fi, VPN up or down, Tailscale exit node).
- Three HTTPS endpoints with fallback, strict response validation, no API keys.
- Nothing about your local network is ever sent anywhere. See
  [SECURITY.md](SECURITY.md).

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Using it](#using-it)
- [Configuration](#configuration)
- [Command line](#command-line)
- [How it works](#how-it-works)
- [Update](#update)
- [Uninstall](#uninstall)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Development](#development)
- [License](#license)

## Requirements

- Omarchy with the Quickshell-based Omarchy shell bar (tested on Omarchy 4.5.0).
- `bash`, `curl`, `jq`, `iproute2` (`ip`), `util-linux` (`flock`),
  `coreutils` and `wl-clipboard` (`wl-copy`). Omarchy installs all of these.
- Optional: NetworkManager's `nmcli`, used only to show the VPN connection's
  name in the tooltip.

No root access, daemon, systemd unit or account is needed.

## Install

```bash
omarchy plugin add https://github.com/Linear-Web-Solutions/omarchy-external-ip.git --enable
```

This clones the repository into `~/.config/omarchy/plugins/lws.external-ip/`,
validates it, and enables the widget. Plugins run inside your shell process, so
it asks you to confirm first; read the code if you like, it is short. It then
asks which bar section to use (default: right).

To put it right beside the network icon:

```bash
omarchy bar move lws.external-ip --before omarchy.network
```

To use the helper from a terminal (optional):

```bash
ln -s ~/.config/omarchy/plugins/lws.external-ip/bin/bar-external-ip ~/.local/bin/bar-external-ip
```

### Manual install

```bash
git clone https://github.com/Linear-Web-Solutions/omarchy-external-ip.git \
  ~/.config/omarchy/plugins/lws.external-ip
omarchy plugin validate ~/.config/omarchy/plugins/lws.external-ip
omarchy-shell shell rescanPlugins
sleep 1   # give the shell a moment to discover the plugin
omarchy plugin enable lws.external-ip --before omarchy.network
```

The directory must be named `lws.external-ip`, the plugin's id.

## Using it

| Action | Result |
|---|---|
| Look | Icon and public IPv4 address, in the bar's text colour and font |
| Hover | Connection details (below). Hovering makes no network request. |
| Left click | Copies the address and shows an Omarchy notification |
| Right click | Looks the address up again now |

The tooltip looks like this:

```
Public IPv4 203.0.113.42
Local IPv4 192.168.1.20
Interface wlan0 (Wi-Fi)
Gateway 192.168.1.1
VPN Office (WireGuard on wg0, 10.8.0.2)
Last refresh 14:02:11 via api.ipify.org

Click to copy · Right-click to refresh
```

The VPN line reads `VPN off` with no VPN, or `VPN not routing internet traffic
(tailscale0 up)` when a tunnel is up but your traffic does not go through it.

### States

| State | Bar shows | Meaning |
|---|---|---|
| ok | `󰖟 203.0.113.42` | Last lookup succeeded |
| stale | `󰖟 203.0.113.42` in the theme's attention colour | Lookups are failing; this is the last known address. The tooltip says since when. |
| offline | `󰪎 Offline` in the attention colour | Lookups are failing and no address is known yet |
| pending | `󰖟`, dimmed | The first lookup since login is still running |

The next successful lookup returns the widget to normal by itself. On a
vertical bar the widget shows the icon only, as the built-in widgets do.

## Configuration

**Refresh interval** in seconds, from 15 to 3600 (default 60):

```bash
omarchy bar set lws.external-ip interval 120 --json
```

This writes `"interval": 120` into the widget's entry in
`~/.config/omarchy/shell.json`, which takes effect immediately. Remove the key
to go back to 60. Lookups after network changes happen regardless.

**Position**: drag the widget along the bar, or:

```bash
omarchy bar move lws.external-ip --before omarchy.network
omarchy bar move lws.external-ip --section centerEnd
```

**Colours, font and size** come from the bar and theme; the widget sets none of
its own.

- Normal text uses the theme's `[bar] text`. Stale and offline use `[bar]
  active`, the colour other bar widgets use for attention. To change it for
  every theme, set it in `~/.config/omarchy/shell.toml` (this also affects the
  other widgets):
  ```toml
  [bar]
  active = "#e06c75"
  ```
- Font: `omarchy font set <name>`. Size: `[font] base-size` in
  `~/.config/omarchy/shell.toml`.

**Endpoints**: the defaults are `DEFAULT_ENDPOINTS` near the top of
`bin/bar-external-ip`: `https://api.ipify.org`, then `https://icanhazip.com`,
then `https://checkip.amazonaws.com`. Any service that answers a plain GET
with the address as text works. For a one-off run, set
`BAR_EXTERNAL_IP_ENDPOINTS` to space-separated `https://` URLs:

```bash
BAR_EXTERNAL_IP_ENDPOINTS="https://icanhazip.com" bar-external-ip fetch --force
```

Only plain `https://host[:port][/path]` URLs are accepted; anything else is
ignored with a warning.

## Command line

The helper is `bin/bar-external-ip` (or `bar-external-ip` if you made the
symlink above).

```bash
bar-external-ip fetch --force   # look up now, print status JSON, update the bar
bar-external-ip status          # status JSON from the cache plus live local details; no request
bar-external-ip get             # print the cached address; exit 1 if there is none
bar-external-ip copy            # copy the cached address and show a notification
bar-external-ip refresh         # ask the running widget to look up now
bar-external-ip help
```

`fetch` without `--force` reuses a result less than 10 seconds old.

The running service also answers on the shell's IPC:

```bash
omarchy-shell lws.external-ip refresh   # same as a right click
omarchy-shell lws.external-ip copy      # same as a left click
omarchy-shell lws.external-ip status    # last status JSON
omarchy-shell lws.external-ip info      # interval, lookup running, route monitor running, helper path
omarchy-shell lws.external-ip reload    # re-read cache and local details; no request
```

### Status JSON

```json
{
  "state": "ok",
  "ip": "203.0.113.42",
  "label": "203.0.113.42",
  "text": "󰖟 203.0.113.42",
  "tooltip": "Public IPv4 203.0.113.42\n...",
  "class": "",
  "alt": "ok",
  "source": "api.ipify.org",
  "updatedAt": 1700000000,
  "checkedAt": 1700000000,
  "failedSince": 0,
  "online": true,
  "local": { "address": "192.168.1.20", "interface": "wlan0", "type": "Wi-Fi", "gateway": "192.168.1.1" },
  "vpn": { "active": true, "interface": "wg0", "kind": "WireGuard", "name": "Office", "address": "10.8.0.2" },
  "otherTunnels": []
}
```

`state` is `ok`, `stale`, `offline` or `pending`. `class` is `stale` or
`offline` when the widget should draw attention, otherwise empty. Times are
Unix seconds; `0` means never. `text`, `tooltip`, `class` and `alt` use Waybar's
custom-module field names.

## How it works

```
 bar on each monitor              one shell service                 helper script
 BarWidget.qml  ── binds to ──►  Service.qml  ── runs async ──►  bin/bar-external-ip
  icon + label                    60 s timer                        fetch / status / copy
  tooltip                         ip -4 monitor route rule          curl -4 over HTTPS
  clicks ───────────────────────► refresh / copy                    validate, cache, JSON
                                  IPC target lws.external-ip        state in $XDG_RUNTIME_DIR
```

**Helper** (`bin/bar-external-ip`, bash). Does every lookup and holds all
the logic, so whatever the widget shows can be reproduced in a terminal.

- It tries each endpoint in turn, over IPv4 and HTTPS only, with a 3 s connect
  and 5 s total timeout. It follows no redirects and ignores `~/.curlrc`.
- It reads at most 64 bytes. The answer must be exactly one canonical, publicly
  routable dotted quad. HTML, private or reserved ranges, extra text and
  non-ASCII digits are all rejected, and the next endpoint is tried.
- Nothing returned is evaluated. All JSON is built with `jq --arg`.
- State is kept in `$XDG_RUNTIME_DIR/bar-external-ip/state.json`. That
  directory is tmpfs (RAM) with mode 0700, the file is replaced atomically, and
  it disappears at logout.
- An exclusive `flock` stops lookups from overlapping.
- When there is no route to the internet at all, curl is not run.

**Local details** come from local commands only:

- `ip route get` (a lookup in the kernel's routing table; no packet is sent)
- `ip route` and `ip -d link`
- optionally `nmcli`, for the VPN connection's name

The egress interface is whatever the kernel would actually use to reach the
internet, policy routing included. That is why WireGuard setups that use their
own routing table (wg-quick and many VPN apps) and Tailscale exit nodes are
detected correctly. The "Local IPv4", "Interface" and "Gateway" lines describe
the physical uplink under any VPN.

**Service** (`Service.qml`). There is one per shell, however many monitors you
have. It owns:

- the refresh timer
- a single `ip -4 -o monitor route rule` child process, which sleeps on a
  netlink socket and wakes on IPv4 route or policy-rule changes
- the lookup process

Because of that, four monitors still mean one request per cycle. Route changes
arrive in bursts, so a lookup runs 2.5 s after they settle, and network-change
lookups are at least 5 s apart. Requests made while a lookup is running collapse
into one follow-up. A watchdog stops a lookup that hangs for more than 45 s.

**Widget** (`BarWidget.qml`). It is built from Omarchy's `WidgetButton` and
`OpticalGlyph`, so it is sized, spaced and coloured exactly like the built-in
icons around it. Text is always drawn as plain text, so nothing in a tooltip or
label can be interpreted as markup.

## Update

```bash
omarchy plugin update lws.external-ip
```

This shows the incoming diff, asks before applying it, and re-validates the
plugin. Saved changes hot-reload; restart the shell (`omarchy restart shell`)
afterwards so the IPC commands pick up any change to `Service.qml`.

## Uninstall

```bash
omarchy plugin remove lws.external-ip
rm -f ~/.local/bin/bar-external-ip                  # only if you made the symlink
rm -rf "$XDG_RUNTIME_DIR/bar-external-ip"           # cached state; also gone at logout
```

`omarchy plugin remove` disables the widget, takes it off the bar and deletes
the checkout. Nothing else on the system was changed by installing it.

## Troubleshooting

```bash
# Installed, valid and enabled?
omarchy plugin list | grep external-ip
omarchy plugin validate ~/.config/omarchy/plugins/lws.external-ip
jq '.bar.layout.right' ~/.config/omarchy/shell.json

# Does the helper work on its own?
~/.config/omarchy/plugins/lws.external-ip/bin/bar-external-ip fetch --force | jq '{state, ip, source}'
curl -4 -s https://api.ipify.org; echo

# Is the service running? Exactly one route monitor should exist.
omarchy-shell lws.external-ip info | jq .
pgrep -af 'ip -4 -o monitor route rule'

# Shell log lines from the plugin
qs log -p "$OMARCHY_PATH/shell" | grep -i external-ip
```

- **Stale or offline while the internet works.** Run the helper by hand. A
  captive portal, a firewall that blocks the endpoints, or rate limiting shows
  up as `"state": "stale"`. Try another endpoint with
  `BAR_EXTERNAL_IP_ENDPOINTS`.
- **"Function not found" from `omarchy-shell lws.external-ip ...`** after
  editing or updating `Service.qml`. The shell keeps the old IPC method list
  until it restarts: run `omarchy restart shell`.
- **Widget stays dimmed.** The first lookup has not finished. `info` shows
  whether a lookup is running and which helper path is in use.

## Limitations

- **IPv4 only, by design.** On an IPv6-only network the widget shows Offline.
- **Proxy-style VPNs are not detected.** A SOCKS or HTTP proxy, a browser
  extension or a per-app split tunnel does not change the system route. The
  widget then reports `VPN off` and shows the system's address, not that app's.
- **Tooltip details can be slightly old.** Local details are refreshed with each
  lookup and on every route change, so they are at most one interval old.
- **English only.** The tooltip and notification text are not translated.
- **Lookups go to third parties.** The endpoint operators see your public
  address and a request about once a minute. See [SECURITY.md](SECURITY.md).

## Development

```
.
├── manifest.json          plugin manifest (kinds: service, bar-widget)
├── Service.qml            shared service: timer, route monitor, IPC
├── BarWidget.qml          the bar widget
├── bin/bar-external-ip    helper: lookup, validation, cache, JSON, copy
├── tests/run.sh           offline test suite
├── docs/TESTING.md        how to test by hand without touching your connection
└── .github/workflows/     CI: ShellCheck and tests/run.sh on every push and pull request
```

Work on a checkout in `~/.config/omarchy/plugins/lws.external-ip`. Saving a
QML file reloads the plugin immediately.

```bash
tests/run.sh                                   # 130+ offline checks; makes no network requests
omarchy plugin validate .
```

`tests/run.sh` replaces curl with a stub. It checks:

- address validation, endpoint filtering and fallback
- that response content is never executed
- curl's safety flags
- state-file tampering, JSON escaping and every widget state
- the no-route path, in an unprivileged network namespace

[docs/TESTING.md](docs/TESTING.md) covers the manual checks: clicks,
notifications, network-change refresh, stale and offline display, and theme
changes.

## License

[MIT](LICENSE) © 2026 Linear Web Solutions
