# v2 remaining feature research

Follow-up to `docs/v2-feature-research.md`, going deeper on six of the eight
items from that doc that hadn't been turned into a spec yet as of this
research pass. (Items #1, #6, #7 from that doc are already specced and
published as issues #3, #2, #4 on `Macs9319/omarchy-world-radio` — not
revisited here.)

**Not covered by this doc, and not yet specced either**: items #2 (the
`/json/vote/{stationuuid}` endpoint) and #8 (a real buffering indicator via
`cache-buffering-state`/`paused-for-cache`) from the original doc. Both were
simply out of scope for this research pass, not resolved or dismissed —
flagged here explicitly so this doc isn't mistaken for full coverage of
everything still unspecced.

Same rule as the original doc: primary sources only — live API calls, this
machine's actual installed `.qmltypes`/`.qml` files, a live `hyprctl` test
against the Hyprland instance actually running on this machine, and official
docs fetched directly, not brainstormed from memory. Two items below
**correct** a claim in the original doc after digging further; both are
flagged explicitly where that happens.

---

## Radio Browser API

### #3 (orig.) — Language filter / mood-by-count picker — **verdict: ready to spec**

Re-confirmed live: `GET /json/tags?limit=5` and
`GET /json/languages?order=stationcount&reverse=true&limit=5` both return
`{"name", "stationcount"}` shapes as the original doc found (English tops
languages at 13,178 stations as of this check). Newly confirmed:
`GET /json/stations/search?languagecodes=fr&...` works standalone and
composes with the plugin's other existing params (`countrycode`, `tag`,
`limit`, `hidebroken`) in the same request — no separate lookup needed once
a language code is chosen, exactly mirroring how `tag`/`tagList` already
work in `stationsProc`. No rate-limit headers were observed on `/json/tags`
or `/json/languages` across repeated calls from this machine.

**Implementation sketch**: a `languageCode` field on `state` (parallel to
`state.tag`/`state.decade`), a fetch-once-cached `allLanguages` list
(parallel to `allCountries`/`countriesProc`), and a `languagecodes=` param
appended in `stationsProc`'s command builder alongside the existing `tag`/
`tagList` logic — same shape, one more optional AND-ed filter.

**Open questions for a spec**: whether a language filter is a free-text
search box (like country) or a chip picker (like mood/decade); whether
sorting the existing fixed 10-tag mood grid by live `stationcount` replaces
or supplements the curated list — the original doc treated these as two
separate options, a spec should pick one.

### #4 (orig.) — Geolocation search — **verdict: ready to spec (revised from "more plausible than ready to build")**

**Correction to the original doc**: it stated "Quickshell has no built-in
geolocation API (not found in any installed qmltypes)." A broader search on
this machine found `/usr/lib/qt6/qml/QtPositioning` *is* installed (Qt's
`PositionSource` type) — but no Geoclue D-Bus service is registered on this
system (`find /usr/share/dbus-1/system-services -iname '*geoclue*'` and
`pacman -Qs geoclue` both empty), so `PositionSource` would have no working
backend to bind to here regardless of the QML type being present. This
doesn't change the practical conclusion, but the original "not found in any
installed qmltypes" claim was checking the wrong module (Quickshell's own,
not Qt's) — worth a factual correction.

What does change the conclusion: this machine's own **first-party
precedent** was found for how Omarchy itself solves "where is the user"
without device GPS — the bundled weather plugin
(`/usr/share/omarchy/shell/plugins/panels/weather/`):

- **IP-based auto-detect**, confirmed live on this machine: the weather
  plugin's own helper script (`/usr/share/omarchy/bin/omarchy-weather-location`)
  falls back to `curl -fsS --max-time 4 "https://wttr.in/?format=%l"` for a
  bare city name when nothing is configured. Going one step further and
  confirmed live: `https://wttr.in/?format=j1` (same host, HTTPS, no API
  key) returns a `nearest_area[0]` object with `latitude`/`longitude`
  fields directly — e.g. this session got `{"latitude": "3.017",
  "longitude": "101.617", "areaName": "Puchong Batu Dua Belas", ...}` from
  this machine's IP. This is the *exact* same host and `curl`-based `Process`
  pattern Omarchy's own weather plugin already trusts and calls, not a new
  third-party dependency.
- **Manual name search with real coordinates**, confirmed live: the weather
  plugin's location picker debounces a `curl` to
  `https://geocoding-api.open-meteo.com/v1/search?name=<query>&count=5&language=en&format=json`
  (`Model.js`/`Panel.qml` in that plugin) and gets back named places with
  lat/long — again a `curl`-based `Process`, same shape this plugin already
  uses everywhere.
- A generic (non-Omarchy) alternative was also confirmed reachable:
  `http://ip-api.com/json/` returns `lat`/`lon` directly over plain HTTP —
  but confirmed live that its HTTPS endpoint is paywalled
  (`https://ip-api.com/json/` → `403 {"message":"SSL unavailable for this
  endpoint, order a key at https://members.ip-api.com/"}`), so it's a worse
  option than `wttr.in` here: either accept plain HTTP or don't use it.
  `https://ipwho.is/` was confirmed to work over HTTPS with no key as a
  second fallback, if ever needed.

**Implementation sketch**: on demand (e.g. a "📍 Near me" button, mirroring
Surprise's shape), fetch `https://wttr.in/?format=j1`, pull
`nearest_area[0].latitude`/`.longitude`, and append `geo_lat=`/`geo_long=`/
`geo_distance=<meters>` to `stationsProc`'s existing param builder — no new
fetch pattern, no new host trust decision (Omarchy already curls this host),
all-HTTPS.

**Open questions for a spec**: what distance radius to default to and
whether it's user-adjustable; whether to compose geo search with the
existing country/tag/language filters or treat it as a separate,
exclusive mode (Radio Browser's params compose freely, so this is a UX
choice, not a technical constraint); whether a manual lat/long entry
fallback is worth the UI cost given `wttr.in`'s IP-detect already covers
the common case.

### #5 (orig.) — Trending / Recently added — **verdict: ready to spec**

**Not a correction — confirms and firms up what the original doc already
proposed.** An earlier draft of this section mischaracterized the original
doc as having proposed calling the dedicated `/stations/topvote` and
`/stations/lastchange` endpoints; re-reading `docs/v2-feature-research.md`
item #5 directly shows its own implementation note already said to reuse
`stationsProc`'s existing command-building shape with `order=votes` instead
of `order=clickcount` — the same conclusion this section reaches, not a
fix to a mistake the original doc made. What *is* newly confirmed here,
live: the plugin's *existing* endpoint, `/json/stations/search`, accepts
`order=votes` and `order=lastchange` (alongside the `order=clickcount` it
already sends) and **composes with every filter already in use** —
confirmed with `tag=jazz&order=votes&reverse=true` and with
`order=lastchange&reverse=true` plus `hidebroken=true`, both returning
correctly filtered/ordered results. Using `stationsProc`'s existing
endpoint with a different `order=` value (instead of a second, separate
endpoint) means "Trending" and "Recently added" can also respect whatever
country/tag/decade filters are already selected, which the dedicated
`/stations/topvote`/`/stations/lastchange` endpoints — being unfiltered,
fixed lists — cannot do.

**Implementation sketch**: one more optional `order=` override in
`stationsProc`'s command-building function (currently hardcoded to
`order=clickcount&reverse=true`), toggled by a "🔥 Trending" / "🆕 Recently
added" control next to Surprise — no new `Process`, no new endpoint.

**Open questions for a spec**: whether Trending/Recently-added should
compose with existing filters (recommended, per above) or reset them like
Surprise does; whether both get their own button or share one toggle with
the default clickcount order.

---

## Quickshell / Hyprland / Omarchy

### #9 (orig.) — `GlobalShortcut` — **verdict: caveat resolved; a Hyprland-side keybind is still required, and it can't go through Omarchy's `o.bind()` helper**

The original doc's open caveat was whether a user still needs one
Hyprland-side config line to actually assign a key, the same as today's
`o.bind(...)` one-liner, "just through a different mechanism." This is now
resolved, definitively, from two primary sources:

1. **Quickshell's own source doc comments** (fetched from
   `git.outfoxxed.me/quickshell/quickshell`, the `GlobalShortcut` C++/QML
   type's header): *"To activate a shortcut, configure a keybind in
   Hyprland using: `bind = <modifiers>, <key>, global, <appid>:<name>`."*
   Also confirmed there: `appid` defaults to `"quickshell"` and can't be
   changed at runtime, and duplicate `appid:name` pairs across running
   clients are rejected (registration conflict).
2. **A live, hands-on test against this machine's actual running Hyprland**
   (version 0.56.2, confirmed via `hyprctl version`): `hyprctl dispatch
   'hl.dsp.global("foo:bar")'` returned `ok` — the `global` dispatcher is
   real and working on this exact install, not just documented. (`hyprctl
   globalshortcuts` currently reports `none` — still zero live registrations
   on this machine, consistent with the original doc's grep finding of zero
   first-party usage anywhere under `/usr/share/omarchy/shell/`.)

**New finding the original doc didn't cover**: this machine's Hyprland uses
the newer native-Lua config format (`~/.config/hypr/*.lua`, not the classic
`hyprland.conf` keyword syntax), and Omarchy's own `o.bind(keys,
description, dispatcher, options)` helper (`/usr/share/omarchy/default/hypr/helpers.lua:92`,
the function the README's current one-liner calls) **always** coerces a
string `dispatcher` argument into `hl.dsp.exec_cmd(dispatcher)` — there is
no pass-through for an arbitrary dispatcher object like `hl.dsp.global(...)`.
So switching to `GlobalShortcut` would not keep the user on the same
`o.bind("SUPER + R", "World Radio", "...")` line the README documents today;
it would require them to drop to the lower-level `hl.bind(keys,
hl.dsp.global("worldradio:next"), opts)` directly in their `bindings.lua`,
bypassing Omarchy's convenience wrapper entirely. This is a real, now-
verified downgrade in ergonomics for Omarchy users specifically (not a
general Hyprland limitation — raw `hl.dsp.global` works fine, `o.bind`
specifically doesn't expose it).

**Implementation sketch** (if pursued anyway): register one `GlobalShortcut
{ appid: "worldradio"; name: "next" }` (and similarly for play/pause,
prev, surprise) per action needed, wire `onPressed` to the same functions
the current buttons call, and document the `hl.bind(..., hl.dsp.global(...))`
line as a replacement for the current `o.bind(...)` line in the README.

**Verdict**: technically sound and now proven end-to-end on this machine,
but the original doc's closing hedge — "the practical win over the current
documented one-liner may be smaller than it looks" — holds up and is now
sharper: it's not smaller, it's arguably a *regression* in ergonomics for
Omarchy users, since it trades one `o.bind()` line for one `hl.bind()` +
`hl.dsp.global()` line that bypasses the framework's own helper. Worth a
spec only if the goal is specifically "portal-registerable, not
hand-bound-only" shortcuts — not as a drop-in replacement for the README's
current instructions.

### #10 (orig.) — `Quickshell.Services.Notifications` — **verdict: correction — this is the wrong API for sending a notification**

**Correction to the original doc**: it described this module as "the
idiomatic API for it in this codebase rather than shelling out to
`notify-send`," for a future track-change notification. Reading the full
type list in the installed
`quickshell-service-notifications.qmltypes` shows this module is a
**notification-server (receiver) toolkit**, not a way for an app to send
one. Its main type, `NotificationServerQml`, and the `Notification` objects
it hands out, only expose receiver-side actions — `expire`, `dismiss`,
`sendInlineReply`, `invoke` — for notifications *already received* from
other apps. Confirmed by cross-referencing Omarchy's own shell: its
notification popup widget
(`/usr/share/omarchy/shell/plugins/notifications/Service.qml`) instantiates
exactly this type (`NotificationServer { ... }`) to *implement the
notification daemon that renders the popups on screen*, and its
`NotificationLogic.js` explicitly pattern-matches incoming notifications by
`app_name === "notify-send"` — i.e. Omarchy's shell is the receiver,
`notify-send` (and any other app) is the sender, and this Quickshell module
is the receiver-side API.

**Implication for a future track-change-notification feature**: sending a
notification would still go through the standard freedesktop
`org.freedesktop.Notifications.Notify` D-Bus method — i.e. shelling out to
`notify-send` (or an equivalent D-Bus call) exactly as the original doc's
phrasing wanted to avoid, is in fact still the correct approach in this
codebase. No Quickshell-native "send a notification" type was found in the
installed modules.

**Verdict**: not something to spec — it corrects a proposed implementation
detail for a feature ("idiomatic API"), and the correction is that
`notify-send`-via-`Process` (the plugin's own already-established pattern
for talking to external programs) remains correct.

### #11 (orig.) — `FileView.watchChanges` for live favorites reload — **verdict: ready to spec; exact semantics confirmed**

Confirmed via Quickshell's own hosted docs (`quickshell.org/docs`, fetched
via search snippet after direct fetch was blocked by the site's own
anti-bot 403): `watchChanges: true` makes `FileView` emit a `fileChanged()`
signal whenever the file's content changes on disk (including the app's
own `setText()`/`setData()` calls) — **it does not auto-reload**; the
documented pattern is `onFileChanged: this.reload()`, i.e. the app must
explicitly trigger a re-read. This exactly matches the original doc's
framing: wiring `watchChanges: true` plus `onFileChanged` calling this
plugin's own hardened `favoritesReadProc` trigger (not `FileView.reload()`,
per the favorites-file-safety design already in the README) is additive,
not a new mechanism.

**Not found in any available doc source (flagged as unverified, not
assumed)**: whether `fileChanged` is debounced by Quickshell itself when the
underlying file changes multiple times in quick succession. No debounce
behavior is documented or visible in the qmltypes (`fileChanged` is a plain
signal with no rate-limiting properties alongside it). A spec should treat
this as an open risk, not a settled fact either way, and consider debouncing
the `favoritesReadProc.running = true` trigger itself (the plugin already
has a working debounce pattern for the mirror-image write case,
`favoritesSaveTimer`) rather than assuming Quickshell handles it.

**Implementation sketch**: `favoritesFile.watchChanges: true` plus
`onFileChanged: favoritesReadProc.running = true` (guarded the same way the
existing `Component.onCompleted`-triggered read already is, so a burst of
external writes can't pile up concurrent `favoritesReadProc` runs).

**Open questions for a spec**: whether to add debouncing given the
undocumented behavior above; whether this is worth shipping at all given
the favorites file is, in the common case, only ever written by this
plugin itself (the scenario this feature helps — another process or a
manually-edited file changing favorites while the panel is open — is a
narrow one).

---

## Summary verdicts

| # | Feature | Verdict |
| - | ------- | ------- |
| 3 | Language filter / mood-by-count | Ready to spec |
| 4 | Geolocation search | Ready to spec (revised — a working, low-friction path exists via `wttr.in`, already trusted by Omarchy) |
| 5 | Trending / Recently added | Ready to spec (confirms the original doc's own proposal — reuse `stationsProc` with a different `order=`, not new endpoints) |
| 9 | `GlobalShortcut` keybinding | Caveat resolved, but the answer is negative: still needs a Hyprland-side line, and a less ergonomic one than today's `o.bind()` for Omarchy users specifically. Not recommended as a replacement for the current README instructions. |
| 10 | `Quickshell.Services.Notifications` for sending | Correction: wrong API for sending; not a feature to spec, and any future notification feature should keep using `notify-send`/D-Bus as originally avoided. |
| 11 | `FileView.watchChanges` for live reload | Ready to spec; semantics confirmed, one real open question (undocumented debounce behavior) flagged for the spec to resolve. |
