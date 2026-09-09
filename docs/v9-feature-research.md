# v9 feature research

Follow-up to `docs/v2-feature-research.md` through `docs/v8-feature-research.md`. v8's
"refresh Favorites" idea is shipped (issue #24, commit `c98fa65`). Its other two ideas —
a treble toggle and a wider mood picker — were never built: the mood picker was
explicitly not recommended, and the treble toggle was left as an open product question
rather than a settled recommendation. Neither is an open GitHub issue (confirmed via
`gh issue list --state all` — 22 issues, #2–#24 minus #17 which is a PR, not an issue,
all closed).

Same rule as the prior docs: primary sources only — a live Radio Browser API call, this
machine's actually-installed Omarchy shell source (`/usr/share/omarchy/shell/`), and a
fresh read of the current `Panel.qml` (post-#24: `favoritesRefreshQueriedUuids`,
`favoritesRefreshRetried`, `isValidStationRow()`, the merge-not-replace logic in
`favoritesRefreshProc`, `maxFavoritesRefreshBatch`, `resortStations()` now called after a
refresh) — never brainstormed from memory. This round also re-read
`docs/v2-feature-research.md`, `docs/v2-remaining-feature-research.md`, and
`docs/v3-feature-research.md` in full for the first time this session, to check nothing
still-unbuilt there was missed.

This is the ninth round of research on a plugin that's already shipped 22 features. As
v8 already noted, new ground is thin. This round found one genuinely new-to-surface item
(an old, still-unbuilt idea from `v2-remaining` that later rounds never re-checked), real
new evidence on the two directed questions, and otherwise came up empty — said plainly
below rather than padded.

---

## Resolving v8's open product question: does a second toggle belong next to Deep bass?

v8 verified the treble filter works (`af add/remove lavfi=[treble=g=10]`, unchanged, not
re-tested here) but left "is one bass toggle enough UI in that corner" as a product
question with no primary source to settle it. Two new, concrete data points this round:

**No first-party precedent for pairing a toggle with a slider in the same row.**
Confirmed by reading `/usr/share/omarchy/shell/plugins/panels/audio/Panel.qml`: its own
volume sliders (`outputSlider` at line 827, others at 922/1217) each sit alone in their
own row (a header + percent readout above, the slider below); the one mute toggle in that
panel (`powerSwitch`, a `ToggleSwitch`) lives separately in the hero row at the top, not
beside any slider. World Radio's own `volumeRow` (`Panel.qml`, `PanelSlider` +
`deepBassButton` `Button` side by side) has no equivalent in Omarchy's own audio UI to
model a second addition after — this isn't evidence *against* a second toggle, just
confirmation that there's no existing "how many toggles cluster with a slider" precedent
to defer to either way.

**Every existing section header in this file marks a browsable category, not a control
cluster.** Confirmed by reading every `PanelSectionHeader` in `Panel.qml` (7 total: HISTORY,
SEARCH BY NAME, COUNTRY, MOOD, DECADE, LANGUAGE, and the right-pane STATIONS header) — each
sits above a genuinely large, browsable set (a text field, a grid of flags, 10 mood chips,
8 decade chips, a scrollable list). The panel's transport/audio-control area — Previous,
Pause, Next, Stop, Sleep timer, Surprise, Shuffle, Trending, Near me,
the volume slider, and Deep bass — already has *more* individual controls than any single
one of those headed sections, and has never gotten a header of its own. By this file's own
established convention, a second toggle (Treble) wouldn't cross any threshold that's
actually been observed to trigger a header elsewhere in this codebase.

**Verdict**: still not something primary sources can hand down as a build/don't-build
call — that's a genuine listener-facing taste judgment, not a technical fact. But the
concrete, previously-missing data point is: nothing in this codebase's own conventions
suggests a second toggle would need new structure (a header, a sub-row) to accommodate —
it would slot into the exact same `volumeRow` Button-after-Button shape Deep bass already
uses, at zero layout cost. The product question itself ("do we want it") is left exactly
where v8 left it.

---

## Radio Browser API

Verified live against `https://de1.api.radio-browser.info` (a single fresh
`/json/stations/search?limit=1` call, full response inspected field by field against
what this plugin already uses).

### Not pursued further

Every field in a fresh response was checked against what `Panel.qml`'s `stationsProc`
parser already extracts (`uuid, name, playUrl, codec, bitrate, tags, favicon, homepage,
votes`) or has already been researched and dismissed: `hls` (confirmed live: `1` on an
`.m3u8` stream in the sample) — mpv already plays HLS transparently via its own demuxer,
nothing to build; `geo_lat`/`geo_long` per-station — already the exact mechanism behind
the shipped Near Me filter, not a new use; `clicktrend`/`clickcount` — already
investigated and rejected in v4 (numerically identical to the sort order already
shipped as the default); `lastcheckoktime` — already found redundant with `hidebroken=true`
in v8; `iso_3166_2`/`state` — already found to have real data-quality problems in v4
(non-normalized, duplicate near-identical values) and not recommended then. Nothing new
survived this pass.

---

## Quickshell — a genuinely still-unbuilt idea from `docs/v2-remaining-feature-research.md`

### 1. Live favorites/history reload via `FileView.watchChanges` — **small, still ready, still unbuilt**

`docs/v2-remaining-feature-research.md` #11 found this "ready to spec" back when this
plugin had only a favorites file, no History file yet — and no later round (v3 through
v8) ever revisited or built it. Confirmed still accurate against the current file:
`grep -n "watchChanges" Panel.qml` shows both `favoritesFile` and `historyFile` still
declare `watchChanges: false` (lines 383, 392) — unchanged since that original research.

The original finding stands unmodified: `watchChanges: true` makes `FileView` emit
`fileChanged()` on any on-disk change (including this plugin's own writes) but does
*not* auto-reload — the app must explicitly re-trigger a read (`favoritesReadProc`/
`historyReadProc`, not `FileView.reload()`, per this plugin's own hardened-read design).
Not re-verified live against Quickshell's docs again this round (the mechanism itself
hasn't changed since v2-remaining verified it, and re-fetching quickshell.org's
anti-bot-gated docs a third time for an unchanged fact isn't a meaningful use of a
primary-source check) — flagged here as a re-surfaced pointer, not a fresh finding.

**Why this is worth a spec now, more than when v2-remaining found it**: this plugin now
has *two* files with this same "only this plugin ever writes them in the common case"
shape (Favorites and History, per `docs/adr/0001-history-separate-file.md`), and the
scenario this feature helps — another process, or a listener hand-editing the file while
the panel is open — remains the same narrow one v2-remaining already flagged as an open
question about whether it's worth shipping at all. Not upgraded in priority, just
confirmed not stale or superseded by anything shipped since.

**Open questions, unchanged from v2-remaining**: whether `fileChanged` needs debouncing
(still undocumented either way); whether the narrow scenario it fixes is worth building
for at all, versus leaving external edits to only take effect on the next full restart
(today's actual behavior).

---

## Ranking (impact / effort)

1. **Live favorites/history reload (#1)** — the only item this round found that's both
   new-to-surface (never actually re-checked since v2-remaining) and still technically
   ready. Ranked "small" on mechanism, but the open question of whether the narrow
   scenario it fixes is worth it at all — the same one v2-remaining already raised —
   is unresolved, so this isn't a clear go the way most top-ranked items in prior
   rounds were.

The treble-toggle product question has real new evidence (above) but explicitly no
verdict — that's a taste call for a person, not something this round's primary sources
can settle. No Radio Browser field survived this pass as a new finding; every field in a
fresh response traces back to something already shipped or already explicitly rejected
in an earlier round. This round is thinner than v8's, honestly: one re-surfaced idea, one
resolved-but-still-open question, nothing else.
