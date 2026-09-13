#!/usr/bin/env python3
"""stream-client-check.py — a tiny reference `paintstream/1` CLIENT (STREAM.md §3, §7 stage 0).

Connects to a server (normally tools/stream/fake-streamer.py), does the HELLO handshake,
prints every STATUS, counts VIDEO frames and keyframes for `--seconds`, and verifies the
protocol's invariants:
  - framing parses cleanly (a parse failure is itself an invariant violation)
  - every keyframe access unit (flags bit0 set) begins with SPS (NAL 7) then PPS (NAL 8)
  - VIDEO pts_us is non-decreasing

Optionally sends a file to the server (`--send`) and/or exercises pause/resume
(`--pause-after N`). Exits 0 if every invariant held (and any requested --send/pause-resume
check succeeded), 1 otherwise, printing what failed to stderr.

Python 3 stdlib only, one file, executable.
"""
import argparse
import asyncio
import json
import os
import re
import socket
import struct
import sys
import time
from pathlib import Path

PROTO_VERSION = 1

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

FILE_CHUNK_MAX = 256 * 1024

NAL_SPS = 7
NAL_PPS = 8
_START_CODE_RE = re.compile(rb"\x00\x00\x01")

VERBOSE = False


def log(msg, *, verbose_only=False):
    if verbose_only and not VERBOSE:
        return
    ts = time.strftime("%H:%M:%S", time.localtime()) + f".{int(time.time() * 1000) % 1000:03d}"
    print(f"[{ts}] {msg}", file=sys.stderr, flush=True)


# ---- framing (same wire format as fake-streamer.py, kept independent on purpose: this
# script is a second, from-scratch implementation of §3, which is itself a check that the
# protocol as written is unambiguous) ----

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


def nal_types_of(au_bytes):
    """Return the NAL types in an access unit, in order, by scanning start codes.
    Used only to check the SPS/PPS-before-IDR invariant — not a decoder."""
    types = []
    for m in _START_CODE_RE.finditer(au_bytes):
        idx = m.end()
        if idx < len(au_bytes):
            types.append(au_bytes[idx] & 0x1F)
    return types


def classify_kind(path):
    ext = Path(path).suffix.lower().lstrip(".")
    if ext in ("jpg", "jpeg", "png", "heic", "gif"):
        return "image"
    if ext in ("mp4", "mov", "m4v"):
        return "video"
    return "other"


class Invariants:
    def __init__(self):
        self.violations = []
        self.frames = 0
        self.keyframes = 0
        self.bytes_total = 0
        self.last_pts = None
        self.start_time = None

    def note_video(self, flags, pts_us, au_bytes):
        if self.start_time is None:
            self.start_time = time.monotonic()
        self.frames += 1
        self.bytes_total += len(au_bytes)
        is_keyframe = bool(flags & 1)
        if is_keyframe:
            self.keyframes += 1
        if self.last_pts is not None and pts_us < self.last_pts:
            self.fail(f"pts_us went backwards: {pts_us} < {self.last_pts}")
        self.last_pts = pts_us
        types = nal_types_of(au_bytes)
        if is_keyframe:
            if types[:2] != [NAL_SPS, NAL_PPS]:
                self.fail(f"keyframe AU #{self.frames} did not start with SPS,PPS "
                          f"(got NAL types {types[:4]}...)")

    def fail(self, msg):
        self.violations.append(msg)
        log(f"INVARIANT VIOLATION: {msg}")

    def summary(self):
        elapsed = (time.monotonic() - self.start_time) if self.start_time else 0.0
        fps = self.frames / elapsed if elapsed > 0 else 0.0
        kbps = (self.bytes_total * 8 / 1000.0) / elapsed if elapsed > 0 else 0.0
        return fps, kbps


class Client:
    def __init__(self, args):
        self.args = args
        self.reader = None
        self.writer = None
        self.inv = Invariants()
        self.streaming_status = None  # last STATUS 'streaming' value seen
        self.incoming = None
        self.pending_out_results = {}
        self.next_out_id = 1
        self.pause_test_result = None  # None until attempted; True/False after

    async def connect(self):
        self.reader, self.writer = await asyncio.open_connection(self.args.host, self.args.port)
        hello = {"proto": PROTO_VERSION, "app": "PaintApp", "version": "check-0.1",
                 "name": socket.gethostname().split(".")[0] or "stream-client-check"}
        await send_frame(self.writer, T_HELLO, jpayload(hello))
        log(f"sent HELLO {hello}")
        mtype, payload = await asyncio.wait_for(read_frame(self.reader), timeout=5.0)
        if mtype != T_HELLO:
            raise RuntimeError(f"expected HELLO reply first, got type 0x{mtype:02x}")
        reply = json.loads(payload)
        log(f"server HELLO: {reply}")
        if reply.get("proto") != PROTO_VERSION:
            raise RuntimeError(f"server proto {reply.get('proto')!r} != {PROTO_VERSION}")
        return reply

    async def run(self):
        deadline = time.monotonic() + self.args.seconds
        if self.args.pause_after is not None:
            deadline = max(deadline, time.monotonic() + self.args.pause_after + 4.0)

        tasks = [asyncio.create_task(self._loop())]
        if self.args.send:
            tasks.append(asyncio.create_task(self._send_files()))
        if self.args.pause_after is not None:
            tasks.append(asyncio.create_task(self._pause_resume_test()))

        async def _deadline_waiter():
            await asyncio.sleep(max(0.0, deadline - time.monotonic()))

        tasks.append(asyncio.create_task(_deadline_waiter()))
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        # if the deadline fired first, or a helper task finished, give the others a
        # moment to be cancelled cleanly
        for t in pending:
            t.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        for t in done:
            exc = t.exception()
            if exc:
                self.inv.fail(f"task error: {exc!r}")

    async def _loop(self):
        while True:
            mtype, payload = await read_frame(self.reader)
            if mtype == T_STATUS:
                status = json.loads(payload)
                self.streaming_status = status.get("streaming")
                log(f"STATUS {status}")
            elif mtype == T_VIDEO:
                if len(payload) < 9:
                    self.inv.fail(f"VIDEO payload too short: {len(payload)} bytes")
                    continue
                flags = payload[0]
                (pts_us,) = struct.unpack(">Q", payload[1:9])
                au_bytes = payload[9:]
                self.inv.note_video(flags, pts_us, au_bytes)
            elif mtype == T_PING:
                await send_frame(self.writer, T_PONG)
            elif mtype == T_PONG:
                pass
            elif mtype == T_FILE_BEGIN:
                await self._handle_file_begin(payload)
            elif mtype == T_FILE_CHUNK:
                self._handle_file_chunk(payload)
            elif mtype == T_FILE_END:
                await self._handle_file_end(payload)
            elif mtype == T_FILE_RESULT:
                self._handle_file_result(payload)
            else:
                log(f"unknown message type 0x{mtype:02x}, len={len(payload)}, skipped",
                    verbose_only=True)

    async def _handle_file_begin(self, payload):
        meta = json.loads(payload)
        fid = meta.get("id")
        if self.incoming is not None:
            await send_frame(self.writer, T_FILE_RESULT, jpayload(
                {"id": fid, "ok": False, "reason": "A transfer is already in progress"}))
            return
        os.makedirs(self.args.save_dir, exist_ok=True)
        name = os.path.basename(meta.get("name", "unnamed"))
        dest = Path(self.args.save_dir) / name
        self.incoming = {"id": fid, "dest": dest, "fh": open(dest, "wb"), "received": 0}
        log(f"FILE_BEGIN id={fid} name={name} size={meta.get('size')} -> {dest}")

    def _handle_file_chunk(self, payload):
        (fid,) = struct.unpack(">I", payload[:4])
        data = payload[4:]
        if self.incoming and self.incoming["id"] == fid:
            self.incoming["fh"].write(data)
            self.incoming["received"] += len(data)

    async def _handle_file_end(self, payload):
        meta = json.loads(payload)
        fid = meta.get("id")
        if not self.incoming or self.incoming["id"] != fid:
            return
        info = self.incoming
        self.incoming = None
        info["fh"].close()
        log(f"FILE_END id={fid}: received {info['received']} bytes -> {info['dest']}")
        await send_frame(self.writer, T_FILE_RESULT, jpayload({"id": fid, "ok": True}))

    def _handle_file_result(self, payload):
        result = json.loads(payload)
        fid = result.get("id")
        fut = self.pending_out_results.get(fid)
        if fut and not fut.done():
            fut.set_result(result)
        log(f"FILE_RESULT id={fid} ok={result.get('ok')} reason={result.get('reason')}")

    async def _send_files(self):
        for path in self.args.send:
            if not os.path.isfile(path):
                self.inv.fail(f"--send {path}: no such file")
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
            log(f"sent {path} ({size} bytes, kind={kind}, id={out_id})")
            try:
                result = await asyncio.wait_for(fut, timeout=15.0)
                if not result.get("ok"):
                    self.inv.fail(f"--send {path}: server refused - {result.get('reason')}")
                else:
                    log(f"--send {path}: ok")
            except asyncio.TimeoutError:
                self.inv.fail(f"--send {path}: timed out waiting for FILE_RESULT")
            finally:
                self.pending_out_results.pop(out_id, None)

    async def _pause_resume_test(self):
        await asyncio.sleep(self.args.pause_after)
        frames_before = self.inv.frames
        log("pause/resume test: sending CONTROL pause")
        await send_frame(self.writer, T_CONTROL, jpayload({"cmd": "pause"}))
        await asyncio.sleep(1.5)
        frames_during_pause = self.inv.frames - frames_before
        # Allow exactly one trailing frame: whatever the server's sender loop had
        # already popped off its queue and was mid-write on the socket at the instant
        # it processed "pause" is already committed to the wire and cannot be recalled.
        # More than one means pause did not actually stop the source promptly.
        if frames_during_pause > 1:
            self.inv.fail(f"{frames_during_pause} VIDEO frame(s) arrived after pause "
                           f"(more than the one in-flight frame pause cannot recall)")
        if self.streaming_status is not False:
            self.inv.fail("no STATUS streaming:false observed after pause")
        log("pause/resume test: sending CONTROL resume")
        keyframes_before = self.inv.keyframes
        frames_before_resume = self.inv.frames
        await send_frame(self.writer, T_CONTROL, jpayload({"cmd": "resume"}))
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if self.inv.frames > frames_before_resume:
                break
            await asyncio.sleep(0.1)
        if self.inv.frames <= frames_before_resume:
            self.inv.fail("no VIDEO frame arrived within 5s of resume")
            self.pause_test_result = False
            return
        if self.inv.keyframes <= keyframes_before:
            self.inv.fail("first frame after resume was not a keyframe")
            self.pause_test_result = False
            return
        if self.streaming_status is not True:
            self.inv.fail("no STATUS streaming:true observed after resume")
            self.pause_test_result = False
            return
        log("pause/resume test: passed")
        self.pause_test_result = True

    async def close(self):
        if self.writer:
            try:
                self.writer.close()
                await self.writer.wait_closed()
            except Exception:
                pass


async def main_async(args):
    client = Client(args)
    await client.connect()
    await client.run()
    await client.close()

    fps, kbps = client.inv.summary()
    log(f"summary: frames={client.inv.frames} keyframes={client.inv.keyframes} "
        f"fps={fps:.1f} kbit/s={kbps:.0f} violations={len(client.inv.violations)}")
    if args.pause_after is not None and client.pause_test_result is not True:
        client.inv.fail("pause/resume test did not complete successfully")

    if client.inv.violations:
        log("FAIL:")
        for v in client.inv.violations:
            log(f"  - {v}")
        return 1
    log("PASS")
    return 0


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Reference paintstream/1 CLIENT for exercising fake-streamer.py "
                    "(or the real Windows streamer) end to end.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=47301)
    p.add_argument("--seconds", type=float, default=5.0,
                    help="how long to receive VIDEO/STATUS before checking invariants")
    p.add_argument("--send", action="append", default=[], metavar="PATH",
                    help="send this file to the server (repeatable)")
    p.add_argument("--save-dir", default="./stream-client-received",
                    help="where files pushed by the server are saved")
    p.add_argument("--pause-after", type=float, default=None, metavar="SECONDS",
                    help="send CONTROL pause at this offset, verify streaming stops, "
                         "then resume and verify a fresh keyframe arrives")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv=None):
    global VERBOSE
    args = parse_args(argv)
    VERBOSE = args.verbose
    try:
        return asyncio.run(main_async(args))
    except (ConnectionRefusedError, OSError) as e:
        log(f"could not connect to {args.host}:{args.port}: {e}")
        return 1
    except RuntimeError as e:
        log(f"FAIL: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
