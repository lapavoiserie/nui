package nui;

/**
	**Pull mode** — the contract a declarative host reads a Haxe view tree through.

	For a host that already diffs and re-renders on its own (SwiftUI, Jetpack
	Compose). The native renderer walks the tree on demand, asking for one thing
	at a time; Haxe answers. Nothing is pushed, nothing is diffed on the Haxe
	side — that would duplicate work the framework already does.

	`Node` is the host's handle on a live Haxe view: `sui` passes its own `View`,
	`aui` passes an opaque `Long` across JNI. Hence the type parameter.

	```haxe
	// a renderer, in pseudo-code
	function render(src:NodeSource<N>, n:N) {
	    switch (src.typeOf(n)) {
	        case "Text":   nativeText(src.stringProp(n, "text"));
	        case "VStack": for (i in 0...src.childCount(n)) render(src, src.childAt(n, i));
	    }
	}
	```

	**The tree must stay reachable from Haxe while the host holds handles into
	it.** A node reached only from native code is invisible to the GC; keep the
	root referenced on the Haxe side.
**/
interface NodeSource<Node> {
	/** The root of the current tree. **/
	function root():Node;

	/** Re-evaluate the tree. The host then re-reads what it needs. **/
	function rebuild():Void;

	/** Discriminant: `"VStack"`, `"Text"`, `"Button"`… **/
	function typeOf(n:Node):String;

	/**
		Stable identity among siblings, or `null` for positional identity.

		Hosts that rebuild their view identity from scratch need this, or they
		destroy and recreate a control that merely moved — which on a text field
		loses focus and caret while the user is typing.
	**/
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

	/**
		Opaque identifier for the node's action, or a negative value if it has
		none. The closure itself stays on the Haxe side — **never hand a closure
		pointer to native code**, it is invisible to the GC.
	**/
	function actionId(n:Node):Int;

	/** Run the node's action. **/
	function invokeAction(n:Node):Void;
}
