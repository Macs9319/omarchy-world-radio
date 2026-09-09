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
— at the time this was named, a "Recently added" sort order also existed
(directory metadata, not listener activity; since removed), and the two
names sitting side by side would have been a near-miss confusion.
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

**Volume boost**:
The volume slider's range above 100%, up to mpv's own 130 ceiling. A
continuous slider position, not a toggle — distinct from Deep bass, a
discrete on/off control that sits in the same area of the panel.
_Avoid_: Bass boost, boosted volume

**Deep bass**:
A toggleable low-frequency shelf boost (mpv's `bass` audio filter), on or
off, persisted as a listener preference across the session. Deliberately
not named "Bass boost" to avoid the word "boost" appearing twice next to
the volume slider — see Volume boost.
_Avoid_: Bass boost, bass toggle
