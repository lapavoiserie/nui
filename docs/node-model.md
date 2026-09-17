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

## Nodes whose props carry rules

Most canonical nodes are a name and a few scalar props. A few carry rules every
backend must apply the same way, so the rules live here rather than in six
renderers.

### `Text`

`text` (required), and how it is set: `scale` (`title`, `subtitle`, `body` — the
default — or `caption`), `family` (a font the receiving application ships),
`weight` (100 to 900), `italic`, and `numbers` (`tabular` for digits of one
width, so a timecode does not jitter as it counts). `nui.TextStyle` says what
each means and what an unknown value falls back to.

**Props, not modifiers.** The modifier chain carried a "font" for a while, and
that is exactly where the six backends drifted apart: one sent a step of its own
vocabulary in `strings`, another read a pixel size from `floats`, a third
discards inbound modifiers on purpose because it has properties and not
modifiers, and a fourth emitted none at all — so a heading crossed as ordinary
text on five backends out of six.

**A family is a name, never a file.** A renderer uses it when the application it
belongs to ships that family, and draws its own default otherwise, silently. A
picture is pulled by content and verified because it is data on a screen;
installing a typeface is an act on a machine. A backend with one font — a
terminal — honours `weight`, `italic` and `numbers`, and ignores the rest.

### `Picker`

`label` (optional), `selectedIndex` (`Int`, `-1` for none), `onSelect` (an index),
and **one `Text` child per option**. `onSelect` is an action like `onClick`;
after a wire it arrives as a string callback and the index is its text. A
renderer applies a received `selectedIndex` only when that option exists and the
list is closed, and never reports a selection it made itself as a choice.

### `Image`

`src` (required), `alt` (required — `""` declares the picture decorative),
`width` and `height` in points (one given, the other follows the picture's
ratio), `fit`: `contain` (default), `cover` or `fill`.

`src` has a scheme, parsed and judged by `nui.ImageSource`:

| scheme | names | built here | received |
|---|---|---|---|
| `asset:path` | a file shipped in the application, optionally `#sha256=…` | yes | yes |
| `blob:sha256=…` | a picture made at run time, served by its sender | yes | yes |
| `https://…` | a picture on the web | yes | only from a trusted host |
| `data:image/png;base64,…` | a small picture in the tree | yes | up to 256 KiB |
| `file:///…` | a local path | yes | never |

Anything else is not loaded. Whatever is not loaded, cannot be decoded or is
still arriving is drawn as the `alt`, never as a broken-image glyph. A received
`https:` is refused unless the panel trusts the host because a panel that loaded
any URL a tree named would contact any host its sender chose.

### `Button`

`label`, `onClick`, and `icon` (optional): a name from `nui.Icons`, drawn beside the
label, or alone when the label is empty — then the icon's name is what a screen
reader says. A backend that draws no icons draws the label. One icon, as a prop
rather than a child, because a button has one icon and one label, and naming it for
accessibility is then the renderer's job, not the tree's.

### `Icon`

`name`, from `nui.Icons.NAMES`, and `label` (optional; absent, the name is what a
screen reader says). Each backend maps the names to its platform's own icons, and
colours the icon like text. A received name it does not know is drawn as its
label.

### `TextInput`

`text`, `placeholder` (optional), `onText`, which carries the whole value and
not the key, and `onSubmit` (optional), which carries nothing and fires when
the field is submitted — Enter, or whatever a platform means by it.

**Both are optional, and which ones a node carries is the whole design.**
`onText` says *this value is live*: every keystroke is worth hearing. That is
right for a filter, a search box, a name shown elsewhere on the panel.

A field with **`onSubmit` and no `onText`** is the other kind: one whose effect
is an act. A page address that would load on every letter, a file path, a
project name that saves. The renderer keeps what is being typed and reports
nothing until it is submitted; nothing crosses until the person says so. This is
the shape a panel used to hand-roll as "a draft plus a Rename button", which is
a good interface and should not have to be built twice.

A field with neither reports nothing and is read-only in practice.

### `SecretInput`

`placeholder`, `isSet` (`Bool`, optional — whether a value is already stored),
`onSecret`, which carries the value **once**, on submission, and `whenRefused`
(optional — see below).

`whenRefused` is what a panel is shown where this field may not be offered at
all: **the application's own words**, in its own language. The refusal happens
far from the application, in whatever is projecting the tree, and that has no
idea what language the application speaks. A library that writes the user's
prose is the wrong division of labour — it decides the refusal, the application
says it. Without one, the projector writes a sentence of its own rather than
nothing: a refusal nobody can read is worse than one in the wrong language.

**It has no `text`, and that is the definition of the type rather than a rule a
renderer must remember.** A stream key, a password, a token: the value is typed
here and leaves through `onSecret`. It never enters the tree, so there is
nothing to republish on every frame, nothing for a log to print from a node,
nothing to redraw on a screen being captured, and "a received value is not
applied" is vacuous — there is no received value.

**Why a type and not `TextInput` with a flag.** A forgotten flag *fails open*: a
renderer that does not know it draws an ordinary field with the secret in clear,
and nothing says so. An unknown type *fails closed* — the renderer draws its
"unknown type" marker, loudly, and nobody reads the key off a screen. For an
ordinary defect that is a preference; for a secret it is the difference between
a bug and a leak.

What a renderer owes it:

- **masked** display, and no copy to the clipboard;
- **nothing reported per keystroke** — one report, on submission;
- **cleared after submitting**, and on losing focus.

`isSet` exists so a panel can say "saved — type to replace" without the value
crossing. It tells a remote observer that a key exists; nothing more. A prefix
of the value — "…ab12", to reassure — is not `isSet` and does not belong in a
tree.

**On the wire.** `onSecret` is the one action whose argument is never written
down: the name is the marking, so a projector derives the set of secret action
ids from it and every trace prints `[secret, N characters]`. Deriving it from
the name rather than from a flag set at each logging site is the same choice as
the type itself — nobody can forget what they do not have to do.

**Where it may be shown at all.** A `SecretInput` is not projected onto a
channel that cannot carry its answer: not loopback, not end-to-end encrypted, no
field. The far side is told to set it on the machine itself. Refusing at
submission instead would be too late — the secret has already been typed, in
front of whatever was watching the screen.

Two limits worth stating rather than hiding: a string cannot be wiped from
memory once it exists, only dereferenced; and masking protects the value on
screen, not the moment it is typed in front of a capture.

**A received `text` is not applied to a field somebody is typing in** — the same
rule a `Picker` has for a list that is open, and for the same reason. The value
belongs to the sender, but during typing the sender is behind: a renderer that
reapplied `text` on every frame would put the previous value back under the
caret between two keystrokes.

The defect that produced this paragraph, found by the Farceur session in a
transition editor: type `A`, let the tree be rebuilt, type `B`, and the field
reads `Fondu BA`. The caret was not lost — the text went backwards underneath
it, and the caret was then clamped to the shorter value it could see. So what a
field shows while it has focus is what was typed into it; when focus leaves, the
value goes back to whoever owns it — including their version of it, if they
disagreed with the edit.
