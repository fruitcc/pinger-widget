# Pinger

A tiny macOS menu bar app that shows your internet health as a colored dot.

- **Green** — connected, latency and packet loss under the yellow thresholds
- **Yellow** — degraded (loss or average latency over the yellow thresholds)
- **Red** — down (loss or average latency over the red thresholds, or all recent pings failed)
- **Gray** — starting up / no data yet

It pings a host (default `8.8.8.8`) every N seconds (default 2s) by invoking
`/sbin/ping`, and evaluates health over a sliding window of the last 10 pings.

**Left-click** the dot for the results panel:

- current status, average latency, and packet loss
- the last 10 ping events (latency in ms, `timed out`, or the error message)

**Right-click** the dot for the settings panel:

- host, interval, timeout, and the yellow/red latency & loss thresholds
- a Quit button

Settings persist in `UserDefaults`. Changing the host, interval, or timeout
resets the sample window; changing only thresholds re-scores the existing window.

## Health criteria

Over the last 10 pings:

| Status | Condition (defaults) |
|--------|----------------------|
| Red    | loss > 40%, or avg latency > 500 ms, or every ping failed |
| Yellow | loss > 10%, or avg latency > 150 ms |
| Green  | otherwise |

All thresholds are editable in the settings panel.

## Build & run

```sh
# quick run from source
swift run

# build a proper .app bundle (menu-bar only, no Dock icon)
./make-app.sh
open dist/Pinger.app
```

To start it at login: System Settings → General → Login Items → add `dist/Pinger.app`.

## Layout

- `Sources/Pinger/main.swift` — app entry point
- `Sources/Pinger/AppDelegate.swift` — status item, dot rendering, panel management
- `Sources/Pinger/PingMonitor.swift` — timer loop, history window, health evaluation
- `Sources/Pinger/Pinger.swift` — runs `/sbin/ping -c 1` and parses the result
- `Sources/Pinger/Settings.swift` — persisted, sanitized configuration
- `Sources/Pinger/StatusAppearance.swift` — status → color/title mapping
- `Sources/Pinger/PanelViews.swift` — SwiftUI panels (results, settings)
- `make-app.sh` — assembles and ad-hoc signs `dist/Pinger.app`
