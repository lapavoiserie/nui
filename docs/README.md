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

Because the host decides, not us. And the question that decides it is narrower
than "declarative or imperative":

> **Does the host preserve widget state across a rebuild?**

| Host | Preserves state? | Mode |
|---|---|---|
| SwiftUI, Jetpack Compose | yes, through their own diff | [pull](pull-mode.md) |
| a terminal | nothing to preserve — the buffer is repainted | pull fits |
| Qt/Silica | stateful widgets, no diff of its own | [push](push-mode.md) |

> **New to this?** [**Pull and push, explained step by step**](pull-vs-push.html) — an
> interactive walkthrough of what happens when a state changes, in each mode.

**Pull** hands the host a tree it walks on demand. Diffing on the Haxe side would
duplicate work the framework already does.

**Push** has Haxe hold the tree, compare it with the previous one and apply
targeted patches — because the host will not do it for you.

Neither reduces to the other. Pull on Qt would mean either destroying and
recreating stateful widgets on every change — losing focus, caret and scroll
position — or making the pull walk diff, which just moves the reconciler into
native code in every backend. Push on SwiftUI would duplicate its diff. So `nui`
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

29 checks, including a toy implementation of each contract — the point being to
prove both are satisfiable, not just declarable.
