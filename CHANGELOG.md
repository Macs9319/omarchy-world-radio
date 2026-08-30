# Changelog

All notable changes to World Radio are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-08-30

### Added

- **Search by name** — a free-text box that filters stations by name,
  worldwide on its own or combined with the selected country, mood, and
  decade. Debounced ~350ms so a request fires once typing pauses, not on
  every keystroke. (Contributed by [@seatrips](https://github.com/seatrips)
  in [#1](https://github.com/Macs9319/omarchy-world-radio/pull/1).)
- **Favorites** — star a station to pin it to the top of its list.
  Favorites persist across shell restarts in
  `~/.local/state/omarchy/world-radio-favorites.json`.
- Netherlands, Malaysia, and Singapore added to the curated country grid;
  Nigeria, Egypt, and India removed (still reachable via country search).
- Per-search station limit raised from 30 to 80, so popular-but-not-top
  stations stay on the list once a mood or decade filter is applied.

### Fixed

- The country search box showed nothing at all on a failed or slow fetch —
  indistinguishable from a genuine "no matches." It now shows a loading
  indicator, a real error message, or "No countries match" as appropriate.
- Selecting a country from search results (as opposed to the curated flag
  grid) could silently fail to load any stations. The click handler cleared
  the search box first, which emptied the results list — the search
  Repeater's own model — destroying the very button whose handler was
  still running, so the actual country-selection call never happened.
  Deferred with `Qt.callLater` so the click has fully finished dispatching
  before the list changes underneath it.
- Clearing the name search (and no country selected) while a station fetch
  was still in flight could let stale results reappear moments later,
  overwriting the intentionally-cleared list. The debounce timer now
  cancels any in-flight fetch on that path too.

### Security

- Hardened the favorites file read against a hostile or corrupted
  replacement at its fixed, predictable path. Earlier iterations checked
  the file with a separate `stat` before reading it through `FileView`
  (a TOCTOU gap — the path could be repointed between the two lookups),
  then closed that gap with a single held-open file descriptor that still
  transparently followed a symlink. The final version opens the path
  exactly once with `O_NOFOLLOW | O_NONBLOCK` (refusing a symlink outright,
  and returning immediately instead of blocking on a FIFO), and every
  check — regular-file, size, the read itself — runs against that one
  descriptor. See [Favorites file safety](README.md#favorites-file-safety)
  for the full explanation. Found and confirmed across three review rounds
  during the [Omarchy Plugin Marketplace](https://omarchyplugins.com/)
  submission ([listing issue](https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/2369)).

## [1.0.0] - 2026-08-25

Initial release: country picker (curated flag grid plus live search), mood
and decade filters, a tuning dial (previous/next/pause/stop, plus a
"🎲 Surprise" random pick), a volume slider, live now-playing ICY track
titles, hardware media key / MPRIS support via mpv, and a two-pane layout
with a full-height station list.
