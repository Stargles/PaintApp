# Rendering — the background baker and export

TODO item (29). **§2 is owner rulings; read them rather than re-deriving them.** §3 onward is the design and
the build order.

## 0. What is already true

- **There is no export feature of any kind.** No share, file-export or photo-library API is reached from
  app code. The word "Export" reaches the artist only as reassurance copy under the Render Resolution knob
  (`Views/ActionsMenu.swift`, `renderResolutionControl`).
- `Compositor.composite(_:) -> CGImage?` (`Engine/Compositor.swift`) is pure and headless — it runs in the
  logic test tier with no view — and `makeRenderRequest` is frame-parametric. What is missing is a driver
  loop, an encoder and a destination, not a renderer.
- Content versions propagate from a leaf to its ancestors, and invalidation is already frame-scoped. "Only
  the modified frames are rebaked" costs nothing new.
- `CompositorBudget.affordableSize` shrinks any composite whose textures do not fit `physicalMemory / 16`
  (192 MiB on a 3 GB iPad), whatever the knob says. §2.12 forbids that.
- One raw frame at 2048² is 16.8 MB; ten seconds at 24 fps is 4 GB. Baked frames must be compressed on disk,
  never held as raw textures.
- Composited playback already misses 24 fps on the owner's iPad with no in-betweens present: a six-layer
  sandwich rebuild at 2048² is MEASURED 54.8 ms against a 41.6 ms budget (PERFORMANCE §2 item 5).
- Two earlier designs describe parts of this cache and are superseded by this file: LAYER_COMPOSITING §9.2
  (sequencer-scoped priority queue with a disk LRU) and KEYFRAMES §4.6 (one keyframe span, eager and
  complete, ruled in KEYFRAMES §2.19-20). KEYFRAMES §2.25 lets a derived frame cost more than 1/24 s
  *because* this prebake exists; dropping this item takes that permission with it.

## 1. The ask, in the owner's words

> "rendering: add the ability to export animations as video or a frame as image"

> "the ipad does not have much memory, so I want the paint program to not use much by storing as many things
> it can to disk. Probably the current active cel is the only thing required to be in memory. The paint
> program automatically pulls unbaked frames from disk (layers, compositing, etc), bakes the compositing and
> stores it back straight to disk, so that when the play is pressed it can be played at 24fps. This way, the
> program doesn't run out of memory even with a hundred layers and a thousand cels. The memory is dynamically
> allocated: lets say we have layers 1 through 10 and the program has only enough memory for 3: the three
> bottom layers are pulled, composited and stored, then the next are pulled etc."

> "The render feature consists of two parts: 1) automatic background rendering and baking. 2) export. The
> background renderer will pretty much replace the behaviour of the current compositor, which at the moment
> renders on the main thread live. This means that on large canvases with many layers, it cannot keep up at
> 24fps. This is why the rendering will be on a background thread, so your UX thread runs smoothly for the
> user, and the background thread automatically renders and stores the frames to disk. This should be smart,
> it only rebakes and stores the frames which matter. When you click on play, it pulls the prerendered frames
> so you get smooth 24fps even with a 30+ layers and complex compositing. The method how it renders should be
> sort of like this: It first pulls the bottom layers that fit in memory, then composite bakes them. Then it
> discards them and pulls the next layers and continues compositing them over the prebaked render. Note: this
> isnt a linear thing, as the compositor is a tree. For exporting, since all the frames are already baked and
> stored into disk, all it has to do is make a video out of them, or export one frame as an image."

> "The goal is this: I want to be able to have an animation with tens to hundreds of layers and thousands of
> cels, and when I click the play button, it plays the animation at 24fps. This should not interfere with the
> FPS of the user interface; there should be no lagspikes."

> "I eventually want to make it android and windows compatible so dynamic allocation of some sort may be nice."

## 2. Rulings

1. **Two parts, one store.** A background baker that composites frames to disk, and an export that reads
   those files. Export re-renders nothing.
2. **The baker replaces live compositing.** The main thread never composites. It handles input, the
   timeline, and draws the live stroke over an already-finished picture.
3. **Only the frames that matter are rebaked.** *"When something is modified, only the modified frames are
   rebaked."*
4. **Compositing is chunked bottom-up under a memory ceiling, and the chunking follows the tree**, not a flat
   layer index. Pull what fits, composite it, discard it, continue over the accumulated result.
5. **The goal is the acceptance test.** Tens to hundreds of layers, thousands of cels, 24 fps on play, and
   the UI frame rate untouched.
6. **Portable.** No budget hard-coded to an iPad and no eviction that only iOS can signal.
7. **Container and codec are the session's decision**, not the owner's. See §3.
8. **Export resolution is the Render Resolution knob's value.** The owner expects a compression method that
   exploits flat colour and frames that do not change: *"remember that this is an anime animator, which has a
   lot of flat colors and frames that dont change."*
9. **One renderer serves both playback and export.** Slow is acceptable on heavy compositing. If resolution
   or quality-versus-speed ever forces a separate export renderer, say so and proceed.
10. **Playback may be visibly stale while the bake catches up.** The frame the artist is on is baked first if
    it is not baked yet, so they can keep drawing.
11. **The bake is dumped between launches by default**, with an option in the export menu to store it in the
    project's folder.
12. **The knob is the truth.** *"If the user slides the slider to full, then the canvas should be set to
    full."* Nothing may silently render below the knob's resolution.
13. **A canvas that shows the previous composite for a split second after pen-up is acceptable**, provided
    the main thread never freezes: the artist must be able to move the canvas and lay the next stroke in
    that interval.
14. **Memory correctness is in scope.** *"I want to see if there are any previous memory allocation things in
    this program which are not built correctly."*

## 3. Design

*(Written after the code audit — see HANDOFF.md for the state of this pass.)*
