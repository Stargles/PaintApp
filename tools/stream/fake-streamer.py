#!/usr/bin/env python3
"""fake-streamer.py — a reference `paintstream/1` server (STREAM.md §3, §7 stage 0).

Stands in for the Windows laptop (streamer/Streamer.Core, not yet built) so the iPad
client can be built and driven before it exists. TCP server on port 47301 (default),
one client at a time. Speaks the wire protocol exactly as STREAM.md §3 describes it:
framing, HELLO/STATUS/VIDEO/CONTROL, file transfer both ways, and PING/PONG.

Video sources (pick one, `--screen` is the default per spec):
  --screen         this Mac's screen via ffmpeg avfoundation (needs Screen Recording
                   permission for the terminal/app running this script)
  --pattern        ffmpeg lavfi testsrc — works headless, no permissions, the CI path
  --file <x.h264>  replay an Annex-B H.264 file in a loop at 30 fps

Python 3 stdlib only (asyncio, struct, json, subprocess, argparse, ...). No third-party
packages. Requires the `ffmpeg` binary (default /opt/homebrew/bin/ffmpeg) for --screen
and --pattern; --file needs no external process to stream, only to have been produced.

See tools/stream/README.md for exact commands.
"""
import argparse
import asyncio
import json
import os
import re
import signal
import socket
import struct
import sys
import time
from pathlib import Path

# --------------------------------------------------------------------------------------
# Protocol constants (STREAM.md §3)
# --------------------------------------------------------------------------------------

PROTO_VERSION = 1
SERVER_APP_NAME = "PaintStreamer"
SERVER_APP_VERSION = "fake-0.1"

T_HELLO = 0x01
T_STATUS = 0x02
T_VIDEO = 0x03
T_CONTROL = 0x04
T_FILE_BEGIN = 0x10
T_FILE_CHUNK = 0x11
T_FILE_END = 0x12
T_FILE_RESULT = 0x13
T_PING = 0x20
T_PONG = 0x21

FILE_CHUNK_MAX = 256 * 1024  # 256 KiB, per §3

DEFAULT_PORT = 47301
DEFAULT_BIND = "0.0.0.0"
DEFAULT_SAVE_DIR = os.path.expanduser("~/PaintAppInbox")

FFMPEG_BIN = "/opt/homebrew/bin/ffmpeg"

PING_SILENCE_SECONDS = 2.0
PING_MISSED_LIMIT = 3

VERBOSE = False
_active_procs = set()  # best-effort cleanup of orphaned ffmpeg children on Ctrl-C
SERVER_START = time.monotonic()  # rebound in run_server(); this default keeps pts_us sane
                                  # even if something reads it before the server starts


# --------------------------------------------------------------------------------------
# Logging — one line per event to stderr with a timestamp (spec's log requirement)
# --------------------------------------------------------------------------------------

def log(msg, *, verbose_only=False):
    if verbose_only and not VERBOSE:
        return
    ts = time.strftime("%H:%M:%S", time.localtime()) + f".{int(time.time() * 1000) % 1000:03d}"
    print(f"[{ts}] {msg}", file=sys.stderr, flush=True)


# --------------------------------------------------------------------------------------
# Framing — u8 type, u32 big-endian length, payload (§3)
# --------------------------------------------------------------------------------------

async def read_frame(reader):
    header = await reader.readexactly(5)
    mtype = header[0]
    (length,) = struct.unpack(">I", header[1:5])
    payload = await reader.readexactly(length) if length else b""
    return mtype, payload


def encode_frame(mtype, payload=b""):
    return struct.pack(">BI", mtype, len(payload)) + payload


async def send_frame(writer, mtype, payload=b""):
    writer.write(encode_frame(mtype, payload))
    await writer.drain()


def jpayload(obj):
    return json.dumps(obj).encode("utf-8")


# --------------------------------------------------------------------------------------
# Access-unit splitting (§3's rule) — Annex-B NAL scanning, stateful across feed() calls
# so it works both on a live ffmpeg stdout stream and on a whole file read at once.
# --------------------------------------------------------------------------------------

_START_CODE_RE = re.compile(rb"\x00\x00\x01")

NAL_SPS = 7
NAL_PPS = 8
NAL_SEI = 6
NAL_AUD = 9
NAL_VCL = (1, 5)  # non-IDR slice, IDR slice
NAL_IDR = 5


class AUSplitter:
    """Groups Annex-B NAL units into access units per STREAM.md §3.

    Rule (the "simpler and sufficient" version the spec gives): SPS/PPS/SEI/AUD NALs
    belong to the FOLLOWING access unit; each VCL NAL (1 or 5) ends the access unit it
    is in. Every AU containing an IDR (type 5) is emitted with the last-seen SPS and
    PPS prepended, if the encoder did not already put them there.
    """

    def __init__(self):
        self.buf = b""
        self.pending = []  # list of (nal_type, nal_bytes_with_start_code)
        self.last_sps = None
        self.last_pps = None

    @staticmethod
    def _find_start_codes(buf):
        positions = []
        for m in _START_CODE_RE.finditer(buf):
            idx = m.start()
            if idx > 0 and buf[idx - 1] == 0:
                idx -= 1  # this was really a 4-byte 00 00 00 01 start code
            positions.append((idx, m.end()))
        return positions

    def feed(self, data=b"", end=False):
        """Feed more bytes (or, with end=True, signal EOF) and return newly closed AUs."""
        self.buf += data
        positions = self._find_start_codes(self.buf)
        if end:
            positions = positions + [(len(self.buf), len(self.buf))]
        aus = []
        if len(positions) < 2:
            if end:
                self.buf = b""
            return aus
        limit = len(positions) - 1
        for i in range(limit):
            start_idx, payload_start = positions[i]
            next_start_idx, _ = positions[i + 1]
            payload = self.buf[payload_start:next_start_idx]
            if not payload:
                continue
            nal_bytes = self.buf[start_idx:next_start_idx]
            nal_type = payload[0] & 0x1F
            self._handle_nal(nal_type, nal_bytes, aus)
        if end:
            self.buf = b""
        else:
            self.buf = self.buf[positions[limit][0]:]
        return aus

    def _handle_nal(self, nal_type, nal_bytes, aus_out):
        if nal_type == NAL_SPS:
            self.last_sps = nal_bytes
        elif nal_type == NAL_PPS:
            self.last_pps = nal_bytes
        self.pending.append((nal_type, nal_bytes))
        if nal_type in NAL_VCL:
            types = [t for t, _ in self.pending]
            is_idr = NAL_IDR in types
            if is_idr and not (NAL_SPS in types and NAL_PPS in types):
                prefix = (self.last_sps or b"") + (self.last_pps or b"")
                au_bytes = prefix + b"".join(b for _, b in self.pending)
            else:
                au_bytes = b"".join(b for _, b in self.pending)
            aus_out.append({"bytes": au_bytes, "keyframe": is_idr, "types": types})
            self.pending = []


def classify_kind(path):
    ext = Path(path).suffix.lower().lstrip(".")
    if ext in ("jpg", "jpeg", "png", "heic", "gif"):
        return "image"
    if ext in ("mp4", "mov", "m4v"):
        return "video"
    return "other"


def probe_dimensions(path):
    """Best-effort ffprobe of a file's video dimensions, for STATUS metadata only.
    Never fatal — falls back to (0, 0) if ffprobe is missing or the file is odd."""
    ffprobe = str(Path(FFMPEG_BIN).with_name("ffprobe"))
    try:
        import subprocess
        out = subprocess.run(
            [ffprobe, "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height", "-of", "json", path],
            capture_output=True, timeout=5, text=True,
        )
        data = json.loads(out.stdout or "{}")
        stream = (data.get("streams") or [{}])[0]
        return int(stream.get("width", 0)), int(stream.get("height", 0))
    except Exception as e:
        log(f"ffprobe on {path} failed, reporting 0x0 in STATUS: {e}", verbose_only=True)
        return 0, 0


# --------------------------------------------------------------------------------------
# Video sources
# --------------------------------------------------------------------------------------

def build_ffmpeg_cmd(mode, avfoundation_device):
    common_encode = [
        "-c:v", "h264_videotoolbox",
        "-realtime", "1",
        "-g", "60",
        "-bf", "0",
        "-b:v", "6M",
        "-profile:v", "main",
        "-allow_sw", "1",
        "-bsf:v", "h264_mp4toannexb",
        "-f", "h264", "pipe:1",
    ]
    loglevel = "info" if VERBOSE else "error"
    if mode == "screen":
        head = [FFMPEG_BIN, "-hide_banner", "-loglevel", loglevel,
                "-f", "avfoundation", "-capture_cursor", "1", "-framerate", "30",
                "-i", avfoundation_device]
    elif mode == "pattern":
        # -re: lavfi's testsrc otherwise generates and encodes as fast as the CPU
        # allows rather than pacing to the wall clock (avfoundation's screen capture
        # paces itself, being a real device, so -re is neither needed nor used there)
        head = [FFMPEG_BIN, "-hide_banner", "-loglevel", loglevel,
                "-f", "lavfi", "-re", "-i", "testsrc=size=1280x720:rate=30"]
    else:
        raise ValueError(mode)
    return head + common_encode


class VideoEngine:
    """Owns the current source (ffmpeg subprocess, or a looping file) for one client
    session. pause=stop(), resume=start() (fresh process/loop => fresh keyframe),
    keyframe=restart() (kill+relaunch is the cheapest way to force an IDR)."""

    def __init__(self, mode, args, queue, on_unexpected_stop):
        self.mode = mode
        self.args = args
        self.queue = queue
        self.on_unexpected_stop = on_unexpected_stop
        self.proc = None
        self.reader_task = None
        self.stderr_task = None
        self.file_task = None
        self.splitter = AUSplitter()
        self.streaming = False
        self.file_aus = None  # precomputed for --file mode

        if mode == "file":
            width, height = probe_dimensions(args.file)
            self.width, self.height = width, height
            self.source_desc = {"kind": "window", "name": Path(args.file).name, "id": str(args.file)}
            data = Path(args.file).read_bytes()
            splitter = AUSplitter()
            aus = splitter.feed(data) + splitter.feed(end=True)
            self.file_aus = aus
            log(f"loaded {args.file}: {len(aus)} access units, "
                f"{sum(1 for a in aus if a['keyframe'])} keyframes")
        elif mode == "pattern":
            self.width, self.height = 1280, 720
            self.source_desc = {"kind": "monitor", "name": "Test Pattern", "id": "pattern"}
        elif mode == "screen":
            w, h = (int(x) for x in args.screen_size.split("x"))
            self.width, self.height = w, h
            self.source_desc = {"kind": "monitor", "name": "Screen 0", "id": "0"}
        else:
            raise ValueError(mode)

    async def start(self):
        if self.mode in ("screen", "pattern"):
            cmd = build_ffmpeg_cmd(self.mode, self.args.avfoundation_device)
            log(f"starting: {' '.join(cmd)}", verbose_only=True)
            self.proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            _active_procs.add(self.proc)
            self.reader_task = asyncio.create_task(self._read_ffmpeg())
            self.stderr_task = asyncio.create_task(self._drain_stderr())
        else:
            self.file_task = asyncio.create_task(self._loop_file())
        self.streaming = True

    async def stop(self):
        self.streaming = False
        # Cancel the tasks that feed the queue FIRST, before doing anything that
        # awaits (like proc.wait()) — an await yields control to the event loop, and
        # the reader/sender tasks would keep running and pushing/sending more AUs
        # during that window. Found by stream-client-check.py's pause/resume check:
        # with terminate()-then-wait() done first, up to 11 buffered frames trickled
        # out after STATUS had already said streaming:false, because the reader task
        # kept draining ffmpeg's stdout for the full ~2s termination grace period.
        for task_name in ("reader_task", "stderr_task", "file_task"):
            t = getattr(self, task_name)
            if t is not None:
                t.cancel()
                setattr(self, task_name, None)
        if self.proc is not None:
            proc, self.proc = self.proc, None
            _active_procs.discard(proc)
            try:
                proc.terminate()
                await asyncio.wait_for(proc.wait(), timeout=2.0)
            except Exception:
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
        self.splitter = AUSplitter()
        # Anything already queued but not yet on the wire predates this stop — drop it,
        # so a subsequent restart's first frame really is the fresh keyframe. The one
        # trailing AU this cannot catch is whatever the sender loop had already popped
        # and was mid-write on the socket at the instant stop() ran — those bytes are
        # already committed to the wire and cannot be recalled.
        while True:
            try:
                self.queue.get_nowait()
            except asyncio.QueueEmpty:
                break

    async def restart(self):
        await self.stop()
        await self.start()

    async def _emit(self, au):
        pts_us = int((time.monotonic() - SERVER_START) * 1_000_000)
        await self.queue.put({"bytes": au["bytes"], "keyframe": au["keyframe"], "pts_us": pts_us})

    async def _read_ffmpeg(self):
        try:
            while True:
                chunk = await self.proc.stdout.read(65536)
                if not chunk:
                    break
                for au in self.splitter.feed(chunk):
                    await self._emit(au)
            if self.streaming:
                log("ffmpeg exited unexpectedly")
                self.streaming = False
                self.on_unexpected_stop("The capture process exited unexpectedly")
        except asyncio.CancelledError:
            raise

    async def _drain_stderr(self):
        try:
            while True:
                line = await self.proc.stderr.readline()
                if not line:
                    break
                log(f"[ffmpeg] {line.decode(errors='replace').rstrip()}", verbose_only=True)
        except asyncio.CancelledError:
            raise

    async def _loop_file(self):
        try:
            interval = 1.0 / 30.0
            while True:
                for au in self.file_aus:
                    await self._emit(au)
                    await asyncio.sleep(interval)
        except asyncio.CancelledError:
            raise


# --------------------------------------------------------------------------------------
# Per-connection session
# --------------------------------------------------------------------------------------

class ClientSession:
    def __init__(self, reader, writer, args, hostname):
        self.reader = reader
        self.writer = writer
        self.args = args
        self.hostname = hostname
        self.peer = writer.get_extra_info("peername")
        self.engine = None
        self.last_rx = time.monotonic()
        self.incoming = None  # active inbound file transfer state
        self.next_out_id = 1
        self.pending_out_results = {}
        self.rate_aus = 0
        self.rate_bytes = 0
        self.rate_keyframes = 0

    async def send_status(self, reason=None):
        d = {
            "source": self.engine.source_desc if self.engine else {"kind": "none", "name": "", "id": ""},
            "width": self.engine.width if self.engine else 0,
            "height": self.engine.height if self.engine else 0,
            "fps": 30,
            "codec": "h264",
            "streaming": bool(self.engine and self.engine.streaming),
        }
        if reason and not d["streaming"]:
            d["reason"] = reason
        await send_frame(self.writer, T_STATUS, jpayload(d))
        log(f"STATUS {d}")

    async def run(self):
        mtype, payload = await asyncio.wait_for(read_frame(self.reader), timeout=10.0)
        if mtype != T_HELLO:
            log(f"expected HELLO first from {self.peer}, got type 0x{mtype:02x}; closing")
            return
        hello = json.loads(payload)
        log(f"HELLO from {self.peer}: {hello}")
        if hello.get("proto") != PROTO_VERSION:
            log(f"proto mismatch ({hello.get('proto')!r} != {PROTO_VERSION}); "
                f"sending nothing further and closing")
            return

        await send_frame(self.writer, T_HELLO, jpayload({
            "proto": PROTO_VERSION, "app": SERVER_APP_NAME,
            "version": SERVER_APP_VERSION, "name": self.hostname,
        }))
        log("sent HELLO reply")

        queue = asyncio.Queue()
        self.engine = VideoEngine(self.args.mode, self.args, queue, self._on_unexpected_stop)
        await self.engine.start()
        await self.send_status()
        log(f"video started ({self.args.mode})")

        # Only these four gate the session's lifetime. --send's file-push task must NOT
        # be in this set: it was, and the whole session (video included) tore itself
        # down the instant the queued files finished sending, because FIRST_COMPLETED
        # fired on it like any other. It now runs alongside as a background task that
        # gets cancelled when the session ends for some other reason, but does not
        # itself end the session.
        core_tasks = [
            asyncio.create_task(self._reader_loop()),
            asyncio.create_task(self._sender_loop(queue)),
            asyncio.create_task(self._watchdog_loop()),
            asyncio.create_task(self._rate_log_loop()),
        ]
        background_tasks = []
        if self.args.send:
            background_tasks.append(asyncio.create_task(self._send_queued_files()))

        done, pending = await asyncio.wait(core_tasks, return_when=asyncio.FIRST_COMPLETED)
        for t in pending:
            t.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        for t in background_tasks:
            if not t.done():
                t.cancel()
        await asyncio.gather(*background_tasks, return_exceptions=True)
        for t in list(done) + background_tasks:
            if not t.done() or t.cancelled():
                continue  # Task.exception() raises CancelledError for a cancelled task
            exc = t.exception()
            if exc is None:
                continue
            if isinstance(exc, (ConnectionResetError, BrokenPipeError, ConnectionAbortedError,
                                 asyncio.IncompleteReadError)):
                log(f"connection closed by peer ({exc!r})")
            else:
                log(f"session task ended with error: {exc!r}")

    def _on_unexpected_stop(self, reason):
        asyncio.create_task(self.send_status(reason=reason))

    async def cleanup(self):
        if self.engine is not None:
            await self.engine.stop()
        try:
            self.writer.close()
            await self.writer.wait_closed()
        except Exception:
            pass

    # ---- reader ----

    async def _reader_loop(self):
        while True:
            mtype, payload = await read_frame(self.reader)
            self.last_rx = time.monotonic()
            if mtype == T_PING:
                await send_frame(self.writer, T_PONG)
            elif mtype == T_PONG:
                pass
            elif mtype == T_CONTROL:
                await self._handle_control(payload)
            elif mtype == T_FILE_BEGIN:
                await self._handle_file_begin(payload)
            elif mtype == T_FILE_CHUNK:
                await self._handle_file_chunk(payload)
            elif mtype == T_FILE_END:
                await self._handle_file_end(payload)
            elif mtype == T_FILE_RESULT:
                self._handle_file_result(payload)
            elif mtype == T_HELLO:
                log("duplicate HELLO, ignored")
            else:
                log(f"unknown message type 0x{mtype:02x}, len={len(payload)}, skipped", verbose_only=True)

    async def _handle_control(self, payload):
        try:
            cmd = json.loads(payload).get("cmd")
        except Exception:
            log("malformed CONTROL payload, ignored")
            return
        log(f"CONTROL {cmd}")
        if cmd == "pause":
            await self.engine.stop()
            await self.send_status(reason="Paused by client")
        elif cmd == "resume":
            await self.engine.start()
            await self.send_status()
        elif cmd == "keyframe":
            await self.engine.restart()
            await self.send_status()
        else:
            log(f"unrecognized CONTROL cmd {cmd!r}, ignored")

    async def _handle_file_begin(self, payload):
        meta = json.loads(payload)
        fid = meta.get("id")
        if self.incoming is not None:
            log(f"FILE_BEGIN id={fid} while a transfer is active, refusing")
            await send_frame(self.writer, T_FILE_RESULT, jpayload(
                {"id": fid, "ok": False, "reason": "A transfer is already in progress"}))
            return
        name = os.path.basename(meta.get("name", "unnamed"))
        dest = Path(self.args.save_dir) / name
        try:
            fh = open(dest, "wb")
        except OSError as e:
            log(f"FILE_BEGIN id={fid}: cannot open {dest}: {e}")
            await send_frame(self.writer, T_FILE_RESULT, jpayload(
                {"id": fid, "ok": False, "reason": str(e)}))
            return
        self.incoming = {"id": fid, "name": name, "size": meta.get("size", 0),
                          "kind": meta.get("kind", "other"), "dest": dest, "fh": fh, "received": 0}
        log(f"FILE_BEGIN id={fid} name={name} size={meta.get('size')} kind={meta.get('kind')} -> {dest}")

    async def _handle_file_chunk(self, payload):
        if len(payload) < 4:
            return
        (fid,) = struct.unpack(">I", payload[:4])
        data = payload[4:]
        if self.incoming is None or self.incoming["id"] != fid:
            log(f"FILE_CHUNK id={fid} with no matching active transfer, ignored")
            return
        self.incoming["fh"].write(data)
        self.incoming["received"] += len(data)

    async def _handle_file_end(self, payload):
        meta = json.loads(payload)
        fid = meta.get("id")
        if self.incoming is None or self.incoming["id"] != fid:
            log(f"FILE_END id={fid} with no matching active transfer, ignored")
            return
        info = self.incoming
        self.incoming = None
        try:
            info["fh"].close()
            log(f"FILE_END id={fid}: saved {info['received']} bytes -> {info['dest']}")
            await send_frame(self.writer, T_FILE_RESULT, jpayload({"id": fid, "ok": True}))
        except OSError as e:
            await send_frame(self.writer, T_FILE_RESULT, jpayload(
                {"id": fid, "ok": False, "reason": str(e)}))

    def _handle_file_result(self, payload):
        result = json.loads(payload)
        fid = result.get("id")
        fut = self.pending_out_results.get(fid)
        if fut and not fut.done():
            fut.set_result(result)
        log(f"FILE_RESULT id={fid} ok={result.get('ok')} reason={result.get('reason')}")

    # ---- sender ----

    async def _sender_loop(self, queue):
        while True:
            au = await queue.get()
            flags = 1 if au["keyframe"] else 0
            payload = struct.pack(">BQ", flags, au["pts_us"]) + au["bytes"]
            await send_frame(self.writer, T_VIDEO, payload)
            self.rate_aus += 1
            self.rate_bytes += len(payload)
            if au["keyframe"]:
                self.rate_keyframes += 1

    async def _rate_log_loop(self):
        while True:
            await asyncio.sleep(5.0)
            fps = self.rate_aus / 5.0
            kbps = (self.rate_bytes * 8 / 1000.0) / 5.0
            log(f"rate: fps={fps:.1f} kbit/s={kbps:.0f} AUs sent={self.rate_aus} "
                f"(keyframes={self.rate_keyframes})")
            self.rate_aus = 0
            self.rate_bytes = 0
            self.rate_keyframes = 0

    async def _watchdog_loop(self):
        missed = 0
        last_ping_sent = None
        while True:
            await asyncio.sleep(0.5)
            silence = time.monotonic() - self.last_rx
            if silence >= PING_SILENCE_SECONDS:
                if last_ping_sent is None or (time.monotonic() - last_ping_sent) >= PING_SILENCE_SECONDS:
                    await send_frame(self.writer, T_PING)
                    last_ping_sent = time.monotonic()
                    missed += 1
                    log(f"PING sent, missed={missed}", verbose_only=True)
                    if missed >= PING_MISSED_LIMIT:
                        log(f"{PING_MISSED_LIMIT} missed PINGs, closing dead connection to {self.peer}")
                        return
            else:
                missed = 0

    async def _send_queued_files(self):
        for path in self.args.send:
            if not os.path.isfile(path):
                log(f"--send {path}: no such file, skipping")
                continue
            size = os.path.getsize(path)
            kind = classify_kind(path)
            out_id = self.next_out_id
            self.next_out_id += 1
            fut = asyncio.get_event_loop().create_future()
            self.pending_out_results[out_id] = fut
            await send_frame(self.writer, T_FILE_BEGIN, jpayload(
                {"id": out_id, "name": os.path.basename(path), "size": size, "kind": kind}))
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(FILE_CHUNK_MAX)
                    if not chunk:
                        break
                    await send_frame(self.writer, T_FILE_CHUNK, struct.pack(">I", out_id) + chunk)
            await send_frame(self.writer, T_FILE_END, jpayload({"id": out_id}))
            log(f"sent {path} ({size} bytes, kind={kind}, id={out_id}), awaiting FILE_RESULT")
            try:
                result = await asyncio.wait_for(fut, timeout=30.0)
                if result.get("ok"):
                    log(f"--send {path}: ok")
                else:
                    log(f"--send {path}: refused - {result.get('reason')}")
            except asyncio.TimeoutError:
                log(f"--send {path}: timed out waiting for FILE_RESULT")
            finally:
                self.pending_out_results.pop(out_id, None)


# --------------------------------------------------------------------------------------
# Server
# --------------------------------------------------------------------------------------

current_client_task = None
stop_event = None  # set for --once


async def handle_client(reader, writer, args, hostname):
    global current_client_task
    peer = writer.get_extra_info("peername")
    my_task = asyncio.current_task()
    prev_task = current_client_task
    current_client_task = my_task
    if prev_task is not None and not prev_task.done():
        log(f"new connection from {peer}, replacing previous client")
        prev_task.cancel()

    log(f"connect from {peer}")
    session = ClientSession(reader, writer, args, hostname)
    try:
        await session.run()
    except asyncio.CancelledError:
        log(f"session for {peer} cancelled (replaced by new client)")
    except (asyncio.IncompleteReadError, ConnectionResetError, BrokenPipeError) as e:
        log(f"connection lost from {peer}: {e!r}")
    except asyncio.TimeoutError:
        log(f"{peer}: timed out waiting for HELLO")
    except Exception as e:
        log(f"session error for {peer}: {e!r}")
    finally:
        await session.cleanup()
        if current_client_task is my_task:
            current_client_task = None
        log(f"disconnect {peer}")
        if args.once and stop_event is not None:
            stop_event.set()


async def run_server(args):
    global stop_event, SERVER_START
    SERVER_START = time.monotonic()
    stop_event = asyncio.Event()
    hostname = socket.gethostname().split(".")[0]

    async def _handler(reader, writer):
        await handle_client(reader, writer, args, hostname)

    server = await asyncio.start_server(_handler, args.bind, args.port)
    addrs = ", ".join(str(sock.getsockname()) for sock in server.sockets)
    log(f"paintstream/1 fake server listening on {addrs} (mode={args.mode}, hostname={hostname})")

    async with server:
        if args.once:
            await stop_event.wait()
        else:
            await server.serve_forever()


def _cleanup_orphans():
    for proc in list(_active_procs):
        try:
            proc.kill()
        except Exception:
            pass


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Reference paintstream/1 server (STREAM.md §3) for testing the "
                    "iPad client before the Windows laptop exists.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--port", type=int, default=DEFAULT_PORT, help="TCP port to listen on")
    p.add_argument("--bind", default=DEFAULT_BIND, help="address to bind")

    src = p.add_mutually_exclusive_group()
    src.add_argument("--screen", action="store_const", dest="mode", const="screen",
                      help="capture this Mac's screen via ffmpeg avfoundation (default)")
    src.add_argument("--pattern", action="store_const", dest="mode", const="pattern",
                      help="synthetic ffmpeg testsrc — no permissions needed, the CI path")
    src.add_argument("--file", metavar="PATH", help="loop an Annex-B .h264 file at 30 fps")
    p.set_defaults(mode="screen")

    p.add_argument("--avfoundation-device", default="1:none",
                    help='avfoundation input spec for --screen, e.g. "1:none" '
                         '(verify the index with -f avfoundation -list_devices true -i "")')
    p.add_argument("--screen-size", default="1920x1080",
                    help="width x height reported in STATUS for --screen (informational "
                         "only — the encoder captures the display's native size)")

    p.add_argument("--send", action="append", default=[], metavar="PATH",
                    help="send this file to the client once its HELLO is in "
                         "(repeatable)")
    p.add_argument("--save-dir", default=DEFAULT_SAVE_DIR,
                    help="where incoming files from the client are saved")
    p.add_argument("--once", action="store_true",
                    help="exit after the first client disconnects (for scripted tests)")
    p.add_argument("-v", "--verbose", action="store_true",
                    help="print ffmpeg's stderr and extra protocol chatter to the log")
    args = p.parse_args(argv)

    if args.file:
        args.mode = "file"
        if not os.path.isfile(args.file):
            p.error(f"--file {args.file}: no such file")
    return args


def main(argv=None):
    global VERBOSE
    args = parse_args(argv)
    VERBOSE = args.verbose
    os.makedirs(args.save_dir, exist_ok=True)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, loop.stop)
            except NotImplementedError:
                pass
        loop.run_until_complete(run_server(args))
    except KeyboardInterrupt:
        pass
    finally:
        _cleanup_orphans()
        try:
            loop.run_until_complete(asyncio.sleep(0.05))
        except Exception:
            pass
        loop.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
