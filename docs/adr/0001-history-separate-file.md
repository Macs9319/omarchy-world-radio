# History gets its own on-disk file, not a second key in the favorites file

The favorites file already has a hardened read/write pattern (`O_NOFOLLOW`/
size-capped read, atomic write, debounced save) that History's storage needs
could largely copy. We still gave History its own file
(`world-radio-history.json`) rather than a second top-level key in
`world-radio-favorites.json`.

Favorites and History have different write triggers (an explicit star click
vs. every successful play) and different lifecycles (user-curated and never
auto-trimmed except at the 500 cap, vs. fully automatic and always trimmed
to 15). Sharing one file means a bug in either feature's write path risks
corrupting the other's data; separate files keep that blast radius isolated,
at the cost of duplicating the read/write plumbing across two files instead
of one.
