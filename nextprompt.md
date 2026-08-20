# Prompt for the next session

Paste the block below.

---

Read HANDOFF.md, then CLAUDE.md and TODO.md.

**Nothing is in flight.** No worktrees, no `tmp/*` branches, no simulator debris, and `TODO.md`'s "In
flight" section is empty — seven branches landed on 2026-08-19/20 and every owner ask on that list is
merged. `main` is at 1357 fast-tier tests passing, 0 failing, verified on a fresh simulator *after*
the merges rather than only on each branch's own base. You are starting clean, which has not been
true for several passes.

**Delegate.** The owner's standing instruction is that this session is an orchestrator: *"save your
context by smartly delegating tasks to sonnet and opus agents"*, and *"if there was a restriction of
using agents anywhere, remove it. You should just be smart in usage."* The old two-stream cap is
lifted. The real throttle is `tools/simlock.sh`'s two slots, which serialize test runs on their own —
so extra agents queue rather than starve the machine. Give each agent its **own** simulator that it
creates and deletes, and tell it never to run `simctl shutdown all`.

**Do the iPad pass first, before writing any code.** HANDOFF.md lists six things a simulator cannot
answer and they are the whole reason to want the owner awake. The Add Text keyboard-over-canvas check
is the priority — nothing headless reaches it, and a box placed near the bottom of the screen is the
likeliest place a real defect is hiding, because there is no `keyboardLayoutGuide` handling at all.
Ask for one `ActionRecorder` capture covering it. **Deploy is blocked, not skipped**: the iPad read
`unavailable` all night. Run the deploy steps from `CLAUDE.md` out of the repo — `deploy/deploy.sh`
pulls `main` and cannot ship branch work.

**Seven things need the owner's ruling** and they are listed at the end of HANDOFF.md. Four are new
consequences of what shipped (two of them change how the cross eraser behaves in ordinary use), three
are carried. Ask them early — several are one-line answers that unblock real work.

Then, in rough order of value:

1. **`PERFORMANCE.md` item 9(b)**, promoted by a measurement taken while building Tier A: on a
   playback tick the `@MainActor` snapshot costs **78.2 ms** against **22.2 ms** of background
   composite, so `renderSources` is now the largest main-thread term on the path. Item **4b is
   declined**, on that measurement rather than on nerve — do not rebuild it. Revisit it only after
   9(b) moves the snapshot off main and the table is re-taken.
2. **Add Text stage 3** — vector layers keep text editable. `ADD_TEXT.md` §3 has the file-by-file
   scope and the tests. Stage 1 is done; **stage 2 is on `main` and must not be rebuilt.**
3. Tier B, which is instruments rather than fixes and mostly wants device numbers.

---

## Notes for whoever writes the next prompt

**Check `git log` for a file before building what a document says is outstanding.** `PERFORMANCE.md`
and `BUGS.md` both described the `scenePhase` triple-save as to-do for two days after `1cbec5b` fixed
it. An agent went to build it and found it already there. That lag is now written into
`PERFORMANCE.md` as the finding beside the item.

**Two of tonight's agents were saved by a control test, and one was not saved by three of them.** The
`Menu` measurement's first draft counted raster strokes on a vector-by-default layer — right answer,
impossible reason — and its paired no-menu control caught it. Conversely, two of the three original
cross-eraser diagnosis agents confidently declared the stub hypothesis *refuted*; both were wrong,
because every test they cited spaced its samples wider than the tolerance it tested, which no real
stroke does. Ask what a passing test would look like if the code were broken.

**Do not tell an agent to cache a UDID in the scratchpad.** Subagents share the parent session's
scratchpad directory, so a fixed filename is silently overwritten — one agent ran a full suite on
another's simulator. Hold it in a shell variable, and read the xcresult's `deviceName` alongside the
count.
