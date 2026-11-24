import Foundation

// Exercises the Foundation-only model layer: no app, no window server, no
// Accessibility. Usage: TrellisSmoke <path to fixtures/export.json>

setvbuf(stdout, nil, _IONBF, 0)

var passed = 0
var failures: [String] = []

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        passed += 1
        print("ok    \(name)")
    } else {
        failures.append(name)
        print("FAIL  \(name)")
    }
}

func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

func token(_ text: String) -> KeyToken { KeyToken(text)! }

func chord(_ text: String) -> [KeyToken] { KeyToken.chord(text)! }

// MARK: - Paths

let home = URL(fileURLWithPath: "/Users/someone")
let defaults = TrellisPaths(environment: [:], home: home)
check("root defaults to ~/.trellis", defaults.root.path == "/Users/someone/.trellis")
check("config defaults under root", defaults.configFile.path == "/Users/someone/.trellis/config.json")
check("runtime defaults under root", defaults.runtimeDir.path == "/Users/someone/.trellis/runtime")
check("socket defaults under runtime", defaults.socket.path == "/Users/someone/.trellis/runtime/trellis.sock")
check("lock sits beside the socket", defaults.lockFile.path == "/Users/someone/.trellis/runtime/trellis.sock.lock")
check("logs sit under runtime", defaults.logsDir.path == "/Users/someone/.trellis/runtime/logs")
check("binary defaults under root", defaults.binary.path == "/Users/someone/.trellis/bin/trellis")

let rooted = TrellisPaths(environment: ["TRELLIS_ROOT": "/tmp/t"], home: home)
check("TRELLIS_ROOT moves every default", rooted.socket.path == "/tmp/t/runtime/trellis.sock")
let overridden = TrellisPaths(environment: [
    "TRELLIS_ROOT": "/tmp/t", "TRELLIS_CONFIG": "/tmp/c.json", "TRELLIS_RUNTIME_DIR": "/tmp/r",
    "TRELLIS_SOCKET": "/tmp/s.sock", "TRELLIS_BINARY": "/tmp/bin/trellis",
], home: home)
check("TRELLIS_CONFIG overrides", overridden.configFile.path == "/tmp/c.json")
check("TRELLIS_RUNTIME_DIR overrides", overridden.runtimeDir.path == "/tmp/r")
check("TRELLIS_SOCKET overrides", overridden.socket.path == "/tmp/s.sock")
check("the lock follows an overridden socket", overridden.lockFile.path == "/tmp/s.sock.lock")
check("TRELLIS_BINARY overrides", overridden.binary.path == "/tmp/bin/trellis")
check("an empty override is ignored", TrellisPaths(environment: ["TRELLIS_ROOT": ""], home: home) == defaults)

// MARK: - Key names

check("CMD+Ctrl+H canonicalizes to ctrl+cmd+h", KeyToken("CMD+Ctrl+H")?.description == "ctrl+cmd+h")
check("aliases canonicalize", KeyToken("Option+Shift+Return")?.description == "alt+shift+return")
check("all four modifiers in canonical order",
      KeyToken("command+shift+opt+control+f12")?.description == "ctrl+alt+shift+cmd+f12")
check("punctuation keys parse", KeyToken("cmd+/")?.description == "cmd+/")
check("an unknown modifier is rejected", KeyToken("hyper+h") == nil)
check("a missing key is rejected", KeyToken("ctrl+") == nil)
check("f13 is not a key", KeyToken("f13") == nil)
check("an empty token is rejected", KeyToken("") == nil)
check("a chord splits on single spaces", KeyToken.chord("l l")?.count == 2)
check("a double space is not a chord", KeyToken.chord("l  l") == nil)
check("a chord canonicalizes each token", KeyToken.canonicalChord("Cmd+L l") == "cmd+l l")
check("the leader displays as ⌃S", token("ctrl+s").display(uppercased: true) == "⌃S")
check("a chord key displays lowercase", token("ctrl+h").display() == "⌃h")
check("named keys display as symbols", KeyToken.chordDisplay(chord("cmd+return right")) == "⌘↩ →")
check("a leader needs a modifier", KeyToken.leaderProblem("s") != nil)
check("escape cannot lead", KeyToken.leaderProblem("ctrl+escape") != nil)
check("ctrl+s is a valid leader", KeyToken.leaderProblem("ctrl+s") == nil)
check("every key has a key code", KeyToken.validKeys.allSatisfy { KeyCodes.byKey[$0] != nil })
check("key codes round-trip", KeyToken.validKeys.allSatisfy { key in
    KeyCodes.token(keyCode: KeyCodes.byKey[key]!, modifiers: [])?.key == key
})
check("the keypad enter is return", KeyCodes.token(keyCode: 76, modifiers: [])?.key == "return")
check("key codes carry modifiers",
      KeyCodes.token(keyCode: 4, modifiers: [.cmd, .ctrl])?.description == "ctrl+cmd+h")

// MARK: - Leader capture

check("device flags keep ctrl and alt", KeyModifiers(deviceFlags: (1 << 18) | (1 << 19)) == [.ctrl, .alt])
check("device flags keep shift and cmd", KeyModifiers(deviceFlags: (1 << 17) | (1 << 20)) == [.shift, .cmd])
check("caps lock, keypad and fn are dropped", KeyModifiers(deviceFlags: (1 << 16) | (1 << 21) | (1 << 23)).isEmpty)
let capturedLeader = LeaderCapture.interpret(keyCode: 1, modifiers: [.ctrl, .alt])
check("⌃⌥S captures as ctrl+alt+s", capturedLeader == .capture(token("ctrl+alt+s")))
if case .capture(let leader) = capturedLeader {
    check("a captured leader displays as ⌃⌥S", leader.display(uppercased: true) == "⌃⌥S")
}
check("a bare escape cancels", LeaderCapture.interpret(keyCode: 53, modifiers: []) == .cancel)
check("a key with no modifier is refused",
      LeaderCapture.interpret(keyCode: 1, modifiers: []) == .refuse("the leader needs at least one modifier"))
check("shift alone is a modifier", LeaderCapture.interpret(keyCode: 1, modifiers: [.shift]) == .capture(token("shift+s")))
check("a modified escape is refused", {
    if case .refuse = LeaderCapture.interpret(keyCode: 53, modifiers: [.ctrl]) { return true }; return false
}())
check("a key outside the key names is refused", {
    if case .refuse = LeaderCapture.interpret(keyCode: 105, modifiers: [.ctrl]) { return true }; return false
}())

// MARK: - Config export (fixtures/export.json)

let fixturePath = CommandLine.arguments.dropFirst().first
let fixtureData = fixturePath.flatMap { FileManager.default.contents(atPath: $0) }
check("the export fixture is readable", fixtureData != nil)

var fixture: TrellisConfig?
do {
    if let fixtureData { fixture = try TrellisConfig.decode(fixtureData) }
} catch {
    print("      decode error: \(error)")
}
check("the export fixture decodes", fixture != nil)

if let config = fixture {
    check("version", config.version == 1)
    check("source", config.source == "file")
    check("leader", config.settings.leader == "ctrl+s")
    check("chord_wait_ms", config.settings.chordWaitMs == 350)
    check("label screens", config.settings.label.screens == .main)
    check("label corner", config.settings.label.corner == .bottomRight)
    check("label linger_ms takes the default", config.settings.label.lingerMs == Settings.defaultLingerMs)
    check("the linger default is 2000 ms", Settings.defaultLingerMs == 2000)
    check("two regions", config.regions.count == 2)
    check("gutter margins", config.regions["gutter"]?.margins == Margins(top: 0, right: 0.05, bottom: 0, left: 0))
    check("gutter gap is 10 points both ways", config.regions["gutter"]?.gap == Gap(x: 10, y: 10))
    check("stack gap has its own y in points", config.regions["stack"]?.gap == Gap(x: 10, y: 2.5))
    check("four placements", config.placements.count == 4)
    check("a null region decodes as none", config.placements["right-half-full"]?.region == nil)
    check("a region name decodes", config.placements["left-half"]?.region == "gutter")
    check("rects decode as objects", config.placements["top-right-third"]?.rect == Rect(x: 0.5, y: 0, w: 0.5, h: 0.25))
    check("six bindings", config.bindings.count == 6)
    check("bindings keep the export's order", config.bindings.map(\.keys) == ["ctrl+cmd+h", "h", "l", "l l", "right", "t"])
    check("chord tokens parse", config.bindings[0].tokens == [token("ctrl+cmd+h")])
    check("a multi-key chord parses", config.bindings[3].tokens == chord("l l"))
    check("a prefix binding is flagged", config.bindings[2].prefix && !config.bindings[1].prefix)
    check("a placement target decodes", config.bindings[1].target == .placement("left-half"))
    check("an action target decodes", config.bindings[4].target == .action(.screenEast))
    check("a waiting chord is not a warning", config.warnings.isEmpty)
    check("a placement's region resolves", config.region(for: config.placements["left-half"]!) == config.regions["gutter"])
    check("no region resolves to none", config.region(for: config.placements["right-half-full"]!) == Region.none)
    check("groups decode in order", config.groups == ["Halves", "Thirds", "Displays"])
    check("a placement's group decodes", config.placements["top-right-third"]?.group == "Thirds")
    check("only configured actions decode", config.actions == ["screen-east": ActionGroup(group: "Displays")])
    check("a binding carries its target's group",
          config.bindings[4].group == "Displays" && config.bindings[5].group == "Thirds")
    check("sections follow groups order", config.bindingSections.map(\.group) == ["Halves", "Thirds", "Displays"])
    check("a section keeps export order",
          config.bindingSections.first?.bindings.map(\.keys) == ["ctrl+cmd+h", "h", "l", "l l"])

    let grid = BindingsGrid(tilesPerRow: 5, tileHeight: 80, tileSpacing: 8,
                            headerHeight: 16, headerSpacing: 6, sectionSpacing: 12)
    check("every fixture section has tiles", config.bindingSections.allSatisfy { !$0.bindings.isEmpty })
    check("each fixture section takes one row", config.bindingSections.map(grid.rows) == [1, 1, 1])
    check("the grid's height adds sections and the space between them",
          near(grid.height(config.bindingSections), 3 * (16 + 6 + 80) + 2 * 12))
    let six = BindingSection(group: "All", bindings: config.bindings)
    check("six tiles take two rows of five", grid.rows(six) == 2 && grid.chunked(six.bindings).map(\.count) == [5, 1])
    check("rows are spaced but not padded", near(grid.height(six), 16 + 6 + 2 * 80 + 8))
    check("no sections take no height", grid.height([]) == 0)
}

func decodes(_ json: String) -> Bool { (try? TrellisConfig.decode(Data(json.utf8))) != nil }

let minimal = """
{"version":1,"source":"starter","path":"x","settings":{"leader":"ctrl+s","chord_wait_ms":400,
"label":{"screens":"all","corner":"top-left","linger_ms":0}},
"groups":["G","Empty"],"regions":{},"placements":{},"actions":{},"bindings":[BINDING],"warnings":[]}
"""
check("a minimal export decodes",
      decodes(minimal.replacingOccurrences(of: "BINDING", with: "")))
check("a target with both placement and action is rejected", !decodes(minimal.replacingOccurrences(
    of: "BINDING",
    with: #"{"keys":"h","chord":["h"],"target":{"placement":"a","action":"screen-east"},"group":"G","prefix":false}"#
)))
check("an unparseable chord token is rejected", !decodes(minimal.replacingOccurrences(
    of: "BINDING",
    with: #"{"keys":"hyper+h","chord":["hyper+h"],"target":{"placement":"a"},"group":"G","prefix":false}"#
)))
check("an unknown action is rejected", !decodes(minimal.replacingOccurrences(
    of: "BINDING",
    with: #"{"keys":"h","chord":["h"],"target":{"action":"screen-north"},"group":"G","prefix":false}"#
)))
check("a binding without a group is rejected", !decodes(minimal.replacingOccurrences(
    of: "BINDING",
    with: #"{"keys":"h","chord":["h"],"target":{"placement":"a"},"prefix":false}"#
)))
let grouped = try? TrellisConfig.decode(Data(minimal.replacingOccurrences(
    of: "BINDING",
    with: #"{"keys":"h","chord":["h"],"target":{"placement":"a"},"group":"G","prefix":false}"#
).utf8))
check("a group with no bindings has no section", grouped?.bindingSections.map(\.group) == ["G"])

// MARK: - Geometry

let gutter = Region(margins: Margins(top: 0, right: 0.05, bottom: 0, left: 0), gap: Gap(x: 5, y: 5))
let thousand = Rect(x: 0, y: 0, w: 1000, h: 800)
let rightSlot = Geometry.slot(Rect(x: 0.5, y: 0, w: 0.5, h: 1), visible: thousand, region: gutter)
check("contract check: x = 477.5 before rounding", near(rightSlot.x, 477.5))
check("contract check: w = 472.5 before rounding", near(rightSlot.w, 472.5))
check("the right edge stays on the area boundary", near(rightSlot.maxX, 950))
let rightFrame = Geometry.frame(Rect(x: 0.5, y: 0, w: 0.5, h: 1), visible: thousand, region: gutter)
check("rounding keeps the right edge at 950", rightFrame.maxX == 950 && rightFrame.x == 478 && rightFrame.w == 472)
let leftSlot = Geometry.slot(Rect(x: 0, y: 0, w: 0.5, h: 1), visible: thousand, region: gutter)
check("a left half keeps its outer edge and gives up half the gap",
      near(leftSlot.x, 0) && near(leftSlot.w, 472.5) && near(leftSlot.h, 800))
check("full height edges do not move", near(leftSlot.y, 0) && near(rightSlot.h, 800))
let wideV = Rect(x: 0, y: 0, w: 2000, h: 600)
let wideLeft = Geometry.slot(Rect(x: 0, y: 0, w: 0.5, h: 1), visible: wideV, region: gutter)
let wideRight = Geometry.slot(Rect(x: 0.5, y: 0, w: 0.5, h: 1), visible: wideV, region: gutter)
check("a gap is the same points on a wider screen", near(wideRight.x - wideLeft.maxX, 5))

let stack = Region(margins: Margins(top: 0, right: 0.05, bottom: 0, left: 0), gap: Gap(x: 5, y: 25))
let squareV = Rect(x: 0, y: 0, w: 1000, h: 1000)
let quarter = Geometry.slot(Rect(x: 0.5, y: 0, w: 0.5, h: 0.25), visible: squareV, region: stack)
check("a quarter of four keeps its outer edge and is a quarter of the space between gaps",
      near(quarter.y, 0) && near(quarter.h, 231.25))
let thirds = (0..<3).map { index in
    Geometry.slot(Rect(x: 0.5, y: Double(index) / 3, w: 0.5, h: 1.0 / 3), visible: squareV, region: stack)
}
check("contract check: three thirds are equal", thirds.allSatisfy { near($0.h, (1000.0 - 2 * 25) / 3) })
check("contract check: the gaps between thirds are equal",
      near(thirds[1].y - thirds[0].maxY, 25) && near(thirds[2].y - thirds[1].maxY, 25))
check("the outer thirds stay on the area boundary", near(thirds[0].y, 0) && near(thirds[2].maxY, 1000))
check("a whole-area rect fills the area whatever the gap",
      Geometry.slot(Rect(x: 0, y: 0, w: 1, h: 1), visible: squareV, region: stack) == Rect(x: 0, y: 0, w: 950, h: 1000))
let margined = Geometry.area(
    visible: Rect(x: 100, y: 50, w: 1000, h: 500),
    region: Region(margins: Margins(top: 0.1, right: 0.05, bottom: 0.2, left: 0.1), gap: .zero)
)
check("margins are fractions of the visible frame per edge",
      margined == Rect(x: 200, y: 100, w: 850, h: 350))
check("scaling a region scales its gap and keeps its margins",
      stack.scaled(by: 0.5) == Region(margins: stack.margins, gap: Gap(x: 2.5, y: 12.5)))

// The primary screen (1728 × 1117 with a 38 pt menu bar), one to its right
// at x = 1728 and one above it at negative y.
let primaryHeight = 1117.0
let primaryAppKit = Rect(x: 0, y: 0, w: 1728, h: 1117)
let primaryVisibleAppKit = Rect(x: 0, y: 0, w: 1728, h: 1079)
let rightAppKit = Rect(x: 1728, y: -200, w: 1920, h: 1080)
let rightVisibleAppKit = Rect(x: 1728, y: -200, w: 1920, h: 1055)
let aboveAppKit = Rect(x: 0, y: 1117, w: 2560, h: 1440)
let aboveVisibleAppKit = Rect(x: 0, y: 1117, w: 2560, h: 1415)

let primaryGlobal = Geometry.globalFromAppKit(primaryAppKit, primaryHeight: primaryHeight)
let primaryVisible = Geometry.globalFromAppKit(primaryVisibleAppKit, primaryHeight: primaryHeight)
let rightGlobal = Geometry.globalFromAppKit(rightAppKit, primaryHeight: primaryHeight)
let rightVisible = Geometry.globalFromAppKit(rightVisibleAppKit, primaryHeight: primaryHeight)
let aboveGlobal = Geometry.globalFromAppKit(aboveAppKit, primaryHeight: primaryHeight)
let aboveVisible = Geometry.globalFromAppKit(aboveVisibleAppKit, primaryHeight: primaryHeight)

check("the primary screen converts to the origin", primaryGlobal == primaryAppKit)
check("the primary visible frame starts under the menu bar", primaryVisible == Rect(x: 0, y: 38, w: 1728, h: 1079))
check("a lower right screen converts to positive y", rightGlobal == Rect(x: 1728, y: 237, w: 1920, h: 1080))
check("a right screen's visible frame starts under its menu bar", rightVisible == Rect(x: 1728, y: 262, w: 1920, h: 1055))
check("a screen above converts to negative y", aboveGlobal == Rect(x: 0, y: -1440, w: 2560, h: 1440))
check("its visible frame does too", aboveVisible == Rect(x: 0, y: -1415, w: 2560, h: 1415))
for (name, rect) in [("primary", primaryAppKit), ("right", rightAppKit), ("above", aboveAppKit)] {
    let back = Geometry.appKitFromGlobal(Geometry.globalFromAppKit(rect, primaryHeight: primaryHeight), primaryHeight: primaryHeight)
    check("conversion round-trips (\(name))", back == rect)
}

let right40 = Geometry.frame(Rect(x: 0.6, y: 0, w: 0.4, h: 1), visible: rightVisible, region: .none)
check("right 40 on a screen at x = 1728 starts at 1728 + 0.6 · 1920",
      right40 == Rect(x: 2880, y: 262, w: 768, h: 1055))
let bottomAbove = Geometry.frame(Rect(x: 0, y: 0.5, w: 1, h: 0.5), visible: aboveVisible, region: .none)
check("a bottom half on a screen above stays at negative y",
      bottomAbove.minY == -708 && bottomAbove.maxY == 0 && bottomAbove.w == 2560)

check("a rect past 1 is invalid", Geometry.validatePlacementRect(Rect(x: 0.6, y: 0, w: 0.5, h: 1)) != nil)
check("a zero width is invalid", Geometry.validatePlacementRect(Rect(x: 0, y: 0, w: 0, h: 1)) != nil)
check("a negative origin is invalid", Geometry.validatePlacementRect(Rect(x: -0.1, y: 0, w: 0.5, h: 1)) != nil)
check("rounding error within 1e-9 is allowed",
      Geometry.validatePlacementRect(Rect(x: 0.7, y: 0, w: 0.3 + 1e-12, h: 1)) == nil)

let moved = Geometry.relocate(Rect(x: 172.8, y: 253.8, w: 864, h: 431.6), from: primaryVisible, to: rightVisible)
check("relocating keeps fractions of the visible frame",
      moved == Rect(x: 1920, y: 473, w: 960, h: 422))

// MARK: - Screens

func screenInfo(_ index: Int, _ frame: Rect, _ visible: Rect, main: Bool = false) -> ScreenInfo {
    ScreenInfo(index: index, uuid: "UUID-\(index)", name: "Screen \(index)", frame: frame,
               visibleFrame: visible, scale: 2, main: main)
}

let order = ScreenNeighbor.order([rightGlobal, primaryGlobal, aboveGlobal])
check("screens order left to right, then top to bottom", order == [3, 2, 1])

let above = screenInfo(1, aboveGlobal, aboveVisible)
let primary = screenInfo(2, primaryGlobal, primaryVisible, main: true)
let right = screenInfo(3, rightGlobal, rightVisible)
let screens = [above, primary, right]
check("east of the primary is the right screen", ScreenNeighbor.neighbor(of: primary, .east, among: screens)?.index == 3)
check("west of the right screen is the primary, not the wider one above",
      ScreenNeighbor.neighbor(of: right, .west, among: screens)?.index == 2)
check("nothing east of the rightmost screen", ScreenNeighbor.neighbor(of: right, .east, among: screens) == nil)
check("nothing west of the primary", ScreenNeighbor.neighbor(of: primary, .west, among: screens) == nil)
check("a window's screen is where its centre is",
      ScreenNeighbor.screen(for: Rect(x: 1600, y: 300, w: 400, h: 300), among: screens)?.index == 3)
check("a window above the primary is on the screen above",
      ScreenNeighbor.screen(for: Rect(x: 100, y: -900, w: 400, h: 300), among: screens)?.index == 1)
check("a window off every screen has none",
      ScreenNeighbor.screen(for: Rect(x: 9000, y: 9000, w: 10, h: 10), among: screens) == nil)

let left = screenInfo(1, Rect(x: -1920, y: 0, w: 1920, h: 1080), Rect(x: -1920, y: 25, w: 1920, h: 1055))
check("a screen left of the origin is west",
      ScreenNeighbor.neighbor(of: primary, .west, among: [left, primary])?.index == 1)

// MARK: - Chord resolver

final class ManualClock {
    var now: TimeInterval = 0
}

let hBinding = ResolverBinding(chord: chord("h"), target: .placement("left-half"))
let lBinding = ResolverBinding(chord: chord("l"), target: .placement("right-half"))
let llBinding = ResolverBinding(chord: chord("l l"), target: .placement("right-half-full"))
let ggxBinding = ResolverBinding(chord: chord("g g x"), target: .placement("third"))
let resolverBindings = [hBinding, lBinding, llBinding, ggxBinding]

let clock = ManualClock()
var resolver = ChordResolver(bindings: resolverBindings, wait: 0.4, clock: { clock.now })

check("h runs at once", resolver.feed(token("h")) == .run(hBinding))
check("the buffer clears after a run", resolver.buffer.isEmpty)

check("l waits", resolver.feed(token("l")) == .waiting(buffer: chord("l"), deadline: 0.4))
clock.now = 0.3
check("l is still waiting before the deadline", resolver.expire() == .waiting(buffer: chord("l"), deadline: 0.4))
clock.now = 0.4
check("l runs when the wait expires", resolver.expire() == .run(lBinding))
check("an expiry with nothing buffered is idle", resolver.expire() == .idle)

clock.now = 1
_ = resolver.feed(token("l"))
check("l l runs at once on the second l", resolver.feed(token("l")) == .run(llBinding))

check("x is rejected at once", resolver.feed(token("x")) == .unrecognized(chord("x")))
check("a miss clears the buffer", resolver.buffer.isEmpty && resolver.deadline == nil)
check("the resolver keeps working after a miss", resolver.feed(token("h")) == .run(hBinding))

func waiting(_ outcome: ChordResolver.Outcome, _ buffer: String, until deadline: TimeInterval) -> Bool {
    guard case .waiting(let actual, let due) = outcome else { return false }
    return actual == chord(buffer) && abs(due - deadline) < 1e-9
}

clock.now = 10
check("g waits", waiting(resolver.feed(token("g")), "g", until: 10.4))
clock.now = 10.3
check("a second key restarts the wait", waiting(resolver.feed(token("g")), "g g", until: 10.7))
clock.now = 10.5
check("the first deadline no longer applies", waiting(resolver.expire(), "g g", until: 10.7))
clock.now = 10.71
check("an expired prefix with no binding of its own is unrecognized", resolver.expire() == .unrecognized(chord("g g")))

check("modifiers are part of a key", resolver.feed(token("ctrl+h")) == .unrecognized([token("ctrl+h")]))

check("resolve: l l", ChordResolver.resolve(chord("l l"), bindings: resolverBindings) == llBinding)
check("resolve: l alone after its wait", ChordResolver.resolve(chord("l"), bindings: resolverBindings) == lBinding)
check("resolve: a run before the last key is unbound", ChordResolver.resolve(chord("h x"), bindings: resolverBindings) == nil)
check("resolve: an unbound prefix is unbound", ChordResolver.resolve(chord("g g"), bindings: resolverBindings) == nil)
check("resolve: a three-key chord", ChordResolver.resolve(chord("g g x"), bindings: resolverBindings) == ggxBinding)

if let config = fixture {
    var fixtureResolver = ChordResolver(bindings: config.resolverBindings, wait: 0.35, clock: { clock.now })
    check("fixture: t runs at once", fixtureResolver.feed(token("t")) == .run(config.resolverBindings[5]))
    check("fixture: ⌃⌘h runs at once",
          fixtureResolver.feed(KeyCodes.token(keyCode: 4, modifiers: [.ctrl, .cmd])!) == .run(config.resolverBindings[0]))
    if case .waiting = fixtureResolver.feed(token("l")) { check("fixture: l waits", true) } else { check("fixture: l waits", false) }
}

// MARK: - Chord confirmation

var confirmation = ChordConfirmation(chord: chord("h"), target: .placement("left-half"))
check("a running confirmation shows the chord and its target", confirmation.ran == "h → left-half" && confirmation.result.isEmpty)
confirmation.outcome = .succeeded
check("a succeeded confirmation is ticked", confirmation.result == " ✓")
let failedMove = ChordConfirmation(chord: chord("ctrl+l l"), target: .action(.screenEast), outcome: .failed("no window is focused"))
check("a failed confirmation shows the error",
      failedMove.ran == "⌃l l → screen-east" && failedMove.result == ": no window is focused")

// MARK: - Target matching

func window(_ id: Int, _ app: String, _ bundle: String?, _ title: String, focused: Bool = false, screen: Int = 2) -> WindowInfo {
    WindowInfo(id: id, app: app, bundleID: bundle, pid: 100 + id, title: title,
               frame: Rect(x: 0, y: 38, w: 800, h: 600), screen: screen, focused: focused, minimized: false)
}

let windows = [
    window(1, "Ghostty", "com.mitchellh.ghostty", "kx — zsh", focused: true),
    window(2, "Ghostty", "com.mitchellh.ghostty", "notes"),
    window(3, "Safari", "com.apple.Safari", "GitHub", screen: 3),
    window(4, "Google Chrome", "com.google.Chrome", "Docs"),
]

func matched(_ target: WindowTarget, _ list: [WindowInfo] = windows) -> Int? {
    if case .success(let window) = TargetMatcher.match(target, in: list) { return window.id }
    return nil
}

func failureCode(_ target: WindowTarget, _ list: [WindowInfo] = windows) -> ErrorCode? {
    if case .failure(let error) = TargetMatcher.match(target, in: list) { return error.code }
    return nil
}

check("no target is the focused window", matched(.focused) == 1)
check("no focused window is not_found", failureCode(.focused, Array(windows.dropFirst())) == .notFound)
check("a window id matches that window", matched(.windowID(3)) == 3)
check("an unknown window id is not_found", failureCode(.windowID(999)) == .notFound)
check("app and title match one window", matched(.app("ghostty", title: "kx")) == 1)
check("a title is a regular expression", matched(.app("Ghostty", title: "^no.es$")) == 2)
check("app matches a bundle ID, ignoring case", matched(.app("COM.GOOGLE.CHROME", title: nil)) == 4)
check("app does not match a substring", failureCode(.app("Ghost", title: nil)) == .notFound)
check("an app with no windows is not_found", failureCode(.app("Xcode", title: nil)) == .notFound)
check("several matches are ambiguous", failureCode(.app("Ghostty", title: nil)) == .ambiguous)
if case .failure(let error) = TargetMatcher.match(.app("Ghostty", title: nil), in: windows) {
    check("ambiguous carries the candidates", error.candidates?.map(\.id) == [1, 2])
}
check("an invalid title regex is bad_request", failureCode(.app("Ghostty", title: "(")) == .badRequest)
if case .success(let list) = TargetMatcher.filter(windows, WindowFilter(screen: 3)) {
    check("windows filter by screen", list.map(\.id) == [3])
}

// MARK: - Envelope

func parsed(_ json: String) -> Result<TrellisRequest, RequestError> {
    TrellisRequest.parse(Data(json.utf8))
}

func parsedCode(_ json: String) -> ErrorCode? {
    if case .failure(let error) = parsed(json) { return error.code }
    return nil
}

check("status parses", parsed(#"{"v":1,"event":"status","ts":1}"#) == .success(.status))
check("detail_data may be absent", parsed(#"{"v":1,"event":"screens","ts":1}"#) == .success(.screens))
check("place by placement parses",
      parsed(#"{"v":1,"event":"place","ts":1,"detail_data":{"placement":"left-half"}}"#)
        == .success(.place(PlaceRequest(target: .focused, shape: .placement("left-half"), screen: nil))))
check("place by rect with region, window id and screen east parses",
      parsed(#"{"v":1,"event":"place","ts":1,"detail_data":{"rect":{"x":0,"y":0,"w":0.5,"h":1},"region":"gutter","target":{"window_id":4211},"screen":"east"}}"#)
        == .success(.place(PlaceRequest(target: .windowID(4211), shape: .rect(Rect(x: 0, y: 0, w: 0.5, h: 1), region: "gutter"), screen: .direction(.east)))))
check("place by screen index parses",
      parsed(#"{"v":1,"event":"place","ts":1,"detail_data":{"placement":"p","screen":2,"target":{"app":"Ghostty","title":"kx"}}}"#)
        == .success(.place(PlaceRequest(target: .app("Ghostty", title: "kx"), shape: .placement("p"), screen: .index(2)))))
check("place with both placement and rect is bad_request",
      parsedCode(#"{"v":1,"event":"place","ts":1,"detail_data":{"placement":"p","rect":{"x":0,"y":0,"w":1,"h":1}}}"#) == .badRequest)
check("place with neither is bad_request", parsedCode(#"{"v":1,"event":"place","ts":1,"detail_data":{}}"#) == .badRequest)
check("an out-of-range rect is bad_request",
      parsedCode(#"{"v":1,"event":"place","ts":1,"detail_data":{"rect":{"x":0.5,"y":0,"w":0.6,"h":1}}}"#) == .badRequest)
check("screen.move parses",
      parsed(#"{"v":1,"event":"screen.move","ts":1,"detail_data":{"direction":"west"}}"#) == .success(.screenMove(.focused, .west)))
check("screen.move needs a direction", parsedCode(#"{"v":1,"event":"screen.move","ts":1}"#) == .badRequest)
check("chord parses", parsed(#"{"v":1,"event":"chord","ts":1,"detail_data":{"keys":"l l"}}"#) == .success(.chord("l l")))
check("windows filters parse",
      parsed(#"{"v":1,"event":"windows","ts":1,"detail_data":{"app":"Safari","screen":3}}"#)
        == .success(.windows(WindowFilter(app: "Safari", title: nil, screen: 3))))
check("config.reload parses", parsed(#"{"v":1,"event":"config.reload","ts":1}"#) == .success(.configReload))
check("a title target without app is bad_request",
      parsedCode(#"{"v":1,"event":"screen.move","ts":1,"detail_data":{"direction":"east","target":{"title":"x"}}}"#) == .badRequest)
check("an unknown event is bad_request", parsedCode(#"{"v":1,"event":"teleport","ts":1}"#) == .badRequest)
check("another envelope version is bad_request", parsedCode(#"{"v":2,"event":"status","ts":1}"#) == .badRequest)
check("garbage is bad_request", parsedCode("not json") == .badRequest)

func replyObject(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

let statusReply = Reply.ok(StatusData(
    version: "0.1.0", pid: 42, accessibility: false, layoutMode: true,
    config: .init(path: "/x/config.json", source: nil, state: .failed, error: "bad")
))
let statusObject = replyObject(statusReply)
let statusData = statusObject?["data"] as? [String: Any]
check("a reply is one line", !statusReply.contains(0x0A))
check("a success reply is ok", statusObject?["ok"] as? Bool == true)
check("status carries layout_mode", statusData?["layout_mode"] as? Bool == true)
check("status config carries a null source", (statusData?["config"] as? [String: Any])?["source"] is NSNull)
check("slashes stay unescaped", String(decoding: statusReply, as: UTF8.self).contains("/x/config.json"))

func statusConfig(_ state: ConfigLoadState) -> [String: Any]? {
    let reply = Reply.ok(StatusData(
        version: "0.1.0", pid: 42, accessibility: true, layoutMode: false,
        config: .init(path: "/x/config.json", source: nil, state: state, error: nil)
    ))
    return (replyObject(reply)?["data"] as? [String: Any])?["config"] as? [String: Any]
}
check("config is loading until the first load finishes",
      ConfigLoadState(hasConfig: false, finishedFirstLoad: false) == .loading)
check("config failed when the first load gave none",
      ConfigLoadState(hasConfig: false, finishedFirstLoad: true) == .failed)
check("a live config is loaded", ConfigLoadState(hasConfig: true, finishedFirstLoad: true) == .loaded)
check("status reports loading as not loaded",
      statusConfig(.loading)?["state"] as? String == "loading" && statusConfig(.loading)?["loaded"] as? Bool == false)
check("status reports loaded", statusConfig(.loaded)?["loaded"] as? Bool == true)

let chordReply = replyObject(Reply.ok(ChordData(keys: "x", target: nil, ran: false)))
check("an unbound chord replies target null", (chordReply?["data"] as? [String: Any])?["target"] is NSNull)
let boundReply = replyObject(Reply.ok(ChordData(keys: "l l", target: .placement("right-half-full"), ran: true)))
check("a bound chord replies its target",
      ((boundReply?["data"] as? [String: Any])?["target"] as? [String: Any])?["placement"] as? String == "right-half-full")

var ambiguous = RequestError(code: .ambiguous, message: "2 windows match")
ambiguous.candidates = Array(windows.prefix(2))
let ambiguousObject = replyObject(Reply.failure(ambiguous))
check("an error reply is not ok", ambiguousObject?["ok"] as? Bool == false)
check("an error reply carries its code", ambiguousObject?["code"] as? String == "ambiguous")
check("an ambiguous reply carries candidates", (ambiguousObject?["candidates"] as? [Any])?.count == 2)
let candidate = (ambiguousObject?["candidates"] as? [[String: Any]])?.first
check("a window object uses the contract's keys",
      candidate?["bundle_id"] as? String == "com.mitchellh.ghostty" && candidate?["frame"] is [String: Any])
check("a plain error reply has no candidates",
      replyObject(Reply.failure(.notPermitted))?["candidates"] == nil)
let screensObject = replyObject(Reply.ok(ScreensData(screens: [primary])))
check("a screen object uses visible_frame",
      ((screensObject?["data"] as? [String: Any])?["screens"] as? [[String: Any]])?.first?["visible_frame"] != nil)

// MARK: - Placement planning

if let config = fixture {
    let focused = WindowInfo(id: 1, app: "Ghostty", bundleID: nil, pid: 1, title: "kx",
                             frame: Rect(x: 100, y: 100, w: 600, h: 400), screen: 2, focused: true, minimized: false)
    func planned(_ shape: PlaceRequest.Shape, _ screen: ScreenSelector? = nil, _ cfg: TrellisConfig? = config) -> Result<Rect, RequestError> {
        PlacementPlanner.frame(for: PlaceRequest(target: .focused, shape: shape, screen: screen),
                               window: focused, screens: screens, config: cfg)
    }
    check("a placement lands on the window's screen",
          (try? planned(.placement("right-half-full")).get()) == Rect(x: 864, y: 38, w: 864, h: 1079))
    check("screen east places on the next screen",
          (try? planned(.placement("right-half-full"), .direction(.east)).get()) == Rect(x: 2688, y: 262, w: 960, h: 1055))
    check("a screen index places there",
          (try? planned(.placement("right-half-full"), .index(1)).get()) == Rect(x: 1280, y: -1415, w: 1280, h: 1415))
    check("a missing screen index is not_found",
          { if case .failure(let e) = planned(.placement("left-half"), .index(9)) { return e.code == .notFound }; return false }())
    check("an unknown placement is bad_request",
          { if case .failure(let e) = planned(.placement("nope")) { return e.code == .badRequest }; return false }())
    check("a placement with no config is unavailable",
          { if case .failure(let e) = planned(.placement("left-half"), nil, nil) { return e.code == .unavailable }; return false }())
    check("a bare rect needs no config",
          (try? planned(.rect(Rect(x: 0, y: 0, w: 1, h: 1), region: nil), nil, nil).get()) == primaryVisible)
    check("a rect takes a named region",
          (try? planned(.rect(Rect(x: 0, y: 0, w: 1, h: 1), region: "gutter")).get()) == Rect(x: 0, y: 38, w: 1642, h: 1079))
    check("screen-east keeps the window's fractions",
          (try? PlacementPlanner.frame(for: .action(.screenEast), window: focused, screens: screens, config: config).get())
            == Geometry.relocate(focused.frame, from: primaryVisible, to: rightVisible))
    let rightmost = WindowInfo(id: 2, app: "a", bundleID: nil, pid: 2, title: "",
                               frame: Rect(x: 2000, y: 300, w: 400, h: 300), screen: 3, focused: true, minimized: false)
    check("screen-east from the rightmost screen is not_found",
          { if case .failure(let e) = PlacementPlanner.move(rightmost, .east, screens: screens) { return e.code == .notFound }; return false }())
}

// MARK: - Menu icon

check("untrusted is blocked, even in layout mode",
      MenuIconState.state(accessibilityTrusted: false, layoutModeActive: true) == .blocked)
check("layout mode", MenuIconState.state(accessibilityTrusted: true, layoutModeActive: true) == .layout)
check("normal", MenuIconState.state(accessibilityTrusted: true, layoutModeActive: false) == .normal)
check("normal and blocked draw the light weight", MenuIconState.normal.weight == .light && MenuIconState.blocked.weight == .light)
check("layout mode draws the halfway weight", MenuIconState.layout.weight == .halfway)
check("blocked is 45% opacity", MenuIconState.blocked.opacity == 0.45 && MenuIconState.normal.opacity == 1)
check("only blocked shows the badge",
      MenuIconState.blocked.showsBadge && !MenuIconState.normal.showsBadge && !MenuIconState.layout.showsBadge)
check("the light inner radius", near(LatticeWeight.light.innerRadius, 2.58))
check("the inner radius floors at 1.2", near(LatticeWeight(frame: 3, slat: 1).innerRadius, 1.2))

// MARK: - Process runner (the CLI's error path)

let runner = ProcessRunner(defaultTimeout: 5)
let echoed = try? await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"])
check("a subprocess's stdout is returned", echoed.map { String(decoding: $0, as: UTF8.self) } == "hi\n")
do {
    _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo 'config is invalid' >&2; exit 1"])
    check("a failing subprocess throws", false)
} catch {
    check("a failing subprocess reports its stderr", error.localizedDescription == "config is invalid")
}
do {
    _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 3"])
    check("a silent failing subprocess throws", false)
} catch {
    check("a silent failing subprocess reports its status",
          (error as? ProcessRunError).map { if case .exited(_, 3, _, _) = $0 { return true }; return false } ?? false)
}
do {
    _ = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exec >&- 2>&-; exec /bin/sleep 5"], timeout: 3
    )
    check("a subprocess that closes its pipes and runs on is not a success", false)
} catch {
    check("a subprocess that closes its pipes and runs on times out",
          (error as? ProcessRunError).map { if case .timedOut = $0 { return true }; return false } ?? false)
}
do {
    _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.2)
    check("a slow subprocess times out", false)
} catch {
    check("a slow subprocess times out", (error as? ProcessRunError).map { if case .timedOut = $0 { return true }; return false } ?? false)
}
do {
    _ = try await runner.run(executable: URL(fileURLWithPath: "/nonexistent/trellis"), arguments: [])
    check("a missing binary fails to launch", false)
} catch {
    check("a missing binary fails to launch", (error as? ProcessRunError).map { if case .launchFailed = $0 { return true }; return false } ?? false)
}

// MARK: - Reload coalescing

actor RunCounter {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}

let quickRuns = RunCounter()
let quick = ReloadCoalescer(window: 0.05) { await quickRuns.next() }
async let firstRequest = quick.request()
async let secondRequest = quick.request()
async let thirdRequest = quick.request()
let burst = await [firstRequest, secondRequest, thirdRequest]
check("requests within the window share one reload", burst == [1, 1, 1])
let afterBurst = await quick.request()
check("a request after the window gets its own reload", afterBurst == 2)

let slowRuns = RunCounter()
let slow = ReloadCoalescer(window: 0.05) { () -> Int in
    let run = await slowRuns.next()
    try? await Task.sleep(nanoseconds: 300_000_000)
    return run
}
let running = Task { await slow.request() }
try? await Task.sleep(nanoseconds: 150_000_000)
let midReload = await slow.request()
let runningOutcome = await running.value
check("a request made mid-reload is answered by the next reload, not the running one",
      runningOutcome == 1 && midReload == 2)

print("")
if failures.isEmpty {
    print("\(passed) checks passed")
    exit(0)
} else {
    print("\(failures.count) of \(passed + failures.count) checks FAILED:")
    for name in failures { print("  \(name)") }
    exit(1)
}
