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

## `cui` — a pull candidate

`cui` renders with `measure(constraint)` then `render(buffer, area)` into a cell
buffer, redrawing wholesale on a dirty flag. It consumes a tree and patches
nothing.

That reads at first like "neither contract fits", but by the criterion that
actually decides — does the host preserve widget state across a rebuild? — a
terminal has **no widget state to lose**, so repainting from a freshly walked
tree costs nothing. `cui` is therefore a natural **pull** candidate, closer to
SwiftUI in this one respect than to Qt.

Still left open on purpose: confirm it once the others have adopted, with
evidence, rather than forcing the fit in advance.

## `wui` — blocked

`wui` runs no Haxe at runtime: its generator transpiles the view tree to C++
statics at compile time and the produced project links no hxcpp. There is nothing
for a runtime contract to attach to until that changes.
