# paintstream/1 reference tools (STREAM.md §7 stage 0)

Two Python 3 stdlib-only scripts standing in for the Windows laptop (not yet built)
and for a client, so the iPad side can be built and driven against a real
`paintstream/1` peer. Single files, executable, with `--help`.

- **`fake-streamer.py`** — the server (laptop role): HELLO/STATUS/VIDEO/CONTROL,
  PING/PONG, files both ways, one client at a time.
- **`stream-client-check.py`** — a reference client: prints STATUS, counts VIDEO
  frames/keyframes, checks SPS/PPS-before-IDR and pts monotonicity, can drive
  `--send` and `--pause-after`. Exits 0 only if every invariant held.

## Three video sources

| flag | what | needs |
|---|---|---|
| `--screen` (default) | this Mac's screen, ffmpeg avfoundation | Screen Recording permission — **not the CI path** |
| `--pattern` | ffmpeg lavfi `testsrc` | nothing — headless, deterministic, **use this for testing** |
| `--file <x.h264>` | loops an Annex-B file at 30 fps | the file to exist |

## Commands

- Server, pattern mode: `tools/stream/fake-streamer.py --pattern --port 47301 -v`
- Check end to end: `tools/stream/stream-client-check.py --port 47301 --seconds 5` (`--help` for `--send`/`--pause-after`)
- Regenerate the iPad fixture:
  ```
  ffmpeg -f lavfi -i testsrc=size=640x360:rate=30 -t 2 -c:v h264_videotoolbox \
    -profile:v main -g 30 -bf 0 -b:v 400k -bsf:v h264_mp4toannexb -f h264 \
    PaintSoftwareUITests/Fixtures/stream-testsrc-640x360.h264
  ```

## Screen Recording permission

`--screen` needs the permission granted to the *process running python3*, not to
Terminal.app in general — a sandboxed/scripted shell may see zero avfoundation
video-capture devices (`ffmpeg -f avfoundation -list_devices true -i ""`) even when
an interactive Terminal would see one. `fake-streamer.py` reports a failed capture
honestly over the wire (`STATUS streaming:false`, a `reason`) rather than crashing —
the fix is granting the permission, not the script. `--pattern` needs no permission
and is the CI / automated-test path.
