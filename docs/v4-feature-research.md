# v4 feature research

Follow-up to `docs/v2-feature-research.md`, `docs/v2-remaining-feature-research.md`,
and `docs/v3-feature-research.md`. All of v2's ideas are shipped; v3's ideas
(homepage link, vote count, is_https/bitrateMin, mpv audio-device override)
remain unspecced but already researched — not re-covered here. This doc looks
for ideas beyond all three, against fields/params/APIs not yet checked by any
of them, confirmed by reading the current `Panel.qml` first.

Same rule as the prior docs: primary sources only — live API calls, a live
`get_property`/`observe_property` test against a real mpv instance on this
machine, and this machine's actual installed Quickshell/Omarchy shell source.

---

## Radio Browser API — unused fields and params

Verified live against `https://de1.api.radio-browser.info`. Current row shape
in `Panel.qml`'s `stationsProc` parser: `uuid, name, playUrl, codec, bitrate,
tags, favicon` — confirmed by reading the `list.push({...})` call directly.

### 1. "Load more" via `offset` — **medium**

Confirmed live: `/json/stations/search` supports real pagination —
`offset=0`/`offset=3` with the same `order=name` returned two genuinely
different, non-overlapping 3-station pages. Confirmed separately via
`/json/countries` that a single country can have far more stations than this
plugin's hardcoded `limit=80` — the US alone reports `stationcount: 8017`.
Right now, once a listener has an unfiltered or lightly-filtered country
selected, roughly 7900+ US stations are simply unreachable, with no
indication more exist beyond the first 80.

**Implementation sketch**: track an `offset` alongside the existing filter
state, add a "Load more" control at the bottom of the station list (visible
only when the last fetch returned a full page, i.e. `count === limit`,
implying more may exist), and on click re-run `stationsProc` with the same
params plus the next `offset`, appending results to `stationsModel` instead
of clearing it first. The existing `resortStations()` favorite-pinning logic
already re-partitions the whole model, so it would need to run again after
an append the same way it already does after a fresh load.

**Open question for a spec**: whether appending should reset if any filter
changes (almost certainly yes — offset only makes sense against a stable
filter set) and whether the "did the last page look full" heuristic is
reliable enough, or whether reading the exact `stationcount` for the current
country from `/json/countries` (already fetched once and cached) could give
an exact "N of 8017 shown" indicator instead of a guess.

### 2. `state` (sub-national region) filter — **investigated, not recommended**

Confirmed live: `state` is a real, populated field for many countries with
sub-national divisions (a US sample returned real values like `'NY'`,
`'Colorado'`, `'Georgia'`), a `state=<name>` search param works as an exact
match (confirmed: `state=Colorado` returned only Colorado stations), and a
`/json/states/<countrycode>` endpoint exists to list them. **Data quality
caveat found live**: the values aren't normalized — `/json/states/US`
returned `"Austin TX"`, `"Austin MN"`, and `"Austin, Texas"` as three
separate, non-deduplicated entries, and the sampled `state` values mixed
abbreviations (`'NY'`) with full names (`'Colorado'`) inconsistently. A
free-text picker over this data (mirroring the language filter's shape)
would surface confusing near-duplicate entries to the listener. Not
recommended without a data-cleanup step this plugin has no way to perform
client-side.

### 3. `clicktrend` as a third sort order — **investigated, not recommended**

Confirmed live: `order=clicktrend&reverse=true` genuinely sorts (distinct
results from a bogus-order control query, matching the same live-verification
method already used for the existing sort orders). But in every sampled
result, `clicktrend` was numerically identical to `clickcount` — the same
field this plugin's *default* (unlabeled) ordering already uses
(`order=clickcount`, hardcoded when no sort override is active). Adding a
"clicktrend" sort option would very likely reorder the list identically to
just clearing Trending/Recently-added back to the default, which would be a
confusing, redundant third button rather than a genuinely new capability.

### Not pursued further

`lastcheckok` (boolean health-check result) is already effectively filtered
out by the existing `hidebroken=true` param — surfacing it separately for
stations that already passed that filter would almost always just show
"OK" and add visual noise. `has_geo_info`/other boolean-flag params were
checked and don't map to any new listener-facing filter beyond what
`geo_lat`/`geo_long`/`geo_distance` (already shipped as "Near me") already
covers.

---

## mpv — unused JSON IPC properties

Verified against mpv's own `input.rst` and a live `get_property` call over
this plugin's own JSON IPC pattern.

### 4. Network cache speed indicator — **small, low priority**

Confirmed live: `get_property cache-speed` over the exact IPC socket this
plugin already drives returns a real number (16048, i.e. bytes/sec of
current network read speed) on a live stream. Documented in mpv's own
`input.rst` as "Current I/O read speed between the cache and the lower
layer." Technically a one-line addition alongside the existing buffering
observers. Low priority: it's only interesting during the exact window the
already-shipped buffering percentage already covers, so it would mostly
duplicate that indicator with a noisier raw-bytes number rather than add new
information a listener would act on.

### Not pursued further

mpv has no built-in named `equalizer` filter (confirmed: not present in
`af.rst`'s filter list) — an EQ would need FFmpeg's `equalizer`/
`superequalizer` filters through the same `lavfi` bridge already used for
loudnorm. Technically reachable, but a real per-band EQ needs real UI
(multiple sliders, presets) that's a large scope jump for this plugin's
current minimalist control set — not recommended without a specific
listener request for it, unlike loudnorm's one-line, no-UI shape.

---

## Quickshell / Omarchy shell — unused local APIs

Verified by reading this machine's installed `/usr/lib/qt6/qml/Quickshell/`
module tree and Omarchy's first-party plugin source.

### 5. Copy stream URL to clipboard — **small**

No `Quickshell.Clipboard` QML type exists in the installed module tree
(confirmed: no match found searching for it), but Omarchy's own first-party
`clipboard` plugin (`/usr/share/omarchy/shell/plugins/clipboard/Clipboard.qml`)
and `wl-copy` itself (confirmed present on this machine, `/usr/bin/wl-copy`)
show the same "shell out via a `Process`" pattern this plugin already uses
for every network call. A small "copy link" affordance next to the
vote/star/favicon row icons, running `wl-copy` with the station's
`url_resolved` (the same field the plugin already stores as `playUrl`) piped
to its stdin, would let a listener paste the raw stream URL into another
player or share it — no new fetch, reuses data already on the row.

**Implementation sketch**: a `Process` with `command: ["wl-copy"]` and the
URL written to its stdin (this plugin doesn't currently write to a
`Process`'s stdin anywhere, so this would be a first for the file — worth
flagging explicitly in a spec rather than assuming it's a drop-in copy of
the existing `curl`-argv-only pattern).

### Not pursued further

No first-party Omarchy panel was found with a "recently played" /
most-recently-used list pattern distinct from an explicit favorites/pin
list (grepped plugin source and READMEs for "recent"/"history"/"MRU" —
no real precedent). A "recently played" feature for this plugin is
plausible in the abstract but has no existing seam or precedent to build
from, and would need its own state file (or a `state`-cleaned addition to
the existing favorites file) — a real design decision, not a small
follow-on the way the items above are.

---

## Ranking (impact / effort)

1. **Load more via offset (#1)** — the only item here that's a real, verified
   gap in existing functionality (most of a large country's stations are
   currently unreachable), not just an unused-but-optional field. Medium
   effort because it touches the fetch/append/resort flow, not just a param
   addition.
2. **Copy stream URL (#5)** — small, real, reuses data already on the row,
   though it's the first `Process` in this file that would need to write to
   stdin rather than just build an argv.
3. **Cache-speed indicator (#4)** — technically ready but low value, mostly
   redundant with the already-shipped buffering percentage.

`state` filter (#2) and `clicktrend` sort (#3) were investigated and are
explicitly **not** recommended — real data quality and redundancy problems
respectively, not just "small/low priority."
