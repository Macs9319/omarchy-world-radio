# v8 feature research

Follow-up to `docs/v2-feature-research.md` through `docs/v7-feature-research.md`. All
three of v7's ideas are shipped (issues #21–#23). Issues #2–#23 are all closed
(confirmed via `gh issue list --state all`), and none overlap anything recommended
below. v3's remaining deprioritized ideas (`is_https`/`bitrateMin` filters, audio-device
override) are unchanged — not re-litigated here, no new evidence has emerged since they
were last re-confirmed in v7.

Same rule as the prior docs: primary sources only — live Radio Browser API calls, a
live hands-on `af add`/`get_property` test against a real mpv instance on this machine
(started fresh for this doc, not assumed from earlier sessions), and this machine's
actually-installed Quickshell/Omarchy shell source. The current `Panel.qml` (post-#21–23:
`homepage`/`votes` on the row shape, `homepageButton`/`voteButton` hit-area reflow,
`deepBassFilter`, `toggleDeepBass()`, the `volumeRow` layout) was re-read directly.

This is the eighth round of research on a plugin that's already shipped 21 features
(issues #2–#23). Genuinely new, unclaimed ground is getting scarcer — two of the four
items below are real but small; the other two investigated ideas turned out to be
already effectively covered or not worth the complexity, and are said so plainly rather
than padded into recommendations.

---

## mpv — unused JSON IPC properties

Verified with a live, hands-on test against a real mpv instance on this machine (mpv
v0.41.0, started fresh with this plugin's own `--no-video --idle=yes` flags against a
real stream), mirroring `toggleDeepBass()`'s exact `af add`/`get_property af`/`af remove`
pattern.

### 1. Treble toggle, pairing with Deep bass — **small, new finding**

Confirmed live: `af add lavfi=[treble=g=10]` succeeds immediately over the same JSON IPC
connection Deep bass already uses, `get_property af` shows it applied
(`{"name":"lavfi","enabled":true,"params":{"graph":"treble=g=10"}}`), and `af remove
lavfi=[treble=g=10]` (the same string) cleanly removes it — the exact same shape v7
verified for `bass=g=10`. FFmpeg's `treble` filter is a real, separate single-knob shelf
filter from `bass`, confirmed by mpv's own `af.rst` listing both as distinct `lavfi`-only
filters (not two names for the same thing).

**Open question, not a code decision**: this is the same size and shape as Deep bass
(#21) — by that ticket's own precedent, not disproportionate scope the way a full EQ
would be. Whether it's worth a *second* toggle next to Deep bass, or whether one bass
toggle is enough UI in that corner of the panel, is a real product judgment call, not
something primary sources can settle — flagged for a spec/grilling round rather than
decided here.

### Not pursued further

`gapless-audio` (confirmed live: `"weak"`, mpv's own out-of-the-box default) is
irrelevant here — this plugin's mpv instance is always started with a single URL and
`--idle=yes`, never a playlist (re-confirmed by reading `mpvProc`'s `command:`, matching
v3's own finding), so there's no track boundary for gaplessness to apply to.
`vo-configured` (confirmed live: `false`) and `video-format` (confirmed live: "property
unavailable") both re-confirm `--no-video` means there is truly no video subsystem to
hook anything to — matches v6's own idle-inhibit finding, not a new avenue.

---

## Radio Browser API — unused fields and endpoints

Verified live against `https://de1.api.radio-browser.info`.

### 2. Refresh Favorites against live data via the `byuuid` batch endpoint — **small-medium, new finding, real gap**

Confirmed by reading `Panel.qml`: Favorites are frozen at star-time (`toggleFavorite()`
copies `row`'s fields into `root.favorites[uuid]` once) and never revalidated — there is
no refresh path anywhere in the file. A favorited station's bitrate can change, or it can
go offline entirely, and the panel would keep showing stale data indefinitely with no
way to know.

Confirmed live: `/json/stations/byuuid?uuids=<uuid1>,<uuid2>,...` accepts a
comma-separated batch of station UUIDs and returns all of them in one response (tested
with two real UUIDs, got both back) — the same `curl`+`StdioCollector`+`JSON.parse`
shape every other endpoint in this file already uses, no new request pattern needed.
This would let a "refresh favorites" action (or an automatic one, e.g. on panel open)
re-fetch current `codec`/`bitrate`/`tags`/`votes`/`homepage` for every favorited station
in a single request rather than one per station.

**Open questions for a spec**: whether refresh is manual (a button) or automatic (on
panel open, rate-limited); whether a favorite whose UUID no longer exists in the
directory (station removed entirely — `byuuid` would simply omit it from the response)
gets dropped silently or flagged to the listener before removal.

### 3. A wider mood picker via `/json/tags`'s real stationcounts — **investigated, not recommended as a redesign, small optional addition**

Confirmed live: `/json/tags?order=stationcount&reverse=true` returns real,
popularity-ranked tag data (`pop` 6185, `music` 5232, `rock` 3221, `news` 3043, `radio`
2376, ...) — already the same data v2/v2-remaining originally found and declined to
build a picker against (their own "Not pursued further" sections), not a new discovery.
Re-checked here only because vote count now gives the panel a second "show real
popularity numbers" precedent that didn't exist when v2 made that call.

**Verdict unchanged from v2**: the fixed 10-entry `curatedTags` array is a deliberate
curation, not a limitation — replacing it with the top-10-by-count would surface
generic buckets (`music`, `radio`) instead of the genre-flavored ones already chosen
(`jazz`, `reggae`, `hiphop`), which is a worse listener experience, not a better one.
Not recommending a redesign. The one genuinely additive option — an optional "more
moods…" expansion into the full tag list below the curated chips — is real but is
scope creep beyond what any primary source here actually demands; noted, not ranked.

### Not pursued further

`lastcheckoktime`/`lastcheckok` (confirmed live: real per-station timestamps exist,
e.g. `"lastcheckoktime":"2026-09-03 21:56:12"`) would be redundant to surface: this
plugin's own `stationsProc` already sends `hidebroken=true` on every search, so every
station shown has already passed that exact check server-side — a "last verified"
badge would just restate a guarantee already implicit in the list, not add new listener
information.

---

## Quickshell / Omarchy shell — unused local APIs

### Investigated: registering quick actions into Omarchy's menu system — **not applicable, already covered**

Checked whether this plugin could register individual actions (e.g. "Surprise me",
"Stop") as separate entries in Omarchy's own launcher/menu, distinct from the existing
bar-widget toggle. Confirmed live by reading `/usr/share/omarchy/shell/README.md` and
`MenuModel.js`: `"menu"` is a distinct plugin *kind* (separate from this plugin's own
`"bar-widget"` kind) that receives "an application-library facade" for
application-launcher-style entries — no mechanism was found for an ordinary bar-widget
plugin to register additional fine-grained actions into it. What this plugin already
has — `barWidget.aliases: ["radio", "worldradio"]` in its own `manifest.json`, matched
by `MenuModel.js`'s own alias lookup (confirmed by reading it) — already makes it
discoverable and toggleable from Omarchy's menu today. There's no evidence of an unused
integration point here, just confirmation that the existing one already does the job.

Checked for a system tray integration (`Tray.qml` exists in Omarchy's bar plugin) —
not applicable either: the tray is for *other* applications' `StatusNotifierItem` icons
to appear in Omarchy's bar, not a registration surface for a plugin that is already
itself a first-class bar-widget.

---

## Ranking (impact / effort)

1. **Refresh Favorites via `byuuid` (#2)** — the only item here fixing a real,
   previously-unaddressed gap (Favorites can silently go stale forever), not just
   adding new-but-optional data. Small-medium because it's a genuinely new fetch
   pattern (batch by UUID) for this plugin, not a one-line addition to an existing call.
2. **Treble toggle (#1)** — small, verified live, exact same shape as the already-shipped
   Deep bass. Ranked behind #2 only because whether a second toggle belongs in that
   corner of the panel is a real open product question, not just an implementation
   detail.

The wider-mood-picker idea (#3) is explicitly **not recommended** as a redesign — the
curated tag list is a deliberate choice, not a gap. No other idea in this round survived
verification as worth building; the menu/quick-actions and tray investigations found the
existing bar-widget integration already sufficient.
