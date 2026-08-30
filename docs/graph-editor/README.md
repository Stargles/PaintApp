# Graph editor — screenshots

Captured 2026-08-30 from `origin/main` at `1ce12f8`, iPad Pro 13-inch (M4) simulator, iOS 26.5,
portrait. KEYFRAMES.md §11 stages **D1, D2 and D4**.

## The document that was authored

One project, built from a fresh 2048×2048 canvas by a throwaway XCUITest driving real taps:

- Four layers, bottom to top: **Vector 1** (two strokes), **Vector 2** (one stroke),
  **HSV Shift** (a value layer in effect mode — the graded one), **Vector 4** (empty).
- The HSV Shift layer's block was stretched to 25 frames, so `sceneFrameCount` is **25**; the
  other three layers keep their original 12-frame block. That is why one row's block is long and
  three are short.
- Three animated channels on the HSV Shift grade, each with keys at frames **0, 12 and 24**:

  | channel | slider range | frame 0 | frame 12 | frame 24 |
  |---|---|---|---|---|
  | Hue | −180…180° | 0° | 162° | 43° |
  | Saturation | 0…2 | 1.00 | 0.39 | 1.67 |
  | Value | 0…2 | 1.00 | 1.27 | 0.18 |

  Authored through the shipped workflow (§2.26/§2.27): Add Keyframe from the cel menu at frame 0,
  move the sliders, Add Keyframe at frame 12 — which commits the old value onto 0 and the new one
  onto 12 — then move the playhead to 24 and move the sliders again, which auto-keys.
- The playhead is parked at **frame 4** in every shot, off the keys.
- The timeline panel was dragged taller (250 → ~440 pt) so all four rows plus the 96 pt band fit on
  screen at once. That is a normal drag on the panel's top bar, not a build setting.

The three ranges are the point: hue spans 360 units and saturation/value span 2, and all three
curves fill the same 96 pt band because each is normalised to its **own** slider range (§11.6).

## The shots

| file | what it shows |
|---|---|
| `1-timeline-with-band.png` | **The money shot.** The whole timeline with the band open: frame ruler, four layer names, four rows of cel blocks, the keyframe diamonds on the HSV Shift row, and the band hanging under that row and pushing Vector 2 and Vector 1 down. The graph-editor toggle (chart icon, 4th from the left) is tinted blue because the band is open, and the channel-list button (5th) has appeared beside it. |
| `2-band-closeup.png` | The band close up — the three curve shapes, the key dots at frames 1, 13 and 25 (1-based ruler), and the three colours, with the ruler above for reference. |
| `3-channel-list.png` | The channel list popup: the **HSV Shift** group row with its own checkbox, and one checked row per animated channel with the swatch that matches its curve. |
| `4-band-saturation-hidden.png` | The same band from the same camera as `2`, with **Saturation** unchecked. The orange curve is gone; the other two are unchanged and in the same place. |
| `0-full-screen.png` | The whole app for context, same state as `1`. |
| `3b-channel-list-full.png` | The whole app with the popup up, showing where it sits relative to the button and the canvas. |

## Reading them

The playhead is a **column** the width of one frame at 35 % blue, not a hairline, and it is drawn
**in front of** the band (§11.3, a deliberate choice). Where a curve crosses it the colour washes
out — the short grey segment at frame 4 in shots `1` and `2` is the orange saturation curve under
that wash, not a break in the line.

## What is *not* in these shots

- **Stage D3 — dragging keys, handles and a marquee — is not in this build.** The key dots are
  drawn; nothing in these images can be picked up or moved. The band is
  `isUserInteractionEnabled = false`, so a touch on it falls through to the timeline's scroll.
- No tangent handles, no per-segment interpolation control, no step-above-1 stem (nothing in the
  app writes a step above 1 yet), and no way to add or delete a key from inside the band.
- The band is drawn for **one** layer at a time — whichever is selected — and follows the
  selection. There is no per-layer toggle and no open-every-animated-layer mode.
- Only effect-parameter channels exist today, so every band has exactly one group in its channel
  list. Transform and object channels are later stages.
