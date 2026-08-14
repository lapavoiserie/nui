# Adopting nui

`nui` was extracted from what three backends had already built, so adoption is
mostly renaming and filling in — not redesign. What follows is the honest gap per
backend, as surveyed before the model was written.

## `sui` — pull, reference implementation

Its `ViewNodeBridge` already covers the whole contract: tree navigation, typed
properties, the modifier chain with a `String` accessor, actions by id, `rebuild`.
It is the most complete of the three, having been pushed all the way by a live
protocol renderer.

**Gap: no `keyOf`.** Identity is reconstructed by deriving the node id from a
stable property, because without it SwiftUI destroyed a text field the user was
typing in. Exposing the key directly replaces a workaround with the real thing.

Naming to align: `getViewType` → `typeOf`, `getChildCount`/`getChild` →
`childCount`/`childAt`, `getTextContent` → the `"text"` property.

## `aui` — pull, a strict subset

Its twelve bridge functions each have an exact `sui` equivalent. Nothing to
redesign; three things to add:

- **typed properties** — it exposes `getProperty:String` only, so every consumer
  parses
- **`modifierString`** — it has the `Float` accessor but not the `String` one
- **`keyOf`**

This is why `aui` should adopt first: if it takes only filling-in, the extraction
was not tailored to `sui`.

## `qui` — push, reference implementation

Its `VNode` / `Renderer` / `Reconciler` is the push contract, device-validated,
including the two things pull mode has no answer for: reactive properties and
read-back callbacks.

**Gap: no modifier chain.** `qui.View`'s modifiers are no-ops returning `this`, so
nothing crosses. Giving it a real ordered chain is the one piece of genuine work.

Naming to align: `VNode` → `Node`, and `PropValue`'s integer tags → the enum.

## `cui` — pull, confirmed

`cui` renders with `measure(constraint)` then `render(buffer, area)` into a cell
buffer, redrawing wholesale on a dirty flag. It consumes a tree and patches
nothing.

That reads at first like "neither contract fits", but by the criterion that
actually decides — does the host preserve widget state across a rebuild? — a
terminal has **no widget state to lose**, so repainting from a freshly walked
tree costs nothing. `cui` is therefore a natural **pull** candidate, closer to
SwiftUI in this one respect than to Qt.

Confirmed since: `cui` implements `NodeSource`, and `pui` reached the same answer
independently. `mui/docs/adding-a-backend.md`, which filed a terminal under push,
has been corrected.

## `pui` — pull, and the second library that draws its own widgets

`pui` owns its surface on five platforms and rebuilds its whole tree on any
write. What has to survive a rebuild — focus, scroll offset, caret, animation
phases — lives in a store indexed by path rather than in the views, so by the
criterion above there is no widget state at all: **pull**, and no `NodeSink`,
because push exists to patch retained controls and `pui` has none.

Two of its answers are richer than `cui`'s. `keyOf` returns a real key, since a
`pui` view can be `identifiedBy(...)`. And `rebuild()` marks a build bit rather
than doing nothing, because `pui` distinguishes repaint from relayout from
rebuild.

One asymmetry is worth recording, because it is the first time a backend has had
it. `pui` holds decoration as **fields** applied in a fixed order by `View.paint`,
not as an array the application ordered. So the chain it emits is synthesised and
always canonical — pad, fill, stroke, fade, cut. Replaying it reproduces what was
drawn; reading it cannot recover an order that was never stored, because there
was never a different one.

## `wui` — blocked, and it will land in push

`wui` runs no Haxe at runtime: its generator transpiles the view tree to C++
statics at compile time and the produced project links no hxcpp. There is nothing
for a runtime contract to attach to until that changes.

When it does, it implements **push**, not pull — despite sitting next to `sui` and
`aui` among "native declarative UI" backends. **WinUI 3 is retained-mode**: you
build a XAML control tree once and mutate it; it neither rebuilds nor diffs the
way SwiftUI and Compose do. Its own generated C++ already says so:

```cpp
s_count_listeners.push_back([text_3]() {
    text_3.Text(winrt::hstring(L"Count: " + std::to_wstring(s_count)));
});
```

A listener capturing a **retained** control and mutating it — the push pattern,
hand-written by the macro. Handing WinUI a tree to re-walk would destroy and
recreate controls on every change, exactly as on Qt.

That is worth stating because the wrong criterion gives the wrong answer here:
XAML *looks* declarative. Ask instead whether the host preserves widget state
across a rebuild — WinUI does not rebuild at all.
