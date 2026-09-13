# Streaming the computer's screen as a layer — TODO (27)

The owner's brief is in [TODO.md](TODO.md) item (27), verbatim. This file is the design: what exists
that it builds on (§0), what the owner ruled (§2), the wire protocol both programs implement (§3), the
Windows streamer (§4), the iPad side (§5), the defaults taken without a ruling (§6), the build order
(§7) and what is unconfirmed (§8). Designed 2026-09-13.

**Two programs, one connection.** A streamer on the Windows laptop captures a monitor or a single
application window, hardware-encodes it as H.264, and serves it over TCP on the Tailscale network. The
iPad app connects, decodes off the main thread, and shows the live picture as an object inside a vector
layer — the same shape as an imported video. The same connection carries files both ways: a file
dropped on the laptop lands in the open document as a new layer; an export from the iPad is saved on
the laptop.

## 0. What exists that this builds on — read before re-deriving

- **A video layer is a `.vector` `LayerKind` layer whose cel holds one `VectorElement.video`**
  (`VectorVideoElement`, `Engine/VectorLayer.swift`). There is no video `LayerKind`, so a stream needs
  no new kind and none of the five exhaustive switches `LayerKindLogicTests` guards. A stream is a
  sixth `VectorElement` case, `.stream(VectorStreamElement)`, encoded through
  `VectorCanvasData.ElementData` with `kind: "stream"`.
- **`PlacedRectangle` is the Move box.** `VectorImageElement` and `VectorVideoElement` conform, and
  `ObjectTransformFrame` / `beginVectorMove(ofElementIDs:)` / `VectorCanvas.quad(of:)` /
  `placed(_:through:)` are written against the protocol, so a conforming stream element moves,
  scales, mirrors and Freeform-stretches with no new code (VIDEO.md §4.2: *"a video is a placed
  rectangle wherever the arm is about the rectangle"*). The same refusal set applies — lasso split,
  Change Colour and interpolation warp refuse a placed rectangle.
- **`CanvasManager.splitCel(layerIndex:celIndex:atFrame:)` (`CanvasManager+Timeline.swift`) is the
  split primitive.** `bakeVideoToCels` (`CanvasManager+VideoBake.swift`) is the model for Bake
  Frame: `splitCel` inside one `withInterpolationUndo(label:touching:)` (not `withStructureUndo` —
  its doc comment says why), then the swap of the element for a `VectorImageElement` with the same
  placement fields, every element `reidentified()`, refusals returned as an outcome enum and
  surfaced through `CanvasNotice`, never a silent `Bool`.
- **Import entry points**: `ActionsMenu` (`Views/ActionsMenu.swift`) → `CanvasManager.insertImage(_:)`
  (joins the active vector layer or makes one, then lifts the element into the Move box) and
  `insertVideo(at:consumingSource:)` (always a new layer, VIDEO.md §2.1; the cel spans
  `min(clip, contentEndFrame)` from the current frame, §2.4). The drop box lands on these two.
- **Export**: `Views/ExportSheet.swift` with `FrameExportSession`, finishing in `.finished(url)`.
  "Send to computer" is a destination for that URL.
- **Render**: `VectorCanvas.renderLocalContent` draws `.video` through `Self.draw(video:into:)` —
  `element.displayFrame` (a `UIImage`) into `element.placement`, or a grey placeholder with a glyph
  in the same rect (RENDER §2.10, *never a hole*). Video frames are resolved per timeline frame by
  `CanvasManager.videoCelContent(for:atFrame:inheriting:)` through `DerivedCelContent`'s
  identity-plus-thunk cache. **Every invalidation in the app is edit-driven** — `bumpVersion()`,
  `celContentChangedOutsideStroke(layerID:celID:)`, `reconcileLayers` — nothing today redraws a cel
  because time passed. A live source is the first thing that does, and §5.3 is how.
- **Bottom-dock bars**: `MoveTransformBottomBar` shows because a piece floats (`isAnyPieceFloating`),
  `SelectPanel` because `activePanel == .select`, `TextSettingsPanel` because `enterTextMode()` set
  `activePanel = .text`, all through `View.bottomDockCard(width:)` and `enum BottomDock`. **No bar
  today appears because the artist is standing on a layer of some kind** — the stream bar is the
  first, and `MoveTransformBottomBar`'s state-driven show is its model.
- **`CanvasManager.canvasInteractionBegan(mayContinueTake:)` fires on the first finger of every canvas
  touch** and `DrawingView` answers by setting `activePanel = .none` — which is TODO (67)'s defect
  and would close the stream bar on a two-finger pan too. The stream bar is shown by *layer state*,
  not by `activePanel`, so it is immune; (67) is fixed on its own.

## 1. The shape

```
 Windows laptop (desktop-cbr0fl6)                       iPad
 ┌──────────────────────────────────────┐   Tailscale   ┌──────────────────────────────────┐
 │ Streamer.Tray (WPF)                  │   TCP 47301   │ ScreenStreamClient (background)  │
 │  picker · drop box · status · folder │◄────────────►│  framing · NAL split · VTDecode  │
 │ Streamer.Core                        │  one socket   │  latest-frame slot per stream    │
 │  SourceCatalog · PipelineBuilder     │  video+files  │ ScreenStreamCoordinator (main)   │
 │  ProtocolServer · FileInbox          │              │  ≤30 Hz tick → bump cel version  │
 │ GStreamer process                    │              │ VectorStreamElement in a .vector │
 │  d3d11screencapturesrc → H.264 enc   │              │  layer, drawn like .video         │
 └──────────────────────────────────────┘              └──────────────────────────────────┘
```

## 2. Owner rulings — 2026-09-13, from the brief and four answers; do not re-litigate

- **2.1 It is a live stream, not a recording**, and the laptop side is a separate program for now.
  Its capture core is written so a future Windows build of the paint app can host it in-process
  (brief point 9; §4.6).
- **2.2 Actions → Stream Screen makes its own layer with the stream object inside it**, like a
  video (point 4).
- **2.3 Standing on that layer shows an options bar of the Move/Lasso kind with Freeze and Bake
  Frame** (point 5).
- **2.4 Bake Frame splits the cel at the current frame and replaces the stream object in the new
  one-frame cel with an image object holding the snapshot**; the neighbours are untouched. Four
  frames, one cel, on frame 2 → [1] [2] [3–4], and only [2] changes (point 5). **The playhead stays
  on the baked frame** (answer 4).
- **2.5 Low latency, and the stream must not lag the main thread** (point 6).
- **2.6 The Move tool moves the stream object like a video object** (point 7).
- **2.7 A source is a monitor or a single application window** (point 8), **and it is picked on the
  Windows app** (answer 1). The iPad shows what the laptop is set to send.
- **2.8 The computer may be turned off and on mid-session** (point 10): the layer keeps showing the
  last picture it received, and streaming resumes on its own when the laptop is back.
- **2.9 A stream layer that is actively moving need not be rendered** (point 11): during playback the
  stream is not fed into the render.
- **2.10 The Windows app has a drop box; a dropped or pasted file appears in the iPad app through
  the existing import-video / import-image feature, straight into the open document** (point 3,
  answer 2); **the iPad can export to the Windows app, which saves to the laptop** (point 3).
- **2.11 Hardware video encoding from the start** (answer 3), on an open-source engine — GStreamer
  (§4.2), which the owner left to us: *"there are open source low latency high performance streaming
  systems you could probably use. Your choice."*
- **2.12 The laptop is reached over Tailscale** (point 12).

## 3. The wire protocol — `paintstream/1`

One TCP connection, laptop listening on **port 47301**, iPad connecting. Every message is a frame:

```
u8  type
u32 length   (big-endian, payload bytes)
[]  payload
```

Payloads marked JSON are UTF-8 JSON objects. Unknown types are skipped by length, never fatal.

| type | name | dir | payload |
|---|---|---|---|
| 0x01 | HELLO | both | JSON `{"proto":1,"app":"PaintStreamer"\|"PaintApp","version":"…","name":"desktop-cbr0fl6"\|"Kevin's iPad"}` — first message each way |
| 0x02 | STATUS | L→I | JSON `{"source":{"kind":"monitor"\|"window"\|"none","name":"Blender","id":"…"},"width":1920,"height":1080,"fps":30,"codec":"h264","streaming":true}` — on connect, on every source change, on pause/resume |
| 0x03 | VIDEO | L→I | `u8 flags` (bit0 = keyframe) `u64 pts_us` then **one H.264 access unit, Annex-B byte stream**. Every keyframe is preceded by SPS and PPS inside the same payload |
| 0x04 | CONTROL | I→L | JSON `{"cmd":"pause"\|"resume"\|"keyframe"}` — pause stops encoding server-side; resume restarts it with a keyframe |
| 0x10 | FILE_BEGIN | both | JSON `{"id":7,"name":"ref.mp4","size":1234567,"kind":"image"\|"video"\|"other"}` |
| 0x11 | FILE_CHUNK | both | `u32 id` then bytes, ≤ 256 KiB |
| 0x12 | FILE_END | both | JSON `{"id":7}` |
| 0x13 | FILE_RESULT | both | JSON `{"id":7,"ok":true}` or `{"id":7,"ok":false,"reason":"No document is open on the iPad"}` — the sender shows `reason` to the person |
| 0x20 | PING | both | empty, every 2 s of silence |
| 0x21 | PONG | both | empty |

**Rules.**
- The laptop encodes only while a client is connected and not paused; STATUS `streaming:false` means
  the picture is stale on purpose (no source picked, paused, or the capture failed — `reason` field).
- The laptop sends a keyframe on connect, on every source change, on `resume`, on `keyframe`, and at
  least every 2 s. The iPad decodes nothing until it has seen SPS/PPS, then decodes every AU in order.
  A decode error requests a keyframe and drops AUs until one arrives.
- **Reconnect is the client's job** (2.8): 1 s → 2 s → 5 s backoff, forever, while the open document
  holds at least one stream element. The laptop's listener is always up while the app runs. No
  session state survives a reconnect except the source selection, which lives on the laptop.
- Three missed PINGs (6 s) is a dead connection on either side.
- Files: one transfer in flight per direction; a FILE_BEGIN while one is active is answered
  `ok:false`. The iPad answers FILE_END after `insertImage` / `insertVideo` returns (so `ok` means
  *inserted*, not *received*). The laptop answers after the file is closed in the save folder.
- Version: HELLO's `proto` must match; a mismatch is reported in words on both screens, and the
  connection closes.

**Bandwidth targets**: 1080p at up to 30 fps, ~6 Mbit/s CBR-ish, low-latency encoder mode, GOP 2 s.
The iPad 9th gen on Tailscale (WireGuard on an A13) is comfortable there. The source's own change rate
is the real cap — a still screen costs a P-frame of a few hundred bytes per tick.

## 4. The Windows streamer — `streamer/` in this repo

### 4.1 Layout

```
streamer/
  PaintStreamer.sln
  Streamer.Core/     net8.0-windows10.0.19041.0 class library — no UI, no process-global state
    SourceCatalog    monitors (EnumDisplayMonitors) and windows (EnumWindows, visible + titled +
                     not tool windows), with small thumbnails for the picker
    PipelineBuilder  a GStreamer command line for a source + encoder (4.2)
    EncoderProbe     runs gst-inspect-1.0 once; picks the first available of
                     nvh264enc · qsvh264enc · amfh264enc · mfh264enc · openh264enc · x264enc
    GstProcess       spawns gst-launch-1.0, reads Annex-B H.264 from a localhost TCP socket
                     (tcpclientsink into Core's listener — not stdout, which Windows may text-mode),
                     splits access units, restarts the pipeline on exit
    ProtocolServer   TcpListener 0.0.0.0:47301, framing (§3), HELLO/STATUS/VIDEO/CONTROL/PING
    FileInbox        FILE_* in both directions; incoming saved to the chosen folder
    StreamerSession  glue: current source, pipeline lifecycle, pause when no client
  Streamer.Tray/     WPF — tray icon and one window (4.4)
  Streamer.Tests/    xunit — framing round trips, AU splitting, pipeline strings, file transfer
```

### 4.2 Capture and encode — GStreamer ≥ 1.22

`d3d11screencapturesrc` with `capture-api=wgc` is Windows.Graphics.Capture: `monitor-index=N` for a
monitor, `window-handle=H` for a single window, `show-cursor=true`. It hands D3D11 textures to the
encoder on the same device — no CPU readback. `mfh264enc` is Media Foundation and reaches whichever
vendor's hardware H.264 MFT the laptop has; `nvh264enc`/`qsvh264enc`/`amfh264enc` are the vendor
elements and are preferred when present. The shape:

```
d3d11screencapturesrc capture-api=wgc window-handle=H show-cursor=true
  ! video/x-raw(memory:D3D11Memory),framerate=30/1 ! d3d11convert
  ! <encoder low-latency, bitrate≈6000, gop≈60>
  ! h264parse config-interval=-1 ! video/x-h264,stream-format=byte-stream,alignment=au
  ! tcpclientsink host=127.0.0.1 port=<Core's ephemeral listener>
```

`config-interval=-1` puts SPS/PPS before every keyframe, which is §3's rule. `EncoderProbe` verifies
the chosen element actually negotiates on this laptop at first run and falls through if not; the
choice and the reason are in the log and in the window.

Requirements: Windows 10 1903+ (WGC), GStreamer 1.22+ MSVC x86_64 runtime with all plugins.
`GraphicsCaptureSession`'s yellow capture border may or may not be suppressible from an unpackaged
app — §8.

**On the owner's laptop, 2026-09-13**: Windows 11 Pro 25H2, Intel Iris Xe (13th-gen Core), one
1920×1080 display. GStreamer **1.26.8** installed from the MSI (`msiexec … ADDLOCAL=ALL /qn`) to
`C:\Program Files\gstreamer\1.0\msvc_x86_64` — 1.28 switched to an `.exe` installer whose silent
flags are undocumented, so the MSI series is the one `install-streamer.ps1` pins. Present:
`d3d11screencapturesrc` (`capture-api`, `monitor-index`, `window-handle`, `window-capture-mode`,
`show-cursor`, `show-border`), **`qsvh264enc`** and **`mfh264enc`** (the latter is the Intel Quick Sync
MFT, D3D11-aware, `low-latency`), `openh264enc`, `x264enc`. Absent: `nvh264enc`, `amfh264enc`. .NET
SDK 8.0.425 at `C:\dotnet`.

### 4.3 Running it, and running it over SSH

An SSH session on Windows is a non-interactive window station: nothing started from it can see the
desktop, so neither the app nor `gst-launch-1.0` can capture from there — `EnumWindows` in that
session sees one fake 1024×768 "WinDisc" display. **And the laptop has two accounts**: SSH (and "Run
as administrator") is the admin `PC`; the person at the screen is the standard user **`kevin`**, whose
session 1 is the only one that can capture. The task runs as `kevin` with an Interactive logon
principal, registered by the admin with no password. The app runs as a **Scheduled
Task** registered to run interactively in the logged-in user's session (`schtasks /create … /it`), and
`tools/windows/streamer.ps1 start|stop|status|log` drives it from SSH. Double-clicking the exe on the
laptop does the same thing by hand. Log: `%LOCALAPPDATA%\PaintStreamer\log.txt`.

`tools/windows/install-streamer.ps1` (run once as Administrator, over SSH): .NET 8 SDK via winget,
GStreamer MSI silently with all features, the firewall rule for 47301 **scoped to 100.64.0.0/10** (the
Tailscale range — nothing on the LAN or the internet reaches it), the scheduled task, and a
`dotnet publish` of the tray app to `%LOCALAPPDATA%\PaintStreamer\app`.

### 4.4 The window

One window, four things: the **source picker** (monitors then windows, thumbnails, a Stream button,
the current one marked; 2.7), the **status** (the iPad's name when connected, fps and kbit/s, the
encoder in use, and what to type on the iPad — `desktop-cbr0fl6` and `100.104.85.111`), the **drop
box** (drag files in, or Ctrl+V with a file or a bitmap on the clipboard; a pasted bitmap is saved as
PNG first; each file shows sent / inserted / the iPad's refusal reason), and the **save folder** for
exports from the iPad (default `%USERPROFILE%\Pictures\PaintApp`, chosen once, remembered). Closing
the window leaves the tray icon running; Quit is on the tray menu.

### 4.5 Source picking (2.7)

Picking a source restarts the pipeline and sends STATUS then a keyframe; the iPad's picture changes
within a second. Closing the picked window stops the pipeline and sends `streaming:false` with
`reason:"The window was closed"`; the iPad holds the last frame. A monitor that is unplugged is the
same.

### 4.6 The future merge — brief point 9

`Streamer.Core` is the whole streamer; `Streamer.Tray` only presents it. Core exposes
`IFrameSink` — the socket is one implementation, and an in-process consumer is another — so a Windows
build of the paint app would host `StreamerSession` directly, read decoded-or-encoded frames through
the sink, and skip the network entirely. Nothing in Core references WPF, a window handle for UI, or
a static. The protocol codec is its own type so a second client (the paint app on another machine)
is the same code path as the iPad.

## 5. The iPad side

### 5.1 The element

`VectorStreamElement: PlacedRectangle` in `Engine/VectorLayer.swift`, beside `VectorVideoElement`:
`id`, the placement group (`transform`, `aspect`, `stretchAxis`, `mirrored`), `naturalSize` (the
laptop's reported width × height, updated on STATUS), `host: String`, `port: UInt16`, `sourceLabel:
String` (for the bar), `isFrozen: Bool`, `lastFrameFileName: String?` — and runtime-only
`displayFrame: UIImage?`. Persisted through `VectorCanvasData.ElementData` as `kind: "stream"` with
a `StreamRef` whose fields are all non-optional (no build has shipped it, VIDEO.md's `VideoRef`
argument). `VectorCanvas.holdsStream` memoised like `holdsVideo`. The z-order slot beside `.video`.

### 5.2 Decoding, off the main thread

`ScreenStreamClient` (new file, `Engine/ScreenStream/`): one per `host:port`, shared by every stream
element in the open document; owns an `NWConnection` (TCP, keepalive) on a serial background queue,
the §3 framing, the reconnect loop, PING/PONG, and the file transfers. VIDEO payloads go to
`H264StreamDecoder`: split Annex-B into NAL units, build `CMVideoFormatDescription` from SPS/PPS
(`CMVideoFormatDescriptionCreateFromH264ParameterSets`), convert each AU to AVCC length-prefixed
`CMSampleBuffer`, decode through `VTDecompressionSession` with `kVTDecompressionPropertyKey_RealTime`
on its own serial queue, and publish the `CVPixelBuffer` into a **latest-frame slot** (a lock around
one buffer; a slow consumer sees the newest frame, never a queue). The slot hands out a `CGImage` via
`VTCreateCGImageFromCVPixelBuffer` on demand — the same draw as `.video`, no Metal path in stage 1.

### 5.3 Redrawing without an edit — the new invalidation

`ScreenStreamCoordinator` (main actor, owned by `CanvasManager`) subscribes to each client's
frame-arrived signal and runs a **tick at most every 33 ms** (coalesced, `CADisplayLink`-free — a
`DispatchSourceTimer` armed on arrival) that, for each unfrozen stream element **whose layer is
visible and whose cel is the one at the current frame**, sets `displayFrame` from the slot and calls
`celContentChangedOutsideStroke(layerID:celID:)`. That is the whole cost on the main thread: one
version bump per tick, then the compositor's usual path. The tick does nothing while
`isPlaying` (2.9), while the app is backgrounded, and while a Move box floats over that element (the
box's own redraw covers it). MEASURE the tick on the device before merging stage 2 — the aim is that
a live 1080p stream costs the main thread under 2 ms per tick.

### 5.4 Freeze

Freeze sets `isFrozen`, writes the current frame to `lastFrameFileName` at once (5.6), and stops the
tick for that element; Unfreeze clears it and asks for a keyframe. When every stream element on the
connection is frozen the client sends `pause`; the first unfreeze sends `resume`. **Freeze is not an
undo step** — it is a viewing state like the render-resolution knob, persisted with the document.
Bake works while frozen and bakes the frozen picture.

### 5.5 Bake Frame (2.4)

`CanvasManager.bakeStreamFrame(layerIndex:celIndex:atFrame:) -> StreamBakeOutcome`: in one
`withInterpolationUndo`, `splitCel` at `frame` when `frame > cel.start` and at `frame + 1` when
`frame + 1 < cel.end`, then in the cel that now spans exactly `frame`, replace `.stream` with a
`VectorImageElement(image:)` carrying the same placement fields, `reidentified()`, image written to
the package as the image path already does. Refusals: `.noFrameYet` (*"No picture from the computer
yet"*), `.notOnStreamCel`. The playhead stays. A bake on a one-frame cel is the swap alone.

### 5.6 Surviving the computer being off (2.8)

`lastFrameFileName` is written on freeze, on bake, on disconnect, and on save (JPEG, quality 0.9, in
the project package like an image element's file — never per frame). On load `displayFrame` is that
file, so the layer opens looking as it last did; the coordinator starts the client, which reconnects
in the background. The bar says **Live** / **Frozen** / **Reconnecting…** / **Not streaming — <reason
from STATUS>**. Nothing modal, ever.

### 5.7 The bar and the Actions entry (2.2, 2.3)

**Actions → Stream Screen** (a row after Insert Video, `addTextRow`'s shape): a sheet with the laptop's
address (MagicDNS name or Tailscale IP; last used prefilled; port 47301 shown, editable) and Connect.
On HELLO it makes a new vector layer with one stream element in one cel **from the current frame to
the end of the timeline** (§6), fitted to the canvas the way `insertVideo` fits (the laptop's aspect,
letterboxed), then lifts it into the Move box as `insertImage` does. If the connection fails the
sheet says so in words and stays open. A second Stream Screen makes a second layer sharing the client.

**`StreamBar`** (`Views/StreamBar.swift`, `bottomDockCard`): shows because the active layer's cel at
the current frame holds a stream element, unless a piece floats (the Move bar wins). Contents: source
label and state (5.6), **Freeze** ⇄ **Unfreeze**, **Bake Frame**, and the address for reconnecting to a
different laptop. It is not an `ActivePanel` case, so `canvasInteractionBegan`'s `activePanel = .none`
cannot close it — a two-finger pan keeps it up.

### 5.8 Files (2.10)

Laptop → iPad: on FILE_END, if a document is open, `kind == "image"` → `insertImage(UIImage)`, `video`
→ `insertVideo(at:consumingSource:true)` after staging the bytes in Application Support as
`VideoImportStore` does; other kinds are refused with a reason. No document open → `ok:false,
reason:"No document is open on the iPad"`. The insert is exactly the picker's, Move-box lift included.

iPad → laptop: `ExportSheet` gains **Send to Computer** beside the existing destination, enabled only
while a client is connected; it sends the `.finished(url)` file and reports the laptop's FILE_RESULT
in the sheet.

## 6. Defaults taken without a ruling — each reversible, each recorded where the behaviour lives

- The stream cel runs **from the current frame to the end of the timeline** (a video is clipped to
  its length; a stream has none).
- One connection per `host:port` per document, shared by all its stream layers; one **source** per
  laptop at a time (the laptop's picker is global).
- Port **47301**; the firewall rule admits only Tailscale addresses.
- Freeze is **not** an undo step; Bake Frame is **one**.
- Snapshots are stored at the laptop's native pixel size, not the canvas's.
- The last frame is saved as JPEG q0.9; the bake snapshot as the image path's existing format.
- Bitrate ~6 Mbit/s, 30 fps cap, GOP 2 s — tune on measurement.
- During playback the picture holds; on stop the next tick resumes it.

## 7. Build order

Each stage lands as its own merge with a fast tier, a Release fast tier (it adds test files), and —
because two features have shipped here that were correct and unusable — **a drive in the simulator
with a screenshot**, a **cold-start reachability test**, and an assertion on **what is drawn**, not
only what is stored (CLAUDE.md, *"A feature is not finished because its model is correct"*).

| stage | what | proves |
|---|---|---|
| **0** ✓ | STREAM.md; `tools/stream/fake-streamer.py` — a Python `paintstream/1` server on this Mac (ffmpeg `avfoundation` screen or `testsrc -re` → `h264_videotoolbox` → Annex-B; also `--send <file>` and a save folder; `stream-client-check.py` is the conformance client both servers are proved against; `--screen` needs Screen Recording permission for the terminal, `--pattern` is the CI path); a ≤200 KB H.264 fixture of `testsrc` for logic tests | the protocol has a reference implementation the iPad is tested against before the laptop exists |
| **1** | iPad: `VectorStreamElement`, Codable round trip, `ScreenStreamClient` + `H264StreamDecoder` (logic tests decode the fixture through the real framing, no network), the coordinator tick, `.stream` draw, Actions → Stream Screen sheet, Move box | a live picture of this Mac's screen moves in the simulator against the fake streamer; a cold-start XCUITest reaches the sheet from a new document |
| **2** | iPad: `StreamBar`, Freeze, Bake Frame via `splitCel` (logic tests pin [1] [2] [3–4] and the one-frame case, undo restores the stream), `lastFrameFileName` and reload, playback gating, reconnect (kill the fake streamer, restart it) | driven; the tick's main-thread cost MEASURED on the device |
| **3** | Windows: `Streamer.Core`, `Streamer.Tray`, tests, `install-streamer.ps1`, `streamer.ps1`; installed on the laptop over SSH and started as the task | the iPad shows Blender from the laptop; source switch, window close, laptop reboot all behave as §4.5/2.8 |
| **4** | Files both ways: drop box → insert, Ctrl+V bitmap, refusal reasons; Send to Computer | driven end to end |
| **5** | Latency and quality pass on the real link: end-to-end latency MEASURED (a clock on the laptop screen photographed beside the iPad), bitrate/GOP tuned, the dirty-screen idle cost | numbers in PERFORMANCE.md |

Stages 1–2 (iPad, simulator) and 3 (Windows, SSH, no simulator) run in parallel lanes.

## 8. Unconfirmed — verify at the stage that touches it

- Whether an unpackaged app can turn off WGC's yellow capture border (`IsBorderRequired`) — stage 3.
- Which encoder element the laptop actually has (GPU vendor unknown until SSH) — `EncoderProbe`.
- The exact main-thread cost of a 1080p tick and of `VTCreateCGImageFromCVPixelBuffer` on the iPad
  9th gen — stage 2, MEASURED; if it is over budget the draw moves to a `CVMetalTextureCache` path.
- Whether `tcpclientsink` on localhost or `fdsink` is the cleaner hand-off on Windows — stage 3.
- Tailscale MTU is 1280; irrelevant to TCP framing, noted in case UDP is ever tried.
