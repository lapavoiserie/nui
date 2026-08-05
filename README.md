# nui — shared node model for La Pavoiserie

The vocabulary a view tree is described with, and the two contracts a renderer
consumes it through. Shared by the platform UI libraries — `sui`, `aui`, `wui`,
`cui`, `qui` — and sitting above [`rui`](https://github.com/lapavoiserie/rui),
which owns state and change propagation.

`nui` describes **what a node is**. It renders nothing.

## Two modes, because one is not enough

A view tree is consumed in one of two ways, and which one is not a matter of
taste — it is dictated by the host:

- **Pull** — the host diffs and re-renders on its own (SwiftUI, Jetpack Compose).
  The native renderer walks the tree on demand and asks for one thing at a time.
  Diffing on the Haxe side would duplicate work the framework already does.
  → [`NodeSource<Node>`](docs/pull-mode.md)
- **Push** — the host diffs nothing (Qt/Silica, a terminal). It has to be *told*
  what changed, so Haxe holds the tree, compares it with the previous one, and
  applies targeted patches.
  → [`Node`](docs/push-mode.md) + `PropValue` + `NodeSink<Native>`

Both express the same vocabulary: `type`, `children`, `key`, typed properties, an
ordered modifier chain, actions.

```haxe
import nui.Node;
import nui.PropValue;

var view = new Node("VStack")
    .child(new Node("Text").prop("text", PString("Bonjour")))
    .child(new Node("Button", "add").prop("label", PString("Ajouter")));
```

**Documentation:** `docs/` (docsify — `docsify serve docs`, or any static server).

## Install

Usually transitive: a backend that has adopted the model declares it. Standalone:

```bash
haxelib git nui https://github.com/lapavoiserie/nui
```

## Status

Young. The vocabulary and both contracts are defined and covered by
`test/Check.hx` (23 checks, including a toy implementation of each contract to
prove both are satisfiable):

```bash
haxe -cp src -cp test -main Check --interp
```

No backend has adopted it yet — that is the next step, `aui` first, since its
existing bridge is a strict subset of `sui`'s and the gap is pure filling-in.

## License

MIT.
