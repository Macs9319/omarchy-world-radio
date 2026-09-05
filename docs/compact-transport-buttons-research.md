# Compact transport buttons research

Research task, not a spec: investigates shrinking this plugin's transport
control buttons — the Previous/Pause-Resume/Next row and the Stop/🎲 Surprise
row in `Panel.qml`'s left column — to be visually smaller and more compact,
"in the spirit of Winamp's classic transport buttons" (small, dense,
icon-first, not full-width bordered text buttons like today's). Same rule as
the prior docs in this directory: primary sources only, live-read files, no
guessing at APIs or numbers.

---

## 1. Current button block, read in full, with real current pixel sizes

`Panel.qml` lines 1164-1238, inside `leftColumnContent` (a `Column`, line
1106, `width: leftColumn.availableWidth`, itself inside the `leftColumn`
`ScrollView`, line 1078, fixed `width: Style.space(320)`):

```qml
// ---------- Tuning dial: previous / pause / next ----------
Row {
  width: parent.width
  spacing: Style.space(6)

  Button {
    width: (parent.width - parent.spacing * 2) / 3
    text: "󰒮"
    tooltipText: "Previous station"
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    enabled: stationsModel.count > 0
    opacity: enabled ? 1.0 : 0.4
    onClicked: root.playRelativeStation(-1)
  }

  Button {
    width: (parent.width - parent.spacing * 2) / 3
    text: root.paused ? "Resume" : "Pause"
    ...
    bordered: true
    ...
  }

  Button {
    width: (parent.width - parent.spacing * 2) / 3
    text: "󰒭"
    ...
    bordered: true
    ...
  }
}

Row {
  width: parent.width
  spacing: Style.space(6)

  Button {
    width: (parent.width - parent.spacing) / 2
    text: "Stop"
    ...
    bordered: true
    ...
  }

  Button {
    width: (parent.width - parent.spacing) / 2
    text: "🎲 Surprise"
    ...
    bordered: true
    ...
  }
}
```

(lines 1165-1238; the Stop/Surprise `Row` is immediately followed by a third
Row, lines 1240-1281, for Trending/Recently-added — out of scope here.)

**Notable existing detail**: the prev/next glyphs are set on the plain
`text` property, not `iconText` — so today they render at
`fontSize`'s default (`Style.font.body`), not at `iconSize`'s default
(`Style.font.icon`). See §4 for why that distinction matters for a
same-precedent rewrite.

**Real current token values**, read from
`/usr/share/omarchy/shell/Commons/Style.qml`:

```qml
readonly property int controlGap:      root.spacingToken("control-gap", 8)
readonly property int controlPaddingX: root.spacingToken("control-padding-x", 10)
readonly property int controlPaddingY: root.spacingToken("control-padding-y", 6)
readonly property int controlHeight:   root.spacingToken("control-height", 28)
```
(lines 245, 246, 247, 249 — defaults shown; `spacingToken` allows a
`shell.toml` `[spacing]` override, but these are the shipped defaults on this
machine.) And font tokens (lines 327-338):

```qml
readonly property int bodySmall: root.fontToken("body-small", root.fontPx(0.917))   // 11
readonly property int body:      root.fontToken("body",       root.fontPx(1.0))     // 12
readonly property int title:     root.fontToken("title",      root.fontPx(1.167))   // 14
readonly property int icon:      root.fontToken("icon",       title)                // 14
readonly property int iconLarge: root.fontToken("icon-large", root.fontPx(1.5))     // 18
```

`Style.spacing.controlHeight` (28) is **not** read anywhere inside
`Button.qml` itself — grepping `/usr/share/omarchy/shell/` shows it's
consumed by `NumberField.qml`, `Dropdown.qml`, `MultiSelect.qml`,
`SearchableDropdown.qml`, `ToggleSwitch.qml`, `PanelSlider.qml`, and one
first-party panel (`network/Panel.qml:1897`), but never by `Button.qml`.
Button height is purely `row.implicitHeight + verticalPadding*2 +
reservedBorder` (Button.qml lines 73-74) — it happens to land close to 28px
at these defaults, not because it's bound to the token.

**Actual current pixel math** for the 3-button row: `leftColumn` is
`Style.space(320)` wide; `leftColumnContent`'s width equals
`leftColumn.availableWidth` (≤320, minus scrollbar reserve only when the
column is actually overflowing and the vertical scrollbar is shown). Taking
320 as the no-scrollbar case: `Row.spacing = Style.space(6) = 6`, so each of
the three buttons is `(320 - 6*2) / 3 ≈ 102.7px` wide — for a single glyph or
a 4-6 character word. The 2-button Stop/Surprise row: `(320 - 6) / 2 = 157px`
per button. Both rows keep the buttons' `bordered: true` outline drawn around
that entire oversized hit area, which is the "full-width bordered text
button" look the task description is asking to move away from.

## 2. The shared `Button` component (`qs.Ui`) — icon-only is already clean

Confirmed import: `Panel.qml` line 6, `import qs.Ui`, resolving to
`/usr/share/omarchy/shell/Ui/Button.qml` (241 lines, read in full).

Sizing knobs it exposes, all plain properties a caller can override
per-instance:

```qml
property string text: ""
property string iconText: ""
property real fontSize: Style.font.body
property real iconSize: Style.font.icon
property real horizontalPadding: Style.spacing.controlPaddingX
property real verticalPadding: Style.spacing.controlPaddingY
property bool leftAlign: false
```

Layout (lines 73-74, 153-190): `implicitWidth`/`implicitHeight` are computed
from `row.implicitWidth/Height + padding*2 + reservedBorder` — `row` is an
inner `Row` with two `Text` children, one gated `visible: root.iconText !==
""` and one gated `visible: root.text !== ""`, laid out with `spacing:
Style.spacing.controlGap` between them when both are visible. **Icon-only is
not an awkward or unsupported combination** — when `text` is left at its
default `""`, that `Text` element's own `text` is empty, so it contributes
zero `implicitWidth` regardless of the `visible` binding; nothing in the
layout math assumes `text` is non-empty. This is confirmed by a real,
shipped usage, not just by reading the property list — see §4's
`BarWidget.qml` example, which sets only `iconText` and never touches `text`
at all, with no explicit `width:` needed on any of the three buttons because
`implicitWidth` alone sizes them.

## 3. Winamp classic-skin transport buttons — dimensions found, with sourcing caveats

Winamp's own `wiki.winamp.com` was unreachable in this session (DNS
resolution failure on `http://wiki.winamp.com/wiki/Main`), so its page could
not be read directly. `winampskins.neocities.org/main` (a community
skinning-tutorial site, fetched and read) explicitly states it does **not**
give exact pixel measurements — it describes what `cbuttons.bmp` is for, in
prose, without a numeric table. It does confirm the qualitative shape:
`cbuttons.bmp` "provides the images for Winamp's playback control buttons,"
laid out as one row of buttons in their normal state and a second row for
the pressed state, with the buttons' hit-area being exactly the pixels the
bitmap occupies (i.e. no extra invisible padding, unlike this plugin's
padded `Button.qml`).

An exact numeric spec was found at a long-standing skin-template README,
`https://www.alpha-ii.com/Info/Template.html` (fetched and read), which
states directly:

- **`CBUTTONS.BMP` overall size: "(136x36) — Required"**
- **"Play control buttons (23x18): Track Back, Play, Pause, Stop, and Track
  Forward"** — i.e. five buttons, each 23px wide × 18px tall, packed
  edge-to-edge left-to-right in the 136px-wide row (5 × 23 = 115, leaving a
  little slack/eject-adjacent margin in the 136px bitmap, plus a sixth,
  differently-sized Eject button)
- **"Eject (22x16): Open file(s)"**
- **"Main window (275x102)"** displayable area, out of a 275×116 total
  background graphic

This matches the "23×18px per button" figure commonly cited in
skinning-community discussion (also echoed, without an exact source, in the
web search results for this topic), and is corroborated independently by
`CBUTTONS.BMP`'s own stated 136×36 total size: 36px tall over two rows
(normal + pressed) is 18px per row, consistent with the 18px button height
figure. **Caveat, stated plainly**: `alpha-ii.com` is a community
skin-template resource, not Winamp's own official documentation page (which
this session could not reach) — but its numbers are internally consistent
with `CBUTTONS.BMP`'s own bitmap-size arithmetic above, so they're treated
here as reliable rather than a guess. No text label appears on any of these
buttons — they're pure icon glyphs baked into the bitmap, packed with no
visible gap between adjacent buttons and no border/background box drawn
around each one individually (the whole row sits on the flush window
background).

## 4. Existing icon-only/compact button precedent in Omarchy's own shell

Grepped `/usr/share/omarchy/shell/plugins/` for `iconText:` usage. Nine
files matched; the directly relevant one is
`/usr/share/omarchy/shell/plugins/services/media/BarWidget.qml` — the
first-party **media-player transport widget**, i.e. the exact same
prev/pause-or-play/next concept this plugin implements for radio stations.
Read in full (313 lines); the transport row (lines 187-221):

```qml
Row {
  anchors.horizontalCenter: parent.horizontalCenter
  spacing: Style.space(6)

  Button {
    iconText: "󰒮"
    foreground: root.bar.foreground
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY
    enabled: root.activePlayer && root.activePlayer.canGoPrevious
    opacity: enabled ? 1.0 : 0.4
    onClicked: ...
  }

  Button {
    iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
    foreground: root.bar.foreground
    horizontalPadding: Style.spacing.panelGap
    verticalPadding: Style.spacing.controlPaddingY
    iconSize: Style.font.iconLarge
    enabled: ...
    opacity: enabled ? 1.0 : 0.4
    onClicked: ...
  }

  Button {
    iconText: "󰒭"
    foreground: root.bar.foreground
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY
    enabled: root.activePlayer && root.activePlayer.canGoNext
    opacity: enabled ? 1.0 : 0.4
    onClicked: ...
  }
}
```

Key differences from this plugin's current buttons, all real and citable:

- **`iconText`, not `text`** — correctly uses `Style.font.icon` (14px
  default) as the glyph's font size, not `Style.font.body` (12px).
- **No `bordered: true`** — these buttons are borderless at rest (a border
  only appears transiently on hover/focus, per `Button.qml`'s state
  precedence, §2/pre-existing behavior of the shared component), unlike this
  plugin's `bordered: true` on every transport button.
- **No explicit `width:` at all** — each button is left to its
  `implicitWidth` (icon glyph + padding + reserved border), not forced to a
  fraction of the row's width. This is the direct, shipped precedent for
  "icon-first, dense, not full-width."
- **The play/pause button gets a bigger `iconSize` (`Style.font.iconLarge`,
  18px) and wider `horizontalPadding` (`Style.spacing.panelGap`, 14px vs.
  the neighbors' `controlPaddingX`, 10px)** — a deliberate "primary action is
  slightly larger" treatment, while prev/next stay at the smaller default
  size. This is a real, in-repo precedent for asymmetric sizing within one
  transport row, not a hypothetical.
- **The glyphs themselves**: `󰒮`/`󰒭` (prev/next) are the identical codepoints
  this plugin already uses (`Panel.qml` lines 1171, 1198) — direct visual
  continuity is free. Play/pause use `󰏤` (pause) and `󰐊` (play) — codepoints
  not currently used anywhere in `Panel.qml` (confirmed: grepping `Panel.qml`
  for its non-ASCII `text:` literals turns up only `󰐹` (hero radio icon,
  lines 1025, 1117), `󰒮`/`󰒭` (prev/next), and plain emoji `🎲`/`🔥`/`🆕`/`📍`
  for Surprise/Trending/Recently-added/Near-me, plus `✕` for two close
  buttons — no stop or play/pause glyph exists in this plugin today). Since
  `BarWidget.qml` already ships `󰏤`/`󰐊` in the same shell, on the same
  Nerd-Font-resolved `fontFamily` machinery (`Style.font.family` /
  `root.bar.fontFamily`), these glyphs are proven to render correctly on
  this exact install — not a guess about font coverage.
- **No stop-icon precedent anywhere**: grepped
  `/usr/share/omarchy/shell/` broadly for a stop-button glyph/codepoint and
  found none — `BarWidget.qml`'s media widget has no Stop button at all (it
  only exposes previous/play-pause/next). A plausible candidate codepoint,
  `󰓛` (Material Design Icons' `nf-md-stop`, `U+F04DB`), is in the same
  Nerd Font icon family as the already-used `󰒮`/`󰒭`/`󰏤`/`󰐊` glyphs, but
  its actual rendering on this install was **not verified** — there is no
  existing usage anywhere in the searched tree to confirm it, unlike the
  prev/next/play/pause glyphs above.

## 5. Concrete size options for this plugin's transport row

All three keep the existing `Button` component and `Style` tokens; none
require a shared-component or `Style.qml` change.

### Option A — icon-only, content-sized, no forced width — **small**

Swap `text: "󰒮"` / `text: "󰒭"` for `iconText: "󰒮"` / `iconText: "󰒭"`
(matching `BarWidget.qml` exactly), give Pause/Resume `iconText: root.paused
? "󰐊" : "󰏤"` (dropping its text label entirely, reusing the same glyphs
already shipped and rendering correctly in `BarWidget.qml`), drop the
`width: (parent.width - parent.spacing * 2) / 3` line from all three buttons
so each sizes to `implicitWidth` (glyph + `controlPaddingX*2` + reserved
border), keep `bordered: true` or drop it to match `BarWidget.qml`'s
borderless-at-rest look, and wrap the `Row` with
`anchors.horizontalCenter: parent.horizontalCenter` (as `BarWidget.qml`
does) since an un-widthed `Row` no longer fills the column on its own.
Concretely, at default tokens, each button becomes roughly
`14px (iconSize) + 10px*2 (controlPaddingX) + border ≈ 34-36px` wide instead
of ~103px — a size reduction of roughly two-thirds, with height essentially
unchanged (`Style.font.icon`'s line height + `controlPaddingY*2` is close to
today's `Style.font.body`-driven height already).
**Tradeoff**: "Pause"/"Resume" becomes a single glyph with no text label —
a listener has to learn `󰏤`/`󰐊` mean pause/play (mitigated by
`tooltipText`, which this plugin already sets on prev/next and could add
here too).

### Option B — Option A plus reduced padding and a fixed square size — **medium**

Everything in Option A, plus replace `horizontalPadding:
Style.spacing.controlPaddingX` / `verticalPadding:
Style.spacing.controlPaddingY` with smaller explicit values (e.g.
`Style.spacing.sm` = 4 for both, per `Style.qml` line 237, or a literal
`Style.space(4)`), and give each button an explicit fixed `width`/`height`
(e.g. `Style.space(28)` square, echoing the existing-but-unused-by-Button
`controlHeight` token) instead of relying on `implicitWidth`, so all three
(or five, if Stop joins) buttons in a row are visually uniform small squares
rather than each sized to its own glyph's metrics. This is the more
literally "Winamp-like" density (§3's 23×18 is close to a 28px square, just
not identical), at the cost of one more explicit sizing decision this repo
would need to own (today nothing in this file hardcodes a pixel-square
button; `Style.space(28)` would be the first).
**Tradeoff**: uniform sizing looks tidier as a row, but a fixed 28px-ish
square is noticeably larger than a bare `implicitWidth` glyph button (Option
A), so it's a smaller shrink than A, traded for tidier alignment.

### Option C — literal Winamp pixel dimensions, borderless, edge-to-edge — **investigated, not recommended**

Hardcode `width: Style.space(23); height: Style.space(18)` per button (§3's
actual cited numbers), `bordered: false`, `spacing: 0` on the `Row` so
buttons touch edge-to-edge exactly as `CBUTTONS.BMP` does. **Not
recommended**: 18px is well under this shell's own `controlHeight` token
(28, §1) and under every other interactive control's height elsewhere in
this same left column (sort toggles, filter buttons, the volume slider's
own `Style.spacing.controlHeight`-derived knob/track sizing) — adopting it
literally would make the transport row visually and functionally
inconsistent with the rest of this plugin's own UI (smaller touch target,
different rhythm), for the sake of matching a 1997 bitmap's exact pixel
count rather than "in the spirit of." Options A/B already deliver the
qualitative Winamp effect (small, icon-first, dense) using this shell's own
existing size vocabulary instead.

## 6. Open questions for a spec

- **Does "Winamp-style" mean icon-only + small (Options A/B), or literally
  row-packed edge-to-edge with zero gaps (closer to Option C's `spacing: 0`
  but at this shell's own sizes, not the literal 23×18)?** This doc treats
  the two as separable: edge-to-edge packing (`Row.spacing: 0`) could be
  layered onto Option A/B independently of adopting Option C's literal pixel
  dimensions.
- **Should Stop/Surprise get the same treatment, or stay as they are?**
  Stop has no verified-rendering icon precedent in this codebase or anywhere
  searched in `/usr/share/omarchy/shell/` (§4) — only the unverified `󰓛`
  candidate codepoint. Surprise already uses a plain emoji (`🎲`) rather
  than a Nerd Font glyph from the same family as prev/next/play/pause/hero
  — there is no dice/shuffle glyph already in use anywhere in this plugin to
  match against, so shrinking Surprise to icon-only would mean keeping the
  emoji alone (dropping the word "Surprise") rather than switching to a
  Nerd Font glyph the way prev/next/pause can. A spec should decide
  explicitly whether Stop/Surprise shrink the same way (accepting the
  unverified stop-glyph risk, and an emoji-only Surprise button) or are left
  as today's bordered text buttons, visually inconsistent with a
  now-compact transport row above them.
- **Tooltips as the accessibility backstop for icon-only labels.** Prev/next
  already set `tooltipText` (Panel.qml lines 1172, 1199); Pause/Resume and
  Stop currently don't. If Pause/Resume/Stop lose their text labels (Options
  A/B), a spec should confirm `tooltipText` gets added to them too, matching
  the pattern already established two lines above in the same file.
- **Row-fill vs. content-sized layout change.** Today's `Row { width:
  parent.width }` with each `Button`'s width forced to a fraction is a
  layout contract this plugin relies on elsewhere too (the identically-
  shaped Trending/Recently-added row, lines 1240-1281, and Country/Mood/
  Decade `Flow`s) — switching only the transport rows to content-sized,
  horizontally-centered buttons (Option A/B) makes them visually
  inconsistent in *alignment logic* (though not necessarily in a bad way)
  with every other 2-3-button row in this same column. Worth deciding
  whether that's an acceptable, deliberate visual distinction ("transport
  controls look different from filter controls") or something a spec wants
  to avoid.
