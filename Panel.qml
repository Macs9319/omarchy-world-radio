import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// World Radio: pick a country (and optionally a mood/genre), get a live
// internet radio station from there and play it — a lightweight nod to
// radiooooo.com's "spin the globe" idea, built on the open Radio Browser
// directory (api.radio-browser.info) rather than any proprietary catalog.
//
// Playback goes through mpv, driven over its JSON IPC socket (Quickshell's
// native Socket type, so no extra CLI dependency like socat/ncat is needed)
// so volume/pause can be controlled live without restarting the stream.
//
// mpv's system-wide config auto-loads the mpv-mpris script for every
// instance, so this already answers to hardware media keys / MPRIS
// (Play/Pause/Stop) without any extra flag here — confirmed live: pausing
// through the shell's own media IPC toggles mpv's pause property. The
// pause/metadata observers below exist so this panel's own Pause/Resume
// label and now-playing title stay correct the instant playback changes
// that way instead of from here.
Panel {
  id: root
  moduleName: "ronnie.worldradio"
  ipcTarget: "ronnie.worldradio"

  readonly property string apiHost: "https://de1.api.radio-browser.info"
  readonly property string userAgent: "OmarchyWorldRadio/1.0 (+https://omarchy.org)"
  readonly property int defaultVolume: setting("defaultVolume", 70)
  // Shared by playStation() (click-tracking) and voteForStation() — both
  // build a URL from an API-supplied stationuuid and need the same shape
  // check before trusting it.
  readonly property var stationUuidPattern: /^[0-9a-fA-F-]{8,64}$/

  // IDs for mpv's observe_property, referenced in both handleMpvMessage and
  // the IPC connect handler — kept as named constants so a future observed
  // property can't silently collide with one of these.
  readonly property int metadataObserveId: 1
  readonly property int pauseObserveId: 2
  readonly property int pausedForCacheObserveId: 3
  readonly property int cacheBufferingStateObserveId: 4

  readonly property var curatedCountries: [
    { code: "US", name: "United States" },
    { code: "BR", name: "Brazil" },
    { code: "GB", name: "United Kingdom" },
    { code: "FR", name: "France" },
    { code: "DE", name: "Germany" },
    { code: "NL", name: "Netherlands" },
    { code: "JP", name: "Japan" },
    { code: "KR", name: "South Korea" },
    { code: "AU", name: "Australia" },
    { code: "MX", name: "Mexico" },
    { code: "AR", name: "Argentina" },
    { code: "ZA", name: "South Africa" },
    { code: "TH", name: "Thailand" },
    { code: "MY", name: "Malaysia" },
    { code: "SG", name: "Singapore" },
    { code: "PL", name: "Poland" }
  ]

  readonly property var curatedTags: ["pop", "rock", "jazz", "classical", "electronic", "reggae", "hiphop", "folk", "news", "talk"]
  readonly property var curatedDecades: ["50s", "60s", "70s", "80s", "90s", "2000s", "2010s", "2020s"]

  PersistentProperties {
    id: state
    reloadableId: "worldradio-state"
    property string countryCode: ""
    property string countryName: ""
    property string tag: ""
    property string decade: ""
    property string languageCode: ""
    property string languageName: ""
    property string sortOrder: ""
    property int volume: root.defaultVolume
    property string stationUuid: ""
    property string stationName: ""
    property string stationUrl: ""
    property bool playing: false
  }

  property bool paused: false
  property string nowPlayingTitle: ""
  property bool buffering: false
  property int bufferingPercent: 0
  property bool pendingSurprise: false

  // True for the one mpvProc.exited that fires because playStation() killed
  // the previous station to switch to a new one. Killing an external process
  // is asynchronous, so that exit signal can land after the new station has
  // already started — without this guard, onExited's "really stopped" reset
  // would clobber state.playing (disabling Stop/Pause) and cancel the new
  // station's socket reconnect, even though it's actively playing.
  property bool switchingStation: false

  // Same guard shape as switchingStation above, for stationsProc: set
  // when a running fetch is killed for a restart or an intentional clear,
  // consumed by onExited so a killed fetch's belated result can't clobber
  // state a newer fetch (or the clear) already set.
  property bool stationsSwitching: false

  // "👍 vote" state. Transient (not in `state`) — vote feedback is
  // inherently momentary, not something worth surviving a shell restart.
  // Unlike stationsProc/geoLocationProc, a new vote never kills an
  // in-flight one (voteForStation() below just ignores the click) —
  // votes are cheap, infrequent, and keyed per-station-uuid, so there's
  // no "supersede the old one" case to reconcile, and no possibility of
  // a killed request's stale response racing a fresh one for the same
  // reused Process.
  // Both the uuid voteProc's command is currently built from and the uuid
  // whose row should show the in-flight state — always the same value
  // (voteForStation() is single-flight, never superseded mid-request),
  // so one property covers both rather than two kept manually in sync.
  property string voteInFlightUuid: ""
  // voteUuid/voteOk are a single shared slot, not a per-station map:
  // voting on a second station while the first's feedback is still
  // showing will replace it early once the second vote completes,
  // rather than each row tracking its own independent feedback window.
  // Accepted deliberately — a per-uuid feedback map would be real
  // complexity for a cosmetic-only edge case (two votes within the same
  // few seconds), disproportionate to how small this feature is meant
  // to be; the failure mode is a checkmark clearing a little early, never
  // wrong or stuck data.
  property string voteUuid: ""
  property bool voteOk: false

  property bool loadingCountries: false
  property string countriesError: ""
  property var allCountries: []
  property string countryQuery: ""
  property var countryMatches: []

  property bool loadingLanguages: false
  property string languagesError: ""
  property var allLanguages: []
  property string languageQuery: ""
  property var languageMatches: []

  // "Near me" geo filter. Deliberately transient (not in `state`), unlike
  // a country or language choice: an IP-derived location can go stale
  // (the machine moves, a VPN changes), so it's looked up fresh each time
  // it's requested rather than carried over from a previous session.
  readonly property int geoDistanceMeters: 50000
  property bool geoActive: false
  property real geoLat: 0
  property real geoLong: 0
  property string geoLabel: ""
  property bool loadingGeo: false
  property string geoError: ""
  // Same guard shape as stationsSwitching above, for geoLocationProc,
  // after a deliberate kill-for-restart (a refresh, a clear, or Surprise).
  property bool geoLookupCancelled: false

  // Free-text station-name filter. Transient (not in `state`): cleared on a
  // shell restart, like countryQuery. Passed straight through to the Radio
  // Browser search as its `name` parameter, AND-ed with country/mood/decade.
  property string nameQuery: ""

  property bool loadingStations: false
  property string stationsError: ""

  property string ipcSocketPath: ""

  // Starred stations, keyed by stationuuid: { uuid, name, playUrl, codec,
  // bitrate, tags }. PersistentProperties (see `state` above) only survives
  // in-process QML reloads, not a real shell restart — confirmed by the
  // absence of any on-disk state for it and by the first-party notifications
  // service's own comment to that effect. Favorites need to actually survive
  // a restart to be worth starring, so they get their own on-disk file
  // instead, following that same service's FileView + debounced-save pattern.
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/"
  readonly property string favoritesPath: stateDir + "world-radio-favorites.json"
  property var favorites: ({})
  property bool favoritesLoaded: false

  // Bounds enforced on the favorites file itself (see favoritesReadProc)
  // and on every entry loaded from or written to it. The path is fixed and
  // predictable, so nothing should ever hand its raw content to JSON.parse
  // or the model without these checked first: a hostile or corrupted
  // replacement (a FIFO swapped in at that path, or just an oversized file)
  // must not be able to block or balloon the shell's memory.
  readonly property int maxFavoritesFileBytes: 1048576
  readonly property int maxFavorites: 500

  ListModel { id: stationsModel }

  Process { id: ensureStateDirProc; command: ["mkdir", "-p", root.stateDir]; running: false }

  // Earlier versions of this read went through progressively narrower gaps:
  // a separate stat-by-path then FileView.reload() (two path lookups, so
  // the path could be repointed between them); then a single bash fd
  // (exec 3<> "$path") checked via /proc/self/fd/3 — which closed that
  // race but still transparently followed a symlink at favoritesPath,
  // since plain open()/bash redirection has no way to refuse one.
  //
  // Bash's redirection operators can't express O_NOFOLLOW, so this uses
  // Python's os.open() to get the real flags: O_NOFOLLOW makes the open
  // itself fail if favoritesPath's final component is a symlink (rather
  // than silently reading whatever it points to), and O_NONBLOCK makes
  // opening a FIFO return immediately instead of blocking for a reader.
  // Every check after that — regular-file, size — runs via fstat() on the
  // already-open fd, and the read is capped at maxFavoritesFileBytes, so
  // nothing about the path is ever consulted a second time and nothing
  // past the cap is ever read off disk.
  //
  // Verified locally against all five cases before shipping: missing path,
  // a valid file, an oversized file, a FIFO with no writer, and a symlink
  // to an otherwise-legitimate regular file elsewhere — only the valid
  // file's content comes back; everything else exits non-zero with no
  // stdout, which loadFavorites("") already treats as "no favorites yet".
  readonly property string favoritesReadScript: `
import os, sys, stat as statmod
path, max_bytes = sys.argv[1], int(sys.argv[2])
try:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
except OSError:
    sys.exit(1)
try:
    st = os.fstat(fd)
    if not statmod.S_ISREG(st.st_mode) or st.st_size > max_bytes:
        sys.exit(1)
    chunks, remaining = [], max_bytes
    while remaining > 0:
        chunk = os.read(fd, min(65536, remaining))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    sys.stdout.buffer.write(b"".join(chunks))
except OSError:
    sys.exit(1)
finally:
    os.close(fd)
  `

  Process {
    id: favoritesReadProc
    command: ["python3", "-c", root.favoritesReadScript, root.favoritesPath, String(root.maxFavoritesFileBytes)]
    stdout: StdioCollector {
      // Empty on any failure branch above (missing path, symlink, non-
      // regular, oversized) — loadFavorites("") already treats that as
      // "no favorites yet", so no separate exit-code handling is needed.
      onStreamFinished: root.loadFavorites(String(text || ""))
    }
  }

  // Write-only: setText()/atomicWrites for persisting favorites back out.
  // Reading goes through favoritesReadProc instead, never through this.
  FileView {
    id: favoritesFile
    path: root.favoritesPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Timer {
    id: favoritesSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushFavorites()
  }

  // Clears a completed vote's row-level feedback (voteUuid) a few seconds
  // after it's shown, so a success/failure icon doesn't linger forever.
  Timer {
    id: voteFeedbackTimer
    interval: 3000
    repeat: false
    onTriggered: root.voteUuid = ""
  }

  // Debounces the name-search field so a request fires ~350ms after the last
  // keystroke rather than on every character. reloadOrClear() handles the
  // "nothing left to search by at all" case by clearing the list instead
  // of pulling the global top stations.
  Timer {
    id: nameSearchTimer
    interval: 350
    repeat: false
    onTriggered: root.reloadOrClear()
  }

  function loadFavorites(raw) {
    if (root.favoritesLoaded) return
    var parsed = {}
    var count = 0
    try {
      var data = JSON.parse(raw || "")
      if (data && typeof data === "object" && data.favorites && typeof data.favorites === "object") {
        for (var uuid in data.favorites) {
          if (count >= root.maxFavorites) break
          var f = data.favorites[uuid]
          if (!f || typeof f !== "object") continue
          var safeUuid = String(uuid).slice(0, 64)
          var name = String(f.name || "").slice(0, 200)
          var playUrl = String(f.playUrl || "").slice(0, 2000)
          // Re-validated on load, not just on write — a hand-edited or
          // corrupted file shouldn't be able to hand mpv a non-http(s) URL.
          if (!safeUuid || !name || !/^https?:\/\//i.test(playUrl)) continue
          parsed[safeUuid] = {
            uuid: safeUuid,
            name: name,
            playUrl: playUrl,
            codec: String(f.codec || "").slice(0, 32),
            bitrate: Math.max(0, Math.min(9999999, Number(f.bitrate) || 0)),
            tags: String(f.tags || "").slice(0, 500)
          }
          count++
        }
      }
    } catch (e) { }
    root.favorites = parsed
    root.favoritesLoaded = true
  }

  function flushFavorites() {
    favoritesFile.setText(JSON.stringify({ version: 1, favorites: root.favorites }, null, 2) + "\n")
  }

  function scheduleFavoritesSave() {
    if (!root.favoritesLoaded) return
    favoritesSaveTimer.restart()
  }

  function isFavorite(uuid) {
    return Object.prototype.hasOwnProperty.call(root.favorites, uuid)
  }

  function toggleFavorite(row) {
    if (!row || !row.uuid) return
    var next = {}
    for (var k in root.favorites) next[k] = root.favorites[k]
    if (next[row.uuid]) {
      delete next[row.uuid]
    } else if (Object.keys(next).length < root.maxFavorites) {
      next[row.uuid] = {
        uuid: String(row.uuid).slice(0, 64),
        name: String(row.name).slice(0, 200),
        playUrl: String(row.playUrl).slice(0, 2000),
        codec: String(row.codec).slice(0, 32),
        bitrate: Math.max(0, Math.min(9999999, Number(row.bitrate) || 0)),
        tags: String(row.tags).slice(0, 500)
      }
    }
    root.favorites = next
    root.scheduleFavoritesSave()
    root.resortStations()
  }

  // Ignores the click (rather than killing and restarting, as
  // loadStations()/findNearMe() do) whenever any vote is already in
  // flight — votes are cheap and infrequent enough that making the user
  // wait for the previous one to resolve is simpler and fully correct,
  // with no killed-process-vs-fresh-request ambiguity to reconcile.
  function voteForStation(uuid) {
    // Same shape check already applied before clickProc's click-tracking
    // request in playStation() — the station data driving this call comes
    // from the same untrusted API response, so it gets the same guard.
    if (!uuid || !root.stationUuidPattern.test(uuid) || voteProc.running) return
    root.voteInFlightUuid = uuid
    // Only clears voteUuid/stops the timer when re-voting the *same* row
    // that's currently showing feedback — otherwise this would revert to
    // the idle icon mid-request, misleadingly looking like nothing is
    // happening. A *different* row's still-displaying feedback is left
    // alone; voteProc's own completion handler owns setting/timing that.
    if (root.voteUuid === uuid) {
      voteFeedbackTimer.stop()
      root.voteUuid = ""
    }
    voteProc.running = true
  }

  // Stable-partitions the currently loaded list so favorited stations sit
  // above everything else, without disturbing relative order otherwise.
  // Called after a fresh search and whenever a favorite is toggled, so a
  // star applied to a station already on screen jumps it to the top live.
  function resortStations() {
    var rows = []
    for (var i = 0; i < stationsModel.count; i++) {
      var r = stationsModel.get(i)
      rows.push({ uuid: r.uuid, name: r.name, playUrl: r.playUrl, codec: r.codec, bitrate: r.bitrate, tags: r.tags, favicon: r.favicon })
    }
    rows.sort(function(a, b) {
      var af = root.isFavorite(a.uuid) ? 0 : 1
      var bf = root.isFavorite(b.uuid) ? 0 : 1
      return af - bf
    })
    stationsModel.clear()
    for (var j = 0; j < rows.length; j++) stationsModel.append(rows[j])
  }

  Component.onCompleted: {
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR")
    ipcSocketPath = (runtimeDir && runtimeDir.length > 0 ? runtimeDir : "/tmp") + "/omarchy-worldradio-" + Math.floor(Math.random() * 1e9) + ".sock"

    ensureStateDirProc.running = true
    Qt.callLater(function() { favoritesReadProc.running = true })
  }

  onOpenedChanged: {
    if (root.opened && root.hasLoadedStations() && stationsModel.count === 0 && !stationsProc.running) {
      root.loadStations()
    }
  }

  function flagFor(code) {
    if (!code || !/^[A-Za-z]{2}$/.test(code)) return "🌐"
    var cc = code.toUpperCase()
    return String.fromCodePoint(cc.charCodeAt(0) - 65 + 0x1F1E6, cc.charCodeAt(1) - 65 + 0x1F1E6)
  }

  function selectCountry(code, name) {
    state.countryCode = code
    state.countryName = name
    root.countryQuery = ""
    root.countryMatches = []
    // A stale "Near me" filter would otherwise AND a brand-new country
    // pick with an unrelated location, almost always yielding zero
    // results with no visible explanation why.
    root.resetGeoFilter()
    root.loadStations()
  }

  // A country pick isn't the only thing that already produces (or should
  // produce) a station list — a worldwide name search or a language-only
  // pick does too. Toggling a filter in any of those states needs to
  // reload, or the UI shows the new filter as active while the visible
  // list silently keeps ignoring it.
  function hasLoadedStations() {
    return state.countryCode !== "" || root.nameQuery.trim() !== "" || state.languageCode !== "" || root.geoActive
  }

  // Killing an already-running stationsProc is asynchronous — its exit
  // can land after the caller has already moved on. Shared by
  // loadStations() and reloadOrClear()'s empty-clear branch.
  function killStationsProc() {
    if (stationsProc.running) root.stationsSwitching = true
    stationsProc.running = false
  }

  // Shared by nameSearchTimer and every "clear a filter" function: reload
  // if any filter is still active, or clear the list directly if not —
  // never fall through to loadStations() with nothing set, which would
  // otherwise pull the unfiltered global top-80.
  function reloadOrClear() {
    if (root.hasLoadedStations()) {
      root.loadStations()
    } else {
      root.killStationsProc()
      stationsModel.clear()
      root.stationsError = ""
      root.loadingStations = false
    }
  }

  function toggleTag(tagName) {
    state.tag = state.tag === tagName ? "" : tagName
    if (root.hasLoadedStations()) root.loadStations()
  }

  function toggleDecade(decadeName) {
    state.decade = state.decade === decadeName ? "" : decadeName
    if (root.hasLoadedStations()) root.loadStations()
  }

  // Mutually exclusive with itself only (not with tag/decade, which stay
  // independent filters): picking "votes" while "changetimestamp" is active
  // switches directly, and re-picking the active one clears back to the
  // default clickcount ordering — same "one active value" toggle shape as
  // toggleTag/toggleDecade, applied to a single field.
  function toggleSortOrder(order) {
    state.sortOrder = state.sortOrder === order ? "" : order
    if (root.hasLoadedStations()) root.loadStations()
  }

  function selectLanguage(code, name) {
    state.languageCode = code
    state.languageName = name
    root.languageQuery = ""
    root.languageMatches = []
    if (root.hasLoadedStations()) root.loadStations()
  }

  function clearLanguage() {
    state.languageCode = ""
    state.languageName = ""
    root.reloadOrClear()
  }

  // Killing an already-running geoLocationProc is asynchronous — its
  // completion can land after the caller has already moved on. Shared by
  // findNearMe() and resetGeoFilter() so the kill sequence only needs to
  // be right in one place.
  function killGeoLookup() {
    if (geoLocationProc.running) root.geoLookupCancelled = true
    geoLocationProc.running = false
  }

  // Fetches (or refreshes, if already active) the listener's approximate
  // location via IP geolocation, then applies it as a search filter once
  // resolved — findNearMe()'s own onStreamFinished handler does the actual
  // state update and reload, since the lookup is asynchronous.
  function findNearMe() {
    root.geoError = ""
    root.loadingGeo = true
    root.killGeoLookup()
    Qt.callLater(function() { geoLocationProc.running = true })
  }

  // Stops a lookup that might still be in flight — otherwise it could
  // complete afterward and silently reinstate a filter that was just
  // dropped, or re-filter an unrelated pick by a stale location. Shared by
  // clearGeo() and surpriseMe() so a future fix (like the missing
  // geoError reset this helper replaced) only needs to happen once.
  function resetGeoFilter() {
    root.killGeoLookup()
    root.loadingGeo = false
    root.geoError = ""
    root.geoActive = false
    root.geoLat = 0
    root.geoLong = 0
    root.geoLabel = ""
  }

  function clearGeo() {
    root.resetGeoFilter()
    root.reloadOrClear()
  }

  function surpriseMe() {
    // Drop any name/language filter first, or the random country would be
    // searched through a stale term and almost always come back empty.
    // (selectCountry(), called below, resets the geo filter on its own.)
    nameField.text = ""
    root.nameQuery = ""
    state.languageCode = ""
    state.languageName = ""
    var pick = root.curatedCountries[Math.floor(Math.random() * root.curatedCountries.length)]
    root.pendingSurprise = true
    root.selectCountry(pick.code, pick.name)
  }

  function loadStations() {
    root.stationsError = ""
    root.loadingStations = true
    stationsModel.clear()
    root.killStationsProc()
    Qt.callLater(function() { stationsProc.running = true })
  }

  // Shared by the country and language pickers: case-insensitive substring
  // match against a fetch-once-cached { code, name } list, capped so a
  // broad query (e.g. a single letter) doesn't dump the whole list.
  function matchesFor(items, query) {
    var q = query.trim().toLowerCase()
    if (q.length === 0) return []
    var out = []
    for (var i = 0; i < items.length && out.length < 8; i++) {
      if (items[i].name.toLowerCase().indexOf(q) !== -1) out.push(items[i])
    }
    return out
  }

  function updateCountryMatches() {
    root.countryMatches = root.matchesFor(root.allCountries, root.countryQuery)
  }

  function ensureCountriesLoaded() {
    if (root.allCountries.length > 0 || countriesProc.running) return
    root.countriesError = ""
    root.loadingCountries = true
    countriesProc.running = true
  }

  function updateLanguageMatches() {
    root.languageMatches = root.matchesFor(root.allLanguages, root.languageQuery)
  }

  function ensureLanguagesLoaded() {
    if (root.allLanguages.length > 0 || languagesProc.running) return
    root.languagesError = ""
    root.loadingLanguages = true
    languagesProc.running = true
  }

  // Shared by playStation(), stopPlayback(), and mpvProc.onExited's
  // "really stopped" cleanup: every piece of mpv-observed playback display
  // state, reset together so a future observed property can't be added to
  // one reset site and forgotten in another.
  function resetPlaybackDisplay() {
    root.paused = false
    root.nowPlayingTitle = ""
    root.buffering = false
    root.bufferingPercent = 0
  }

  function playStation(uuid, name, url) {
    if (!/^https?:\/\//i.test(url)) return
    state.stationUuid = uuid
    state.stationName = name
    state.stationUrl = url
    state.playing = true
    root.resetPlaybackDisplay()

    if (mpvProc.running) root.switchingStation = true
    ipcSocket.connected = false
    mpvProc.running = false
    Qt.callLater(function() {
      mpvProc.running = true
      ipcRetryTimer.attempts = 0
      ipcRetryTimer.restart()
    })

    if (root.stationUuidPattern.test(uuid)) {
      clickProc.running = false
      Qt.callLater(function() { clickProc.running = true })
    }
  }

  // Steps to the previous/next station in the currently loaded list, like
  // turning a tuning dial. Starts from the top of the list if nothing (or
  // something no longer in the list) is playing.
  function playRelativeStation(delta) {
    if (stationsModel.count === 0) return
    var idx = -1
    for (var i = 0; i < stationsModel.count; i++) {
      if (stationsModel.get(i).uuid === state.stationUuid) { idx = i; break }
    }
    var nextIdx = idx === -1 ? 0 : (idx + delta + stationsModel.count) % stationsModel.count
    var s = stationsModel.get(nextIdx)
    root.playStation(s.uuid, s.name, s.playUrl)
  }

  function togglePause() {
    if (!state.playing || !ipcSocket.connected) return
    root.paused = !root.paused
    ipcSocket.write(JSON.stringify({ command: ["set_property", "pause", root.paused] }) + "\n")
    ipcSocket.flush()
  }

  function stopPlayback() {
    if (ipcSocket.connected) {
      ipcSocket.write(JSON.stringify({ command: ["quit"] }) + "\n")
      ipcSocket.flush()
    }
    ipcRetryTimer.stop()
    mpvProc.running = false
    ipcSocket.connected = false
    state.playing = false
    root.resetPlaybackDisplay()
  }

  function handleMpvMessage(line) {
    // Guards against a message already in flight when the socket was torn
    // down to switch stations (playStation()/stopPlayback() both flip
    // ipcSocket.connected synchronously before this could fire again) from
    // clobbering the state the panel already reset for the new station.
    if (!ipcSocket.connected) return
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || msg.event !== "property-change") return
    if (msg.id === root.metadataObserveId && msg.data && typeof msg.data === "object") {
      // mpv sends this immediately on observe_property registration (with
      // the current value) and again on every future change, so this alone
      // covers both the initial seed and instant live updates — confirmed
      // against mpv's own client.h: "You always get an initial change
      // notification."
      root.nowPlayingTitle = String(msg.data["icy-title"] || "")
    } else if (msg.id === root.pauseObserveId && typeof msg.data === "boolean") {
      // Keeps the Pause/Resume label correct even when playback was toggled
      // from a hardware media key or another MPRIS controller, not this panel.
      root.paused = msg.data
    } else if (msg.id === root.pausedForCacheObserveId && typeof msg.data === "boolean") {
      root.buffering = msg.data
    } else if (msg.id === root.cacheBufferingStateObserveId && typeof msg.data === "number") {
      // Documented as 0-100, but clamped the same way other externally
      // sourced numbers in this file already are (e.g. bitrate), rather
      // than trusting it unconditionally.
      root.bufferingPercent = Math.max(0, Math.min(100, msg.data))
    }
  }

  Process {
    id: countriesProc
    command: ["curl", "-sS", "-L", "--max-time", "8", "-A", root.userAgent, root.apiHost + "/json/countries"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.loadingCountries = false
        var parsed = []
        var ok = false
        try {
          var data = JSON.parse(String(text || ""))
          if (Array.isArray(data)) {
            ok = true
            for (var i = 0; i < data.length; i++) {
              var code = String((data[i] && data[i].iso_3166_1) || "")
              var name = String((data[i] && data[i].name) || "")
              if (/^[A-Za-z]{2}$/.test(code) && name.length > 0) parsed.push({ code: code.toUpperCase(), name: name })
            }
          }
        } catch (e) { }
        root.allCountries = parsed
        // Previously silent: a failed/empty fetch (network hiccup, the
        // hardcoded API mirror being briefly down) left the search box
        // showing nothing with zero indication anything went wrong. Now
        // it's surfaced so it reads as "couldn't load" instead of "your
        // country doesn't exist".
        root.countriesError = ok ? "" : "Couldn't load the country list. Check your connection."
        root.updateCountryMatches()
      }
    }
  }

  Process {
    id: languagesProc
    command: ["curl", "-sS", "-L", "--max-time", "8", "-A", root.userAgent,
      root.apiHost + "/json/languages?order=stationcount&reverse=true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.loadingLanguages = false
        var parsed = []
        var ok = false
        try {
          var data = JSON.parse(String(text || ""))
          if (Array.isArray(data)) {
            ok = true
            for (var i = 0; i < data.length; i++) {
              var code = String((data[i] && data[i].iso_639) || "")
              var name = String((data[i] && data[i].name) || "")
              if (/^[A-Za-z]{2,3}$/.test(code) && name.length > 0) {
                parsed.push({ code: code.toLowerCase(), name: name.charAt(0).toUpperCase() + name.slice(1) })
              }
            }
          }
        } catch (e) { }
        root.allLanguages = parsed
        root.languagesError = ok ? "" : "Couldn't load the language list. Check your connection."
        root.updateLanguageMatches()
      }
    }
  }

  // IP-based geolocation for the "Near me" filter — the same host and
  // curl-based request shape Omarchy's own bundled weather plugin already
  // trusts and calls (its omarchy-weather-location helper), not a new
  // third-party dependency.
  Process {
    id: geoLocationProc
    command: ["curl", "-sS", "-L", "--max-time", "8", "-A", root.userAgent, "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      onStreamFinished: {
        // A killed-for-restart lookup's belated result — a fresher
        // refresh (or a clear/Surprise) already superseded it. onExited
        // is the final signal for this same kill, and resets the guard.
        if (root.geoLookupCancelled) return
        root.loadingGeo = false
        var lat = NaN
        var long = NaN
        var label = ""
        var ok = false
        try {
          var data = JSON.parse(String(text || ""))
          var area = data && Array.isArray(data.nearest_area) && data.nearest_area[0]
          if (area) {
            lat = parseFloat(area.latitude)
            long = parseFloat(area.longitude)
            var nameEntry = Array.isArray(area.areaName) && area.areaName[0]
            label = String((nameEntry && nameEntry.value) || "")
            // Radio Browser returns a raw SQL error (HTTP 500) for
            // out-of-range coordinates rather than an empty result set
            // (confirmed live), so a malformed value here must never be
            // forwarded into the station search. A missing place name
            // doesn't invalidate an otherwise-usable coordinate pair —
            // fall back to the coordinates themselves for display.
            ok = isFinite(lat) && lat >= -90 && lat <= 90 &&
                 isFinite(long) && long >= -180 && long <= 180
            if (ok && label.length === 0) label = lat.toFixed(2) + ", " + long.toFixed(2)
          }
        } catch (e) { }
        if (ok) {
          // A stale country selection would otherwise AND with the new
          // location almost certainly nonsensically (e.g. a Singapore
          // filter combined with a US location) — the same silent
          // zero-results failure mode selectCountry() already guards
          // against in the opposite direction.
          state.countryCode = ""
          state.countryName = ""
          root.geoActive = true
          root.geoLat = lat
          root.geoLong = long
          root.geoLabel = label
          root.geoError = ""
          root.loadStations()
        } else {
          // Leaves any previously active geo filter untouched — a failed
          // refresh shouldn't silently drop an already-working filter.
          root.geoError = "Couldn't determine your location. Check your connection."
        }
      }
    }
    onExited: function(code, status) {
      if (root.geoLookupCancelled) { root.geoLookupCancelled = false; return }
      // Backstop for when curl never produces a stdout close at all (e.g.
      // it fails to spawn) — onStreamFinished alone would otherwise leave
      // loadingGeo stuck true with no feedback.
      root.loadingGeo = false
      if (code !== 0) root.geoError = "Couldn't determine your location. Check your connection."
    }
  }

  Process {
    id: stationsProc
    command: {
      var params = []
      if (state.countryCode) params.push("countrycode=" + encodeURIComponent(state.countryCode))
      // Confirmed live: `languagecodes=` does not filter results at all
      // (Radio Browser silently ignores it here); `language=` does a
      // case-sensitive substring match against the station's lowercase
      // `language` field, so the display name is lowercased before sending.
      if (state.languageCode) params.push("language=" + encodeURIComponent(state.languageName.toLowerCase()))
      if (root.geoActive) {
        params.push("geo_lat=" + encodeURIComponent(root.geoLat))
        params.push("geo_long=" + encodeURIComponent(root.geoLong))
        params.push("geo_distance=" + root.geoDistanceMeters)
      }
      if (root.nameQuery.trim() !== "") params.push("name=" + encodeURIComponent(root.nameQuery.trim()))
      var tags = []
      if (state.tag) tags.push(state.tag)
      if (state.decade) tags.push(state.decade)
      if (tags.length === 1) params.push("tag=" + encodeURIComponent(tags[0]))
      else if (tags.length > 1) params.push("tagList=" + encodeURIComponent(tags.join(",")))
      params.push("limit=80")
      // Confirmed live: order=lastchange is not a valid Radio Browser order
      // value and silently falls back to the API's default ordering;
      // order=changetimestamp is the value that actually sorts by recency.
      params.push("order=" + (state.sortOrder || "clickcount"))
      params.push("reverse=true")
      params.push("hidebroken=true")
      return ["curl", "-sS", "-L", "--max-time", "8", "-A", root.userAgent,
        root.apiHost + "/json/stations/search?" + params.join("&")]
    }
    stdout: StdioCollector {
      onStreamFinished: {
        // A killed-for-restart stationsProc's belated result — a fresher
        // fetch (or an intentional clear) already superseded it. onExited
        // is the final signal for this same kill, and resets the guard.
        if (root.stationsSwitching) return
        root.loadingStations = false
        var raw = String(text || "")
        var list = []
        try {
          var data = JSON.parse(raw)
          if (Array.isArray(data)) {
            for (var i = 0; i < data.length; i++) {
              var s = data[i]
              var url = String((s && (s.url_resolved || s.url)) || "")
              var uuid = String((s && s.stationuuid) || "")
              var name = String((s && s.name) || "").trim()
              if (!uuid || !name || !/^https?:\/\//i.test(url)) continue
              // Same scheme check already applied to the play URL above —
              // an Image element can resolve non-http(s) schemes (e.g.
              // file://), so an untrusted directory response shouldn't get
              // to hand one straight to it.
              var favicon = String((s && s.favicon) || "")
              if (!/^https?:\/\//i.test(favicon)) favicon = ""
              list.push({
                uuid: uuid,
                name: name,
                playUrl: url,
                codec: String((s && s.codec) || ""),
                bitrate: Number((s && s.bitrate) || 0),
                tags: String((s && s.tags) || ""),
                favicon: favicon
              })
            }
          }
        } catch (e) { }
        for (var j = 0; j < list.length; j++) stationsModel.append(list[j])
        root.resortStations()
        if (root.pendingSurprise) {
          root.pendingSurprise = false
          if (stationsModel.count > 0) {
            var pick = stationsModel.get(Math.floor(Math.random() * stationsModel.count))
            root.playStation(pick.uuid, pick.name, pick.playUrl)
          }
        }
      }
    }
    onExited: function(code, status) {
      if (root.stationsSwitching) { root.stationsSwitching = false; return }
      root.loadingStations = false
      if (code !== 0) root.stationsError = "Couldn't reach the radio directory. Check your connection."
    }
  }

  Process { id: clickProc; command: ["curl", "-sS", "--max-time", "6", "-A", root.userAgent, root.apiHost + "/json/url/" + state.stationUuid] }

  Process {
    id: voteProc
    command: ["curl", "-sS", "--max-time", "6", "-A", root.userAgent, root.apiHost + "/json/vote/" + root.voteInFlightUuid]
    stdout: StdioCollector {
      onStreamFinished: {
        // Mirrors onExited's own guard below: if onExited has already run
        // (empirically it doesn't, on this Quickshell version — see its
        // comment — but this keeps the pair correct without depending on
        // that holding true), voteInFlightUuid is already cleared and
        // onExited already recorded its own backstop result, which this
        // must not overwrite with an empty/misattributed uuid.
        if (root.voteInFlightUuid === "") return
        var votedUuid = root.voteInFlightUuid
        root.voteInFlightUuid = ""
        var ok = false
        try {
          // Confirmed live: the vote endpoint always returns HTTP 200 —
          // success or failure (rate-limited, invalid station id, etc.)
          // is only distinguishable via this "ok" field, never the HTTP
          // status or curl's own exit code.
          var data = JSON.parse(String(text || ""))
          ok = !!(data && data.ok === true)
        } catch (e) { }
        root.voteUuid = votedUuid
        root.voteOk = ok
        voteFeedbackTimer.restart()
      }
    }
    onExited: function(code, status) {
      // A non-empty voteInFlightUuid here means onStreamFinished never
      // ran for this invocation — a genuine backstop case (e.g. curl
      // failed to spawn), not the normal path, which already cleared it.
      // This relies on onStreamFinished always firing before onExited for
      // a normal completion — confirmed empirically on this Quickshell
      // version (not just assumed): a standalone Process+StdioCollector
      // test against this same endpoint showed onStreamFinished firing
      // and completing before onExited, consistently across repeated runs.
      if (root.voteInFlightUuid === "") return
      // Without this, voteInFlightUuid (and thus every future vote) would
      // be stuck forever, and the button would silently revert to "👍"
      // with no indication anything went wrong — matching the error
      // feedback the stationsProc/geoLocationProc backstops already give.
      var votedUuid = root.voteInFlightUuid
      root.voteInFlightUuid = ""
      root.voteUuid = votedUuid
      root.voteOk = false
      voteFeedbackTimer.restart()
    }
  }

  Process {
    id: mpvProc
    command: ["mpv", "--no-video", "--idle=yes", "--really-quiet",
      "--input-ipc-server=" + root.ipcSocketPath, "--volume=" + state.volume, state.stationUrl]
    onExited: function(code, status) {
      if (root.switchingStation) {
        // Expected: playStation() killed this instance to start the next
        // station, which is already (re)starting on its own. Nothing here
        // belongs to that new station's lifecycle, so touch nothing else.
        root.switchingStation = false
        return
      }
      ipcRetryTimer.stop()
      ipcSocket.connected = false
      state.playing = false
      root.resetPlaybackDisplay()
    }
  }

  Timer {
    id: ipcRetryTimer
    interval: 400
    repeat: true
    property int attempts: 0
    onTriggered: {
      attempts += 1
      if (ipcSocket.connected || attempts > 20) { stop(); return }
      ipcSocket.path = root.ipcSocketPath
      ipcSocket.connected = true
    }
  }

  Socket {
    id: ipcSocket
    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(data) { root.handleMpvMessage(data) }
    }
    onConnectionStateChanged: {
      if (connected) {
        ipcRetryTimer.stop()
        write(JSON.stringify({ command: ["set_property", "pause", false] }) + "\n")
        // Internet radio streams vary wildly in loudness station-to-station;
        // mpv's bundled loudnorm filter evens that out. Fire-and-forget,
        // same as the pause reset above — no reply is awaited or checked,
        // and a failed af here must never block playback from starting.
        // Confirmed against mpv's own input.rst: the runtime command is
        // `af <operation> <value>` ("add" to append to the filter chain) —
        // there is no separate "af-add" command in the JSON IPC protocol.
        write(JSON.stringify({ command: ["af", "add", "lavfi=[loudnorm]"] }) + "\n")
        // Registered once per connection. mpv sends an immediate
        // property-change event with the current value on registration
        // (per its own client.h docs), then another on every future
        // change — so this alone seeds state on connect *and* keeps it
        // instantly in sync, with no separate get_property call needed.
        write(JSON.stringify({ command: ["observe_property", root.metadataObserveId, "metadata"] }) + "\n")
        write(JSON.stringify({ command: ["observe_property", root.pauseObserveId, "pause"] }) + "\n")
        // Surfaces real "Buffering…" feedback during the connection gap
        // (or a later rebuffer) instead of leaving that window blank —
        // confirmed live against a real mpv instance and stream.
        write(JSON.stringify({ command: ["observe_property", root.pausedForCacheObserveId, "paused-for-cache"] }) + "\n")
        write(JSON.stringify({ command: ["observe_property", root.cacheBufferingStateObserveId, "cache-buffering-state"] }) + "\n")
        flush()
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰐹"
    active: state.playing
    tooltipText: state.playing
      ? ("Playing: " + state.stationName + (root.buffering
          ? (" — Buffering… " + root.bufferingPercent + "%")
          : (root.nowPlayingTitle ? " — " + root.nowPlayingTitle : "")))
      : "World Radio"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.stopPlayback()
      else if (b === Qt.MiddleButton) root.togglePause()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Two panes side by side: a fixed-width left column for the pickers,
    // and a right pane that gets whatever's left for the station list — so
    // the list isn't squeezed into whatever's left below a tall stack of
    // controls.
    contentWidth: panel.fittedContentWidth(Style.space(780))
    // A deliberately oversized desired height clamps to
    // availableCardHeight inside fittedContentHeight — i.e. the panel
    // always grows to fill the screen down to the bar/margins, so the
    // station list below gets all the leftover room instead of a small
    // fixed-height peephole.
    contentHeight: panel.fittedContentHeight(Style.space(4000))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Item {
        anchors.fill: parent

        Column {
          id: leftColumn
          width: Style.space(320)
          anchors.left: parent.left
          anchors.top: parent.top
          spacing: Style.space(12)

          // ---------- Now playing hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              text: "󰐹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "World Radio"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: state.playing ? state.stationName : "Not playing"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                visible: root.buffering || root.nowPlayingTitle !== ""
                text: root.buffering ? ("Buffering… " + root.bufferingPercent + "%") : root.nowPlayingTitle
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

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
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              enabled: state.playing
              opacity: enabled ? 1.0 : 0.4
              onClicked: root.togglePause()
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "󰒭"
              tooltipText: "Next station"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              enabled: stationsModel.count > 0
              opacity: enabled ? 1.0 : 0.4
              onClicked: root.playRelativeStation(1)
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Stop"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              enabled: state.playing
              opacity: enabled ? 1.0 : 0.4
              onClicked: root.stopPlayback()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "🎲 Surprise"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.surpriseMe()
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "🔥 Trending"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              active: state.sortOrder === "votes"
              onClicked: root.toggleSortOrder("votes")
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "🆕 Recently added"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              active: state.sortOrder === "changetimestamp"
              onClicked: root.toggleSortOrder("changetimestamp")
            }
          }

          Button {
            width: parent.width
            text: "📍 Near me"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: root.geoActive
            onClicked: root.findNearMe()
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            visible: root.geoActive

            Text {
              width: parent.width - geoClearButton.width - parent.spacing
              text: root.geoLabel
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: geoClearButton
              text: "✕"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearGeo()
              }
            }
          }

          Text {
            width: parent.width
            visible: root.loadingGeo
            text: "Finding your location…"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.geoError !== ""
            text: root.geoError
            color: root.bar.foreground
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: 100
            step: 1
            integer: true
            value: state.volume
            onMoved: function(v) {
              state.volume = v
              if (ipcSocket.connected) {
                ipcSocket.write(JSON.stringify({ command: ["set_property", "volume", v] }) + "\n")
                ipcSocket.flush()
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }
          PanelSectionHeader { text: "SEARCH BY NAME"; foreground: root.bar.foreground }

          TextField {
            id: nameField
            width: parent.width
            placeholderText: "Station name…"
            foreground: root.bar.foreground
            onTextChanged: {
              root.nameQuery = text
              nameSearchTimer.restart()
            }
          }

          Text {
            width: parent.width
            visible: root.nameQuery.trim() !== ""
            text: state.countryCode !== ""
              ? "Matching “" + root.nameQuery.trim() + "” in " + state.countryName
              : "Matching “" + root.nameQuery.trim() + "” worldwide"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.bar.foreground }
          PanelSectionHeader { text: "COUNTRY"; foreground: root.bar.foreground }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.curatedCountries
              delegate: Button {
                required property var modelData
                text: root.flagFor(modelData.code) + " " + modelData.name
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.space(4)
                bordered: true
                active: state.countryCode === modelData.code
                onClicked: root.selectCountry(modelData.code, modelData.name)
              }
            }
          }

          TextField {
            id: countryField
            width: parent.width
            placeholderText: "Search any country…"
            foreground: root.bar.foreground
            onTextChanged: {
              root.countryQuery = text
              root.ensureCountriesLoaded()
              root.updateCountryMatches()
            }
          }

          Text {
            width: parent.width
            visible: root.countryQuery.trim() !== "" && root.loadingCountries
            text: "Searching countries…"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.countriesError !== ""
            text: root.countriesError
            color: root.bar.foreground
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: !root.loadingCountries && root.countriesError === "" && root.countryQuery.trim() !== "" && root.allCountries.length > 0 && root.countryMatches.length === 0
            text: "No countries match “" + root.countryQuery.trim() + "”."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.countryMatches.length > 0
            Repeater {
              model: root.countryMatches
              delegate: Button {
                required property var modelData
                width: parent.width
                leftAlign: true
                text: root.flagFor(modelData.code) + "  " + modelData.name
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.space(4)
                onClicked: {
                  // Deferred: selectCountry() clears root.countryMatches,
                  // which is this Repeater's own model — doing that
                  // synchronously from inside this delegate's own click
                  // handler destroys the Button mid-handler (the first-
                  // party notifications service hits the same class of
                  // bug and documents it as Qt.callLater avoiding a
                  // QV4::Object::insertMember crash when a Repeater is
                  // mid-incubation while its model is mutated). Without
                  // this, the handler aborted after clearing the search
                  // text and never reached selectCountry() at all, so
                  // picking a search result silently failed to load its
                  // stations — confirmed via a live "ReferenceError: root
                  // is not defined" at this exact line in journalctl.
                  var pickedCode = modelData.code
                  var pickedName = modelData.name
                  Qt.callLater(function() {
                    countryField.text = ""
                    root.selectCountry(pickedCode, pickedName)
                  })
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }
          PanelSectionHeader { text: "MOOD (OPTIONAL)"; foreground: root.bar.foreground }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.curatedTags
              delegate: Button {
                required property var modelData
                text: modelData
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.space(4)
                bordered: true
                active: state.tag === modelData
                onClicked: root.toggleTag(modelData)
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }
          PanelSectionHeader { text: "DECADE (OPTIONAL)"; foreground: root.bar.foreground }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.curatedDecades
              delegate: Button {
                required property var modelData
                text: modelData
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.space(4)
                bordered: true
                active: state.decade === modelData
                onClicked: root.toggleDecade(modelData)
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }
          PanelSectionHeader { text: "LANGUAGE (OPTIONAL)"; foreground: root.bar.foreground }

          Row {
            width: parent.width
            spacing: Style.space(6)
            visible: state.languageCode !== ""

            Text {
              width: parent.width - languageClearButton.width - parent.spacing
              text: state.languageName
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: languageClearButton
              text: "✕"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearLanguage()
              }
            }
          }

          TextField {
            id: languageField
            width: parent.width
            placeholderText: "Search any language…"
            foreground: root.bar.foreground
            onTextChanged: {
              root.languageQuery = text
              root.ensureLanguagesLoaded()
              root.updateLanguageMatches()
            }
          }

          Text {
            width: parent.width
            visible: root.languageQuery.trim() !== "" && root.loadingLanguages
            text: "Searching languages…"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.languagesError !== ""
            text: root.languagesError
            color: root.bar.foreground
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: !root.loadingLanguages && root.languagesError === "" && root.languageQuery.trim() !== "" && root.allLanguages.length > 0 && root.languageMatches.length === 0
            text: "No languages match “" + root.languageQuery.trim() + "”."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.languageMatches.length > 0
            Repeater {
              model: root.languageMatches
              delegate: Button {
                required property var modelData
                width: parent.width
                leftAlign: true
                text: modelData.name
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.space(4)
                onClicked: {
                  // Same deferred-selection pattern as the country search
                  // results above (selectLanguage() clears this Repeater's
                  // own model mid-click-handler otherwise).
                  var pickedCode = modelData.code
                  var pickedName = modelData.name
                  Qt.callLater(function() {
                    languageField.text = ""
                    root.selectLanguage(pickedCode, pickedName)
                  })
                }
              }
            }
          }
        }

        Rectangle {
          id: columnDivider
          width: 1
          color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          anchors.left: leftColumn.right
          anchors.leftMargin: Style.space(8)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
        }

        // ---------- Right pane: stations get the whole rest of the panel ----------
        Item {
          id: rightPane
          anchors.left: columnDivider.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom

          PanelSectionHeader {
            id: stationsHeader
            text: "STATIONS"
            foreground: root.bar.foreground
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
          }

          Text {
            anchors.top: stationsHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.loadingStations
            text: "Loading stations…"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.top: stationsHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !root.loadingStations && root.stationsError !== ""
            text: root.stationsError
            color: root.bar.foreground
            wrapMode: Text.WordWrap
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.top: stationsHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !root.loadingStations && root.stationsError === "" && !root.hasLoadedStations()
            text: "Pick a country, search by name, pick a language, or find stations near you, to tune in."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.top: stationsHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !root.loadingStations && root.stationsError === "" && root.hasLoadedStations() && stationsModel.count === 0
            text: "No stations found — try a different name, mood, country, language, or location."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Fills every remaining pixel down to the bottom of the panel.
          ListView {
            id: stationsList
            anchors.top: stationsHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: stationsModel.count > 0
            clip: true
            spacing: Style.space(2)
            model: stationsModel

            delegate: Rectangle {
              id: row
              required property string uuid
              required property string name
              required property string playUrl
              required property string codec
              required property int bitrate
              required property string tags
              required property string favicon

              width: stationsList.width
              height: Style.space(44)
              radius: Style.cornerRadius
              color: rowMouse.containsMouse
                ? Style.hoverFillFor(root.bar.foreground, Color.accent)
                : (state.stationUuid === row.uuid ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent")

              // Row-wide click target underneath everything else, so the
              // star button (declared last, on top) can claim clicks in its
              // own smaller area first.
              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.playStation(row.uuid, row.name, row.playUrl)
              }

              // Only the API's own favicon field, already present in every
              // stationsProc response — no new fetch. Left unshown entirely
              // when empty, and allowed to fail silently (blank) on a dead
              // or invalid URL, same as any other third-party image source.
              Image {
                id: faviconImage
                visible: row.favicon !== ""
                width: Style.space(24)
                height: Style.space(24)
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                source: row.favicon
                fillMode: Image.PreserveAspectFit
                // Decode at (roughly) display resolution instead of full
                // size — up to 80 rows can each carry a favicon, and some
                // directory entries are large PNGs/ICOs.
                sourceSize: Qt.size(48, 48)
                asynchronous: true
                smooth: true
              }

              Column {
                anchors.left: faviconImage.visible ? faviconImage.right : parent.left
                anchors.right: voteButton.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: faviconImage.visible ? Style.space(6) : Style.space(10)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: row.name
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: [row.codec, row.bitrate ? row.bitrate + "kbps" : "", row.tags].filter(function(s) { return s }).join(" · ")
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Text {
                id: voteButton
                text: root.voteUuid === row.uuid ? (root.voteOk ? "✓" : "✕") : "👍"
                // Success gets the same accent already used for an active
                // filter/favorite; failure isn't a color this app uses
                // anywhere (no error-red exists in this file), so it gets
                // the undarkened foreground instead of the same muted tone
                // as the idle icon, rather than blending in as "just 👍".
                color: root.voteUuid === row.uuid
                  ? (root.voteOk ? Color.accent : root.bar.foreground)
                  : Qt.darker(root.bar.foreground, 1.4)
                // Dims fully for the row actually voting, and slightly for
                // every other row while any vote is in flight — a click on
                // another row is silently ignored (voteForStation()'s
                // single-flight guard), so this at least signals "busy"
                // instead of looking fully idle and interactive.
                opacity: root.voteInFlightUuid === row.uuid ? 0.4 : (voteProc.running ? 0.7 : 1.0)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                // Fixed width + centered text, unlike starButton (whose
                // two Nerd Font glyphs already share the same intrinsic
                // width): "👍" and "✓"/"✕" don't, so anchoring by
                // right-edge alone would shift this icon (and the text
                // Column anchored to its left) sideways on every vote.
                width: Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                anchors.right: starButton.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                // Expands outward on every side except toward starButton —
                // a uniform -Style.space(6) here would reach exactly
                // Style.space(6) past this icon on the right, meeting (and
                // overlapping) starButton's own -Style.space(6) expansion
                // to its left, since the two icons only sit Style.space(6)
                // apart to begin with. Splitting that gap in half instead
                // of doubling it into an overlap keeps a click nearest
                // each icon going to that icon.
                MouseArea {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.topMargin: -Style.space(6)
                  anchors.bottomMargin: -Style.space(6)
                  anchors.leftMargin: -Style.space(6)
                  anchors.rightMargin: -Style.space(3)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.voteForStation(row.uuid)
                }
              }

              Text {
                id: starButton
                text: root.isFavorite(row.uuid) ? "󰓎" : "󰓒"
                color: root.isFavorite(row.uuid) ? Color.accent : Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                // Mirrors voteButton's MouseArea above: expands less
                // toward voteButton (its only neighbor) than on every
                // other side, so the two hit-areas meet rather than
                // overlap.
                MouseArea {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.topMargin: -Style.space(6)
                  anchors.bottomMargin: -Style.space(6)
                  anchors.leftMargin: -Style.space(3)
                  anchors.rightMargin: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleFavorite(row)
                }
              }
            }
          }
        }
      }
    }
  }
}
