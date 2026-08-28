# World Radio

An [Omarchy](https://omarchy.org/) shell plugin: pick a country and (optionally) a mood
or decade, then listen to a live internet radio station from there — a lightweight nod
to [radiooooo.com](https://app.radiooooo.com/)'s "spin the globe" idea, built entirely on
the open [Radio Browser](https://www.radio-browser.info/) directory rather than any
proprietary catalog.

![World Radio panel](preview.png)

## Features

- **Country picker** — a curated grid of flags plus a live search over every country in
  the Radio Browser directory.
- **Mood and Decade filters** — optional tag chips (pop, rock, jazz, classical, 80s, 90s,
  2000s, ...) that narrow the station list; combine both at once.
- **Tuning dial** — Previous/Next buttons step through the current station list; a
  "🎲 Surprise" button spins a random country and station.
- **Favorites** — star a station to pin it to the top of its list. Favorites are stored
  in `~/.local/state/omarchy/world-radio-favorites.json` and survive shell restarts.
- **Live playback controls** — Play/Pause, Stop, and a volume slider, driven over mpv's
  JSON IPC socket (via Quickshell's native `Socket` type — no extra CLI dependency).
- **Now playing** — shows the live ICY stream title when the station sends one.
- **Hardware media keys / MPRIS** — mpv's system-wide config already auto-loads the
  `mpv-mpris` script, so `XF86AudioPlay/Pause/Stop` and any MPRIS-aware widget control
  the radio too, with no extra flags needed here.
- Two-pane layout: pickers on the left, the station list gets its own full-height pane
  on the right.

## Requirements

- [Omarchy](https://omarchy.org/) with the shell (Quickshell) plugin system.
- `mpv` for playback (with the `mpv-mpris` script for hardware media key support —
  install via `omarchy pkg add mpv-mpris` if it isn't already on your system).
- `curl` for talking to the Radio Browser API.
- `python3` (standard on Omarchy) for reading the favorites file safely — see
  [Favorites file safety](#favorites-file-safety) below.

## Install

```sh
omarchy plugin add https://github.com/Macs9319/omarchy-world-radio --enable
```

Or manually:

```sh
git clone https://github.com/Macs9319/omarchy-world-radio ~/.config/omarchy/plugins/ronnie.worldradio
omarchy plugin enable ronnie.worldradio --section right
```

## Uninstall

```sh
omarchy plugin remove ronnie.worldradio
```

This disables the plugin and deletes `~/.config/omarchy/plugins/ronnie.worldradio`. It
doesn't touch anything outside that folder — no other config files are modified. If you
also added the optional keybinding from Usage below, remove that line yourself from
`~/.config/hypr/bindings.lua`.

## Usage

Click the radio icon in the bar (or bind a key, e.g. in
`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + R", "World Radio", "omarchy-shell shell toggle ronnie.worldradio")
```

Pick a country, optionally a mood and/or decade, then click a station to play it.
Right-click the bar icon to stop, middle-click to pause/resume.

## Settings

One setting is exposed in the plugin's settings form:

- **Default volume** (0–100, default 70)

## Favorites file safety

Favorites live at `~/.local/state/omarchy/world-radio-favorites.json`, a fixed,
predictable path. Reading it goes through a small Python helper (bundled in
`Panel.qml`, not a separate file) that opens it with `O_NOFOLLOW | O_NONBLOCK`
and validates the result on the same file descriptor before reading a single
byte:

- **`O_NOFOLLOW`** refuses to open if the path is a symlink, instead of
  transparently reading whatever it points to.
- **`O_NONBLOCK`** makes opening a FIFO return immediately instead of blocking
  forever waiting for a writer.
- Only a plain regular file, checked via `fstat()` on the already-open
  descriptor (never a second lookup of the path), is read — and only up to a
  1 MiB cap, enforced by the read itself rather than trimmed afterward.

This closes both a TOCTOU window (checking and reading must be the same
open, not two lookups of a path that could change in between) and a
symlink-following gap, so a hostile or corrupted replacement at that path —
a FIFO, an oversized file, or a symlink elsewhere — can't hang or bloat the
shell process. Favorite count (500) and per-field string lengths are also
capped on both load and write.

## Notes

Station data comes from the community-run [Radio Browser](https://www.radio-browser.info/)
API. This project is not affiliated with or endorsed by radiooooo.com — it's an
independent plugin inspired by the idea of exploring the world through radio.

## License

MIT
