# Push mode — `Node`, `PropValue`, `NodeSink<Native>`

For a host with **stateful widgets and no diff of its own**: Qt/Silica. It has to
be told what changed, so Haxe holds the tree, compares it with the previous one,
and applies targeted patches — anything coarser would destroy and recreate
controls that merely moved, losing focus, caret and scroll position.

## The tree

```haxe
class Node {
    var type:String;
    var key:Null<String>;
    var props:Map<String, PropValue>;
    var modifiers:Array<Modifier>;
    var children:Array<Node>;
    var childrenThunk:Null<Void->Array<Node>>;
}
```

Built fluently:

```haxe
var view = new Node("VStack")
    .child(new Node("Text").prop("text", PString("Bonjour")))
    .child(new Node("Button", "add").prop("label", PString("Ajouter")))
    .modifier({type: "padding", floats: [12]});
```

### Deferred children

`childrenThunk` lets a list re-evaluate **only itself**. When its dependencies
change, that node's children are recomputed and re-reconciled while the
surrounding tree is never touched.

```haxe
var list = new Node("List");
list.childrenThunk = () -> [for (t in todos.get()) row(t)];
```

## `PropValue`

```haxe
enum PropValue {
    PString(v:String);  PInt(v:Int);  PFloat(v:Float);  PBool(v:Bool);
    PCallback(fn:Void->Void);
    PCallbackString(fn:String->Void);
    PCallbackFloat(fn:Float->Void);
    PCallbackInt(fn:Int->Void);
    PReactive(thunk:Void->PropValue);
}
```

The last four have **no equivalent in pull mode**, and both earn their place.

**`PReactive`** carries a thunk instead of a value. The renderer wraps the
application of *that one property* in `bindReactive`, which is what gives
per-binding granularity: a write re-applies one property, with no tree walk and no
diff.

**The read-back callbacks** (`PCallbackString` / `Float` / `Int`) are handed the
**live value of the native control** rather than what Haxe last wrote. That is what
makes a two-way control correct: at the moment of the tap, the truth is what is in
the field.

`PropValueTools.resolve` collapses a thunk (nested ones included) to a concrete
value; `PropValueTools.equals` compares the **resolved** contents, so a
re-evaluated thunk that produced the same thing does not read as a change.
Callbacks compare by reference.

## The sink

```haxe
interface NodeSink<Native> {
    function create(node:Node, parent:Null<Native>):Native;
    function applyProp(target:Native, key:String, value:PropValue):Void;
    function applyModifiers(target:Native, modifiers:Array<Modifier>):Void;
    function insert(parent:Native, child:Native, index:Int):Void;
    function remove(parent:Native, child:Native):Void;
    function destroy(target:Native):Void;

    var bindReactive(get, set):(Void->Void)->Void;
}
```

`Native` is whatever the backend manipulates — a Silica item, a widget handle, a
buffer region.

## Granularity is one hook

`bindReactive` decides how fine updates are, and it is the only place that
decides.

**Default — coarse.** Applied immediately:

```haxe
function(fn) fn();
```

The render effect re-runs, the tree is rebuilt and reconciled. This suits a
`body():View` contract, where the app hands back plain values.

**Fine — per binding.** Each application gets its own reactive effect:

```haxe
sink.bindReactive = fn -> new rui.Signal.Effect(fn);
```

Now a write re-applies exactly one property. No tree walk, no diff. This is how
`qui` drives Silica, validated on a device: adding a list item re-runs the list's
own binding while the surrounding view is never touched.

Both granularities use the same tree and the same sink. Only the hook changes.
