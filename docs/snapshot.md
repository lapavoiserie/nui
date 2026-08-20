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
