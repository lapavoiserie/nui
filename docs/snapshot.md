# Snapshot — the tree as pure data

A live `Node` cannot leave the process: its props carry closures and thunks,
its children may be a thunk themselves. A **detached surface** — a widget
another process samples, a companion view on another machine — needs the tree
as *data*, with every closure replaced by something that can cross: an
integer. That is the pattern every boundary in this ecosystem already settled
on (`NodeSource.actionId`/`invokeAction`, wui's callback ids over the C ABI,
qui's `Bridge.emit(id)`), stated once for whole trees.

```haxe
var table = new nui.Snapshot.ActionTable();
var snap  = nui.Snapshot.project(tree, table);   // closures -> ids, thunks sampled
var wire  = nui.Snapshot.toJson(snap);           // haxe.Json both ways

// ... on the far side, an id comes back:
table.invoke(id);            // a plain handler
table.invoke(id, "hello");   // a typed one; the table knows the shape
```

## What the shape holds

`SnapshotNode` is `haxe.Json`-safe by construction: `type`, `key`, scalar
`props`, an `actions` map (prop name → id), `modifiers` (already plain data),
`children`. `PReactive` thunks are resolved at projection time — a snapshot is
*sampled*; liveness is the co-resident model's business. Children thunks are
forced, for the same reason sui's `classify` forces the lazy parts: a
snapshot classifies against a complete picture.

## The action table

- **One instance per consumer.** Never a static registry: two detached
  surfaces must not share a namespace.
- **Ids are monotonic and never reused.** A stale id names a hole — the
  policy every backend's handle table keeps.
- **Ids are stable by place.** `project` keys each action by its node path
  and prop, so the same button in the same slot keeps its id across
  generations (closure updated) — a tap racing a re-projection does what the
  unchanged button says. Keyed children keep ids across reorders.
- **A late tap on a *retired* id is data.** Only a control that left the
  tree retires; `invoke` on its id degrades with a word, never a crash.
- **Types live in the table, not on the wire.** The argument crosses as a
  string; the recorded callback shape says how to read it.

## Keeping one current: `Follow`

A snapshot is *sampled*, which raises the question the projection itself does
not answer: sampled **when**? Nobody on the far side will notice that a cell
changed — there is no reconciler over there, and often no process of ours at
all — so noticing is this side's job.

```haxe
var follower = nui.Follow.tree(
    () -> buildMyTree(),                      // read cells freely
    snap -> channel.send(Snapshot.toJson(snap))
);
```

The thunk runs inside a `rui.Effect`, so every cell it reads subscribes this
surface — and only this surface — to its own state. A write re-projects and
publishes; nothing else re-projects. Dependencies are recaptured on every run,
so a branch that starts reading a different cell is followed without ceremony.

Three properties are decided here rather than by each caller:

- **The table outlives the projections.** `Follow` keeps one `ActionTable` for
  the life of the follower and never clears it between runs. Combined with ids
  keyed by place, a tap that arrives after a re-projection invokes the current
  closure instead of finding a hole. Clearing was exactly how the first
  interactive companion turned every keystroke into a stale remote tap.
- **Whether the first run publishes** is `publishFirst`, and it is a real
  question rather than a knob. A second process that follows the same
  declaration — an iOS widget extension handling a tap — would otherwise
  publish its own pre-tap state over the picture the application put there.
  Pass `false` when you are following in order to *act*, not to show.
- **Sampling on demand** is `sampleNow()`, for a host that pulls rather than
  receives — Android asks for a widget's picture when it decides to draw.

`dispose()` ends it. What a backend keeps for itself is the callback: what to
do with the picture is the only part that differs between a wire, an App Group
container, and a launcher.

## The far side: `inflate`

A received snapshot becomes an ordinary `Node` tree — which is what makes a
remote renderer nearly free instead of a project: any backend's existing
`NodeRenderer` draws it, and every action prop inflates as a closure handing
its id (plus the control's live value) back to the channel you supply.

```haxe
var tree = nui.Snapshot.inflate(nui.Snapshot.fromJson(wire),
    (id, arg) -> channel.sendAction(id, arg));
// hand `tree` to the backend's NodeRenderer; callbacks route themselves
```

The callback *shape* stayed on the serving side, in its table; here every
action is `PCallbackString` (the shape that carries anything), and the table
parses the argument against the recorded truth.
