# Next version research

Primary sources only, per this repo's own convention: `manifest.json`,
`CHANGELOG.md`, this repo's `git log`, the actual [semver.org](https://semver.org/)
spec text (fetched directly), and this machine's installed Omarchy shell
source — not brainstormed from memory.

## Current state, confirmed

- `manifest.json`'s `version` field is still literally `"1.1.0"` as of
  `HEAD` (`git log -p --follow -- manifest.json` shows only two commits
  touching it ever: `1.0.0` at `e1b405a`, bumped to `1.1.0` at `7b98442`
  on 2026-08-30 — no later bump exists).
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
  and has exactly two entries: `1.0.0` (initial release) and `1.1.0`
  (2026-08-30), the latter with `### Added` / `### Fixed` / `### Security`
  sections.
- Since the `1.1.0` bump, `git log --oneline` shows 8 feature/fix commits
  (plus 2 CI-related ones) corresponding to closed GitHub issues **#2–#9**,
  all labeled `enhancement` + `ready-for-agent`, confirmed via
  `gh issue list --state closed`:
  - #2: Sync now-playing title and pause state via mpv's observe_property
    instead of polling
  - #3: Show station favicon in the station list
  - #4: Apply loudness normalization (loudnorm) to every stream
  - #5: Add a language filter to station search
  - #6: Add Trending / Recently-added station ordering
  - #7: Add a Near Me geolocation filter for station search
  - #8: Show a real buffering indicator during connection/rebuffering
  - #9: Add a vote button to upvote stations in the public directory
  - Plus, outside the issue tracker: a GitHub Actions CI workflow
    (`manifest.json` + `Panel.qml` sanity checks) and a CI status badge
    added to the README.
- None of the above changes `manifest.json`'s schema, the plugin's
  settings (`defaultVolume` is untouched), or the favorites file format —
  every change is either a new, independently-usable filter/control, or a
  fix to existing behavior. Nothing requires a user to reconfigure or
  breaks an existing installation.

## What semver.org actually says

Fetched `https://semver.org/` directly (not recalled from memory).
Verbatim:

> Given a version number MAJOR.MINOR.PATCH, increment the:
> MAJOR version when you make incompatible API changes
> MINOR version when you add functionality in a backward compatible [manner]
> PATCH version when you make backward compatible bug fixes

This release is overwhelmingly "add functionality in a backward
compatible manner" (six genuinely new features: favicon, loudnorm,
language filter, trending/recent sort, geolocation, vote button), plus
one behavior improvement that's arguably a fix (#2, replacing polling
with instant sync) and non-user-facing CI infra. Per the spec's own
plain wording, this is a **MINOR** bump, not PATCH (there's real new
functionality, not just bug fixes) and not MAJOR (nothing incompatible
was changed).

This exactly mirrors this repo's own prior precedent: `1.0.0 → 1.1.0`
was also "new features (search-by-name, favorites) + fixes + security
hardening, no breaking changes" — the same shape as this release, bumped
MINOR.

## Omarchy's own manifest schema — version field format

Searched `/usr/share/omarchy/` (this machine's installed Omarchy shell)
for any schema or validation logic governing the `version` field:

- No JSON Schema file for the plugin manifest was found anywhere under
  `/usr/share/omarchy/`.
- Every first-party plugin's own `manifest.json` under
  `/usr/share/omarchy/shell/plugins/*/manifest.json` (agents, background,
  bar, clipboard, dev-gallery, emojis, image-picker, lock, menu,
  notifications, osd, polkit, reminders, and the bar's own widgets) uses
  a plain semver-shaped string, universally `"1.0.0"` — but this is
  observed *convention*, not a *documented requirement*: no regex,
  schema, or validation code enforcing this shape was found in any `.py`
  file searched under `/usr/share/omarchy/`.
- `/usr/share/omarchy/shell/README.md`'s own plugin-manifest example
  (the "Cool clock" sample manifest, line 56) also uses `"1.0.0"`.
- **Explicitly not found, not assumed**: any code path that parses,
  validates, or otherwise cares about the exact format of the `version`
  string. It appears to be advisory/display-only at the schema level
  checked here. This doesn't rule out validation existing somewhere else
  (e.g. a marketplace-side check, since this plugin was submitted to the
  [Omarchy Plugin Marketplace](https://omarchyplugins.com/) per the
  1.1.0 CHANGELOG entry) — only that nothing in this machine's installed
  Omarchy shell source enforces it.

## Recommendation

**Bump to `1.2.0`.**

- Justification: six new backward-compatible features plus a
  behavior-improvement fix, no breaking changes — a MINOR bump per
  semver.org's own definition, and the same bump level this repo used
  for an equivalently-shaped prior release (1.0.0 → 1.1.0).
- `preview.png` was updated for the 1.1.0 bump (per `2b70464 Update
  preview.png for v1.1.0`) — if the panel's visual appearance changed
  meaningfully (new favicon column, new Trending/Near-Me/vote controls),
  consider whether a refreshed screenshot belongs in this release too;
  not verified here since that's a visual judgment call, not a research
  question.

## Draft CHANGELOG.md entry

Matches the existing `1.0.0`/`1.1.0` entries' exact heading style. Uses
today's date (2026-09-05, per this session's own commits) and the real
issue titles above rather than paraphrased wording.

```markdown
## [1.2.0] - 2026-09-05

### Added

- **Station favicon** — the station list now shows each station's own
  favicon next to its name, using the same data Radio Browser already
  returns. ([#3](https://github.com/Macs9319/omarchy-world-radio/issues/3))
- **Loudness normalization** — mpv's bundled `loudnorm` filter is now
  applied to every stream, evening out the wide loudness swings between
  stations. ([#4](https://github.com/Macs9319/omarchy-world-radio/issues/4))
- **Language filter** — a free-text language search, mirroring the
  existing country search, composes with country/mood/decade/name.
  ([#5](https://github.com/Macs9319/omarchy-world-radio/issues/5))
- **Trending / Recently added** — two toggleable sort orders next to
  Surprise, reordering the current list by votes or by recency instead
  of all-time click count.
  ([#6](https://github.com/Macs9319/omarchy-world-radio/issues/6))
- **Near me** — an IP-based geolocation filter finds stations within
  50km of your approximate location, composing with other filters.
  ([#7](https://github.com/Macs9319/omarchy-world-radio/issues/7))
- **Buffering indicator** — the now-playing area shows a real
  "Buffering… NN%" state during the connection gap after clicking a
  station, or during a later rebuffer, instead of leaving that window
  blank. ([#8](https://github.com/Macs9319/omarchy-world-radio/issues/8))
- **Vote button** — upvote a station in the public Radio Browser
  directory directly from its row.
  ([#9](https://github.com/Macs9319/omarchy-world-radio/issues/9))
- A GitHub Actions CI workflow (manifest/QML sanity checks) and a CI
  status badge on the README.

### Fixed

- The now-playing title and Pause/Resume label synced via a 2-second
  poll; both now update the instant mpv itself reports a change, via
  mpv's `observe_property` mechanism instead of polling.
  ([#2](https://github.com/Macs9319/omarchy-world-radio/issues/2))
```
