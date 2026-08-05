# nui

**nui** is the shared node model of the La Pavoiserie UI libraries. It answers one
question — *what is a node in a view tree?* — and provides the two contracts a
renderer consumes that tree through.

It renders nothing. Rendering belongs to each platform library; `nui` is what they
agree on so they stop describing the same tree five different ways.

```
        app : body() → view tree
                    │
    rui ────────────┼──────────── state and change propagation
                    │
    nui ────────────┴──────────── what a node is, and how it is consumed
                    │
   ┌────────────┬───┴────┬─────────────┐
 SwiftUI      Compose   Silica       terminal
  (pull)       (pull)   (push)        (push)
```

## Why two contracts

Because the host decides, not us.

**SwiftUI and Compose already diff and re-render on their own.** Handing them a
tree they can walk on demand is the natural fit; diffing on the Haxe side would
duplicate work the framework does anyway. That is [pull mode](pull-mode.md).

**Qt/Silica and a terminal diff nothing.** They have to be told what changed, so
Haxe must hold the tree, compare it with the previous one and apply targeted
patches. That is [push mode](push-mode.md).

Neither reduces to the other without losing something: pull on Silica would
rebuild the UI on every change, push on SwiftUI would duplicate its diff. So `nui`
normalises both rather than pretending one wins.

## What is shared

The [vocabulary](node-model.md) — `type`, `children`, `key`, typed properties, an
ordered modifier chain, actions, and a rebuild signal. Both modes express it; only
*who holds the tree* differs. In pull mode the node is the backend's own view
object, read through accessors. In push mode it is a `nui.Node`.

## Install

```bash
haxelib git nui https://github.com/lapavoiserie/nui
```

`nui` depends on [`rui`](https://github.com/lapavoiserie/rui) and on nothing else.

## Check

```bash
haxe -cp src -cp test -main Check --interp
```

23 checks, including a toy implementation of each contract — the point being to
prove both are satisfiable, not just declarable.
