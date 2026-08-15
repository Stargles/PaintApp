#!/usr/bin/env python3
"""
recording2xcuitest.py — turn an ActionRecorder .jsonl recording into a skeleton XCUITest.

    tools/recording2xcuitest.py recording-20260815-141203.jsonl > MyRepro.swift
    tools/recording2xcuitest.py rec.jsonl --class BugFooUITests --test testTheThing

WHAT THIS IS FOR
    The owner reproduces a bug on their iPad with their own hands, hands us the recording, and this
    turns it into something a human or an agent can finish in a minute instead of reverse-engineering
    from a screen capture. It does NOT aim to emit a test that compiles and passes untouched — see
    the limits below, several of which are unfixable in principle. It aims to get the tedious,
    error-prone 90% (which element, in what order, how far apart in time) onto the page correctly.

WHAT IT EMITS
    * A tap                -> app.buttons["identifier"].tap()
    * A tap off-centre     -> element.coordinate(withNormalizedOffset:).tap()
    * A drag               -> start.press(forDuration:thenDragTo:)
    * App state changes    -> // comments on the timeline, so the reader can see what the app did
    * Anything unreplayable-> a loud comment, never a silent approximation

LIMITS — read these, they are the difference between a useful skeleton and a wrong test
    1. **XCUITest cannot synthesise Apple Pencil touches. At all.** There is no API: every
       XCUITest-driven touch arrives as `UITouch.TouchType.direct`. A recording made with a pencil is
       therefore NOT mechanically replayable, and this script refuses to pretend otherwise — pencil
       interactions are emitted as `#warning` plus a commented-out finger approximation, never as a
       plain `.tap()`. That distinction is central to at least two bugs this project is chasing
       (pencil-only mode gating a finger out; palm rejection racing a stroke), so a converter that
       quietly downgraded a pencil to a finger would produce a green test for a broken app.
    2. **Multi-touch is barely expressible.** XCUITest has `pinch(withScale:velocity:)`,
       `twoFingerTap()` and `rotate(withRotation:velocity:)` — canned gestures with no control over
       where each finger goes or when it lands. A recording of "hold the pen down, then drop a second
       finger" has no XCUITest spelling whatsoever. Concurrent touches are emitted as a comment
       describing what happened, plus a best-effort canned gesture where one plausibly matches.
    3. **Timing is approximate.** The recording has millisecond timestamps; a test has
       `Thread.sleep`. Gaps under 250 ms are dropped (the harness is slower than that anyway), larger
       ones become a `sleep`. A race that needs sub-100 ms precision will not reproduce.
    4. **Force, tilt and azimuth are unreplayable** and are emitted as comments only.
    5. **Touches with no identifier** (`"target": null`) cannot be replayed as element queries. They
       become a window-normalised `.coordinate` tap plus a TODO. The dominant cause is not a missing
       identifier in the app — it is that **SwiftUI only builds its accessibility elements when an
       accessibility client is attached to the process**, so a recording made by the artist on their
       own iPad reports null for every SwiftUI button while resolving the canvas perfectly (the canvas
       is UIKit). See `WindowEventTap.resolveTarget`'s doc comment, which documents the measurement.
       Practical consequences when you read a file full of nulls:
         - the `hitClass` and the `model` line right after the touch usually name what was tapped;
         - the emitted `wnx`/`wny` coordinate tap does replay, on a window of the same proportions;
         - if you need a fully-identified capture, record while an XCUITest runner is attached.
    6. **Element type is guessed from accessibility traits.** `role: "other"` found through the view
       chain becomes `app.otherElements[...]`; anything else unknown becomes an untyped
       `descendants(matching: .any)` query, which is correct but slower and can match more than one
       element. Tighten by hand when it matters.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict

# Accessibility role -> XCUIElementQuery accessor. Anything not here becomes an untyped descendant
# query rather than a guess: a wrong element type produces a test that fails for the wrong reason,
# which is worse than a slow one.
ROLE_TO_QUERY = {
    "button": "buttons",
    "slider": "sliders",
    "staticText": "staticTexts",
    "image": "images",
    "link": "links",
    "searchField": "searchFields",
}

# Gaps shorter than this are dropped rather than slept through: XCUITest's own dispatch overhead
# already exceeds it, so sleeping would only make the test slower without making it more faithful.
MIN_SLEEP = 0.25

# A tap this close to the centre of its element is emitted as a plain `.tap()`, which reads far
# better than a normalised coordinate and behaves identically. Beyond it the offset is kept, because
# for wide controls (a slider, the canvas) *where* you tapped is the whole point.
CENTRE_TOLERANCE = 0.15

# Below this travel a press-and-drag is really a tap that wobbled — the artist's finger, or the
# simulator's own jitter.
DRAG_MIN_TRAVEL = 12.0


def element_expression(target: str, role: str, resolution: str) -> str:
    """The XCUIElement query for one identifier.

    A target found through the `UIView` chain with no useful traits is a plain accessible view, which
    XCUITest types as `.other` — so `app.otherElements[...]`, which is exactly what this repo's own
    UI tests already use for `canvas.host`. Anything genuinely unknown falls back to an untyped
    descendant query rather than a guess: a wrong element type fails for the wrong reason.
    """
    escaped = target.replace("\\", "\\\\").replace('"', '\\"')
    accessor = ROLE_TO_QUERY.get(role)
    if accessor:
        return f'app.{accessor}["{escaped}"]'
    if resolution == "view":
        return f'app.otherElements["{escaped}"]'
    return f'app.descendants(matching: .any)["{escaped}"]'


def normalized_expression(expr: str, nx: float, ny: float) -> str:
    return f"{expr}.coordinate(withNormalizedOffset: CGVector(dx: {nx:.3f}, dy: {ny:.3f}))"


class Gesture:
    """One touch sequence — everything from a `began` to its `ended`/`cancelled`."""

    def __init__(self, began: dict):
        self.samples = [began]
        self.touch_id = began["touch"]
        self.start = began
        self.end = began
        self.closed = False

    def add(self, sample: dict):
        self.samples.append(sample)
        self.end = sample
        if sample["phase"] in ("ended", "cancelled"):
            self.closed = True

    @property
    def t0(self) -> float:
        return self.start["t"]

    @property
    def t1(self) -> float:
        return self.end["t"]

    @property
    def duration(self) -> float:
        return self.t1 - self.t0

    @property
    def travel(self) -> float:
        dx = self.end.get("wx", 0) - self.start.get("wx", 0)
        dy = self.end.get("wy", 0) - self.start.get("wy", 0)
        return (dx * dx + dy * dy) ** 0.5

    @property
    def used_pencil(self) -> bool:
        return any(s.get("type") == "pencil" for s in self.samples)

    @property
    def max_concurrent(self) -> int:
        return max((s.get("down", 1) for s in self.samples), default=1)


def parse(path: str):
    header = None
    events = []
    bad = 0
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                # A truncated final line is expected when the app was killed mid-recording — the
                # whole reason the format is JSONL. Count it and carry on.
                bad += 1
                continue
            if event.get("event") == "header":
                header = event
            else:
                events.append(event)
    return header, events, bad


def build_gestures(events):
    """Group touch samples into gestures, keyed by the recorder's per-touch id."""
    open_gestures: dict[int, Gesture] = {}
    gestures: list[Gesture] = []
    for event in events:
        if event.get("event") != "touch":
            continue
        touch_id = event.get("touch")
        phase = event.get("phase")
        if phase == "began":
            gesture = Gesture(event)
            open_gestures[touch_id] = gesture
            gestures.append(gesture)
        elif touch_id in open_gestures:
            open_gestures[touch_id].add(event)
            if open_gestures[touch_id].closed:
                del open_gestures[touch_id]
        else:
            # Recording started mid-gesture. The recorder adopts these, so a gesture with no `began`
            # is legitimate; treat the first sample we saw as its start.
            gesture = Gesture(event)
            gestures.append(gesture)
            if not gesture.closed:
                open_gestures[touch_id] = gesture
    return gestures


def emit_state_comments(events, lo: float, hi: float, out: list[str], indent: str):
    """App-state events between two gestures, as comments — the cause-and-effect half of the file."""
    for event in events:
        t = event.get("t", 0)
        if not (lo < t <= hi):
            continue
        kind = event.get("event")
        if kind == "model":
            out.append(f'{indent}// [{t:7.3f}] {event["key"]} = {event["value"]}')
        elif kind == "recognizer" and event.get("to") in ("began", "ended", "cancelled", "failed"):
            out.append(
                f'{indent}// [{t:7.3f}] recognizer {event["name"]}: '
                f'{event["from"]} -> {event["to"]} ({event.get("src", "?")})'
            )
        elif kind == "requireFailure" and event.get("answer"):
            out.append(
                f'{indent}// [{t:7.3f}] {event["asker"]} is waiting on {event["other"]} to fail'
            )


def emit_gesture(gesture: Gesture, out: list[str], indent: str, warnings: list[str]):
    start = gesture.start
    end = gesture.end
    target = start.get("target")
    role = start.get("role", "other")
    hit_class = start.get("hitClass", "?")
    label = start.get("label")
    nx, ny = start.get("nx", 0.5), start.get("ny", 0.5)

    described = f'{target or "<no identifier>"}'
    if label:
        described += f' ("{label}")'
    kind = "drag" if gesture.travel >= DRAG_MIN_TRAVEL else "tap"
    out.append(f'{indent}// [{gesture.t0:7.3f}] {start.get("type")} {kind} on {described}')

    if start.get("depth", 0) > 0 and target:
        out.append(
            f"{indent}//   NOTE: the touch landed on {hit_class}, {start['depth']} level(s) inside "
            f'"{target}" — the replay drives the container, not the exact subview.'
        )
    if start.get("via") == "none" or not target:
        warnings.append(f"t={gesture.t0:.3f}: no accessibility identifier for a touch on {hit_class}")
        wnx, wny = start.get("wnx", 0.0), start.get("wny", 0.0)
        out.append(f"{indent}// TODO: no element identifier for this touch — window coordinate instead.")
        out.append(f"{indent}//   Hit view was {hit_class}. If that is a SwiftUI hosting view, the app's")
        out.append(f"{indent}//   identifier exists but was unreachable while recording (see limit 5 in this")
        out.append(f"{indent}//   script's header) — read the `model` comments around this line to see what")
        out.append(f"{indent}//   the tap did, then replace this with the real element query.")
        end_wnx, end_wny = end.get("wnx", wnx), end.get("wny", wny)
        if gesture.travel >= DRAG_MIN_TRAVEL:
            out.append(
                f"{indent}app.windows.firstMatch.coordinate(withNormalizedOffset: "
                f"CGVector(dx: {wnx:.4f}, dy: {wny:.4f}))"
            )
            out.append(
                f"{indent}    .press(forDuration: {max(gesture.duration, 0.05):.2f}, thenDragTo: "
                f"app.windows.firstMatch.coordinate(withNormalizedOffset: "
                f"CGVector(dx: {end_wnx:.4f}, dy: {end_wny:.4f})))"
            )
        else:
            out.append(
                f"{indent}app.windows.firstMatch.coordinate(withNormalizedOffset: "
                f"CGVector(dx: {wnx:.4f}, dy: {wny:.4f})).tap()"
            )
        return

    expression = element_expression(target, role, start.get("via", "none"))
    is_drag = gesture.travel >= DRAG_MIN_TRAVEL

    if gesture.used_pencil:
        warnings.append(f"t={gesture.t0:.3f}: Apple Pencil interaction on {target} — NOT replayable")
        out.append(f"{indent}// ######## APPLE PENCIL — XCUITest CANNOT REPRODUCE THIS ########")
        out.append(
            f"{indent}// Every XCUITest touch is UITouch.TouchType.direct. This gesture was a pencil"
        )
        out.append(f"{indent}// (force {start.get('force', 0)}, altitude {start.get('altitude', 0)},")
        out.append(f"{indent}//  azimuth {start.get('azimuth', 0)}), and the app branches on that")
        out.append(f"{indent}// (pencilOnlyDrawing, StrokeGestureRecognizer.requiresPencilOnly).")
        out.append(f"{indent}// The finger approximation below WILL behave differently. Left commented out")
        out.append(f"{indent}// on purpose: uncomment only once you have decided the difference is irrelevant")
        out.append(f"{indent}// to what you are testing.")
        prefix = f"{indent}// "
    else:
        prefix = indent

    if gesture.max_concurrent > 1:
        warnings.append(
            f"t={gesture.t0:.3f}: {gesture.max_concurrent} concurrent touches on {target} — approximated"
        )
        out.append(f"{indent}// !!!! {gesture.max_concurrent} fingers were down during this gesture.")
        out.append(f"{indent}// XCUITest has no way to place individual fingers. The closest canned gestures are")
        out.append(f"{indent}// pinch(withScale:velocity:), rotate(withRotation:velocity:) and twoFingerTap().")
        out.append(f"{indent}// Pick whichever matches the intent, or drive it with two XCUICoordinate objects")
        out.append(f"{indent}// if the exact interleaving matters (it does for the transform-deadlock bug).")
        out.append(f"{prefix}{expression}.twoFingerTap()   // <- verify this is what you meant")
        return

    if is_drag:
        end_target = end.get("target")
        start_coord = normalized_expression(expression, nx, ny)
        if end_target and end_target != target:
            end_expression = element_expression(end_target, end.get("role", "other"), end.get("via", "none"))
            end_coord = normalized_expression(end_expression, end.get("nx", 0.5), end.get("ny", 0.5))
        else:
            end_coord = normalized_expression(expression, end.get("nx", 0.5), end.get("ny", 0.5))
        out.append(
            f"{prefix}{start_coord}"
        )
        out.append(
            f"{prefix}    .press(forDuration: {max(gesture.duration, 0.05):.2f}, thenDragTo: {end_coord})"
        )
        moves = sum(1 for s in gesture.samples if s["phase"] == "moved")
        skipped = sum(s.get("skipped", 0) for s in gesture.samples)
        out.append(
            f"{indent}//   path: {moves} recorded move samples ({skipped} coalesced away), "
            f"{gesture.travel:.0f} pt travelled in {gesture.duration:.2f}s"
        )
        out.append(
            f"{indent}//   press(thenDragTo:) interpolates a straight line. If the SHAPE of the path"
        )
        out.append(f"{indent}//   matters, drive the intermediate points by hand from the jsonl.")
    else:
        centred = abs(nx - 0.5) <= CENTRE_TOLERANCE and abs(ny - 0.5) <= CENTRE_TOLERANCE
        if centred:
            out.append(f"{prefix}{expression}.tap()")
        else:
            out.append(f"{prefix}{normalized_expression(expression, nx, ny)}.tap()")


def render(header, events, gestures, class_name, test_name):
    out: list[str] = []
    warnings: list[str] = []

    out.append("import XCTest")
    out.append("")
    out.append("/// Generated by tools/recording2xcuitest.py from an in-app ActionRecorder recording.")
    out.append("/// THIS IS A SKELETON, NOT A PASSING TEST. Read every `TODO`, `!!!!` and `########`")
    out.append("/// before trusting it; the converter's limits are documented in the script's header.")
    if header:
        out.append("///")
        out.append(f'/// Recorded on {header.get("device", "?")}, iOS {header.get("os", "?")}, '
                   f'app {header.get("app", "?")}')
        out.append(f'/// Project "{header.get("project", "?")}", canvas '
                   f'{header.get("canvasW", "?")}x{header.get("canvasH", "?")}, '
                   f'window {header.get("windowW", "?")}x{header.get("windowH", "?")}')
        out.append(f'/// Started {header.get("startedAt", "?")}, source file {header.get("file", "?")}')
        if header.get("touchCapture", "on") != "on":
            out.append(f'/// !!!! touchCapture was {header["touchCapture"]} — this recording has NO touches.')
    out.append(f"final class {class_name}: XCTestCase {{")
    out.append(f"    func {test_name}() throws {{")
    out.append("        let app = XCUIApplication()")
    out.append("        app.launch()")
    out.append("")

    indent = "        "
    previous_end = 0.0
    emitted_multitouch_until = -1.0
    for gesture in gestures:
        # A two-finger gesture arrives here as two Gesture objects, one per finger, overlapping in
        # time. Emitting both would put two `twoFingerTap()` calls in the test for one real gesture,
        # so the second (and any further) finger of an overlapping multi-touch is folded into the
        # first — its own line would be a duplicate, not extra information.
        if gesture.max_concurrent > 1 and gesture.t0 < emitted_multitouch_until:
            continue
        emit_state_comments(events, previous_end, gesture.t0, out, indent)
        gap = gesture.t0 - previous_end
        if gap >= MIN_SLEEP and previous_end > 0:
            out.append(f"{indent}Thread.sleep(forTimeInterval: {gap:.2f})   // artist paused here")
        emit_gesture(gesture, out, indent, warnings)
        out.append("")
        previous_end = gesture.t1
        if gesture.max_concurrent > 1:
            emitted_multitouch_until = max(emitted_multitouch_until, gesture.t1)

    # Anything the app did after the last touch — often the interesting part, since a hang shows up
    # as state that never arrives.
    tail = [e for e in events if e.get("t", 0) > previous_end]
    if tail:
        out.append(f"{indent}// ---- after the last touch ----")
        emit_state_comments(events, previous_end, float("inf"), out, indent)
        out.append("")

    out.append(f"{indent}// TODO: assert something. The recording says what happened, not what should have.")
    out.append("    }")
    out.append("}")

    if warnings:
        out.append("")
        out.append("/*")
        out.append(" * CONVERSION WARNINGS — every one of these is a place the test is NOT faithful:")
        for warning in warnings:
            out.append(f" *   - {warning}")
        out.append(" */")
    return "\n".join(out), warnings


def summarise(header, events, gestures, bad_lines, stream):
    counts = defaultdict(int)
    for event in events:
        counts[event.get("event", "?")] += 1
    print("recording2xcuitest: summary", file=stream)
    if header:
        print(f"  device      {header.get('device')}  iOS {header.get('os')}  app {header.get('app')}", file=stream)
        print(f"  window      {header.get('windowW')}x{header.get('windowH')}  "
              f"canvas {header.get('canvasW')}x{header.get('canvasH')}", file=stream)
        print(f"  touchCapture {header.get('touchCapture')}  windowClass {header.get('windowClass')}", file=stream)
    else:
        print("  !! no header line — is this an ActionRecorder recording?", file=stream)
    for kind in sorted(counts):
        print(f"  {kind:16} {counts[kind]}", file=stream)
    print(f"  gestures         {len(gestures)}", file=stream)
    pencil = sum(1 for g in gestures if g.used_pencil)
    if pencil:
        print(f"  !! {pencil} of them used an Apple Pencil and CANNOT be replayed by XCUITest", file=stream)
    multi = sum(1 for g in gestures if g.max_concurrent > 1)
    if multi:
        print(f"  !! {multi} of them were multi-touch and are approximated", file=stream)
    unidentified = sum(1 for g in gestures if not g.start.get("target"))
    if unidentified:
        print(f"  !! {unidentified} of them hit nothing with an accessibilityIdentifier", file=stream)
    if bad_lines:
        print(f"  {bad_lines} unparseable line(s) skipped (a truncated tail is normal)", file=stream)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recording", help="path to a .jsonl written by the in-app recorder")
    parser.add_argument("--class", dest="class_name", default="RecordedReproUITests")
    parser.add_argument("--test", dest="test_name", default="testRecordedRepro")
    parser.add_argument("-o", "--output", default=None, help="write here instead of stdout")
    args = parser.parse_args()

    header, events, bad_lines = parse(args.recording)
    gestures = build_gestures(events)
    source, _ = render(header, events, gestures, args.class_name, args.test_name)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(source + "\n")
    else:
        print(source)

    # Summary always to stderr, so `> Repro.swift` still shows it.
    summarise(header, events, gestures, bad_lines, sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
