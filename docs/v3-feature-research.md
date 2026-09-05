# v3 feature research

Follow-up to `docs/v2-feature-research.md` and `docs/v2-remaining-feature-research.md`,
both of which are now fully shipped (search by name, favorites, favicon,
loudnorm, language filter, Trending/Recently-added, Near me geolocation,
buffering indicator, vote button). This doc looks for genuinely new ideas
beyond those two, against the same primary sources those docs used, plus
mpv's and Quickshell's own docs/source and a fresh read of the current
`Panel.qml` to confirm nothing here is already implemented.

Same rule as the prior docs: primary sources only — live API calls, a
hands-on mpv JSON IPC test on this machine, and this machine's actual
installed Quickshell/Omarchy shell source — not brainstormed from memory.

---

## Radio Browser API — unused fields and endpoints

Verified live against `https://de1.api.radio-browser.info`.

### 1. Station homepage link — **small**

Every station object returned by `/json/stations/search` (and
`/json/stations/byuuid`) already includes a `homepage` field — confirmed
live: `"homepage":"https://www.rtl.fr/"` on a real station. This plugin
already receives and discards it, exactly the same situation the favicon
field was in before item #1 of the original research doc. A small "🔗"
link next to the vote/star buttons, opening `row.homepage` via QML's
built-in `Qt.openUrlExternally()`, would let a listener visit a station's
own site — no new fetch, no new endpoint, no process spawn (this is a
plain Qt global function, not a shell-out). No first-party Omarchy plugin
was found using `Qt.openUrlExternally()` or shelling out to `xdg-open`
(grepped `/usr/share/omarchy/shell/plugins/*/*.qml`), but `xdg-open` is
present on this machine (`/usr/bin/xdg-open`) as a fallback if
`Qt.openUrlExternally()` ever proves unavailable in this Quickshell build
— not verified further since the Qt API is the simpler, dependency-free
path.

**Implementation sketch**: add `homepage: String((s && s.homepage) || "")`
to the row mapping in `stationsProc`'s parser (same place `favicon` was
added), validate it's `http(s)://` shaped the same way `favicon` already
is (this plugin already treats API-supplied URLs as untrusted), and add a
small "🔗" `Text` + `MouseArea` in the station row delegate, visible only
when non-empty, calling `Qt.openUrlExternally(row.homepage)`.

### 2. Vote count display — **small**

Every station object already includes its own `votes` count (confirmed
live: `"votes":2155`). This plugin already reads `votes` indirectly — the
existing "🔥 Trending" sort orders by it server-side — but never displays
the number itself. Showing it (e.g. appended to the existing
codec/bitrate/tags caption line, "AAC · 64kbps · 2,155 votes") would give
the vote button's own action a visible before/after effect, and let a
listener gauge popularity without needing to switch to Trending order.

**Implementation sketch**: add `votes: Number((s && s.votes) || 0)` to the
same row mapping, and append it to the existing caption `Text`'s joined
string in the delegate (`[row.codec, row.bitrate ? ... : "", row.tags]`
already uses `.filter(...).join(" · ")` — one more entry). No new fetch.

### 3. Minor search filters: `is_https`, `bitrateMin` — **small, low priority**

Both confirmed live and working: `is_https=true` returns only stations
whose `url` is `https://` (verified: both results in a live test were
`https://`), and `bitrateMin=256` returns only stations at or above that
bitrate (verified: results had `bitrate: 320` and `800`). Both are
one-line additions to `stationsProc`'s param builder, same shape as the
existing filters. Listed as low priority because neither maps to an
already-expressed listener need the way the other items in this doc do —
they're technically ready, not clearly wanted.

### Not pursued further

`/json/stations/broken` and `/json/stations/improvable` are Radio
Browser's own community-moderation queues (stations flagged as dead or
needing metadata fixes) — confirmed live they return real data, but
they're curation tooling for the directory's maintainers, not a listener-
facing feature for this plugin. `/json/codecs` (confirmed live: AAC, MP3,
OGG, FLAC, etc. with counts) could back a codec filter, but codec choice
isn't a filter listeners of an internet radio app typically reason about
the way country/language/mood already are — no clear use case found.

---

## mpv — unused JSON IPC properties

Verified against mpv's own `input.rst` (fetched directly) and a live
hands-on JSON IPC test against a real mpv instance on this machine (not
just read from docs).

### 4. Audio output device selection — **medium, caveat**

Confirmed both in mpv's own `input.rst` and live: `get_property
audio-device-list` over the exact JSON IPC socket this plugin already
uses returns a real, usable array of `{name, description}` pairs (live
result on this machine included `pipewire`, `alsa/hdmi:...`, specific
named devices, etc.), and `audio-device` is documented read/write —
setting it reinitializes mpv's audio output to that device.

**Caveat, found while checking for existing precedent**: this machine's
Omarchy shell already ships a first-party Audio panel
(`/usr/share/omarchy/shell/plugins/panels/audio/`) built on
`Quickshell.Services.Pipewire` (`Pipewire.defaultAudioSink`,
`Pipewire.preferredDefaultAudioSink`, confirmed by reading that panel's
own QML) — a system-wide, per-application-capable audio routing UI that
already exists and that a Bluetooth/USB device switch already goes
through today. Adding a *second*, mpv-specific, per-app device picker
inside World Radio would duplicate that system control with a narrower,
less capable mechanism (mpv's own device list, not Pipewire's live
per-stream routing). Worth a spec only if the goal is specifically "route
just this radio stream to a different output than my system default
without changing it system-wide" — a real but narrow use case — not as a
general audio-routing feature, since Omarchy already has one.

### Not pursued further

Playlist-related commands (`playlist-next`, `loadlist`, etc.) don't apply
here: this plugin's mpv instance is always started with a single URL and
`--idle=yes`, never a playlist, confirmed by reading `mpvProc`'s own
`command:` in `Panel.qml`. ReplayGain properties exist in mpv but only
apply to files carrying ReplayGain tags in their own metadata, which
internet radio streams essentially never do (no fixed file, no tag store)
— not applicable to this use case.

---

## Quickshell / Omarchy shell — unused local APIs

Verified by reading this machine's actual installed
`/usr/lib/qt6/qml/Quickshell/` module list and Omarchy's own first-party
plugin source under `/usr/share/omarchy/shell/plugins/`.

Beyond confirming the Pipewire precedent above (item #4's caveat), no new
first-party Quickshell service was found with a clear, unduplicated
listener-facing use for this specific plugin. `Quickshell.Bluetooth`
exists but has no relevance to an internet-radio player (it's an input
device / discovery API, not audio routing). `Quickshell.Services.Mpris`
is already effectively covered for this plugin by the system-wide
`mpv-mpris` integration the README already documents.

---

## Ranking (impact / effort)

1. **Homepage link (#1)** — same near-zero-cost shape as the already-
   shipped favicon feature: the data already arrives in every response
   this plugin already makes, and it's a real, small, listener-visible
   addition (visit a station's own site).
2. **Vote count display (#2)** — equally near-zero cost, and gives the
   existing vote button and Trending sort a visible number to look at,
   directly reusing data already in the response.
3. **Minor search filters (#3)** — technically ready and cheap, but no
   clearly expressed listener need behind either one; lower priority than
   #1/#2 for that reason alone.
4. **Audio output device override (#4)** — real and verified, but
   redundant with Omarchy's own first-party Pipewire-based Audio panel
   for the common case; only worth specifying if the narrower "just this
   stream, not system-wide" use case is actually wanted.
