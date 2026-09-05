package nui;

import nui.PropValue.PropValueTools;

/**
	The pull contract, over `nui.Node` itself.

	## Why a source over the model's own nodes

	Every backend implements `NodeSource` over *its* view type — `aui.View`,
	`sui.View`, a `cui` widget — because that is where a live tree lives when
	the application is the one drawing it. But a tree that **arrived** is
	already `Node`s: it was inflated from a snapshot, and there is nothing
	underneath it to walk.

	So a sink has two options. Convert the received tree into the backend's own
	views, which means writing that backend's `Describe` backwards and keeping
	two name tables in step — the drift that made `wui`'s native setter throw
	`label` away in silence. Or read the nodes directly, which is this: no
	table, no copy, and nothing that can disagree with itself, because reading
	`type`, `props` and `children` off a `Node` is the identity.

	## What this makes possible

	A backend whose renderer takes a `NodeSource` can draw a foreign tree
	without knowing it is foreign. That is what the contract has always
	claimed; this is the piece that lets a backend honour it.

	```haxe
	var tree = Snapshot.inflate(received, (id, arg) -> channel.send(id, arg));
	var source = new SelfSource(() -> tree);
	// hand `source` to the backend's renderer
	```

	## The thunk

	`root` is re-evaluated through the thunk rather than captured, because a
	sink replaces its tree on every generation and the renderer must see the
	new one after `rebuild` without being handed a new source.

	## Actions

	Ids are assigned per source, lazily, by walking to find action props — the
	same "never hand a closure to native code" rule every backend keeps. They
	are **positional within a generation** and not stable across rebuilds,
	which is correct here and worth saying: a received tree's *durable* ids are
	the ones `Snapshot` keyed by place on the serving side. These are only the
	handle a renderer holds between drawing a control and someone touching it.
**/
class SelfSource implements NodeSource<Node> {
	final content:() -> Node;

	var current:Node;
	var actions:Array<Node> = [];

	/** The prop names an action can hide under, in the canonical vocabulary.
		Kept here rather than guessed per call: a renderer asks `actionId`
		without knowing whether it is holding a button or a switch. **/
	static final ACTION_KEYS = ["onClick", "click", "onToggle", "onText", "onValue", "onSubmit"];

	public function new(content:() -> Node) {
		this.content = content;
		this.current = content();
		index();
	}

	public function root():Node
		return current;

	public function rebuild():Void {
		current = content();
		index();
	}

	public function typeOf(n:Node):String
		return n == null ? "" : n.type;

	/**
		A received tree carries whatever keys the serving side gave it.

		Passed through rather than dropped: the sending backend may have keyed
		its rows, and a host that rebuilds identity from scratch would
		otherwise destroy and recreate a text field that merely moved.
	**/
	public function keyOf(n:Node):Null<String>
		return n == null ? null : n.key;

	public function childCount(n:Node):Int
		return n == null ? 0 : n.resolveChildren().length;

	public function childAt(n:Node, index:Int):Node {
		if (n == null)
			return null;
		var kids = n.resolveChildren();
		return index >= 0 && index < kids.length ? kids[index] : null;
	}

	public function hasProp(n:Node, key:String):Bool
		return n != null && n.props.exists(key);

	public function stringProp(n:Node, key:String):String
		return PropValueTools.asString(resolved(n, key));

	public function intProp(n:Node, key:String):Int
		return PropValueTools.asInt(resolved(n, key));

	public function floatProp(n:Node, key:String):Float
		return PropValueTools.asFloat(resolved(n, key));

	public function boolProp(n:Node, key:String):Bool
		return PropValueTools.asBool(resolved(n, key));

	public function modifierCount(n:Node):Int
		return n == null ? 0 : n.modifiers.length;

	public function modifierType(n:Node, index:Int):String {
		var m = modifierAt(n, index);
		return m == null ? "" : m.type;
	}

	public function modifierFloat(n:Node, index:Int, param:Int):Float {
		var m = modifierAt(n, index);
		if (m == null || m.floats == null || param < 0 || param >= m.floats.length)
			return 0;
		return m.floats[param];
	}

	public function modifierString(n:Node, index:Int, param:Int):String {
		var m = modifierAt(n, index);
		if (m == null || m.strings == null || param < 0 || param >= m.strings.length)
			return "";
		return m.strings[param];
	}

	/**
		Whether a modifier parameter is actually there.

		Not in the pull contract — it cannot express an optional parameter yet —
		but every source is asked it, so answering is cheaper than making each
		caller special-case a received tree.
	**/
	public function modifierHasParam(n:Node, index:Int, param:Int):Bool {
		var m = modifierAt(n, index);
		if (m == null || param < 0)
			return false;
		// Presence, not emptiness. A float slot cannot be null on a static
		// target, so being within the array IS the answer for floats; a string
		// slot can be, and an absent string is not the same as an empty one.
		if (m.floats != null && param < m.floats.length)
			return true;
		return m.strings != null && param < m.strings.length && m.strings[param] != null;
	}

	public function actionId(n:Node):Int {
		if (n == null || !carriesAction(n))
			return -1;
		return actions.indexOf(n);
	}

	/**
		Run whatever the node carries.

		The shapes are tried in the order a control is likely to hold them, and
		a node holding none is a shrug rather than an error: a renderer may ask
		about any node it draws.
	**/
	public function invokeAction(n:Node):Void {
		if (n == null)
			return;
		// One gesture, one render -- the rule `NodeSource.invokeAction` states.
		rui.Signal.Scheduler.batch(() -> {
			for (key in ACTION_KEYS) {
				var v = PropValueTools.resolve(n.props.get(key));
				if (v == null)
					continue;
				switch (v) {
					case PCallback(fn):
						fn();
						return;
					case PCallbackString(fn):
						fn("");
						return;
					case PCallbackBool(fn):
						fn(!PropValueTools.asBool(resolved(n, "isOn")));
						return;
					case PCallbackFloat(fn):
						fn(PropValueTools.asFloat(resolved(n, "value")));
						return;
					case PCallbackInt(fn):
						fn(PropValueTools.asInt(resolved(n, "value")));
						return;
					case _:
				}
			}
		});
	}

	/** Run the action of the node an id names — what a host sends back when it
		only ever held the integer. **/
	public function invokeActionId(id:Int):Void {
		if (id >= 0 && id < actions.length)
			invokeAction(actions[id]);
	}

	function resolved(n:Node, key:String):Null<PropValue>
		return n == null ? null : PropValueTools.resolve(n.props.get(key));

	function modifierAt(n:Node, index:Int):Null<Modifier> {
		if (n == null || index < 0 || index >= n.modifiers.length)
			return null;
		return n.modifiers[index];
	}

	static function carriesAction(n:Node):Bool {
		for (key in ACTION_KEYS)
			if (n.props.exists(key))
				return true;
		return false;
	}

	function index():Void {
		actions = [];
		walk(current);
	}

	function walk(n:Node):Void {
		if (n == null)
			return;
		if (carriesAction(n))
			actions.push(n);
		for (c in n.resolveChildren())
			walk(c);
	}
}
