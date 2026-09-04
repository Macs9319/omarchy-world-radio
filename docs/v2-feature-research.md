# v2 feature research

Researched against primary sources only (live API calls, official docs, and
this machine's actual installed QML type definitions) — not brainstormed
from memory. Each entry cites what was actually verified and where.

No existing notes convention in this repo, so this file lives at
`docs/v2-feature-research.md` — a new location, flagged here explicitly.

This repo's own issue/PR tracker (`gh issue list` / `gh pr list` on
`Macs9319/omarchy-world-radio`) has no open issues and one merged PR (#1,
already built: search-by-name). Nothing outstanding there to pull from, so
everything below comes from reading the Radio Browser API, mpv's manual and
IPC docs, and Quickshell's installed qmltypes.

---

## Radio Browser API — unused capabilities

Verified live against `https://de1.api.radio-browser.info` and its own
endpoint documentation.

### 1. Station favicon/logo — **small**
Every station object already returned by `/json/stations/search` (the exact
endpoint this plugin calls) includes a `favicon` field — confirmed on a live
response: `"favicon":"https://mangoradio.de/wp-content/uploads/cropped-Logo-192x192.webp"`.
Nothing new to fetch; the plugin already receives this and discards it. An
`Image { source: row.favicon }` in the station row delegate would show real
station logos. Some are empty strings or dead links, so needs a
`visible: row.favicon !== ""` guard and no crash-on-404 handling (Image
already fails silently to a blank in QtQuick).

### 2. Vote endpoint — **small**
Documented and confirmed live: `GET /json/vote/{stationuuid}`, JSON format,
rate-limited to once per IP per 10 minutes (per the API's own reference).
This plugin already calls the sibling `/json/url/{stationuuid}` click-count
endpoint on play. A "👍" button next to the star that calls `/json/vote/...`
the same way (a `Process` running `curl`, argv-only, same pattern already
used) would let favoriting *also* upvote a station in the public directory —
same trust boundary already accepted for the click call, no new risk.

### 3. `tags` / `languages` endpoints return counts — **medium**
Confirmed live: `GET /json/tags/jazz?limit=3` →
`[{"name":"1.fm jazz","stationcount":1},{"name":"acid jazz","stationcount":18},...]`,
and `GET /json/languages?order=stationcount&reverse=true` →
`[{"name":"english","iso_639":"en","stationcount":13149},...]`. Both are the
same fetch-once-then-search-locally shape this plugin already uses for
`allCountries`/countriesProc. A free-text **language filter** (mirrors the
existing country-search TextField exactly, `languagecodes` param maps 1:1)
or a smarter **mood picker** sorted/filtered by real station count instead
of the current fixed 10-tag grid are both direct extensions of code that
already exists — medium only because it's two near-duplicate UI sections,
not because anything is technically hard.

### 4. Geolocation search — **medium**
Confirmed via the API's own endpoint list: `geo_lat`, `geo_long`,
`geo_distance` (meters) are documented `stations/search` parameters,
combinable with the params this plugin already sends. Would need a location
source — Quickshell has no built-in geolocation API (not found in any
installed qmltypes; would require an IP-geolocation HTTP call or manual
lat/long entry), so this is more "plausible" than "ready to build."

### 5. `/stations/topvote`, `/stations/lastchange` — **small**
Confirmed live: `topvote` returns real stations sorted by a `votes` field
(current top result had 823,093 votes). `lastchange` would surface newly
added/edited stations. Either is a one-line addition to the existing
Surprise-style "pick a station list, populate it" flow — a "🔥 Trending"
or "🆕 Recently added" button next to Surprise, reusing `stationsProc`'s
existing command-building shape with `order=votes` instead of
`order=clickcount`.

---

## mpv — unused JSON IPC / properties

Verified against `mpv.io/manual/master` and mpv's own
`DOCS/man/ipc.rst` on GitHub (raw source, not a secondary summary).

### 6. `observe_property` instead of polling — **medium, architectural**
Confirmed from mpv's own `ipc.rst`: `{"command": ["observe_property", 1,
"volume"]}` registers a watch, and mpv then pushes
`{"event": "property-change", "id": 1, "data": 52.0, "name": "volume"}`
whenever it changes — no further request needed. This plugin currently
polls `get_property` for `metadata` and `pause` on a 2-second `Timer`
(`nowPlayingTimer` in `Panel.qml`). Switching to `observe_property` once at
connect time would make the now-playing title and pause-state-from-hardware-
-key sync *instant* instead of up to 2s stale, and cuts the periodic IPC
traffic entirely. This is a real behavior improvement, not just a nice-to-
-have, but touches the core playback plumbing (`ipcSocket`, `handleMpvMessage`)
rather than being additive — hence "architectural."

### 7. Loudness normalization via `af add` — **small**
Confirmed from the mpv manual's audio filter section: filters are
added/removed at runtime via commands, with the documented chain syntax
`--af=foo:option1=value1,bar` for the option format. **Correction (caught
during implementation, re-verified against mpv's own `input.rst`)**: the
runtime IPC command is `af <operation> <value>` (e.g. `["af", "add",
"lavfi=[loudnorm]"]`) — there is no separate `af-add` command in the JSON
IPC protocol; that name doesn't exist anywhere in mpv's input command list.
mpv bundles FFmpeg's `loudnorm` filter. Internet radio streams vary wildly
in loudness station-to-station; sending
`{"command": ["af", "add", "lavfi=[loudnorm]"]}` once per stream start
would even that out. Small because it's one more IPC command alongside the
`set_property`/`pause` calls already sent in `playStation()`.

### 8. Real buffering indicator via `cache-buffering-state` / `paused-for-cache` — **small**
Confirmed present in the mpv manual's stats/status-line documentation:
`cache-buffering-state` and `paused-for-cache` reflect whether playback is
currently stalled waiting on network buffer. Polling (or, better, observing
per #6) this would let "Not playing" / station-name text show a real
"Buffering…" state during the connection gap between clicking a station and
audio actually starting — right now there's no feedback in that window at
all.

---

## Quickshell / Omarchy shell — unused local APIs

Verified by reading the actual installed `.qmltypes` files on this machine
under `/usr/lib/qt6/qml/Quickshell/` and `/usr/share/omarchy/shell/`.

### 9. `Quickshell.Hyprland._GlobalShortcuts` `GlobalShortcut` — **medium, caveat**
Confirmed present:
`/usr/lib/qt6/qml/Quickshell/Hyprland/_GlobalShortcuts/quickshell-hyprland-global-shortcuts.qmltypes`
defines a real `GlobalShortcut` QML type (`name`, `description`,
`pressed`/`released` signals) that registers through Hyprland's own global-
-shortcuts portal. In principle this could expose "Next station" /
"Play-Pause" as portal-registerable actions instead of requiring the
hand-edited `~/.config/hypr/bindings.lua` line the README currently
documents. **Caveat**: grepped the entire `/usr/share/omarchy/shell/` tree
and found zero existing first-party usage of this type — nothing in this
codebase to confirm the full binding flow (whether the user still has to
add one Hyprland-side config line to actually assign a key to the
registered action, same as today, just through a different mechanism).
Feasible per the type's own API surface, but unproven end-to-end in this
environment — would need real hands-on testing before committing to it,
and the practical win over the current documented one-liner may be smaller
than it looks.

### 10. `Quickshell.Services.Notifications` instead of shelling out — **small, cosmetic**
Confirmed present (`Quickshell/Services/Notifications/quickshell-service-notifications.qmltypes`),
a proper QML notification-server client. Not a new *feature* — the plugin
doesn't currently send any desktop notifications at all — but if a
track-change notification is ever added (already discussed with the user
outside this research), this is the idiomatic API for it in this codebase
rather than shelling out to `notify-send`.

### 11. `Quickshell.Io.FileView` `watchChanges` for live favorites reload — **small**
The plugin's own `favoritesFile: FileView` already sets `watchChanges: false`
deliberately (reads go through the hardened Python `O_NOFOLLOW`/`O_NONBLOCK`
path, not `FileView.reload()`, per the favorites-file-safety work already
documented in the README). `watchChanges: true` is a real, documented
`FileView` property, but wiring it up would mean re-running the same
hardened read path on every external file change rather than just at
startup — a small, self-contained addition to the existing
`favoritesReadProc` trigger, not a new mechanism.

---

## Ranking (impact / effort)

1. **`observe_property` (#6)** — biggest real UX win (instant title/pause
   sync vs. up to 2s stale) for a contained change to code that already
   exists, using a documented, primary-source-confirmed mpv IPC feature.
2. **Station favicon (#1)** — near-zero cost (the data already arrives in
   every response this plugin already makes) for a real visual upgrade to
   the station list.
3. **Loudness normalization (#7)** — one more `af add` IPC call, directly
   solves a real annoyance (wildly inconsistent volume jumping between
   stations) using a filter mpv ships with by default.

Everything else is real and sourced but either larger in scope (#3/#4/#9)
or purely additive rather than fixing something already imperfect (#2/#5).
