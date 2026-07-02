# Pinger

A tiny macOS menu bar app that shows your internet health as a colored dot.

- **Green** — connected and healthy
- **Yellow** — degraded (elevated smoothed loss or latency)
- **Red** — down (consecutive failures, or smoothed loss/latency past the red thresholds)
- **Gray** — starting up / no data yet

It pings a destination (default `8.8.8.8`) every N seconds (default 2s) by
invoking `/sbin/ping`.

**Left-click** the dot: results panel — current status, smoothed latency and
loss, and the last 10 ping events (latency in ms, `timed out`, or the error).

**Right-click** the dot: menu with your destination list (switch instantly),
**Settings…**, and **Quit**.

**Settings window**: manage the destination list, pick a detection profile
(Sensitive / Balanced / Steady / Custom), and tune every number — ping
interval, timeout, yellow/red latency and loss thresholds, consecutive-failure
and recovery counts, and reactivity. Settings persist in `UserDefaults`.

## How detection works

Designed to react fast without flip-flopping:

1. **Recency-weighted scoring** — loss and latency are exponentially weighted
   moving averages (EWMA), so the last few pings dominate and old samples fade
   instead of lingering for a fixed 10-ping window.
2. **Failure fast path** — N consecutive failures force red immediately,
   regardless of the averages.
3. **Sticky recovery** — leaving red requires M consecutive successes, so one
   lucky ping during an outage can't flash green; on recovery the averages
   reset so green shows immediately.
4. **Adaptive burst probing** — at the first sign of a transition (a failure
   while up, a success while down) the ping rate quadruples (capped at 2/s)
   until the state is confirmed, so verdicts land in seconds without raising
   the steady-state ping rate.

### Profiles

| Profile | Red after | Recover after | Reactivity α | Yellow/red loss |
|---------|-----------|---------------|--------------|-----------------|
| Sensitive | 2 fails (~2–3 s) | 2 OKs | 0.45 | 15% / 50% |
| Balanced (default) | 3 fails (~4 s) | 3 OKs | 0.30 | 35% / 60% |
| Steady | 5 fails (~7 s) | 4 OKs | 0.18 | 40% / 70% |

A single lost ping spikes the loss EWMA to α×100%, so Sensitive blinks yellow
on one drop (by design) while Balanced and Steady need two or more. Editing
any preset-owned number switches the profile to Custom.

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
- `Sources/Pinger/AppDelegate.swift` — status item, dot rendering, panel/menu/window management
- `Sources/Pinger/PingMonitor.swift` — adaptive ping loop and health engine
- `Sources/Pinger/Pinger.swift` — runs `/sbin/ping -c 1` and parses the result
- `Sources/Pinger/Settings.swift` — persisted, sanitized configuration and profiles
- `Sources/Pinger/StatusAppearance.swift` — status → color/title mapping
- `Sources/Pinger/PanelViews.swift` — SwiftUI results panel and settings window
- `make-app.sh` — assembles and ad-hoc signs `dist/Pinger.app`
