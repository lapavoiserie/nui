# The node model

The vocabulary both contracts express. These names are normative: a backend that
adopts `nui` uses them, so that `getViewType` here and `getType` there stop being
two words for one idea.

| Term | Type | Meaning |
|---|---|---|
| **type** | `String` | The discriminant a renderer switches on: `"VStack"`, `"Text"`, `"Button"`… |
| **children** | ordered, 0..n | Order is significant. A node with no children is a leaf. |
| **key** | `String?` | Stable identity among siblings. `null` means positional identity. |
| **property** | typed, by key | `String` / `Int` / `Float` / `Bool`, plus a presence test. |
| **modifier** | ordered list | `(type, params)`. Order matters — a border after a padding is not a border before it. |
| **action** | id + invoke | An opaque identifier; the closure stays on the Haxe side. |
| **rebuild** | signal | "The tree changed, re-read it." Pull mode only. |

## Text is a property

There is no `getText` accessor. A `Text` node carries a `"text"` property like any
other. Both `sui` and `aui` grew a special accessor for it independently, and it
buys nothing — a renderer that already reads properties can read this one.

## Keys earn their place

`key` looks optional until a control has state of its own. Without it, a
reconciler that identifies nodes by position destroys and rebuilds a control that
merely moved — and on a text field that means **losing focus and caret while the
user is typing**. `sui` hit exactly this and worked around it by deriving its node
identity from a stable property; `nui` makes the key explicit instead.

Set one on anything interactive, and on list rows.

## Modifiers are a list, not a map

```haxe
node.modifier({type: "padding", floats: [12]})
    .modifier({type: "border", floats: [1], strings: ["#333"]});
```

A map would lose the order, and the order is the semantics. `sui` and `aui` both
model it as an ordered chain; `qui` currently has no chain at all — its modifiers
are no-ops that return `this` — which is one of the gaps [adopting](adopting.md)
has to close.

## Actions never cross as closures

A node exposes an action **identifier**, and an invoke entry point. The closure
itself stays in Haxe.

This is not stylistic. A Haxe closure held only by native code is invisible to the
hxcpp GC and will be collected under you. Both `sui` and `qui` hit this and both
solved it the same way — a registry on the Haxe side, an id across the boundary.
The model bakes that in so the third backend does not have to rediscover it.
