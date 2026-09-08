# v6 feature research

Follow-up to `docs/v2-feature-research.md` through `docs/v5-feature-research.md`.
v5's four ideas are all shipped (issues #13–#16, released as v1.4.0). Several
older ideas remain unspecced but already fully researched — not re-covered
here: homepage link and vote-count display (v3 #1/#2), `is_https`/`bitrateMin`
filters (v3 #3), audio-device override (v3 #4, caveat: redundant with
Omarchy's own Pipewire Audio panel), `FileView.watchChanges` live favorites
reload (v2-remaining #11), `offset` pagination / copy-stream-URL / mpv
`cache-speed` (v4). `GlobalShortcut` keybinding (v2-remaining #9) and sending
via `Quickshell.Services.Notifications` (v2-remaining #10, wrong API — it's
receiver-only) are both already researched and **not recommended** — not
revisited here either.

Same rule as the prior docs: primary sources only — live Radio Browser API
calls, official docs fetched directly, a live hands-on mpv JSON-IPC test
against a real mpv instance on this machine, and this machine's actually-
installed Quickshell/Omarchy shell source — never brainstormed from memory.
The current `Panel.qml` (post-v1.4.0: `playStation()` takes a full row,
`sanitizeStationRow()`, `shuffleActive`/`sleepTimerOption`/`history` state)
was re-read directly, not assumed from memory of earlier in this session.
`gh issue list --state all` was checked — issues #2–#16 are all filed;
nothing below overlaps an existing issue. **Aside, outside this doc's own
scope**: issues #13–#16 are still open despite being implemented, released,
and pushed in v1.4.0 — worth closing separately.

---

## Radio Browser API

### 1. Server discovery + failover via `all.api.radio-browser.info` — **medium, real gap against the API's own documented usage**

`root.apiHost` is hardcoded to `https://de1.api.radio-browser.info` and used
by every single API call in `Panel.qml` (countries, languages, stations
search, click, vote) — confirmed by reading every `root.apiHost +` call
site. No retry logic exists anywhere in the file for any of them (confirmed:
zero matches for "retry" in `Panel.qml`).

Confirmed live by fetching `https://api.radio-browser.info/` directly (the
API's own onboarding docs, not a secondary summary) — its own "HowTo"
section states the API's intended usage is: (1) DNS-lookup
`all.api.radio-browser.info` to get the list of available servers, (2)
"randomize the list and choose the first entry... if a request fails just
retry the request with the next entry in the list." This plugin does
neither — it hardcodes one specific mirror with no fallback, which is
exactly the anti-pattern the API's own docs warn against.

**Caveat, confirmed live and worth flagging explicitly for a spec**: right
now the actual pool is tiny. `GET /json/servers` against `de1` and a DNS
lookup of `all.api.radio-browser.info` (`python3 socket.gethostbyname_ex`)
both currently return exactly **one** host (`de1.api.radio-browser.info`,
`91.98.4.78`) — so switching the hostname alone buys zero redundancy today.
The real, immediate win is the **retry-on-failure** half of the documented
pattern (currently entirely absent), which protects against a transient
timeout/5xx from this one server regardless of pool size; switching the
hostname to `all.api.radio-browser.info` is what makes it automatically
benefit if/when the mirror pool grows again, with no further code change.

**Implementation sketch**: resolve `all.api.radio-browser.info` once at
startup (a `Process` running e.g. `getent hosts` or `python3 -c
'import socket; ...'`, matching the plugin's existing `python3 -c`-script
pattern already used for the favorites/history read), cache the resulting
host list, and on any `stationsProc`/`countriesProc`/etc. failure (`code !==
0`), retry once against the next host in the list before surfacing the
existing `stationsError` message. **Open question for a spec**: whether to
resolve once per session (simple, matches how `allCountries` is already
fetch-once-cached) or re-resolve periodically in case the pool changes
during a long session.

### Not pursued further

`/json/stations/topvote` and `/json/stations/lastchange` as dedicated
endpoints were already correctly rejected by v2-remaining #5 in favor of
reusing `stationsProc` with a different `order=` value (already shipped as
Trending/Recently-added) — not revisited. A "similar stations" endpoint was
already confirmed live not to exist by v5's own research (its own "Not
pursued further" section) — not re-checked here.

---

## mpv — unused JSON IPC data

Verified with a live, hands-on `get_property` test over a real mpv instance
on this machine (mpv v0.41.0), against this plugin's own already-registered
`observe_property` for `"metadata"`.

### 2. Genre/station-name from already-observed ICY metadata — **small, near-zero cost**

Confirmed live: the exact `metadata` property this plugin already registers
via `observe_property` (`metadataObserveId`, confirmed by reading
`Panel.qml`) returns far more than the single `icy-title` field currently
extracted (`root.nowPlayingTitle = String(msg.data["icy-title"] || "")`). A
live test against a real stream (SomaFM's DEF CON Radio channel) returned:
`icy-genre` ("Electronic Hacking"), `icy-name` (the stream's own
self-reported station name), `icy-br` (the stream's *actual* live bitrate,
as opposed to Radio Browser's directory-recorded value), `icy-url`, and
`icy-pub`, alongside the already-used `icy-title`. Since this data arrives
on the exact same already-registered property — no new IPC call, no new
`observe_property` registration — showing `icy-genre` alongside the
existing now-playing title (e.g. under the Buffering/title caption) would be
a real, listener-visible enrichment using data already being received and
silently discarded today.

**Implementation sketch**: in `handleMpvMessage`'s existing
`metadataObserveId` branch, also read `msg.data["icy-genre"]` into a new
`root.nowPlayingGenre` property, shown conditionally next to
`nowPlayingTitle` the same way `bufferingPercent`/`nowPlayingTitle` already
share that caption `Text`. **Open question for a spec**: `icy-genre` isn't
sent by every station (confirmed: absent from streams that don't populate
ICY metadata at all, the same station-to-station inconsistency the existing
`nowPlayingTitle` already tolerates via `visible: ... || root.nowPlayingTitle
!== ""`) — needs the same graceful-absence handling, not a hard requirement.

### 3. Desktop notification on track/station change — **small-medium, genuinely unbuilt (only an implementation detail was corrected, never speced)**

v2-remaining #10 corrected an *implementation* claim (Quickshell's own
`Services.Notifications` module is receiver-only, confirmed by reading
Omarchy's own notification-popup source, which uses it to *implement* the
daemon) — but never speced a notification feature itself, and none of
issues #2–#16 build one. Confirmed live on this machine: `/usr/bin/notify-send`
exists, and no first-party Omarchy plugin currently *sends* one via
`notify-send` (grepped `/usr/share/omarchy/shell/plugins/*/*.qml`/`*.js` —
existing matches are all the notification daemon's own *receiver*-side code
matching `app_name === "notify-send"`, not a sender). This plugin does,
however, already have its own internal precedent for shelling out to an
external program via a bare-argv `Process` (every `curl` call) — extending
that same pattern to `notify-send` is a small, self-contained step, not a
new mechanism.

Confirmed live via `notify-send --help`: `-a/--app-name`, `-t/--expire-time`,
and `-i/--icon` (a filename or *stock icon name* — **not a URL**, so the
station's own favicon can't be passed directly without downloading and
caching it locally first, a real added step this plugin doesn't currently
do for any image).

**Implementation sketch**: a `notifyProc` `Process` (argv-only, no stdin/
stdout collector needed, mirroring `clickProc`'s fire-and-forget shape) run
from `playStation()` alongside the existing `clickProc` trigger:
`["notify-send", "-a", "World Radio", "-t", "4000", row.name, "Now
playing"]`. **Open questions for a spec**: whether to use a generic stock
icon (`audio-x-generic`, simplest) rather than the station's favicon
(requires a download-and-cache step this codebase doesn't have a precedent
for yet); whether every station change should notify, or only ones the
listener didn't directly click (Prev/Next/Surprise/Shuffle, where the
result isn't already visually obvious from a just-clicked row).

### 4. Idle-inhibit while playing — **investigated, not recommended**

The concrete question — does background audio playback keep the screen
awake — was checked against both real paths on this machine, and **both are
blocked for this plugin's actual runtime shape**, not just theoretically
available:

- **mpv's own `--stop-screensaver`** (default `yes`): confirmed via mpv's
  own `options.rst`, fetched directly: *"stopping the screensaver is only
  possible if a video output is available (i.e. there is an open mpv
  window)."* Confirmed live against a real mpv instance run with this
  plugin's exact flags (`--no-video --idle=yes`): `get_property
  stop-screensaver` → `true` (mpv *wants* to inhibit) but `get_property
  vo-configured` → `false` (no video output exists to inhibit through) — mpv
  itself confirms it has nothing to act on, live, not just per the docs.
- **Quickshell's own `Quickshell.Wayland.IdleInhibitor`** type does exist on
  this machine (confirmed:
  `/usr/lib/qt6/qml/Quickshell/Wayland/_IdleInhibitor/`) and Omarchy's own
  idle service (`Service.qml`) already respects standard inhibitors
  (`IdleMonitor { respectInhibitors: true }`, confirmed by reading its
  source) — so an inhibitor registered anywhere would genuinely work.
  **But** `IdleInhibitor` requires binding to a `window` (a real Wayland
  surface, confirmed from its own `.qmltypes`), and this plugin's only
  window is the transient browse `KeyboardPanel` — closed for most of actual
  listening time, since the whole point of a bar-widget is background
  playback continuing after the panel is closed. An inhibitor tied to that
  window would stop inhibiting the instant a listener closes the panel to
  do something else, which is exactly when they'd most want the screen to
  stay awake for their music.

**Verdict**: not recommended. Both available mechanisms are real and
verified working in principle, but neither actually covers this plugin's
real usage pattern (background, panel-closed playback) without a much
larger change (an always-present hidden surface just to hold an inhibitor —
disproportionate complexity for what this feature is worth).

### Not pursued further

`demuxer-cache-duration` and similar buffer-window-only diagnostics would be
redundant with mpv's `cache-speed` property already researched (and ranked
low-priority) by v4 #4 — not re-investigated. ReplayGain properties were
already ruled out as inapplicable to streaming radio by v3 (streams carry no
file-level ReplayGain tags) — not re-checked.

---

## Ranking (impact / effort)

1. **Genre/station-name enrichment (#2)** — smallest possible change (read
   one more key off data already arriving on an already-registered
   property), real listener-visible value, no new IPC call or endpoint.
2. **Server discovery + retry (#1)** — medium effort (a resolve step, a
   retry branch on every existing fetch), but corrects a real, officially-
   documented anti-pattern this plugin currently has, and the retry half
   helps regardless of the mirror pool's current size.
3. **Now-playing notification (#3)** — small-medium, genuinely new (not
   just re-covering a prior doc), reuses this plugin's own established
   shell-out-via-Process pattern; ranked behind #1/#2 because it's a pure
   convenience add rather than fixing or enriching something already there.

Idle-inhibit (#4) was investigated in real depth and is explicitly **not**
recommended — both real mechanisms on this machine are blocked by this
plugin's own audio-only, background-playback shape, not a documentation gap.
