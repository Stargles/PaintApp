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
  `min(clip, contentEndFrame)` **from frame 0**, not from the current frame — `addVectorLayer`'s cel
  starts at 0 and `VideoImportLogicTests` pins `startFrame == 0`; this file said "from the current
  frame" until stage 1 read the code). The drop box lands on these two.
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
  least every 60 encoded frames. **The capture is damage-driven** (stage 3 MEASURED it: a still
  desktop produced one frame in 27 s, not a trickle of P-frames as this section first claimed), so a
  still screen sends nothing, and there is no wall-clock keyframe interval — connect, `resume` and
  `keyframe` each *restart the capture session*, and Windows delivers a first frame on every new
  session, so a client that needs a picture always gets one within about a second. **Stage 4 MEASURED
  the edge of that claim**: against the laptop idle and unattended (nobody at the keyboard — screen
  state not confirmed, possibly locked) the encoder engaged cleanly every time (STATUS went
  `streaming:true` within ~1.3 s of connect every run, and the GStreamer log shows a clean "pipeline
  connected, streaming" with no errors on each attempt) but zero VIDEO frames arrived: none in 33 s of
  passive observation, and none in the 5 s window `stream-client-check.py --pause-after` allows after
  a `resume`-forced pipeline restart (an `INVARIANT VIOLATION: no VIDEO frame arrived within 5s of
  resume`). So "within about a second" is conditioned on *some* damage existing for WGC to report —
  restarting the capture session guarantees a fresh *attempt*, not a fresh *frame*, on a desktop with
  literally nothing changing. Unconfirmed whether the cause is specifically a locked session (this Mac
  cannot drive kevin's interactive session 1 to check or to unlock it) or just a quieter idle desktop
  than the 27 s reference measurement's; either way it is a capture-pipeline question, not a stage-4
  regression — nothing stage 4 touched (`FileInbox`/`FileOutbox`/the Tray window) is in the video path,
  and the pipeline's own connect/encode mechanics were clean throughout. The iPad decodes
  nothing until it has seen SPS/PPS, then decodes every AU in order. A decode error requests a
  keyframe and drops AUs until one arrives. A VIDEO payload may begin with an AUD NAL before the
  SPS (`qsvh264enc` always emits one); the rule is that SPS and PPS precede the IDR slice, not that
  they are the first bytes.
- **Reconnect is the client's job** (2.8): 1 s → 2 s → 5 s backoff, forever, while the open document
  holds at least one stream element. The laptop's listener is always up while the app runs. No
  session state survives a reconnect except the source selection, which lives on the laptop.
- Three missed PINGs (6 s) is a dead connection on either side.
- Files: one transfer in flight per direction; a FILE_BEGIN while one is active is answered
  `ok:false`. The iPad answers FILE_END after `insertImage` / `insertVideo` returns (so `ok` means
  *inserted*, not *received*). The laptop answers after the file is closed in the save folder.
- Version: HELLO's `proto` must match; a mismatch is reported in words on both screens, and the
  connection closes.

**Bandwidth targets**: 1080p at up to 30 fps, ~6 Mbit/s CBR-ish, low-latency encoder mode, GOP 60
frames. The iPad 9th gen on Tailscale (WireGuard on an A13) is comfortable there. The source's own
change rate is the real cap — a still screen costs **nothing** (above), and stage 3 MEASURED a moving
desktop at ~3.6 Mbit/s and ~18 fps with `qsvh264enc` at 6.4% CPU for GStreamer and ~1.5% for the app.

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
    ProtocolServer   TcpListener 0.0.0.0:47301, framing (§3), HELLO/STATUS/VIDEO/CONTROL/PING,
                     AdmissionPolicy-gated (§4.3)
    FileInbox        FILE_* in both directions; incoming saved to the chosen folder
    StreamerSession  glue: current source, pipeline lifecycle, pause when no client
    AdmissionPolicy  TODO (98): Tailscale, or the laptop's own live RFC1918 subnets — the one
                     place the LAN admission rule is spelled out (§4.3)
    Discovery/       TODO (98): MdnsAdvertiser — a hand-rolled `_paintstream._tcp` responder, no
                     NuGet dependency (§4.3)
  Streamer.Tray/     WPF — tray icon and one window (4.4); SingleInstanceGuard (TODO (99))
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

**Three things only the hardware taught (stage 3)**: the laptop's display sleeps after 60 s on AC and
WGC keeps capturing a black desktop with a live cursor on it, so the streamer holds
`SetThreadExecutionState(ES_DISPLAY_REQUIRED)` while a pipeline runs — without it the feature's own
use case (walk away, rotoscope from the iPad) goes black in a minute; a window source produces frames
only while that window is not fully occluded (z-order matters; inherent to WGC, so the picker should
say so if the picture stops); and `show-border=false` works from an unpackaged exe (§8 closed).

**On the owner's laptop, 2026-09-13**: Windows 11 Pro 25H2, Intel Iris Xe (13th-gen Core), one
1920×1080 display. GStreamer **1.26.8** installed from the MSI (`msiexec … ADDLOCAL=ALL /qn`) to
`C:\Program Files\gstreamer\1.0\msvc_x86_64` — 1.28 switched to an `.exe` installer whose silent
flags are undocumented, so the MSI series is the one `install-streamer.ps1` pins. Present:
`d3d11screencapturesrc` (`capture-api`, `monitor-index`, `window-handle`, `window-capture-mode`,
`show-cursor`, `show-border`), **`qsvh264enc`** and **`mfh264enc`** (the latter is the Intel Quick Sync
MFT, D3D11-aware, `low-latency`), `openh264enc`, `x264enc`. Absent: `nvh264enc`, `amfh264enc`. .NET
SDK 8.0.425 at `C:\dotnet`.

### 4.3 Running it, and running it over SSH — and as a normal program (TODO (99))

An SSH session on Windows is a non-interactive window station: nothing started from it can see the
desktop, so neither the app nor `gst-launch-1.0` can capture from there — `EnumWindows` in that
session sees one fake 1024×768 "WinDisc" display. **And the laptop has two accounts**: SSH (and "Run
as administrator") is the admin `PC`; the person at the screen is the standard user **`kevin`**, whose
session 1 is the only one that can capture.

**The artist's own way in is a Start Menu shortcut and a desktop shortcut**, both pointing at
`Streamer.Tray.exe` — "just like any normal computer program, clicking the app launches the
program" (TODO (99)). The Scheduled Task from stage 3's build is still there, registered as `kevin`
with an Interactive logon principal, but **carries no trigger**: nothing starts it at logon or on any
schedule. It exists purely as `tools/windows/streamer.ps1 start|stop|status|log`'s remote-start
mechanism — `Start-ScheduledTask` is how a non-interactive SSH connection reaches into kevin's
already-open session 1, the same reason the task existed at all. The shortcut and the task launch the
identical exe with no arguments, so `Streamer.Tray`'s own named-mutex guard
(`SingleInstanceGuard`, `App.xaml.cs`) is what stops a double-click from starting a second instance
while the task's is already running, rather than the two mechanisms being kept apart by convention.
Log either way: `%LOCALAPPDATA%\PaintStreamer\log.txt`.

`tools/windows/install-streamer.ps1` (run once as Administrator, over SSH): .NET 8 SDK via winget,
GStreamer MSI silently with all features, the firewall rule for 47301 (§6's admission rule), the Start
Menu and desktop shortcuts, the triggerless scheduled task, and a `dotnet publish` of the tray app to
`%LOCALAPPDATA%\PaintStreamer\app`.

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

**Lock and display-off are the same shape (2026-09-13).** §3's stage 4 finding — locked, the encoder
engaged cleanly but zero VIDEO frames ever arrived, so `streaming:true` sat on a frozen picture with
no word said about it — is fixed by treating a lock exactly like a closed window: the pipeline stops
outright (there is no picture to encode from a secure desktop) and STATUS reports `streaming:false`
with `reason:"The laptop is locked"` or, for the rarer case the running-pipeline keep-awake (§4.2)
should prevent, `reason:"The laptop's display is off"`. Detected two ways *at once*, not one as a
fallback for the other: `WTSRegisterSessionNotification`/`WM_WTSSESSION_CHANGE` and
`RegisterPowerSettingNotification`/`WM_POWERBROADCAST` on the tray window's HWND
(`Streamer.Tray/MainWindow.xaml.cs`, forwarding into the Core-testable, window-free
`Streamer.Core/SessionLockMonitor.cs`), plus a 2s poll (`SessionLockPoller.cs`) for the case a
Scheduled-Task-launched process never receives the window message at all.

**MEASURED against the real laptop, locked, 2026-09-13**: the poll turned out load-bearing rather
than redundant. `WM_WTSSESSION_CHANGE` never fired in the deployed process — expected, since it only
fires on a *transition* and the process started already locked — while the poll correctly reported
`blocked — The laptop is locked` within milliseconds of startup, before `MainWindow` had even opened
(a message-only design would have reported unblocked until some later lock/unlock that, on an
already-locked laptop, may never come). The poll's first implementation was itself wrong, caught by
the same run: `OpenInputDesktop` (the commonly cited technique — fails, or names a desktop other than
"Default", when locked) reported the session *accessible* while `LogonUI.exe` was confirmed running
in the session and the session confirmed locked over SSH (`query user` showed `kevin`'s console
session "Active" — the known wrong-but-plausible reading — and `Get-Process LogonUI` found it).
Caught with a one-shot `--check-lock` CLI diagnostic (`Streamer.Tray`, same one-off-Scheduled-Task
trick `streamer.ps1 sources` already uses to reach kevin's interactive session) and replaced with
checking for `LogonUI.exe` in this process's own session instead — the exact process Winlogon runs to
render the secure desktop for a lock, a UAC prompt, or Ctrl+Alt+Del, so its presence is a direct
signal rather than an inference from a desktop handle's name.

Confirmed end-to-end with `stream-client-check.py --host 100.104.85.111 --seconds 15 -v` against the
real, locked laptop: STATUS arrived `streaming: False, reason: 'The laptop is locked'` within ~20 ms
of HELLO, zero VIDEO frames, zero violations, and the log shows no `GstProcess: launching` line for
that connection at all — the pipeline is never started for a client connecting while locked, not
started-then-stopped. Unlocking was not exercised live — the laptop was locked when this stage began
and the rule is never to unlock it — so "unlock restarts the pipeline" is pinned instead by
`StreamerSessionEnvironmentBlockTests.cs` and `SessionLockMonitorTests.cs`/`SessionLockPollerTests.cs`
(Streamer.Tests), including a regression test for a bug the first version of the unblock path had: it
could reach `StartPipelineLockedAsync` — whose first line throws if the encoder has not been probed
yet — for a client that connected before any source was ever picked, a path every other caller of that
method already guarded against and this one, until fixed, did not.

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
`DispatchQueue.main.asyncAfter` armed on arrival). The tick does two things, and the split between
them is TODO (96) and TODO (97) respectively:

1. **It writes the newest frame into every unfrozen stream element naming the endpoint — on every
   cel, displayed or not** — through `VectorCanvas.setStreamFrame(id:image:index:)`. The picture
   lives in a `StreamPicture` box the element holds by reference, so every copy of the element (an
   undo step's list, a split's neighbour, a float) shows the one newest frame and pins one decoder
   buffer between them; the canvas records the decoder index it was last told, so a tick on an
   unchanged slot writes nothing and a split's far cel is still told about a frame its shared box
   already holds. `version` moves (the memo re-walks on its next read, the host knows the picture
   is stale) and a new `committedVersion` — which `LayerContentVersion` and the posed/video
   identities read — does not, so the bake, the dirty sweep and the sandwich key are blind to a
   live frame by construction. **A cel the artist is not looking at is written all the same**; when
   they change frame onto it, or show its layer, the host's ordinary repaint draws the newest
   picture, and no further frame has to arrive — which matters because a laptop whose screen is not
   changing sends nothing that would.
2. **For the elements on a visible layer whose cel is the one at the current frame, it presents the
   frame** through a closure `CanvasView` installs (`onStreamFrame`, the shape of
   `StrokeCanvasView.guideOverlayNeedsUpdate` — never `objectWillChange`, which is a whole SwiftUI
   pass thirty times a second). The host answers with `presentStreamFrame`: the element's *window*
   — its footprint, clipped to its quad, in true z-order with the ink under and over it — is drawn
   off the main thread by the memo's own walk (`VectorCanvas.drawStreamWindow`) into one of two
   `IOSurface`s the host owns per stream element (`StreamSurfaceView`), frame-positioned over the
   base the way the scratch is positioned at a stroke's window. **Nothing canvas-sized is allocated,
   rasterized or uploaded per frame, and the render server maps two objects once.** The base under
   the surface is not redrawn for a `version` move that left `committedVersion` still while a
   surface is up (`refreshDisplayIfStale`); it catches up on the next committed change, or when the
   surfaces go — a cel switch, a blanked host, a derived (posed) base, the Move box lifting or
   landing. While the Move box holds the element the surface rides inside the float, drawn from the
   lifted ids alone as the float shows them; a Distort float has no window and keeps the picture it
   was lifted with.

   The path this replaced re-rasterized the canvas per frame and handed Core Animation a fresh
   canvas-sized `CGImage` thirty times a second; on the owner's iPad the render server reached its
   1850 MB limit and was killed four times in two days. PERFORMANCE.md §21 is the measurement.

Once a second — not per tick — the coordinator also publishes (`celContentChangedOutsideStroke`)
for the displayed cel, so the layer-panel thumbnail catches up through its 400 ms debounce. The tick
does nothing while `isPlaying` (2.9) or while the app is backgrounded.

**A canvas on the engaged sandwich at rest shows the stream at whatever the bake froze** — a blend
mode, a mask, an effect, a container pose. Stage 2 measured the alternative and kept the staleness,
in words: a per-tick in-memory composite of the current frame MEASURED **45.8 ms a tick on
CoreGraphics and 72.7 ms on Metal** (Debug, 2048², three layers, a 1920×1080 frame, the stream
layer on Multiply; `StreamSandwichBench`), an order of magnitude over the ~4 ms a 30 Hz tick could
carry. So the bar says it instead — `StreamBarState.sandwichNote`, *"Live picture pauses while a
blend mode, mask, effect or transformation layer is in the document"*, shown while
`CanvasManager.streamPictureIsHeldByTheSandwich`. A *dimmed* reference is a layer opacity, which
stays on the flat row and stays live; it is a *multiplied* one that pauses. Never silent staleness.

MEASURED on the simulator (Debug, 2048² canvas, a 1280×720 `testsrc` from the fake streamer,
2026-09-17): the tick delivers **23–29 frames/s at 0.38–0.48 ms mean, ≤1.5 ms max** on the main
actor. Every tick is an `OSSignposter` interval (`PaintSoftware` / `ScreenStream`) and once a second
the coordinator logs the ticks since the last line with their mean and worst main-actor cost —
`log stream --predicate 'subsystem == "PaintSoftware" && category == "ScreenStream"'` on a device,
`xcrun simctl spawn <udid> log stream …` on the simulator; `StreamBar` puts the same line on the
hidden `streamBar.tickSummary` marker for an XCUITest.

### 5.4 Freeze

Freeze sets `isFrozen` and stops the tick for that element; Unfreeze clears it and asks for a
keyframe. When every stream element on the connection is frozen the client sends `pause`; the first
unfreeze sends `resume` (whose keyframe §3 guarantees — no second request rides with it), and an
unfreeze on a connection that was not paused sends `keyframe`. **Freeze is not an undo step** — it is
a viewing state like the render-resolution knob, persisted with the document. Bake works while
frozen and bakes the frozen picture.

**Built (stage 2), with two corrections.** *"Writes the current frame to `lastFrameFileName` at
once"* is gone: `ProjectStore` stages a whole new package on every save and swaps it in by rename, so
a file written into the live package outside a save is in no package the next load reads — the
picture a freeze holds is `displayFrame`, which the next save encodes (§5.6). And the verb is
addressed by cel — `CanvasManager.setStreamFrozen(layerIndex:celIndex:elementID:_:)` — because a
split copies an element's id into a second cel, so after a Bake Frame the cels either side hold two
streams with one id and the artist freezes the one they are standing on; **the freeze gives that
element a `StreamPicture` of its own**, since the copies otherwise share one box and the far cel goes
on receiving frames a frozen picture must not (§5.3). The pause is reconciled by
one function (`ScreenStreamCoordinator.syncPauseState`) on freeze, on backgrounding, on foregrounding
and on every `.connected` transition, since a laptop just reconnected to knows nothing of the pause
the old connection carried; the decoder is reset on `resume` rather than on `pause`, so the resume's
keyframe is the first thing decoded and an access unit still in flight after a pause is not turned
into a keyframe *request* (which the fake streamer answers by restarting the pipeline the pause
stopped). One consequence to know: the flag lives on the element, and the element is what an undo
step snapshots — so undoing a bake made *while* frozen puts the stream back frozen even if it was
unfrozen since. Reported rather than special-cased.

### 5.5 Bake Frame (2.4)

`CanvasManager.bakeStreamFrame(layerIndex:celIndex:atFrame:) -> StreamBakeOutcome`: in one
`withInterpolationUndo`, `splitCel` at `frame` when `frame > cel.start` and at `frame + 1` when
`frame + 1 < cel.end`, then in the cel that now spans exactly `frame`, replace `.stream` with a
`VectorImageElement(image:)` carrying the same placement fields, `reidentified()`, image written to
the package as the image path already does. Refusals: `.noFrameYet` (*"No picture from the computer
yet"*), `.notOnStreamCel`. The playhead stays. A bake on a one-frame cel is the swap alone.

**Built (stage 2), `CanvasManager+StreamBake.swift`.** Which ids move: the image is minted fresh and
every other element on the baked cel is `reidentified()` as the video bake does; **the cels either
side keep their ids verbatim, the stream's included** — they are `splitCel`'s own copies, which is
what Split Drawing does to every cel it cuts, and the two copies share one `StreamPicture` (§5.3),
so nothing keys on a stream id across cels. The picture is `displayFrame` — live, frozen, or
the one the last save wrote and the load put back — so a bake with the laptop off bakes the last
picture it sent. **The placed image is a copy of the frame's pixels** (`streamSnapshot`), never the
decoder's own `CGImage`, which wraps a VideoToolbox pool buffer and pinned one per bake for the
life of the document (PERFORMANCE.md §21); a decoded frame whose pixel size disagrees with the
STATUS-reported `naturalSize` is resampled to `naturalSize` on the way, because the stream drew its
frame *into* that rect and a placed image's rect is its own pixel size. A pose channel on the cel is baked into the geometry
and dropped, the video bake's rule. `StreamBakeLogicTests` pins [1] [2] [3–4], [1] [2–4], [1–3]
[4], the one-frame swap, four cels after a second bake, undo to one ticking stream cel, and the baked
frame green through the real compositor while both neighbours follow the stream to red.

### 5.6 Surviving the computer being off (2.8)

`lastFrameFileName` is written **on save, and only on save** (JPEG, quality 0.9, in the project
package beside the placed images — never per frame): `ProjectStore` stages a whole package on every
save and swaps it in, so "on freeze, on bake, on disconnect" — what this section said until stage 2 —
would have written files into a package the next save replaces. Every one of those events leaves the
picture in `displayFrame`, and the save encodes whatever it holds: the live frame, the frozen one, or
the last one received before the laptop went away. The name is minted per cel and per element
(`<celID>_stream_<elementID>.jpg`) rather than reused, because a split copies an element's id into a
second cel and two cels writing one name would keep whichever wrote last. On load `displayFrame` is
that file (`UIImage(contentsOfFile:)` — the decode waits for the first draw), so the layer opens
looking as it last did; the coordinator starts the client on the first canvas pass, which reconnects
in the background, and nothing waits on it. A missing file is a log line, not damage. The bar says
**Live** / **Frozen** / **Reconnecting…** / **Not streaming — <reason from STATUS>** — and
**Connecting…** for the first attempt, before any answer, which a document just opened is in for up
to five seconds. Nothing modal, ever. `StreamPersistenceLogicTests` pins the JPEG in `images/`, the
reloaded cel drawing it, a bake of it with the laptop off, and an open with the laptop unreachable
that blocks nothing. **§4.5's lock/display-off detection needed no change here**: `"The laptop is
locked"` and `"The laptop's display is off"` are just two more STATUS `reason` strings, and
`StreamBarState.notStreaming(reason:)` (`Engine/ScreenStream/ScreenStreamCoordinator.swift:566,574`)
already renders any `reason` verbatim as `"Not streaming — \(reason)"` — confirmed by reading it and
`Views/StreamBar.swift` rather than assumed, 2026-09-13.

### 5.7 The bar and the Actions entry (2.2, 2.3)

**Actions → Stream Screen** (a row after Insert Video, `addTextRow`'s shape): a sheet with a
**Nearby** section (TODO (98)) above the address field, then the laptop's address (MagicDNS name or
Tailscale IP; last used prefilled; port 47301 shown, editable) and Connect. On HELLO it makes a new
vector layer with one stream element in one cel **from the current frame to the end of the
timeline** (§6), fitted to the canvas the way `insertVideo` fits (the laptop's aspect, letterboxed),
then lifts it into the Move box as `insertImage` does. If the connection fails the sheet says so in
words and stays open. A second Stream Screen makes a second layer sharing the client.

**Nearby (TODO (98))**: `StreamDiscoveryBrowser` (`Engine/ScreenStream/StreamDiscovery.swift`)
browses `_paintstream._tcp` with `NWBrowser` while the sheet is on screen, so a laptop on the same
Wi-Fi as the iPad appears as a row the artist taps instead of typing an address; the typed-address
path is unchanged and is still how a Tailscale-only laptop (not on this Wi-Fi) gets connected to. A
tapped row fills `host`/`port` from the discovered laptop's own name (`"<name>.local"`, resolved the
same way as a typed MagicDNS name — no new connect path) and calls the same `connect()` the button
does. Empty off-network is the expected state (`streamConnect.nearbyEmpty`), not a fallback.
`StreamDiscovery.nearbyStreamers(from:)` is the pure, testable half (`StreamDiscoveryLogicTests`);
`NWBrowser.Result` itself has no public initializer, which is why the browser hands endpoints to that
function rather than results. **Not driven end to end**: the Mac and the laptop were not on the
iPad's Wi-Fi network while this was built, so this is proved by that logic test plus the Windows
side's `Streamer.Core/Discovery/MdnsAdvertiser.cs` and its `MdnsAdvertiserTests` (§4.1), not by
watching a real laptop appear in the list.

**`StreamBar`** (`Views/StreamBar.swift`, `bottomDockCard`): shows because the active layer's cel at
the current frame holds a stream element, unless a piece floats (the Move bar wins). Contents: source
label and state (5.6), **Freeze** ⇄ **Unfreeze**, **Bake Frame**, and the address for reconnecting to a
different laptop. It is not an `ActivePanel` case, so `canvasInteractionBegan`'s `activePanel = .none`
cannot close it — a two-finger pan keeps it up.

**Built (stage 2).** `DrawingView.bottomDock` reads `CanvasManager.activeStreamCel`; the bar observes
`ScreenStreamCoordinator` (an `ObservableObject` now — connection states and STATUSes published,
never frames) and shows `barState(for:)`'s word, with the sandwich note (§5.3) under it while the
canvas is on the composite. The address row opens `StreamConnectSheet` with a `StreamRetarget`, and a
successful connect there is `CanvasManager.retargetStream` — host, port, label and size rewritten on
the element in one undo step, placement and picture kept — rather than a second layer. Identifiers
`streamBar.sourceLabel` / `stateLabel` (value: `live` · `frozen` · `connecting` · `reconnecting` ·
`notStreaming`) / `freezeButton` / `bakeFrameButton` / `addressButton` / `sandwichNote`.
`StreamBarStateLogicTests` pins the cold-start reach, the word's precedence and the pause protocol.

### 5.8 Files (2.10)

Laptop → iPad: on FILE_END, if a document is open, `kind == "image"` → `insertImage(UIImage)`, `video`
→ `insertVideo(at:consumingSource:true)` after staging the bytes in Application Support as
`VideoImportStore` does; other kinds are refused with a reason. No document open → `ok:false,
reason:"No document is open on the iPad"`. The insert is exactly the picker's, Move-box lift included.

iPad → laptop: `ExportSheet` gains **Send to Computer** beside the existing destination, enabled only
while a client is connected; it sends the `.finished(url)` file and reports the laptop's FILE_RESULT
in the sheet.

**iPad half built, stage 4.** `ScreenStreamClient` owns both directions: FILE_BEGIN opens a temp file
in a new `StreamTransferStore` directory (Application Support, beside `VideoImportStore` — never
memory, so a hundred-plus-MB video never touches RAM in transit), FILE_CHUNK appends, and FILE_END
checks the declared size against what actually arrived before handing the whole file to
`ScreenStreamCoordinator.routeReceivedFile` on the main queue — `insertImage`/`insertVideo`, kind for
kind, exactly the picker's own verbs including the Move-box lift, with the temp file deleted whichever
way it went. One inbound transfer at a time; a second FILE_BEGIN is refused
`"A transfer is already in progress"` without disturbing the one under way. `sendFile` is the reverse:
BEGIN/CHUNK(≤256 KiB)/END on the client's own queue, resolved by the laptop's FILE_RESULT;
`ExportSheet`'s new button (`export.sendToComputer`) reuses `ScreenStreamCoordinator.connectionStates`
— the same `@Published` property `StreamBar` already watches — rather than adding a second notion of
"connected," and reports the answer as a sentence (`export.sendResult`): the laptop's own HELLO name
(`ScreenStreamClient.remoteName`) on success, its `reason` otherwise. `handle(_:)` is exposed rather
than `private`, the same seam stage 1 gave `H264StreamDecoder.feed`, so `StreamFileTransferLogicTests`
and `StreamFileSendLogicTests` drive both directions with no socket at all. Pinned: an image joining
the active vector layer, a video always in its own new layer (both with the resulting pixels checked,
not only the model), `other` and an unreadable file each refused with their sentence, a second BEGIN
mid-transfer refused, a size mismatch at FILE_END refused with nothing inserted, no document open
answering its sentence, the 700 KiB → three-chunk arithmetic, and the pause cycle below.

**§6's new bullet — corrected, not merely implemented.** Stage 2's `b07984d` had already read "no
element names this endpoint" as "leave the pause alone," to stop a pause/resume pair firing four
milliseconds apart on every Stream Screen connect (between the sheet's own `connect()` and the
element it is about to insert, nothing names the endpoint yet). Stage 4 needed the *opposite* answer
for the ambient, document-level connection this bullet asks for — a connection that can sit with no
element naming it for the rest of a session must read as **paused**, not "left alone," or a laptop the
artist is not looking at keeps encoding for nobody. The two windows are distinguished by
`pendingConnects`: populated only for the span `connect(to:)` opens and its own STATUS (or failure)
closes, and never true of the ambient connection, which nothing ever calls `connect(to:)` for. So the
stage-2 fix stays exactly where it was needed and stage 4's rule applies everywhere else — pinned by
`StreamBarStateLogicTests.testAConnectionStillBeingConnectedIsNotPausedMidConnect` (the old case,
narrowed) and `testAConnectionNoElementNamesIsNowPaused` (pause with nothing naming it, resume the
moment an element does, pause again the moment it stops).

## 6. Defaults taken without a ruling — each reversible, each recorded where the behaviour lives

- The stream cel runs **from the current frame to the end of the timeline** (a video is clipped to
  its length; a stream has none).
- One connection per `host:port` per document, shared by all its stream layers; one **source** per
  laptop at a time (the laptop's picker is global). **And a document keeps a connection to the
  last-used laptop open even with no stream layer in it** (stage 4), held `pause`d unless a stream
  element needs pictures — so the drop box lands files and Send to Computer is enabled whenever a
  document is open, not only after Stream Screen. The laptop encodes nothing for a paused client, and
  a laptop that is off costs the iPad one connection attempt every 5 s.
- Port **47301**; the firewall rule admits Tailscale addresses **or the laptop's own local
  subnets** (TODO (98), widened from Tailscale-only). `AdmissionPolicy.cs` is the one place the
  rule is actually spelled out and the only thing that checks it precisely (live NIC data, per
  connection); the firewall rule is a coarser, static superset of the same ranges, because a
  static rule cannot know which subnet the laptop is on at any given moment. `MdnsAdvertiser.cs`
  advertises `_paintstream._tcp` on the LAN so the iPad's connect sheet can offer the laptop under
  "Nearby" (§5.7) instead of the artist typing an address — no new port or protocol, purely how
  the address gets into the sheet.
- **USB, investigated and declined (TODO (98)).** The iPad is the client and the laptop is the
  server (§3: "the laptop listening ... the iPad connecting"), and USB reaches an iPad only through
  `usbmuxd` — a multiplexer that lets a *host* dial a port the *device* listens on, the opposite
  direction from how this protocol is wired. Building it would mean the iPad opening a local TCP
  listener (straightforward) and the laptop driving `usbmuxd`'s protocol to reach it (not
  straightforward on Windows: no first-party client exists, and the practical routes are bundling
  Apple Mobile Device Support/iTunes or vendoring `libimobiledevice`'s USB multiplexing, an
  undocumented protocol, as a new dependency of a laptop that is otherwise dependency-light by
  design — §4.3). That cost buys a cable-only fallback for a laptop already reachable over Tailscale
  or, now, the LAN; left undone, and the ask counted as answered by that ruling rather than by code.
- Freeze is **not** an undo step; Bake Frame is **one**.
- Snapshots are stored at the laptop's native pixel size, not the canvas's.
- The last frame is saved as JPEG q0.9, on save alone (§5.6); the bake snapshot as the image
  path's existing format.
- A bake's neighbours keep the stream element's id; only the baked cel is re-identified (§5.5).
- The engaged sandwich says the live picture is paused rather than paying a per-tick composite (§5.3).
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
| **1** ✓ | ~~iPad: `VectorStreamElement`, Codable round trip, `ScreenStreamClient` + `H264StreamDecoder` (logic tests decode the fixture through the real framing, no network), the coordinator tick, `.stream` draw, Actions → Stream Screen sheet, Move box~~ **Built.** `Engine/ScreenStream/`, `Views/StreamConnectSheet.swift`, `CanvasManager.insertStream(host:port:status:)`; five suites (`StreamElementLogicTests`, `StreamFramingLogicTests`, `H264StreamDecoderLogicTests`, `StreamInsertLogicTests`, `StreamScreenUITests`). §5.3 carries what the build corrected | driven against `fake-streamer.py --pattern`: the pattern moves in the Move box and on the committed layer (two screenshots 2 s apart differ in 15–18% of the rect's sampled pixels); the cold-start XCUITest reaches the sheet |
| **2** ✓ | ~~iPad: `StreamBar`, Freeze, Bake Frame via `splitCel` (logic tests pin [1] [2] [3–4] and the one-frame case, undo restores the stream), `lastFrameFileName` and reload, playback gating, reconnect (kill the fake streamer, restart it)~~ **Built.** `Views/StreamBar.swift`, `CanvasManager+StreamBake.swift`, the coordinator's pause/resume and published state, the save's JPEG; four suites (`StreamBakeLogicTests`, `StreamBarStateLogicTests`, `StreamPersistenceLogicTests`, `StreamSandwichBench`). §5.3–5.7 carry what the build corrected | driven against `fake-streamer.py --pattern` on the simulator with a throwaway XCUITest: the pattern moves at rest (13% of the rect's pixels differ 2 s apart) and holds during playback (0.0%), resumes on stop; the streamer killed → **Reconnecting…** in 0.9 s with the last picture kept, restarted → **Live** in 1.0 s; Freeze holds (0.0%) and the server log shows `CONTROL pause`, Unfreeze shows `resume`; Bake Frame on a 12-frame cel gives three cels with the middle one still (0.0%) and no bar on it; a pinch leaves the bar up; six strokes on a layer above while live. The tick delivered ~28.5 frames/s at **0.2–0.5 ms mean, ≤2.5 ms typical max** on the main actor (simulator, Debug). **The device figure was not taken**: the iPad was reachable and the Release build (stage 2) installed, but XCUITest cannot start on a locked device and nothing on the Mac unlocks it — the outlet is in place (§5.3) for the run that can |
| **3** ✓ | Windows: `Streamer.Core`, `Streamer.Tray` (WPF + WinForms tray icon), 44 xunit tests, `install-streamer.ps1`, `streamer.ps1`, `streamer-remote.sh`; installed on the laptop and running as the `PaintStreamer` task in kevin's session | proved from this Mac with `stream-client-check.py`: 602 frames / 11 keyframes / 0 violations with motion, a decoded frame is the laptop's real desktop, a window source shows only that window, a killed process reconnects with a keyframe in ~1.2 s. Six bugs found only on hardware are in `f17df26`'s message. The iPad-to-Blender drive is stage 5's |
| **4** | ~~Files both ways: drop box → insert, Ctrl+V bitmap, refusal reasons; Send to Computer~~ **iPad half built** — `ScreenStreamClient`'s FILE_BEGIN/CHUNK/END both ways, `ScreenStreamCoordinator.routeReceivedFile`, `ExportSheet`'s Send to Computer, §6's document-level connection and its pause-rule correction; two suites (`StreamFileTransferLogicTests`, `StreamFileSendLogicTests`). §5.8 carries what the build corrected. Windows half (the drop box, Ctrl+V) is the sibling worktree's | driven against `fake-streamer.py --pattern --send <png> --send <mp4>` with a throwaway XCUITest, two passes (the first pass's own `rm *.png` swept the queued PNG out from under the streamer before it read it — the second pass's own bug, not the product's): connecting via Stream Screen with **no prior stream layer** gets an mp4 auto-sent moments after HELLO inserted as its own new video layer, and a PNG sent the same way joins the **active vector layer** (the stream layer itself, since it was still active) rather than making a new one — `insertImage`'s ordinary rule, visible on screen as the dropped picture composited into the live layer. Undoing the stream insert then reads `CONTROL pause` in the streamer's own log — confirming live, not just in `StreamBarStateLogicTests`, that §6's ambient connection pauses once nothing names it. Export → Send to Computer round-tripped `Untitled-frame-0.png` into `--save-dir` byte-for-byte (78139 bytes both ends) with the sheet reading "Saved on Julias-MacBook-Pro", sent successfully **while the connection was paused** — confirming FILE_* is not gated on streaming. Killing the fake streamer afterward raised no alert and left the toolbar usable |
| **5** | Latency and quality pass on the real link: end-to-end latency MEASURED (a clock on the laptop screen photographed beside the iPad), bitrate/GOP tuned, the dirty-screen idle cost | numbers in PERFORMANCE.md |

Stages 1–2 (iPad, simulator) and 3 (Windows, SSH, no simulator) run in parallel lanes.

## 8. Unconfirmed — verify at the stage that touches it

- ~~Which encoder element the laptop actually has~~ — `EncoderProbe` picks `qsvh264enc` there.
- The exact main-thread cost of a 1080p tick and of `VTCreateCGImageFromCVPixelBuffer` on the iPad
  9th gen — **still open**: the iPad was locked when the run was attempted (2026-09-13), and
  XCUITest cannot start on a locked device. The number is one unlocked run away: connect to the fake
  streamer on this Mac's Tailscale address (`100.70.148.78`, `fake-streamer.py --pattern`, the
  firewall is off) and read either `log stream --predicate 'subsystem == "PaintSoftware" && category
  == "ScreenStream"'` or the bar's `streamBar.tickSummary` marker. Simulator figures are in §5.3.
  What that run has to price now is the off-main window draw (`VectorCanvas.drawStreamWindow`) —
  the frame resampled into its rect plus whatever ink crosses it — and the render server's
  memory, which the simulator cannot stand in for (PERFORMANCE.md §21): `backboardd` must be flat
  over minutes of streaming, and a device has no `footprint`, so read it off the next jetsam report
  or its absence.
- ~~Whether `tcpclientsink` on localhost or `fdsink` is the cleaner hand-off~~ — loopback `tcpclientsink` is clean; `d3d11convert` alone negotiates with `qsvh264enc`, no `d3d11download`.
- Tailscale MTU is 1280; irrelevant to TCP framing, noted in case UDP is ever tried.
