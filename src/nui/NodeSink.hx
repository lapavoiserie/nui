package nui;



/**
	**Push mode** — the contract an imperative host is driven through.

	For a host that diffs nothing (Qt/Silica, a terminal): it has to be *told*
	what changed. Haxe builds a `Node` tree, compares it with the previous one,
	and calls the operations below for the differences only.

	`Native` is whatever the backend manipulates — a Silica item, a widget
	handle, a buffer region.

	## Granularity

	`bindReactive` is the single hook that decides how fine the updates are.
	Left at its default, a property is applied immediately and the tree is
	re-reconciled whenever the render effect re-runs — the coarse path, which
	suits a `body():View` contract.

	Set it to wrap each application in a reactive effect and the granularity
	becomes per-binding: a write re-applies **one property**, with no tree walk
	and no diff. That is how `qui` drives Silica, validated on device.

	```haxe
	sink.bindReactive = fn -> new rui.Signal.Effect(fn);
	```
**/
interface NodeSink<Native> {
	/** Materialise a node. Children are handled by `insert`. **/
	function create(node:Node, parent:Null<Native>):Native;

	/**
		Apply one property.

		`type` is the node's type — the same string `create` received. It is
		passed rather than looked up because **a native handle does not
		necessarily know what it is**: a Silica item carries no type name, so
		without this every adopter keeps a side table of handle to type. Hosts
		that can recover the type from the handle are free to ignore it.

		The value may still be `PReactive` — read it with
		`PropValueTools.asString` and friends, which are null-safe, and wrap the
		application in `bindReactive` so the binding owns its own effect.
	**/
	function applyProp(target:Native, type:String, key:String, value:PropValue):Void;

	/** Apply the ordered modifier chain. Takes `type` for the same reason as `applyProp`. **/
	function applyModifiers(target:Native, type:String, modifiers:Array<Modifier>):Void;

	function insert(parent:Native, child:Native, index:Int):Void;
	function remove(parent:Native, child:Native):Void;
	function destroy(target:Native):Void;

	/**
		Wraps every property application. Default is immediate:
		`function(fn) fn();`
	**/
	var bindReactive(get, set):(Void->Void)->Void;
}
