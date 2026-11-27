# Testing

## Automated

```bash
tests/run.sh
```

The suite runs offline, as your user, in a temporary directory. It makes no
network requests: curl is replaced by a stub that returns canned responses, and
the no-route case runs inside an unprivileged network namespace
(`unshare -rn`). That case is skipped if your kernel does not allow those.

| Area | Checks |
|---|---|
| Syntax and manifest | `bash -n`, executable bit, manifest fields, `omarchy plugin validate` when available |
| Address validation | Public addresses accepted. Private, CGNAT, loopback, link-local, documentation, benchmarking, multicast and reserved ranges rejected. Leading zeros, extra text, IPv6, HTML, shell syntax and non-ASCII digits rejected. |
| Endpoints | Only plain `https://` URLs accepted from the override. Falls back to the defaults. Default order. |
| Lookup | Falls past failing, HTML, private-range, multi-line, oversized and shell-syntax responses to the first valid one, and stops there. Response content is never executed. curl is called with `-q -4 --fail --proto =https --tlsv1.2`, the timeouts and the size limit, without redirects. |
| State | Modes 0700/0600. Round trip. Tampered, malformed and symlinked state files are ignored or sanitised. |
| Status JSON | Valid JSON for ok, stale, offline and pending. Hostile strings (quotes, backslashes, markup, newlines) survive escaping exactly. Tooltip lines. |
| No route | `fetch` reports offline without calling curl and records the failed check. |
| Command line | Help, exit codes for bad commands and options, `get` with no cache. |

Run it before every commit.

## Manual

These need a running Omarchy shell with the widget enabled. Each one leaves
your network connection alone.

`H` stands for the helper:

```bash
H=~/.config/omarchy/plugins/lws.external-ip/bin/bar-external-ip
```

### Lookup and display

1. `"$H" fetch --force | jq '{state, ip, source}'` gives `"state": "ok"` and
   your address.
2. `curl -4 -s https://icanhazip.com` prints the same address.
3. The bar shows the address beside the network icon on every monitor. Hovering
   shows the tooltip, and makes no request: `checkedAt` in `"$H" status` does
   not change.

### Clicks

1. **Left click.** The address is on the clipboard (`wl-paste`), and an
   "External IP / Public IP copied" notification appears. This replaces your
   current clipboard.
2. **Right click.** `"$H" status | jq .checkedAt` changes within a second or
   two.

### Automatic refresh

Watch `checkedAt` advance about every 60 seconds:

```bash
while sleep 5; do "$H" status | jq -r '"\(now | strftime("%T")) checked \(.checkedAt | strftime("%T"))"'; done
```

### Refresh on network change, without touching your connection

Add a dummy interface that never becomes a default route. Bringing it up and
down changes the routing table, which the service sees as a network change,
while your real traffic keeps flowing through the same route.

```bash
nmcli connection add type dummy con-name extip-route-test ifname extiptest0 \
  connection.autoconnect no connection.permissions "user:$USER" \
  ipv4.method manual ipv4.addresses 192.0.2.250/32 ipv4.never-default yes \
  ipv6.method disabled
ip -4 route get 1.1.1.1                    # note the route
nmcli connection up extip-route-test       # a lookup follows about 3 s later
nmcli connection down extip-route-test     # and again
nmcli connection delete extip-route-test
ip -4 route get 1.1.1.1                    # same route as before
```

### Stale and offline, without going offline

1. **Stale.** Point the helper at an address that cannot resolve:
   ```bash
   BAR_EXTERNAL_IP_ENDPOINTS="https://unreachable.invalid" "$H" fetch --force | jq '{state, ip}'
   ```
   The bar keeps the last address in the theme's attention colour. The tooltip
   adds "(last known)" and "Lookups failing since …".
2. **Offline.** Also hide the cache first:
   ```bash
   mv "$XDG_RUNTIME_DIR/bar-external-ip/state.json" "$XDG_RUNTIME_DIR/bar-external-ip/state.json.saved"
   BAR_EXTERNAL_IP_ENDPOINTS="https://unreachable.invalid" "$H" fetch --force | jq '{state, label}'
   ```
   The bar shows `󰪎 Offline`.
3. **Recovery.** Right-click the widget, or run `"$H" refresh`. The widget
   returns to normal, then:
   ```bash
   rm -f "$XDG_RUNTIME_DIR/bar-external-ip/state.json.saved"
   ```
4. **No route at all.** This runs in a private, empty network namespace:
   ```bash
   unshare -rn env XDG_RUNTIME_DIR="$(mktemp -d)" "$H" fetch --force --from-bar | jq '{state, online}'
   ```
   It reports `offline`, instantly, and runs no curl.

### Shell integration

1. **Reloads.** `omarchy-shell shell rescanPlugins` and `omarchy restart shell`
   both bring the widget back. After each, `pgrep -af 'ip -4 -o monitor route
   rule'` lists exactly one process.
2. **Other modules.** `jq '.bar.layout' ~/.config/omarchy/shell.json` still
   lists every other widget, and they all still draw.
3. **Theme switching.** Use `omarchy theme set <other theme>`, then set your
   own theme back. The widget's colours follow live, and stale uses the new
   theme's attention colour.
4. **Interval.** `omarchy bar set lws.external-ip interval 120 --json`, then
   `omarchy-shell lws.external-ip info` reports `"refreshSeconds": 120`. Remove
   the key to go back to 60.
5. **Logs.** `qs log -p "$OMARCHY_PATH/shell" | grep -i external-ip` shows no
   errors.
