# World Radio

An Omarchy shell bar-widget plugin for browsing and listening to live internet
radio stations from the Radio Browser directory.

## Language

**Station**:
A single live internet radio stream, identified by its Radio Browser
`stationuuid`.

**Favorites**:
A user-curated list of stations the listener has explicitly starred; entries
persist until the listener unstars them.
_Avoid_: Saved stations, bookmarks

**History**:
An automatically-maintained, size-capped list of the most recently played
distinct stations, most-recent-first, updated on every successful play and
bumped (not duplicated) on replay. Deliberately not named "Recently played"
to avoid confusion with the existing "Recently added" sort order, an
unrelated concept (directory metadata, not listener activity).
_Avoid_: Recently played, recents, play history

**Shuffle**:
A one-shot reorder of the listener's *current filtered* station list.
_Avoid_: Randomize, Surprise

**Surprise**:
A one-shot pick of a random station from an entirely random country,
ignoring the listener's current filters. Distinct from Shuffle, which
respects the current filters.
_Avoid_: Shuffle

**Sleep timer**:
A countdown that stops playback automatically after a chosen duration;
canceled if the listener picks a new station or stops playback manually.
