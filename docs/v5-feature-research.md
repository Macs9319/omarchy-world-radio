# v5 feature research

Follow-up to `docs/v2-feature-research.md`, `docs/v2-remaining-feature-research.md`,
`docs/v3-feature-research.md`, and `docs/v4-feature-research.md`. All of v2/v2-remaining's
ideas are shipped (issues #2–#9); v3's ideas (homepage link, vote count,
`is_https`/`bitrateMin`, mpv audio-device override) remain unspecced but already
researched — not re-covered here. v4's three ranked ideas (`offset` pagination,
copy-stream-URL via `wl-copy`, mpv `cache-speed`) are also still unspecced and
unimplemented — confirmed live: no `offset`, `wl-copy`, `cache-speed`, `clicktrend`, or
`state=` anywhere in the current `Panel.qml` — but not re-researched here either. This
doc looks for ideas beyond all four, verified against primary sources not yet checked by
any of them.

Same rule as the prior docs: primary sources only — live Radio Browser API calls, a
live `get_property`/`set_property` test against a real mpv instance on this machine, and
this repo's own current `Panel.qml` read directly rather than assumed from the README.
`gh issue list --state all` and `gh label list` were both checked — issues #2–#12 are all
closed/shipped, no open issue or label overlaps with anything recommended below.

---

## Radio Browser API

### 1. Shuffle via `order=random` — **small, real caveat found**

Confirmed live: `order=random` on `/json/stations/search` genuinely reorders results
(`GNN Radio`, `Democracy Now!`, `THE WELL` vs. `WBJC 91.5 FM`, `Radio Paradise Main Mix`,
`Acme Radio Live` — two calls, same filters, two different orderings). This plugin's
existing "🎲 Surprise" button doesn't use this at all — it picks a random *country* then
a random station from that country's default-ordered list (confirmed by reading
`surpriseMe()`/`stationsProc`'s `onStreamFinished` in `Panel.qml`), so a listener with an
already-chosen country/language/mood has no way to just reshuffle the current filtered
list. A "🔀 Shuffle" toggle in `stationsProc`'s existing `order=` slot (parallel to the
already-shipped `votes`/`changetimestamp` toggle) would let a listener reorder *within*
their current filters instead of abandoning them.

**Caveat, confirmed live and worth flagging explicitly for a spec**: repeating the
*exact same* `order=random` query twice in quick succession (same params, no
cache-busting) returned **identical** results both times — this API's own server appears
to cache identical query strings for some short window (`server: tiny-http (Rust)`,
confirmed via response headers — not a browser/client cache, since this was a fresh
`curl` process each time). Only varying an unrelated param (a throwaway `_=<n>` value)
produced genuinely different orderings. A naive "click Shuffle again" implementation
would silently do nothing for however long that server-side window lasts. **Open
question for a spec**: append a monotonically-increasing throwaway param (e.g.
`_shuffle=<Date.now()>`) to `stationsProc`'s command whenever `order=random` is active,
the same way this plugin already builds every other param — a one-line addition once
identified, but easy to ship broken (a "Shuffle" button that reorders once, then appears
to do nothing) without this fix.

### Not pursued further

No "similar stations" / recommendation-style endpoint exists on this API — confirmed by
reading its own current endpoint list (`/json/stations/search`, `/topclick`, `/topvote`,
`/lastclick`, `/lastchange`, `/broken`, `/improvable`, plus the `by<field>` family) and
`/json/stats` (confirmed live: `58159` stations, `12120` tags, `241` countries, `660`
languages) — nothing keyed off "stations like this one." The unfiltered `/json/tags`
list (confirmed live, top entries `pop` 6159, `music` 5224, `rock` 3205, ...) is the same
data v2/v2-remaining already found and already recommended a mood-by-count picker
against — not re-litigated here, and still unbuilt in the current `curatedTags` fixed
10-tag array (confirmed by reading `Panel.qml`).

---

## mpv — unused JSON IPC properties

Verified with a live, hands-on `get_property`/`set_property` test over a real mpv
instance on this machine (mpv v0.41.0), mirroring the exact JSON-IPC pattern this
plugin's own `ipcSocket` already uses.

### 2. Volume boost past 100% — **small, real caveat found**

Confirmed live: mpv's default `volume-max` is **130**, not 100 (`get_property
volume-max` → `130.000000` with no flags set) — softvol amplification past unity gain is
already mpv's own out-of-the-box default ceiling, not something this plugin would be
introducing. This plugin's existing `PanelSlider` volume control is hardcoded
`minimum: 0, maximum: 100` (confirmed by reading `Panel.qml`), so a listener on a quiet
stream has no way to reach even mpv's own already-permitted headroom today.

**Caveat, confirmed live and important for a spec**: `volume-max` is **not** a hard
clamp enforced by mpv itself on `set_property volume` — setting `volume-max` to `150`
and then `set_property volume 200` both succeeded, and `get_property volume` echoed back
literally `200`, past both the default 130 ceiling and the 150 the property was just set
to. Any actual ceiling this plugin wants (100, 130, or otherwise) would need to be
enforced client-side, in the slider's own `maximum` and in whatever writes `set_property
volume`, exactly the way `bitrate`/`bufferingPercent`/other externally- or
user-influenced numbers in `Panel.qml` are already clamped in JS rather than trusted to
mpv or the API to bound.

**Implementation sketch**: raise `volumeSlider`'s `maximum` from `100` to `130` (mpv's
own default ceiling — no need to also raise `volume-max` itself, since the property's
own default already permits it), and clamp `state.volume` writes to `[0, 130]` the same
place `state.volume`'s persisted value is already read out of `PersistentProperties`.
**Open question for a spec**: whether values above 100% should show a visibly distinct
slider fill/color (a plain 0–130 bar makes "100" a non-obvious past-unity boundary), and
whether to warn that boosted volume can clip/distort quieter streams' peaks rather than
just add gain cleanly — this is a real audio-quality tradeoff, not a UI nice-to-have.

### 3. Sleep timer via a plain `Timer` — **small, no new API**

Not a primary-source discovery so much as a confirmed non-blocker: this plugin already
has four independent `Timer { }` instances in `Panel.qml`
(`favoritesSaveTimer`, `voteFeedbackTimer`, `nameSearchTimer`, `ipcRetryTimer`) and an
existing `stopPlayback()` function that fully tears down playback cleanly. A "sleep in
15/30/60 min" control needs neither a new dependency nor an mpv IPC feature — one more
`Timer { interval: <n * 60000>; onTriggered: root.stopPlayback() }`, restarted whenever
the listener picks a new duration and stopped/reset on manual stop or a station change.
**Open question for a spec**: whether picking a new station or manually pressing Stop
should cancel a pending sleep timer (almost certainly yes, to avoid a confusing "why did
it stop" moment on the *next* station), and what duration options to expose.

### Not pursued further

Re-confirms v4's finding, not new: no named `equalizer` filter ships with mpv, and a
real per-band EQ needs FFmpeg's `lavfi` bridge (already used for `loudnorm`) plus
genuine multi-slider UI — still a large scope jump not worth it without a specific
listener request, unchanged from v4's verdict.

---

## Quickshell / Omarchy shell

### 4. Recently played list — **medium, real seam now found (in this plugin's own code, not another plugin's)**

v4 flagged this as "plausible... but has no existing seam or precedent to build from,"
based on grepping other first-party Omarchy plugins for a "recent"/"history"/"MRU"
pattern and finding none. Re-examined here against a different, better primary
source: **this plugin's own already-shipped favorites file**. `Panel.qml` already
contains a complete, hardened, on-disk JSON list pattern —
`favoritesReadProc`'s `O_NOFOLLOW`/`O_NONBLOCK`/size-capped Python read,
`favoritesFile`'s `atomicWrites: true` `FileView` for writes, `favoritesSaveTimer`'s
200ms debounce, and `maxFavoritesFileBytes`/`maxFavorites` bounds — built and verified
for exactly this shape of problem (a small, bounded, uuid-keyed on-disk list that must
survive a real shell restart, confirmed necessary because `PersistentProperties` alone
doesn't). A "recently played" list is the same shape: bounded size, keyed by
`stationuuid`, written on every successful `playStation()` call, read back once at
startup. This is a real, in-repo precedent to build from, not a speculative one.

**Implementation sketch**: a second small file (e.g.
`~/.local/state/omarchy/world-radio-recent.json`) or a second top-level key in the
existing favorites file, capped at a small count (10–20, well under
`maxFavorites`'s 500), storing the same row shape (`uuid, name, playUrl, codec, bitrate,
tags`) already used for favorites, appended-and-trimmed in `playStation()` rather than
on every station-list fetch. Reuses `favoritesReadScript`'s exact hardened-read approach
(same trust boundary — an on-disk file at a fixed, predictable path) rather than
inventing a second read mechanism.

**Open questions for a spec**: one file with two keys (`favorites` + `recent`) vs. two
separate files (simpler blast radius per feature, doubles the boilerplate); whether
replaying a station bumps its recency (de-duplicating) or always inserts a new entry;
whether "recently played" gets its own list section in Expand mode or is folded into an
existing picker.

---

## Ranking (impact / effort)

1. **Volume boost past 100% (#2)** — smallest real change (one slider bound plus a
   client-side clamp), directly usable today per mpv's own already-permissive default,
   though it needs its own clamp since mpv won't provide one.
2. **Recently played list (#4)** — medium only because it's a second on-disk file/key,
   not because anything about it is technically uncertain — it can copy this plugin's
   own already-hardened favorites-file pattern almost verbatim.
3. **Sleep timer (#3)** — small, self-contained, no new API surface at all; ranked
   below the above two only because it's a pure convenience add rather than fixing or
   extending an existing capability.
4. **Shuffle via `order=random` (#1)** — real and verified, but the server-side
   identical-query caching caveat means it needs one extra throwaway param to actually
   work as a repeatable "shuffle again" button, not just a one-line `order=` swap like
   the existing Trending/Recently-added toggles.
