# v7 feature research

Follow-up to `docs/v2-feature-research.md` through `docs/v6-feature-research.md`. All
three of v6's ideas are shipped (issues #18–#20). Issues #13–#20 are all closed
(confirmed via `gh issue list --state all`), and none overlap anything recommended
below.

v3's four ideas remain unspecced but already researched — not re-litigated here except
to re-verify them still unbuilt and still accurate, since that doc is now two major
versions old: homepage link and vote-count display (both re-confirmed live below,
still absent from `Panel.qml`'s row parser — `grep` for `homepage`/`votes:` finds
nothing), `is_https`/`bitrateMin` filters (still absent, still low priority — no
clearer listener need has emerged since v3), and audio-device override (re-confirmed:
`/usr/share/omarchy/shell/plugins/panels/audio/Panel.qml` still exists and is still
Pipewire-based — the redundancy v3 found still holds).

Same rule as the prior docs: primary sources only — live Radio Browser API calls, mpv's
own docs fetched directly, a live hands-on `af add`/`af remove` test against a real mpv
instance on this machine, and this machine's actually-installed Quickshell/Omarchy shell
source — never brainstormed from memory. The current `Panel.qml` (post-v1.4.0 plus
#18–#20: `nowPlayingGenre`, `currentApiHost`/`apiServers`, `notifyProc`, `historyList` as
a fixed-height `ListView`) was re-read in full, not assumed from earlier in this session.

---

## mpv — unused JSON IPC properties

### 1. Bass boost toggle — **small, new finding, near-zero cost**

v4 checked for a full parametric equalizer and correctly ruled it out (disproportionate
UI for what the feature is worth) — but never checked FFmpeg's much smaller `bass`
filter, a single-knob shelf boost distinct from a full multi-band EQ. Confirmed live: mpv
's own `af.rst` (fetched directly) lists no native bass/equalizer filter, only pointing
to the `lavfi` wrapper for "most actual filters" — matching v4's finding. But a live,
hands-on test against a real mpv instance (loading an actual stream, not just reading
docs) confirms `af add lavfi=[bass=g=10]` succeeds immediately over the exact same JSON
IPC command this plugin's own `loudnorm` filter already uses on every connection
(`ipcSocket`'s `onConnectionStateChanged`, confirmed by reading it), and `af remove
lavfi=[bass=g=10]` (same string) cleanly removes it afterward — `get_property af`
returned `[]` post-removal. A real, working, fully toggleable filter, not just an
add-only one-way switch.

**Implementation sketch**: a small icon-only `Button` (matching the existing
Surprise/Shuffle/Trending icon-button row) toggling a new transient `property bool
bassBoostActive: false`, writing `{ command: ["af", "add", "lavfi=[bass=g=10]"] }` when
turned on and `{ command: ["af", "remove", "lavfi=[bass=g=10]"] }` when turned off — the
exact string used for both add and remove, matching how mpv's own `af remove` command
works (removes by matching filter string, confirmed live). **Open questions for a spec**:
whether the boost amount (`g=10`, confirmed live as a real, audible gain value — not
tested against every possible value) should be fixed or exposed as a level; whether the
toggle state should persist per-session (in `state`) or reset on every stream like
`nowPlayingGenre` does, since unlike loudnorm (applied unconditionally, silently), this
is a listener-visible preference the existing Compact/Expand toggle precedent suggests
listeners expect to persist.

### Not pursued further

Re-confirms v4's finding, not new: no native mpv equalizer/superequalizer exists outside
`lavfi`, and a full multi-band EQ still needs real per-band UI — still a large scope jump
not worth it without a specific listener request, unchanged from v4's verdict.

---

## Radio Browser API — re-verifying v3's still-unspecced ideas

Re-confirmed live against `https://de1.api.radio-browser.info/json/stations/search` (a
fresh call, not assumed from v3): the exact same response shape v3 found is still there.
`"homepage":"https://kiisfm.iheart.com/"` and `"votes":2616` both present on a real,
current station object. Both remain genuinely unbuilt — `grep -n "homepage\|votes:"
Panel.qml` finds nothing.

### 2. Station homepage link — **small** (re-surfacing v3 #1)

Unchanged from v3: every response already carries `homepage`, this plugin already
discards it, and a small link icon next to vote/star (opening it via
`Qt.openUrlExternally()`, still the simplest path — no first-party Omarchy plugin uses
it or `xdg-open`, confirmed by re-grepping `/usr/share/omarchy/shell/plugins/*/*.qml`,
but `xdg-open` is still present on this machine as a fallback) would let a listener visit
a station's own site. See v3 for the full writeup; nothing material has changed.

### 3. Vote count display — **small** (re-surfacing v3 #2)

Unchanged from v3: `votes` is already fetched and already used indirectly (Trending
sorts by it server-side) but never shown as a number. Appending it to the existing
codec/bitrate/tags caption line (`[row.codec, row.bitrate ? ... : "", row.tags]` already
uses `.filter(...).join(" · ")` — one more entry) remains a one-line addition. See v3 for
the full writeup.

### Not pursued further

`is_https`/`bitrateMin` filters (v3 #3) are unchanged: still technically ready, still no
clearer listener need than when v3 flagged this — not re-elevated in priority just for
being older. Audio-device override (v3 #4) is unchanged: Omarchy's own Pipewire-based
Audio panel still exists at the same path, still covers the general case; only the
narrow "just this stream" use case would justify it, and no new evidence changes that
call.

---

## Quickshell / Omarchy shell — patterns for History/Favorites

Checked whether History's new fixed-height, capped `ListView` (added since v6, shipped
in the layout-fix commit) matches an existing first-party Omarchy idiom, or whether a
better pattern exists to align it — or a future Favorites section — with.

### Investigated: a shared "capped list" pattern — **not recommended, no better idiom found**

The one first-party Omarchy plugin with a comparable embedded list, the clipboard
history panel (`/usr/share/omarchy/shell/plugins/clipboard/Clipboard.qml`), uses a
different shape entirely: its `ListView`'s height is `parent.height - headerHeight -
contentSpacing` — it fills whatever's left in an already fixed-size card, not
"content-sized up to N rows, then scrolls" the way History's `Math.min(count,
historyVisibleRows) * rowHeight` approach works. That's a different layout problem (a
fixed-size popup vs. an item embedded in a taller, independently-scrolling column) with
no shared idiom to borrow. History's own approach isn't wrong or non-idiomatic — there's
just no existing first-party precedent for this specific shape to more closely match.

Favorites has no comparable section to align in the first place: it's deliberately not a
separate list (pinned to the top of the main station list via `resortStations()`,
confirmed by reading it), a different design already settled well before this session —
not revisited here.

---

## Ranking (impact / effort)

1. **Bass boost toggle (#1)** — the only genuinely new discovery in this doc: real,
   verified live (not just read from docs), reuses the exact IPC pattern already used
   for loudnorm, fully toggleable. Smallest change with the most listener-audible effect.
2. **Homepage link (#2)** — unchanged from v3, still near-zero cost, still unbuilt.
3. **Vote count display (#3)** — unchanged from v3, equally cheap, still unbuilt.

`is_https`/`bitrateMin` filters and audio-device override remain correctly deprioritized
per v3's own reasoning, re-verified rather than re-litigated. The capped-list pattern
investigation found no actionable change — History's current approach stands as-is.
