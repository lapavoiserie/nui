# Pull mode — `NodeSource<Node>`

For a host that **diffs and re-renders on its own**: SwiftUI, Jetpack Compose.

> See [pull and push explained step by step](pull-vs-push.html) if you want the
> sequence before the signatures.

The native renderer walks the tree on demand, asking for one thing at a time.
Haxe answers. Nothing is pushed and nothing is diffed on the Haxe side — that
would duplicate work the framework already does.

```haxe
interface NodeSource<Node> {
    function root():Node;
    function rebuild():Void;

    function typeOf(n:Node):String;
    function keyOf(n:Node):Null<String>;

    function childCount(n:Node):Int;
    function childAt(n:Node, index:Int):Node;

    function hasProp(n:Node, key:String):Bool;
    function stringProp(n:Node, key:String):String;
    function intProp(n:Node, key:String):Int;
    function floatProp(n:Node, key:String):Float;
    function boolProp(n:Node, key:String):Bool;

    function modifierCount(n:Node):Int;
    function modifierType(n:Node, index:Int):String;
    function modifierFloat(n:Node, index:Int, param:Int):Float;
    function modifierString(n:Node, index:Int, param:Int):String;

    function actionId(n:Node):Int;
    function invokeAction(n:Node):Void;
}
```

## Why the type parameter

`Node` is the host's **handle** on a live Haxe view, and each host holds it
differently: `sui` passes its own `sui.View`, `aui` passes an opaque `Long` across
JNI. Parameterising avoids forcing either into a shape that suits the other.

## A renderer, in outline

```haxe
function render<N>(src:NodeSource<N>, n:N):Native {
    return switch (src.typeOf(n)) {
        case "Text":
            nativeText(src.stringProp(n, "text"));
        case "Button":
            nativeButton(src.stringProp(n, "label"), () -> src.invokeAction(n));
        case "VStack":
            var kids = [for (i in 0...src.childCount(n)) render(src, src.childAt(n, i))];
            nativeStack(kids);
        case other:
            nativeUnknown(other);
    }
}
```

The host decides when to call this. `rebuild()` is the only signal it gets: *the
tree changed, re-read what you need*.

## The trap: keep the tree reachable

The host holds handles into live Haxe objects. **A node reached only from native
code is invisible to the hxcpp GC** and will be collected while the renderer still
points at it.

Keep the root referenced on the Haxe side for as long as the host may walk it —
one strong reference at the root is enough, since it retains the whole tree.

## Read properties with the typed readers

**Do not switch on a property value yourself.** A property a node does not carry
resolves to `null`, and on a compiled target (hxcpp) `switch` on a null enum is a
**segmentation fault**, not a caught error:

```haxe
// WRONG — segfaults the first time a node lacks "text"
switch (PropValueTools.resolve(props.get("text"))) { case PString(v): v; case _: ""; }

// RIGHT
PropValueTools.asString(props.get("text"));
PropValueTools.asInt(props.get("spacing"), 0);
PropValueTools.asFloat(props.get("value"));
PropValueTools.asBool(props.get("checked"));
```

Interpreted runs never show this: `--interp` tolerates the null switch. It cost a
segfault in the first backend to adopt the contract, on a test suite that had been
green under `--interp` all along. **Run your checks on a compiled target too.**

## Typed properties

`aui`'s existing bridge exposes properties as `String` only, so every consumer
parses. `nui` requires the four typed accessors plus `hasProp`, matching what
`sui` already does. It is filling-in work, not redesign, and it removes a class of
silent parse failures.
