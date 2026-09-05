# Expand / Compact view research

Research task, not a spec: investigates whether this plugin's popup panel
could grow a two-mode view — an "Expand" mode (today's full browser) and a
"Compact" mode (a smaller/denser view) — against this repo's own `Panel.qml`,
the Omarchy shell's first-party plugin source installed on this machine, and
Quickshell's own installed `.qmltypes`. Same rule as the prior docs in this
directory: primary sources only, live-read files, no guessing at APIs.

---

## 1. What the popup shows today, and its current sizing

Read in full: `Panel.qml` (1895 lines). The popup is a `KeyboardPanel`
(`/usr/share/omarchy/shell/Ui/KeyboardPanel.qml`) with:

```qml
contentWidth: panel.fittedContentWidth(Style.space(780))
contentHeight: panel.fittedContentHeight(Style.space(4000))
```

`fittedContentWidth`/`fittedContentHeight` (defined in `KeyboardPanel.qml`,
lines 161-173) clamp a *desired* size down to `availableCardWidth`/
`availableCardHeight` — the screen minus the bar strip and margins. The
`Style.space(4000)` height is a deliberate oversized value specifically so it
always clamps to "fill the screen down to the bar/margins" (Panel.qml's own
comment, lines 1051-1056) — i.e. **today's mode already always uses the
maximum available screen height**, not a size chosen to fit its own content.
`contentWidth`/`contentHeight` are plain read/write `int` properties (see
§3), so nothing prevents binding them to something other than these two fixed
expressions.

Inside that card, `PanelKeyCatcher` holds two side-by-side panes
(`Panel.qml` lines 1064-1891):

- **Left column** (`ScrollView`, fixed `width: Style.space(320)`, lines
  1077-1635): now-playing hero (icon + station name + buffering/title),
  prev/pause/next row, stop/surprise row, trending/recently-added sort
  toggles, "Near me" geo filter + status text, a volume `PanelSlider`, then
  four independently-scrolled filter sections — Search by name (`TextField`),
  Country (16 curated flag buttons + free-text search-and-pick), Mood (10
  curated tag buttons), Decade (8 curated buttons), Language (free-text
  search-and-pick). This column already needed its own `ScrollView` (added in
  commit `a036994`, "the language filter was unreachable") because it grew
  past one screen's height.
- **Right pane** (`Item` + `ListView`, everything right of a 1px divider,
  lines 1647-1890): "STATIONS" header, loading/error/empty states, then the
  full-height `ListView` of up to 80 station rows (favicon, name, codec ·
  bitrate · tags, vote button, favorite star).

What's expensive/large about this for a compact mode: the entire right pane
(the whole station-browser `ListView`, potentially 80 rows) and most of the
left column's filter pickers (country/mood/decade/language sections, each
with its own header + `Flow`/`Repeater` of buttons) — none of that is needed
once a station is already playing. Only the "now playing hero" block
(icon/name/buffering line), the prev/pause/next + stop row, and the volume
slider are relevant to a listener who already picked a station and just wants
transport controls.

## 2. First-party Omarchy plugins — no compact/expand precedent found

Searched `/usr/share/omarchy/shell/plugins/` (bar, panels/{audio,bluetooth,
network,power,weather,dropbox,tailscale,clock,disk-speedtest,monitor,
wifiqr,speedtest}, agents, notifications, image-picker, polkit) and
`/usr/share/omarchy/shell/Ui/` for `compact|expand|collapse` (case-
insensitive grep). Two kinds of hits turned up, neither of which is a
panel-wide view-mode toggle:

- **"Compact" as an adjective for a widget, not a mode.** Audio, Bluetooth,
  Tailscale, and Dropbox panels each have the identical comment "Compact
  on/off switch on the trailing edge of the hero" (e.g.
  `/usr/share/omarchy/shell/plugins/panels/tailscale/Panel.qml:476`) — this
  describes a small `ToggleSwitch` component placed next to the hero text,
  not a panel size/content toggle. No `compact`/`expanded` boolean property
  exists anywhere in the searched tree.
- **Per-row inline expand/collapse, not whole-panel.** The network plugin's
  Wi-Fi list (`/usr/share/omarchy/shell/plugins/panels/network/Panel.qml`)
  has a `NetworkRow` component whose own comment says "Collapses to a
  one-line pill normally; expands inline to a passphrase prompt" (line
  1592-1593): `implicitHeight: rowBody.implicitHeight + (isPasswordOpen ?
  passwordPanel.implicitHeight + Style.spacing.md : 0)` (line 1668). Nearby
  (lines 1357-1364), a sibling collapsible section actually animates:
  ```qml
  Item {
    height: root.bandPillsVisible ? bandRow.implicitHeight : 0
    opacity: root.bandPillsVisible ? 1 : 0
    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  }
  ```
  This is a real, citable pattern for animated show/hide of a *section*
  inside a panel — but every first-party panel that uses `fittedContentHeight`
  (network's own `Panel.qml:986` included) still only ever computes one
  height from the currently visible content; none of them swap between two
  distinct named layouts or persist a "which mode" choice.

**Conclusion for this section**: there is no existing Omarchy first-party
precedent to copy for a whole-panel Expand/Compact toggle. The nearest
reusable idea is the height-`Behavior` pattern above, which this plugin would
apply itself, not inherit from a shared component.

## 3. What Quickshell's own window API actually allows

Read `/usr/lib/qt6/qml/Quickshell/_Window/quickshell-window.qmltypes` (the
installed module — not a guess). The base class every Quickshell window type
derives from is `ProxyWindowBase` (line 270), which declares (lines 296-330):

```
Property { name: "implicitWidth"; type: "int"; write: "setImplicitWidth"; notify: "implicitWidthChanged" }
Property { name: "implicitHeight"; type: "int"; write: "setImplicitHeight"; notify: "implicitHeightChanged" }
Property { name: "width"; type: "int"; write: "setWidth"; notify: "widthChanged" }
Property { name: "height"; type: "int"; write: "setHeight"; notify: "heightChanged" }
```

These are ordinary read/write, change-notified properties — nothing marked
`isReadonly` or `isPropertyConstant` — so a window's size genuinely can be
changed at runtime, and (being regular QML properties) a `Behavior on width`/
`Behavior on height` can be attached to animate the change, exactly as the
network plugin already does for a `height` property elsewhere (§2).

In practice, though, this plugin's actual popup (`KeyboardPanel`,
`/usr/share/omarchy/shell/Ui/KeyboardPanel.qml`) does **not** resize its own
backing `PanelWindow` at all: the `PanelWindow` itself is always
full-screen-anchored (`anchors { top: true; bottom: true; left: true; right:
true }`, line 109-114) so it can host the outside-click dismissal overlay
across the whole screen. The *visible* card is a `BorderSurface` positioned
inside that full-screen surface:

```qml
BorderSurface {
  id: card
  x: root.cardOrigin.x
  y: root.cardOrigin.y
  width: root.contentWidth
  height: root.contentHeight
  ...
}
```

(lines 379-389). `root.contentWidth`/`contentHeight` are plain `int`
properties this plugin already sets (§1) — there is no `Behavior` on either
one today, so any resize (including today's normal open/close and every
`fittedContentHeight`/`fittedContentWidth` recompute) is instant, not
animated. `cardOrigin` (lines 194-219) is a `readonly property point`
recomputed from `contentWidth`/`contentHeight` plus the anchor position, so
shrinking `contentWidth`/`contentHeight` at runtime already correctly
repositions the card (e.g. re-centers it under the bar icon) with no extra
work — this machinery is generic, not specific to this plugin's current two
fixed expressions.

**What this confirms for a toggle design**: the resize mechanism this plugin
would need already exists and is exercised on every open (recomputing
`fittedContentWidth`/`Height`) — it just needs `contentWidth`/`contentHeight`
to be driven by a mode-dependent expression instead of the two hardcoded
`Style.space(780)`/`Style.space(4000)` calls, and (if a smooth resize is
wanted rather than an instant snap) a `Behavior on width`/`Behavior on
height` added to `KeyboardPanel`'s `card` — which is a shared `qs.Ui`
component this plugin doesn't own, so a smooth animation would either need
that upstream change or be approximated by animating this plugin's own
inner content instead (fading/collapsing the browse column the way network's
`bandPillsClip` does, while the outer card size still snaps).

## 4. Existing state persistence — what a mode toggle could reuse

Grepped `Panel.qml` for persistence patterns. Two, with different
guarantees, already coexist:

- **`PersistentProperties`** (lines 67-82, `reloadableId:
  "worldradio-state"`): holds `countryCode`, `tag`, `decade`, `languageCode`,
  `sortOrder`, `volume`, the currently-playing station, and `playing`. This
  plugin's own comment (lines 168-172) states outright: "`PersistentProperties`
  ... only survives in-process QML reloads, not a real shell restart —
  confirmed by the absence of any on-disk state for it and by the first-party
  notifications service's own comment to that effect." Confirmed independently:
  `PersistentProperties` in the installed
  `/usr/lib/qt6/qml/Quickshell/quickshell-core.qmltypes` (line 753) is a plain
  `Reloadable`-derived type with only `loaded`/`reloaded` signals — no file
  path or serialization property of its own.
- **On-disk `FileView` + `Process`-based JSON** (lines 173-321): favorites
  are the one piece of state this plugin considers worth surviving an actual
  shell restart, so they get their own file
  (`~/.local/state/omarchy/world-radio-favorites.json`), read through a
  hardened `python3 -c` script (`O_NOFOLLOW`/`O_NONBLOCK`, size-capped) and
  written through `FileView.setText()` with `atomicWrites: true`, debounced
  200ms after each change.

A view-mode flag (`compact: true/false`) is exactly the same shape as
`sortOrder`/`tag`/`decade` today — a small enum-ish string/bool the panel
already re-derives its UI from — so the natural, lowest-effort place for it
is a new property on the existing `state` (`PersistentProperties`) object.
That gets it "remembered" across reopens within one shell session (which is
most of what a toggle needs — a listener rarely wants Compact to silently
revert to Expand every time they click the tray icon) but **not** across an
actual `hyprctl reload`/shell restart, matching every other filter this
plugin already has except favorites. Making it survive a real restart would
require lifting it into the favorites-file pattern instead (a second field
in that JSON, or a second small file) — a deliberate scope increase a spec
would need to call out explicitly, not something to default into.

## 5. Proposed design

**Compact mode** would show only: the now-playing hero block (icon, station
name, buffering/title line — lines 1111-1162 today), the prev/pause/next row
(1165-1209), the stop/surprise row (1211-1238), and the volume slider
(1334-1350). Everything else — Trending/Recently-added, Near me, Search by
name, Country/Mood/Decade/Language pickers, and the entire right-pane station
`ListView` — would be hidden. This mirrors exactly the subset of the left
column that's still relevant once a station is already selected, and drops
the two things flagged as expensive in §1 (the picker sections and the
80-row list).

**Expand mode** is today's existing full two-pane layout, unchanged.

**Toggle trigger**: a small button/icon in the panel header area — there
isn't a dedicated header today (the hero `Item` at lines 1111-1162 is the
top-most element in the left column, and the right pane's "STATIONS"
`PanelSectionHeader`, lines 1656-1663, is the closest thing to a title on
that side) — the natural spot is next to the hero, e.g. a small icon-only
`Button` anchored at `heroLabels.right`/`parent.right` in the hero `Item`
(lines 1111-1162), following the same `bordered: true` icon-button shape
already used throughout this file (prev/next/stop/surprise buttons), rather
than introducing a new visual language.

**Resizing mechanism**: per §3, drive `contentWidth`/`contentHeight` (set on
the `KeyboardPanel` instance, lines 1050-1056) from the new mode flag instead
of the two fixed `Style.space(...)` calls, e.g. compact mode requesting a
narrower `fittedContentWidth` (roughly the left column's own
`Style.space(320)` plus padding, since the right pane and divider would be
hidden entirely) and a `fittedContentHeight` sized to the visible content's
actual `implicitHeight` rather than the oversized
`Style.space(4000)` "fill the screen" trick — i.e. compact mode would be the
first place in this file that lets the popup shrink to its content instead
of always maximizing. This works because `contentWidth`/`contentHeight` are
plain, already-reactive properties consumed by `KeyboardPanel`'s own
`cardOrigin`/`fittedContentWidth`/`fittedContentHeight` machinery (§3) — no
change to the shared `qs.Ui` component is required for a functionally
correct (if instantly-snapping) resize. A smooth animated resize would
additionally need either an upstream `Behavior on width`/`height` on
`KeyboardPanel`'s `card` (not this plugin's file to change) or this plugin
animating its own inner content's visibility/height the way network's
`bandPillsClip` does (§2) while accepting an instant outer-card snap.

**Hiding content**: the right pane (`rightPane` `Item`, line 1648) and the
picker-section `Column`/`Flow` blocks inside `leftColumnContent` (Search by
name through Language, lines 1352-1633) would each need a `visible:
!root.compact`-style guard (or be moved into a `Loader`/conditional block) —
straightforward given every section is already a clearly-delimited sibling
in the existing `Column`.

## 6. Open questions for a spec

- **Default mode.** Should a fresh install (or a fresh shell reload, since
  `PersistentProperties` doesn't survive that per §4) open Expanded (today's
  behavior, no regression) or Compact (assumes most opens are "check/adjust
  what's already playing")? The existing `onOpenedChanged` handler
  (lines 403-407) already special-cases "reopen with something loaded" vs.
  not — a mode default could piggyback on that same `hasLoadedStations()`/
  `state.playing` distinction (e.g. default to Compact only when
  `state.playing` is true) rather than a single hardcoded default.
- **Should compact remember the last station**, or is that already implied
  since `state.stationUuid`/`stationName`/`stationUrl` (lines 78-80) already
  persist independently of any view mode? (Almost certainly the latter — no
  new persistence needed here, just display.)
- **Interaction with Surprise/Trending/Near-me**, all of which currently
  live only in the left column: should Compact mode keep Surprise (it's a
  one-tap "give me something new" action, arguably still useful compact) but
  drop Trending/Near-me (which are really browse-refinement tools)? This
  doc's §5 design keeps Surprise and drops the rest, but a spec should
  confirm that split is actually what listeners want rather than assuming.
- **Keyboard/tab order.** `PanelKeyCatcher`'s `onTabRequested` (line 1062)
  currently tabs between this plugin's panel and sibling bar panels; within
  Compact mode there are far fewer focusable controls, so whatever
  keyboard-navigation order exists today across the hidden sections would
  need to skip them cleanly rather than tab into invisible controls.
- **Resize animation.** Per §3/§5, an instantly-snapping resize is free;
  an animated one needs either an upstream `KeyboardPanel` change (outside
  this plugin) or a same-plugin approximation. Worth deciding explicitly
  rather than discovering the limitation mid-implementation.
- **Where the toggle lives once Compact is active.** If the right pane and
  most of the left column are hidden, the toggle button itself must remain
  reachable in the now-playing hero (§5) — a spec should sketch the compact
  layout's exact vertical order (hero + toggle, transport row, stop/surprise
  row, volume) rather than leave it implicit.
