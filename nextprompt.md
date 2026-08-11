Read LAYER_COMPOSITING.md first — the agreed design, settled with the product owner. §11 is the build
order. Phases 0 through 3 are done, committed and green. **You are doing phase 4: group properties —
isolated / pass-through, group opacity, and the §4.1 visibility change.** Stop at that phase boundary
and report; the product owner re-scopes there rather than in the middle.

You are the orchestrator. You may delegate to worker sessions and pick the model per task, but **at
most 2 sonnet + 1 opus workers running at any one moment** — this is a token budget, not a
suggestion. If usage crosses 90% the product owner will send a save-your-work prompt; commit what you
have with an honest state-of-play note and stop until they send a continue. Ask them directly if
something is genuinely ambiguous — they answer quickly, and §10.3 (whether old projects need a
visibility migration) is *your phase's* open item, so ask it early rather than guessing.

What phases 2–3 built, so you don't rediscover it:
- `Engine/RenderRequest.swift` — the immutable snapshot (§9.1 point 3): the `RenderNode` tree,
  `sources` holding one already-rendered `CGImage` per `layers` index, frame, canvas size, background,
  quality. Built by `CanvasManager.makeRenderRequest(atFrame:includeBackground:)`, `@MainActor`,
  modelled on `ProjectStore.SaveSnapshot`. **The composite itself reads nothing live** — no
  `@Published`, no view, no `RasterLayerTexture`/`VectorCanvas`. Keep it that way; it is the whole
  reason §9.2 can be added later instead of rewritten for.
- `Engine/Compositor.swift` — the entry point and the CoreGraphics reference. `Compositor.backend`
  is the flag, `.coreGraphics` by default, `.metal` opt-in with automatic CPU fallback.
- `Engine/MetalCompositor.swift` + `Engine/Composite.metal` — the GPU backend. Ping-pong `rgba8Unorm`
  textures, premultiplied source-over, no cache.
- `PixelOps.compositeCanvas` is **deleted**. Its flat walk lives on as
  `CompositorParityLogicTests.flatWalkComposite`, the frozen oracle. Phase 4 is the first phase
  allowed to change composited output, so when you change it, update that test *by hand and on
  purpose* — do not relax the oracle to make a failure go away.

**Two decisions in the compositor are exactly what phase 4 overturns. Read them before you start.**
1. *A transparent group gets no buffer of its own.* `CoreGraphicsCompositor.draw` recurses into a
   folder drawing straight onto the parent context. That is not an optimisation — an intermediate
   buffer re-quantizes to 8-bit once per nesting level, and byte-identity fails for any document
   containing a folder. Phase 4 makes isolation and group opacity real, so those groups now *need*
   the intermediate. Expect the parity tests to hold for transparent/pass-through groups and to need
   new, separate expectations for isolated ones. `testNestingLayersInFoldersDoesNotChangeCompositeCost`
   in `PerfBaselineTests` guards the no-buffer case; it should keep passing for pass-through.
2. *A group's own `isVisible` is not consulted.* `toggleFolderVisibility` still writes through to
   descendants, so honouring the folder flag today would double-apply and change shipped behaviour.
   §4.1 is where that changes. `testAChildReShownInsideAHiddenFolderStillRendersToday` and the comment
   in `Compositor.draw` are both written to be changed and say so.

Phase 4's model work: `LayerFolder` gains `opacity`, `blendMode`, `isIsolated`, `alphaMask`, persisted
in `FolderManifest` **all defaulted, so existing projects decode unchanged** — check that by round-
tripping a project saved before your change, not by reading the decoder. `RenderNode` already carries
`opacity`/`isVisible` uninterpreted and hardcodes folder opacity to 1 in `RenderTree.swift`; that
hardcode is yours to remove.

Gotchas that each cost a cycle:
- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** A malformed `-only-testing` makes
  xcodebuild report success having run nothing, and zsh causes it by not word-splitting unquoted
  `$VAR`. Use an array, `"${SUITES[@]}"`, and read `totalTestCount` from `xcresulttool`, never the
  banner. CLAUDE.md has the full recipe.
- **Read CLAUDE.md's "Triaging a failed XCUITest" before diagnosing any failure.** Erase the
  simulator, re-run the single test, treat a clean pass as confirmation. Do not re-run the 22-minute
  suite to decide. Use the dedicated simulator by UDID (`75C8B97E-47AF-484B-B7D2-CA7EB1B51B03`); a
  `-destination name=...` that matches no real device falls back silently. `uptime` is useless here —
  use `top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1`.
- **A new app source used by tests** goes in the pbxproj group "App sources shared with
  PaintSoftwareUITests" *and* the `PaintSoftwareUITests` Sources phase, and must contain no SwiftUI
  `View`. The app target needs nothing — `PaintSoftware/` is a `PBXFileSystemSynchronizedRootGroup`.
  Copy how `RenderRequest.swift` is registered.
- **A new `.metal` file needs explicit test-target membership**, and that is only half of it: under
  XCUITest `Bundle.main` is the *runner app*, so `makeDefaultLibrary()` finds nothing. Ask for the
  library with `Bundle(for:)` against a class in your own bundle — `CompositorMetalEngine` shows both
  halves. `MetalFillEngine` does neither, which is why its GPU path is still XCUITest-only.
- Memory assertions: `phys_footprint` cannot measure retention in this test process. Assert on
  `cgImage.bytesPerRow * height` — see `PerfBaselineTests.testEmptyVectorLayersRetainNothingWhenTheDisplayRefreshes`.
- Vector is the default layer kind, so default names are "Vector N" and `readLayerStrokeCount` reads 0
  on one — use `readVectorMarker(app, layerIndex:)?.strokes`, or `addRasterLayer(app)` for tests
  genuinely about the raster tier.

Numbers worth having before you optimise anything: six layers at 2048² cost **276 ms to snapshot and
84 ms to composite**, and six levels of nesting cost the same as flat (38.6 vs 38.9 ms). The expensive
half is building the snapshot. The GPU's 1189 ms is simulator-bound and is not a verdict on Metal.
There is no texture cache because the one written for phase 2 was measured never hitting —
`PixelOps.rasterize` mints a fresh `UIImage` per call, so an identity key cannot hit; a key that works
must come from the model (cel id + the two `version`s + the two image identities + quality).

Still open, all recorded in the doc, none of them yours unless you want them: §5.2's sandwich now
rides with phase 5's blend modes; the onion skin flattens a cel set at alpha 1 ignoring layer opacity
and visibility, so converging it changes what artists see; and the project thumbnail ships
transparent-backed on a black gallery.

Constraints: follow CLAUDE.md (multi-session protocol, build/test tiers, graphify). Run the fast
`*LogicTests` tier constantly; run the full suite at the phase boundary, and if you skip it say so
plainly rather than implying it passed. Match the surrounding comment density and idiom — this
codebase explains why, not what, and it is worth reading a neighbouring file before writing in it.
Keep the docs short: prune what is done rather than appending status. Append the one-line
SESSION_LOG.md entry (keeping only the last five) and refresh the graphify report.

When phase 4 is done and verified, end by writing the copy-paste prompt for the next session —
whatever is genuinely next, including what you learned that would otherwise be rediscovered, and the
same instruction to write the following session's prompt at the end. Keep it about this long. **Write
it to `nextprompt.md` in the repo root and commit it**, rather than only to a scratchpad: a previous
session left it in a session-scoped temp directory and it had to be recovered from a transcript.
