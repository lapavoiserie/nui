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

**And the names are a closed set** (`nui.Modifiers`): `padding`,
`backgroundColor`, `foregroundColor`, `border`, `opacity`, `clip`, `width`,
`height`, `flex`. That had to be written down, because this page said a modifier is
ordered and typed and never said what `type` may *be* — so six backends each
invented their own, and by the time anybody counted they had drifted:

| | emitted |
|---|---|
| `pui` | backgroundColor, border, clip, opacity, padding |
| `cui` | alignment, backgroundColor, border, foregroundColor, height, padding, width |
| `aui` | backgroundColor, bold, border, cornerRadius, font, foregroundColor, italic, opacity, padding, paddingHorizontal, paddingVertical |

`pui` never sent a `foregroundColor`, so text colour did not cross from it at
all. `aui` sent `font`, `bold` and `italic` as modifiers while the fonts canon
above had already made weight, italic and family **props of `Text`** — the same
thing said twice, in two vocabularies, and a receiver sees whichever it happens
to read.

Three things are deliberately *not* in the set. A free-standing `cornerRadius`,
because a radius belongs to the thing being rounded and `backgroundColor` and
`border` each carry theirs. `font`, `bold` and `italic`, because `Text` owns
them. And `alignment`, because it is not a decoration — it changes how a parent
places a child, and no two backends meant the same thing by it.

## A colour is a role or its components

```haxe
Color.role(Danger)        // what it is FOR — the receiver resolves it
Color.rgb(200, 50, 60)    // what it IS — nobody resolves anything
```

`backgroundColor`, `foregroundColor` and `border` carry a `nui.Color`, which is
one of those two and crosses as a word: `"role:danger"` or `"#c8323c"`.

**A role stays a role.** An application that resolved `Danger` to `#C8323C`
would send that number to a panel in dark mode, or in high contrast, or on a
platform whose accent the person chose themselves — and nothing in it would say
it had ever meant "danger". Same argument as the scale, and the same as "a
family is a name, never a file": the wire carries the word, and whoever draws it
resolves it with what they have.

Eight roles — `accent`, `danger`, `warning`, `success`, `surface`, `text`,
`muted`, `border` — because each resolves to something real on at least two
platforms. **Named colours do not cross.** `Red` is an rgb with extra steps: it
cannot resolve to anything per-platform, and carrying it would make it look
semantic when it is not. An application that wants red says `rgb` and means it.

A backend that cannot represent a colour exactly approximates and says so on its
own page — `cui` has sixteen and picks the nearest. That is the answer this page
already gives for a terminal with one font, and the place to learn it is the
backend's documentation rather than a surprise on screen.

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

Two of these have a Haxe form that is not the wire form: an application writes
`true` for tabular digits and picks a scale from four named constants, while
the wire carries `"tabular"` and a lowercase word. `nui.Numbers` and
`nui.Scale` are those two values as types, and the conversion is the cast:

```haxe
var numbers:nui.Numbers = true;          // an application writes a Bool
node.prop("numbers", PString(numbers));  // the wire gets "tabular"
if (numbers) …                           // painting code reads a Bool again
```

Nothing new is decided here — `TextStyle.scaleOf` and `TextStyle.isTabular`
have always been the rule. What changes is that a backend no longer calls them
by hand at each boundary, which is where a describer and a renderer come to
disagree about one value. A field typed `nui.Scale` cannot be described as
anything but a scale.

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

### `Tabs` and `Tab`

`Tabs` carries `selectedIndex` (`Int`) and `onSelect` (an index), and its
children are `Tab` nodes. A `Tab` carries `label` and, optionally, `icon` — a
name from `nui.Icons`.

**Only the selected tab carries its page**, as its child. The others are empty.

```
Tabs  selectedIndex: 1  onSelect: …
  Tab  label: "Source"
  Tab  label: "Transitions"
    VStack  …the page…
  Tab  label: "Diffusion"
  Tab  label: "Projet"
```

That one rule does three jobs at once, which is why it is the rule.

**A snapshot stays one picture.** `pui` and `cui` used to *flatten* a tab view
to its selected page and say so in a trace, because describing four pages
describes views nobody is looking at. Here there is nothing to flatten: the
tree already holds one page, and the tab titles — which are what a receiver
needs to draw the bar — are all there.

**The selection is the application's**, like a `Picker`'s index. It is in the
tree and it comes back through `onSelect`, so a tap somewhere else entirely —
a click on a source in a video monitor — can bring the Source tab back by
writing a cell. A selection living inside the control could not be reached that
way.

**A page nobody chose cannot leak.** The Broadcast tab of a régie holds a
`SecretInput`; an unselected tab has no children, so there is nothing in the
tree to project, redact or forget to redact. The guarantee is structural rather
than a rule someone has to remember — which is the same argument `SecretInput`
itself makes about not having a `text`.

A backend with no tab control draws the bar as a `Picker` over the page: the
index and the action are the same two things.

### `Disclosure`

`title`, `summary` (optional) and `open` (optional, `Bool`): a heading that is
always visible, with a line on the right that says what is inside, and children
that are shown or not.

```
Disclosure  title: "Position précise"  summary: "640, 302 · ×1,6 · 0°"
  VStack  …four sliders…
```

**The summary is the application's sentence**, not a count. It says what the
section holds *now* — the position, the scale, the rotation — so a reader knows
whether to open it without opening it. A library writing that sentence would be
writing in a language it does not know, which is the same argument
`SecretInput.whenRefused` makes.

**Whether it is open is the receiver's**, and it is not in the tree unless the
application puts it there. A panel that opened a section is a panel whose
person opened it, not a fact about the thing being described — and the machine
that sent the tree has no business deciding what is unfolded on somebody else's
screen. `open` exists for the case where the application *does* want to say,
and a receiver honours it as the state to start from.

That state has to **survive a rebuild**. An application that rebuilds its tree
on every change — which is what a régie does — would otherwise fold every
section on each keystroke. A backend keeps it under the view's place, not in
the object: `pui` has a store by path, and identity there is the place and
never the pointer.

Children are always *described*, whether it is open or not: what a section
holds does not change because somebody folded it, and a receiver that draws it
open needs them. A section holding a secret is a different question, and the
answer is the same as everywhere — a `SecretInput` carries no value.

### `Slider`

`value`, `min`, `max`, `onValue`, and **`orientation`** (optional):
`horizontal`, the default, or `vertical`.

A vertical slider runs **low at the bottom**. That is not a presentation
choice: a fader that grew downwards would read as the opposite of every mixing
desk ever built, and a tree that crossed to a machine drawing it the other way
would be showing the wrong value, not a different shape. The orientation is
*how it is laid out*; which end is the minimum is *what it means*.

A backend with only a horizontal slider draws one, and the value is still the
value.

### `Picker`

`label` (optional), `selectedIndex` (`Int`, `-1` for none), `onSelect` (an index),
and **one `Text` child per option**. `onSelect` is an action like `onClick`;
after a wire it arrives as a string callback and the index is its text. A
renderer applies a received `selectedIndex` only when that option exists and the
list is closed, and never reports a selection it made itself as a choice.

**`style`** (optional) says how it should be *presented*: `segmented` asks for
the choices side by side, as a row of buttons, rather than a list that opens.
Two or three short labels — Preview/Program, 30/60 — read better that way, and
a dozen sources do not.

This is a **hint**, and it fails soft: a backend with no segmented control
draws an ordinary picker, and nothing is lost but the shape. That is the right
answer *here* and the wrong one for `PasswordInput`, and the difference is
worth naming — a forgotten presentation shows the same choices differently, a
forgotten password shows the password. A flag fails open only where opening is
harmless.

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

### `PasswordInput`

`text`, `placeholder` (optional), `onText`, `onSubmit` (optional) — a
`TextInput` in every respect but one: **it is drawn masked**, one mark per code
point, and never shows what it holds.

The value is in the tree. That is the whole difference from `SecretInput`
below, and it is a difference of purpose rather than of degree:

| | `PasswordInput` | `SecretInput` |
|---|---|---|
| the value | in the tree, bound, read back | never in the tree |
| who owns it | the application | the person typing, until they submit |
| what it is for | a password field an application manages | a key, a token, entered once |

An application that wants to pre-fill a field, read it back, validate it as it
is typed or keep it in its own state wants this one. An application that must
never hold the value wants the other.

**Why a type and not `masked: true` on `TextInput`.** The same reason
`SecretInput` is a type: a renderer that does not know the flag draws the
password in clear, and nothing says so. An unknown type draws its marker
instead. A flag fails open; a type fails closed. It costs nothing in an
implementation — on a renderer that draws its own text it is one method
overridden — because what differs is how it is shown and not what it does.

Everything `TextInput` says still holds, including that a received `text` is
not applied to a field somebody is typing in.

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
