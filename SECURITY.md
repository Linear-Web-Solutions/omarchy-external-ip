# Security and privacy

The widget runs as your desktop user and needs no root access. It contacts the
internet for one reason: to ask a public service what address your connection
appears to come from. This document lists exactly what leaves the machine, what
stays local, and how untrusted input is handled.

## What is sent

Each lookup is one HTTPS GET, made with curl, to one endpoint at a time.
Endpoints are tried in this order, and the first valid answer stops the
sequence:

1. `https://api.ipify.org`
2. `https://icanhazip.com`
3. `https://checkip.amazonaws.com`

A request carries:

- the TLS handshake, including the endpoint's host name (SNI)
- `GET /` with the endpoint's `Host` header
- `Accept: text/plain`
- curl's default `User-Agent` (`curl/<version>`)

That is all. No cookies, no query string, no body, no API key. Your `~/.curlrc`
is ignored (`curl -q`), so a personal curl setup cannot add headers. curl still
honours the standard proxy environment variables (`https_proxy`, `all_proxy`)
if you set them.

The endpoint operator therefore learns:

- your public IPv4 address, which every server you contact sees anyway
- that a request arrives about once a minute, plus one after each network change
- the curl version

**Never sent anywhere:**

- local IP addresses and interface names
- gateway addresses, MAC addresses and the hostname
- VPN connection names
- anything else about the local network

That information is read with `ip` and `nmcli` and only ever appears in the
helper's standard output, the shell's tooltip and the IPC replies, all on this
machine.

## What is trusted, and what is not

**Endpoint responses are untrusted.**

- curl runs with `--proto =https`, `--tlsv1.2`, `--fail`, no redirects, a 3 s
  connect and 5 s total timeout, and `--max-filesize 64`. The output is cut to
  64 bytes regardless.
- The body must be exactly one canonical dotted-quad IPv4 address, optionally
  surrounded by whitespace. It must have no leading zeros and only ASCII
  digits; bracket ranges like `[0-9]` can match other digits in UTF-8 locales,
  so an explicit `0123456789` check runs first.
- It must also be publicly routable. Private, shared (CGNAT), loopback,
  link-local, documentation, benchmarking, multicast and reserved ranges are
  rejected, since no server on the internet could have seen such an address.
- Anything else, such as HTML, captive-portal pages, error text or multiple
  addresses, is discarded and the next endpoint is tried.
- Response data is never evaluated, sourced, passed to a shell, or used in a
  command line. JSON output is produced with `jq --arg`, so every value is
  escaped. The widget draws all text with `Text.PlainText`, so nothing can be
  interpreted as markup.

**The local state file is treated as untrusted too.**

- State lives in `$XDG_RUNTIME_DIR/bar-external-ip/`, a per-user tmpfs
  directory. The helper creates it with mode 0700 and uses a umask of 077.
- It refuses a symlinked state directory and ignores a symlinked state file.
- If `$XDG_RUNTIME_DIR` is missing or not owned by you, it falls back to
  `~/.cache/bar-external-ip/`.
- Every field read back is stripped of unexpected characters and validated
  again, so a tampered file cannot inject anything.
- Writes go to a `mktemp` file in the same directory, which is then renamed
  into place.

**Endpoint overrides are validated.** `BAR_EXTERNAL_IP_ENDPOINTS` accepts only
plain `https://host[:port][/path]` URLs. Anything with a query, credentials,
another scheme or unusual characters is ignored.

## Processes

- **Nothing is persistent outside the shell.** No daemon, systemd unit, timer
  or cron job is installed.
- **One long-lived child process.** While the shell runs, there is one
  `ip -4 -o monitor route rule`. It listens on a netlink socket and sends
  nothing.
- **Lookups never overlap.** An exclusive `flock` serialises them. The service
  runs at most one at a time and stops any that hangs for more than 45 seconds.
- **No root, ever.** Nothing in the plugin uses `sudo`, `pkexec`, setuid
  binaries or elevated capabilities. The tests use an unprivileged user and
  network namespace (`unshare -rn`).
- **The clipboard only ever gets the public address.** The copy action puts it
  there with `wl-copy`; the notification shows the same address.

## Trusting the plugin

Omarchy shell plugins run unsandboxed inside the long-lived shell process, with
your user's permissions. Review the code before you enable any plugin, this one
included. It is under 1000 lines across `Service.qml`, `BarWidget.qml` and
`bin/bar-external-ip`.

`omarchy plugin update` shows the full diff before applying an update.

## Reporting a vulnerability

Please report security problems privately. Use **Report a vulnerability** on
the repository's **Security** tab
(<https://github.com/Linear-Web-Solutions/omarchy-external-ip/security/advisories/new>),
not a public issue. Include steps to reproduce and the affected version from
`manifest.json`.
