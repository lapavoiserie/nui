# nui

> The shared node model of La Pavoiserie.

What a view tree *is* — type, children, identity, typed properties, ordered
modifiers, actions — and the two contracts a renderer consumes it through.
It renders nothing itself.

- **Pull** for hosts that diff themselves — SwiftUI, Compose
- **Push** for hosts that diff nothing — Qt/Silica, terminals
- One vocabulary, so a backend describes a tree the same way as its siblings
- Sits above `rui`, which owns state and change propagation

[GitHub](https://github.com/lapavoiserie/nui)
[Get Started](node-model.md)
