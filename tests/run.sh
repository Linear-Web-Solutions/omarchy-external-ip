#!/bin/bash
#
# Offline test suite for the External IP widget. Makes no network requests:
# curl is replaced by a stub, and the no-route case runs in an unprivileged
# network namespace when the kernel allows one.
#
# Usage: tests/run.sh

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
HELPER=$ROOT/bin/bar-external-ip

pass=0 fail=0 skip=0
ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  printf 'FAIL: %s\n' "$*"
}
skipped() {
  skip=$((skip + 1))
  printf 'skip: %s\n' "$*"
}
section() { printf '%s\n' "-- $*"; }

for tool in jq bash; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "tests: $tool is required" >&2
    exit 1
  }
done

WORK=$(mktemp -d) || exit 1
trap 'rm -rf -- "$WORK"' EXIT
mkdir -m 700 "$WORK/runtime" "$WORK/stub"

# ------------------------------------------------------------ syntax
section "syntax"
for file in "$HELPER" "$ROOT/tests/run.sh"; do
  if bash -n "$file"; then ok; else bad "bash -n $file"; fi
done
if [[ -x $HELPER ]]; then ok; else bad "helper is not executable"; fi

# ---------------------------------------------------------- manifest
section "manifest"
if jq -e '
  .schemaVersion == 1 and .id == "lws.external-ip"
  and (.kinds | index("service")) != null and (.kinds | index("bar-widget")) != null
  and .entryPoints.service == "Service.qml" and .entryPoints.barWidget == "BarWidget.qml"
' "$ROOT/manifest.json" >/dev/null; then ok; else bad "manifest.json fields"; fi
for file in Service.qml BarWidget.qml; do
  [[ -f $ROOT/$file ]] && ok || bad "missing $file"
done
for file in "$ROOT/Service.qml" "$ROOT/BarWidget.qml" "$HELPER"; do
  if grep -q 'lws.external-ip' "$file"; then ok; else bad "plugin id missing from $file"; fi
done
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  if omarchy-plugin-validate "$ROOT"; then ok; else bad "omarchy-plugin-validate"; fi
else
  skipped "omarchy-plugin-validate not installed"
fi

# Source the helper's functions with an isolated state directory.
export XDG_RUNTIME_DIR=$WORK/runtime
unset BAR_EXTERNAL_IP_ENDPOINTS
# shellcheck source=../bin/bar-external-ip
source "$HELPER"

# --------------------------------------------------- address validation
section "public IPv4 validation"
expect_public() {
  local want=$1 got
  shift
  for ip in "$@"; do
    if valid_public_ipv4 "$ip"; then got=accept; else got=reject; fi
    if [[ $got == "$want" ]]; then ok; else bad "$(printf 'valid_public_ipv4 %q: want %s, got %s' "$ip" "$want" "$got")"; fi
  done
}
expect_public accept 8.8.8.8 1.1.1.1 9.9.9.9 52.95.110.1 100.63.255.255 100.128.0.1 \
  172.15.0.1 172.32.0.1 192.0.1.1 223.255.255.254
expect_public reject \
  "" 10.0.0.1 127.0.0.1 192.168.1.1 172.16.5.4 172.31.255.255 100.64.0.1 100.127.1.1 \
  169.254.1.1 0.1.2.3 224.0.0.1 255.255.255.255 240.0.0.1 192.0.2.1 198.51.100.7 \
  203.0.113.42 198.18.0.1 192.0.0.8 256.1.1.1 1.2.3 1.2.3.4.5 01.2.3.4 1.2.3.04 \
  " 1.2.3.4" "1.2.3.4 " "1.2.3.4x" "<html>" '1.2.3.4;id' '$(id)' $'1.2.3.4\n5.6.7.8' \
  "::1" "2001:db8::1" "1.2.3.-1" "１.2.3.4" "1.2.3.４" '<img src="https://example.invalid/x">'

section "local IPv4 validation"
for ip in 10.0.0.1 192.168.1.20 100.64.0.1 8.8.8.8; do
  if valid_local_ipv4 "$ip"; then ok; else bad "valid_local_ipv4 $ip rejected"; fi
done
for ip in "" 1.2.3 300.1.1.1 "１.2.3.4" "10.0.0.1/24" "fe80::1"; do
  if valid_local_ipv4 "$ip"; then bad "valid_local_ipv4 '$ip' accepted"; else ok; fi
done

section "interface names"
for name in eth0 wlan0 enp0s31f6 wg-home wg0 tailscale0; do
  if valid_ifname "$name"; then ok; else bad "valid_ifname $name rejected"; fi
done
for name in "" "a b" 'x;id' "averyveryverylongname" $'eth0\n'; do
  if valid_ifname "$name"; then bad "$(printf 'valid_ifname %q accepted' "$name")"; else ok; fi
done

# ---------------------------------------------------------- endpoints
section "endpoint list"
BAR_EXTERNAL_IP_ENDPOINTS="http://plain.example https://ok.example/ip file:///etc/passwd https://query.example/?q=1 https://port.example:8443/v4 https://user@at.example"
load_endpoints 2>/dev/null
if [[ ${ENDPOINTS[*]} == "https://ok.example/ip https://port.example:8443/v4" ]]; then ok; else bad "endpoint filter kept: ${ENDPOINTS[*]}"; fi
BAR_EXTERNAL_IP_ENDPOINTS="ftp://x.example javascript:alert(1)"
load_endpoints 2>/dev/null
if [[ ${ENDPOINTS[*]} == "$DEFAULT_ENDPOINTS" ]]; then ok; else bad "no valid override should fall back to defaults"; fi
unset BAR_EXTERNAL_IP_ENDPOINTS
load_endpoints
if [[ ${ENDPOINTS[*]} == "https://api.ipify.org https://icanhazip.com https://checkip.amazonaws.com" ]]; then ok; else bad "default endpoint order"; fi
if [[ $(endpoint_host https://port.example:8443/v4) == port.example ]]; then ok; else bad "endpoint_host"; fi

# ------------------------------------------------------------- lookup
section "lookup (stubbed curl)"
cat >"$WORK/stub/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$CURL_LOG"
url=${!#}
case $url in
  https://fail.example*) exit 22 ;;
  https://html.example*) printf '<html><body>8.8.8.8</body></html>' ;;
  https://private.example*) printf '10.0.0.1\n' ;;
  https://two.example*) printf '8.8.8.8\n8.8.4.4\n' ;;
  https://command.example*) printf '$(touch %s/pwned)\n' "${CURL_LOG%/*}" ;;
  https://long.example*) printf '1.2.3.4%.0s' {1..20} ;;
  https://good.example*) printf ' 8.8.4.4\r\n' ;;
  https://other.example*) printf '9.9.9.9\n' ;;
esac
STUB
chmod 755 "$WORK/stub/curl"
export CURL_LOG=$WORK/curl.log
ORIG_PATH=$PATH
PATH="$WORK/stub:$PATH"
hash -r

ENDPOINTS=(https://fail.example https://html.example https://private.example https://two.example
  https://command.example https://long.example https://good.example https://other.example)
if lookup_public_ip && [[ $FOUND_IP == 8.8.4.4 && $FOUND_SOURCE == good.example ]]; then
  ok
else
  bad "fallback should skip bad responses and stop at good.example (got '$FOUND_IP' via '$FOUND_SOURCE')"
fi
if [[ ! -e $WORK/pwned ]]; then ok; else bad "response content was executed"; fi
if [[ $(wc -l <"$CURL_LOG") -eq 7 ]]; then ok; else bad "expected 7 requests, got $(wc -l <"$CURL_LOG")"; fi
if ! grep -q 'other.example' "$CURL_LOG"; then ok; else bad "lookup continued after a valid answer"; fi
first=$(head -n 1 "$CURL_LOG")
for flag in "-q" "-4" "--fail" "--proto =https" "--tlsv1.2" "--max-filesize 64" "--max-time 5" "--connect-timeout 3"; do
  if [[ " $first " == *" $flag "* ]]; then ok; else bad "curl call lacks $flag"; fi
done
if [[ $first != *--location* && $first != *" -L "* ]]; then ok; else bad "curl must not follow redirects"; fi

ENDPOINTS=(https://fail.example https://html.example)
if lookup_public_ip; then bad "all-bad endpoints should fail"; else ok; fi

PATH=$ORIG_PATH
hash -r

# -------------------------------------------------------------- state
section "state file"
ensure_state_dir || bad "ensure_state_dir"
if [[ $(stat -c %a "$STATE_DIR") == 700 ]]; then ok; else bad "state directory mode is $(stat -c %a "$STATE_DIR")"; fi

CACHED_IP=8.8.8.8 SOURCE=api.example UPDATED_AT=100 CHECKED_AT=200 FAILED_SINCE=0
save_state || bad "save_state"
if [[ $(stat -c %a "$STATE_FILE") == 600 ]]; then ok; else bad "state file mode is $(stat -c %a "$STATE_FILE")"; fi
load_state
if [[ $CACHED_IP == 8.8.8.8 && $SOURCE == api.example && $UPDATED_AT == 100 && $CHECKED_AT == 200 ]]; then ok; else bad "state round trip"; fi

printf '%s' '{"ip":"1.2.3.4;id","source":"x","updatedAt":5,"checkedAt":6,"failedSince":0}' >"$STATE_FILE"
load_state
if [[ -z $CACHED_IP && $UPDATED_AT == 0 && $CHECKED_AT == 6 ]]; then ok; else bad "tampered ip should be dropped"; fi

printf '%s' '{"ip":"8.8.8.8","source":"evil\"$(id)`x`","updatedAt":"1;id","checkedAt":7,"failedSince":0}' >"$STATE_FILE"
load_state
if [[ $CACHED_IP == 8.8.8.8 && $SOURCE =~ ^[A-Za-z0-9.-]+$ && $UPDATED_AT =~ ^[0-9]+$ ]]; then ok; else bad "tampered fields should be sanitised (source '$SOURCE', updatedAt '$UPDATED_AT')"; fi

printf 'not json' >"$STATE_FILE"
load_state
if [[ -z $CACHED_IP && $CHECKED_AT == 0 ]]; then ok; else bad "unreadable state should load as empty"; fi

rm -f -- "$STATE_FILE"
printf '%s' '{"ip":"8.8.8.8","source":"x","updatedAt":1,"checkedAt":1,"failedSince":0}' >"$WORK/elsewhere.json"
ln -s "$WORK/elsewhere.json" "$STATE_FILE"
load_state
if [[ -z $CACHED_IP ]]; then ok; else bad "symlinked state file should be ignored"; fi
rm -f -- "$STATE_FILE"

# ------------------------------------------------------------- routes
section "route parsing"
route="1.1.1.1 via 192.168.1.1 dev wlan0 table 51820 src 192.168.1.20 uid 1000"
if [[ $(route_field dev "$route") == wlan0 && $(route_field src "$route") == 192.168.1.20 &&
  $(route_field via "$route") == 192.168.1.1 ]]; then ok; else bad "route_field"; fi
if route_field metric "$route" >/dev/null; then bad "route_field should fail on a missing key"; else ok; fi
for pair in wireguard:WireGuard tun:TUN ovpn-dco:OpenVPN xfrm:IPsec gre:"IP tunnel"; do
  if [[ $(kind_label "${pair%%:*}") == "${pair#*:}" ]]; then ok; else bad "kind_label ${pair%%:*}"; fi
done

# ------------------------------------------------------------- output
section "status JSON"
set_network() {
  NET_ONLINE=true PHYS_DEV=eth0 PHYS_SRC=192.168.1.20 PHYS_GW=192.168.1.1 PHYS_TYPE=Ethernet
  VPN_ACTIVE=false VPN_DEV="" VPN_KIND="" VPN_NAME="" VPN_ADDR=""
  OTHER_TUNNELS=()
}
now=$(now_epoch)

set_network
CACHED_IP=8.8.8.8 SOURCE=api.ipify.org UPDATED_AT=$now CHECKED_AT=$now FAILED_SINCE=0
VPN_ACTIVE=true VPN_DEV=wg0 VPN_KIND=WireGuard VPN_ADDR=10.2.0.2
VPN_NAME=$'Work "VPN" \\ <b>bold</b> & co\nsecond line'
out=$(print_status)
if jq -e . >/dev/null <<<"$out"; then ok; else bad "print_status is not valid JSON"; fi
if [[ $(jq -r '.vpn.name' <<<"$out") == "$VPN_NAME" ]]; then ok; else bad "VPN name did not survive JSON escaping"; fi
if jq -e '.state == "ok" and .class == "" and .ip == "8.8.8.8" and .label == "8.8.8.8" and .online == true
  and .local.interface == "eth0" and .vpn.active == true and .vpn.interface == "wg0"' >/dev/null <<<"$out"; then ok; else bad "ok status fields"; fi
tooltip=$(jq -r '.tooltip' <<<"$out")
for line in "Public IPv4 8.8.8.8" "Local IPv4 192.168.1.20" "Interface eth0 (Ethernet)" "Gateway 192.168.1.1" \
  "VPN Work \"VPN\"" "via api.ipify.org" "Click to copy · Right-click to refresh"; do
  if [[ $tooltip == *"$line"* ]]; then ok; else bad "tooltip lacks '$line'"; fi
done

set_network
CACHED_IP=8.8.8.8 SOURCE=api.ipify.org UPDATED_AT=$((now - 300)) CHECKED_AT=$now FAILED_SINCE=$((now - 120))
out=$(print_status)
if jq -e '.state == "stale" and .class == "stale" and .ip == "8.8.8.8"' >/dev/null <<<"$out"; then ok; else bad "stale status"; fi
if [[ $(jq -r .tooltip <<<"$out") == *"(last known)"*"Lookups failing since"* ]]; then ok; else bad "stale tooltip"; fi

set_network
NET_ONLINE=false PHYS_DEV="" PHYS_SRC="" PHYS_GW="" PHYS_TYPE=""
CACHED_IP="" SOURCE="" UPDATED_AT=0 CHECKED_AT=$now FAILED_SINCE=$now
out=$(print_status)
if jq -e '.state == "offline" and .class == "offline" and .label == "Offline" and .online == false' >/dev/null <<<"$out"; then ok; else bad "offline status"; fi
if [[ $(jq -r .tooltip <<<"$out") == *"No network connection"*"Offline since"* ]]; then ok; else bad "offline tooltip"; fi

set_network
CACHED_IP="" SOURCE="" UPDATED_AT=0 CHECKED_AT=0 FAILED_SINCE=0
OTHER_TUNNELS=(tailscale0 wg1)
out=$(print_status)
if jq -e '.state == "pending" and .label == "" and .otherTunnels == ["tailscale0","wg1"]' >/dev/null <<<"$out"; then ok; else bad "pending status"; fi
if [[ $(jq -r .tooltip <<<"$out") == *"VPN not routing internet traffic (tailscale0, wg1 up)"* ]]; then ok; else bad "idle tunnel tooltip"; fi

# --------------------------------------------------------- no route
section "fetch with no route (network namespace)"
if command -v unshare >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
  mkdir -m 700 "$WORK/runtime-netns"
  : >"$CURL_LOG"
  out=$(unshare -rn env PATH="$WORK/stub:$ORIG_PATH" CURL_LOG="$CURL_LOG" \
    XDG_RUNTIME_DIR="$WORK/runtime-netns" "$HELPER" fetch --force --from-bar)
  if jq -e '.state == "offline" and .online == false' >/dev/null <<<"$out"; then ok; else bad "no-route fetch should report offline: $out"; fi
  if [[ ! -s $CURL_LOG ]]; then ok; else bad "no-route fetch should not call curl"; fi
  if [[ -f $WORK/runtime-netns/bar-external-ip/state.json ]]; then ok; else bad "no-route fetch should record the failed check"; fi
else
  skipped "unprivileged network namespaces unavailable"
fi

# ---------------------------------------------------------- commands
section "command line"
if "$HELPER" help | grep -q '^Usage: bar-external-ip'; then ok; else bad "help"; fi
"$HELPER" bogus >/dev/null 2>&1
if [[ $? == 2 ]]; then ok; else bad "unknown command should exit 2"; fi
"$HELPER" fetch --bogus >/dev/null 2>&1
if [[ $? == 2 ]]; then ok; else bad "unknown fetch option should exit 2"; fi
if XDG_RUNTIME_DIR="$WORK/runtime" "$HELPER" get >/dev/null 2>&1; then bad "get with no cache should fail"; else ok; fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
((fail == 0))
