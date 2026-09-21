package nui;

import nui.PropValue;
import nui.Modifier;

/**
	A node tree as pure data — what crosses a process boundary.

	A live `Node` cannot leave the process: its props map carries closures and
	thunks, and its children may be a thunk themselves. A detached surface — a
	widget another process samples, a companion view on another machine — needs
	the tree as *data*, and needs the closures replaced by something that can
	cross: an integer. That is the pattern every boundary in this ecosystem
	already settled on — `NodeSource.actionId`/`invokeAction` in pull mode,
	wui's callback ids over the C ABI, qui's `Bridge.emit(id)` — stated here
	once, for trees instead of single calls.

	## The shape

	`SnapshotNode` holds only what `haxe.Json` can carry both ways: the type,
	the key, scalar props, modifiers (already plain data), children, and an
	`actions` map naming which prop is invocable and by which id. `PReactive`
	thunks are resolved at projection time — a snapshot is *sampled*, that is
	its whole point; liveness is the co-resident model's business.

	## The action table

	Ids are monotonic and never reused — a hole answers nothing, the policy
	every backend's handle table already keeps. The table records each
	callback's *shape*, so a remote tap can carry the control's live value
	back with the right type: `invoke(id)` for a plain handler,
	`invoke(id, "text")` for the typed ones (the argument crosses as a string
	and is parsed against the recorded shape — the wire has no types, the
	table does).

	Ids are STABLE BY PLACE across generations: `project` keys each action by
	its node path and prop, so the same button in the same slot keeps its id
	from one projection to the next, with the closure updated — a remote tap
	arriving one generation late does what the unchanged button says. Only a
	control that genuinely left the tree retires its id, and `invoke` on a
	retired id is a no-op with a word: a tree received as data degrades, it
	never crashes.
**/
typedef SnapshotNode = {
	var type:String;
	var ?key:String;
	var ?props:haxe.DynamicAccess<Dynamic>;
	var ?actions:haxe.DynamicAccess<Int>;
	var ?modifiers:Array<Modifier>;
	var ?children:Array<SnapshotNode>;
}

class Snapshot {
	/**
		Project a live tree into pure data, registering every callback in
		`table`. Children thunks are resolved — a snapshot samples the whole
		picture, the same reason sui's `classify` forces the lazy parts.
	**/
	/**
		The action ids in a snapshot whose argument must never be written down.

		Derived from the snapshot, which both ends have: the one that projected
		it and the one that received it. **Derived, and not a flag somebody
		sets** — the marking is the canon's own key name (`SECRET_KEY`), so a
		trace, a relay or a loss log cannot print a secret by forgetting to
		check a boolean it was never given. A flag at each logging site is the
		shape that fails open, which is the same reason `SecretInput` is a type
		and not an option on a text field.

		Cheap enough to call per frame: one walk of a tree that was just built.
	**/
	public static function secretIds(snap:Null<SnapshotNode>):Array<Int> {
		var found:Array<Int> = [];
		gatherSecrets(snap, found);
		return found;
	}

	static function gatherSecrets(snap:Null<SnapshotNode>, into:Array<Int>):Void {
		if (snap == null)
			return;
		if (snap.actions != null) {
			var id = snap.actions.get(SelfSource.SECRET_KEY);
			if (id != null)
				into.push(id);
		}
		if (snap.children != null)
			for (child in snap.children)
				gatherSecrets(child, into);
	}

	/**
		What a log prints in place of a secret.

		The length, because a diagnostic that says nothing at all cannot tell
		"the key arrived empty" from "the key arrived": both are worth knowing
		when a stream will not start, and neither needs the value.
	**/
	public static function redacted(arg:Null<String>):String {
		var n = arg == null ? 0 : arg.length;
		return "[secret, " + n + " characters]";
	}

	public static function project(node:Node, table:ActionTable):SnapshotNode {
		table.beginGeneration();
		var out = projectAt(node, table, "");
		table.sweep();
		return out;
	}

	/**
		The walk, carrying the node's PLACE as the action key.

		Identity is the place, never the pointer — the house stance — so an
		action's id is keyed by "path#prop": the same button in the same slot
		keeps its id across generations, and a remote tap that arrives one
		generation late invokes the CURRENT closure, which is what the button
		means. A keyed node contributes its key instead of its index, so a
		keyed row keeps its actions when the list reorders. Only a control
		that genuinely left the tree retires its id.

		Paid for on the very first interactive companion: the serving state
		beat every two seconds, each beat cleared the whole table, and a
		human's Enter reliably found a freshly-retired id — "stale remote
		tap" on a button that had not changed at all.

		## The place is not enough, and the key says what the control IS

		"The current closure at that place" is what the button means only
		while it is the same button. INSERT one above it and the place names
		somebody else: a tap on "Delete row 2", arriving one generation late,
		ran whatever had taken slot 2 — a wrong action, on another machine,
		with nothing on either side to say so. Found on 2026-09-21 by asking
		where else `sui`'s slider crash could live: same hole, across a wire.

		So the key also carries a **signature** (`signatureOf`): the node's type
		and what it says — its label. An unchanged button keeps its id, which
		is everything the paragraph above bought. A place taken by a different
		control is a NEW key: the old id retires at the sweep, and the late tap
		is dropped with a word (`invoke` on an unknown id) instead of being
		misdirected. A button whose own label changed — "Play" to "Pause" —
		drops a late tap too, and that is the safe reading: the person tapped
		Play, and what is there now would pause.

		What it cannot tell apart is two unkeyed siblings of one type that say
		the same thing — a column of "Delete" buttons. That is what a key is
		for, and it is the one case where writing one is not optional.
	**/
	/** The props that say what a control is called. Never a VALUE: a field's
		`text` changes with every keystroke, and an id that moved with it
		would drop the next one. **/
	static final SAYS = ["label", "title", "placeholder", "icon", "name"];

	/** What a control is, for its actions' keys: its type and what it says. **/
	static function signatureOf(node:Node):String {
		var said = "";
		if (node.props != null) {
			for (key in SAYS) {
				var value = PropValueTools.resolve(node.props.get(key));
				switch (value) {
					case PString(v) if (v != ""): said = v;
					case _:
				}
				if (said != "") break;
			}
		}
		return node.type + ":" + said;
	}

	static function projectAt(node:Node, table:ActionTable, path:String):SnapshotNode {
		if (node == null) return null;
		var out:SnapshotNode = {type: node.type};
		if (node.key != null) out.key = node.key;

		if (node.props != null) {
			var props:haxe.DynamicAccess<Dynamic> = {};
			var actions:haxe.DynamicAccess<Int> = {};
			var hasProps = false;
			var hasActions = false;
			var signature:Null<String> = null;
			for (key in node.props.keys()) {
				var resolved = PropValueTools.resolve(node.props.get(key));
				if (resolved == null) continue;
				switch (resolved) {
					case PString(v): props.set(key, v); hasProps = true;
					case PInt(v): props.set(key, v); hasProps = true;
					case PFloat(v): props.set(key, v); hasProps = true;
					case PBool(v): props.set(key, v); hasProps = true;
					case PCallback(_) | PCallbackString(_) | PCallbackFloat(_)
						| PCallbackInt(_) | PCallbackBool(_):
						if (signature == null) signature = signatureOf(node);
						actions.set(key, table.registerAt(path + "#" + key + "@" + signature, resolved));
						hasActions = true;
					case PReactive(_):
						// resolve() runs reactives to a fixed point; reaching
						// here means the fixed point was itself a thunk, which
						// resolve() already guards. Nothing to carry.
				}
			}
			if (hasProps) out.props = props;
			if (hasActions) out.actions = actions;
		}

		if (node.modifiers != null && node.modifiers.length > 0)
			out.modifiers = node.modifiers;

		var kids = node.resolveChildren();
		if (kids != null && kids.length > 0) {
			out.children = [];
			for (i in 0...kids.length) {
				var child = kids[i];
				var seg = child != null && child.key != null ? "k" + child.key : Std.string(i);
				out.children.push(projectAt(child, table, path + "/" + seg));
			}
		}

		return out;
	}

	/** The snapshot as a wire string. `haxe.Json` both ways — the shape holds
		nothing it cannot carry. **/
	public static function toJson(snap:SnapshotNode):String
		return haxe.Json.stringify(snap);

	public static function fromJson(wire:String):SnapshotNode
		return haxe.Json.parse(wire);

	/**
		The far side of the wire: a received snapshot back into a `Node` tree
		a renderer can draw.

		This is what makes a remote renderer nearly free instead of a project:
		the inflated tree is ordinary `nui.Node`, so any backend's existing
		`NodeRenderer` draws it — and every action prop comes back as a
		closure that hands the id (and the control's live value, for the
		typed shapes) to `invoke`, which is where the channel back to the
		serving process plugs in. The renderer wires callbacks exactly as it
		would for a local tree; it cannot tell the difference, which is the
		point.

		Scalar props inflate by JSON shape (Float when fractional, Int
		otherwise, Bool, String); the receiving renderer reads them through
		the null-safe `PropValueTools.as*` accessors like any other tree, so
		a shape surprise degrades instead of crashing. Which callback SHAPE an
		action prop had is knowledge the serving side's table kept — here every
		action inflates as `PCallbackString`, the shape that can carry
		anything, and `invoke`'s table parses the string against the recorded
		truth. A renderer that fires a plain click through it sends "" — the
		table's `PCallback` case ignores the argument either way.
	**/
	public static function inflate(snap:SnapshotNode, invoke:(id:Int, arg:String) -> Void):Node {
		if (snap == null) return null;
		var node = new Node(snap.type, snap.key);
		if (snap.props != null) {
			for (key in snap.props.keys()) {
				var v:Dynamic = snap.props.get(key);
				if (Std.isOfType(v, Bool)) node.prop(key, PBool(v));
				else if (Std.isOfType(v, String)) node.prop(key, PString(v));
				else if (Std.isOfType(v, Int)) node.prop(key, PInt(v));
				else if (Std.isOfType(v, Float)) node.prop(key, PFloat(v));
				// Anything else came off a wire this shape never writes:
				// dropped, and the null-safe readers answer the default.
			}
		}
		if (snap.actions != null) {
			for (key in snap.actions.keys()) {
				var id = snap.actions.get(key);
				node.prop(key, PCallbackString(arg -> invoke(id, arg)));
			}
		}
		if (snap.modifiers != null)
			for (m in snap.modifiers) node.modifier(m);
		if (snap.children != null)
			for (child in snap.children) node.child(inflate(child, invoke));
		return node;
	}
}

/**
	The closure side of a projection: ids out, invocations in.

	One instance per projection consumer (a surface, a widget host). Not a
	static registry — two detached surfaces must not share a namespace, the
	lesson every `_registry` comment in this ecosystem already carries.
**/
class ActionTable {
	// Monotonic, never reused: a stale id from a remote surface one
	// round-trip behind names a hole, not someone else's action.
	var _next:Int = 0;
	var _actions:Map<Int, PropValue> = new Map();

	// Place-key -> id, so the same control in the same slot keeps its id
	// across generations; _renewed marks which keys this generation still
	// declares, and sweep() retires the rest.
	var _idsByKey:Map<String, Int> = new Map();
	var _renewed:Map<String, Bool> = new Map();

	public function new() {}

	/** Register one callback-carrying value; the id is what crosses. For
		anonymous one-shot use — a projection keys by place through
		`registerAt` instead, which is what keeps ids stable. **/
	public function register(callback:PropValue):Int {
		var id = _next++;
		_actions.set(id, callback);
		return id;
	}

	/** Open a generation: every keyed id is up for retirement until its key
		is renewed. `Snapshot.project` brackets this itself. **/
	public function beginGeneration():Void {
		_renewed = new Map();
	}

	/**
		Register under a stable place key. A known key keeps its id and gets
		the CURRENT closure — so a remote tap arriving one generation late
		still does what the unchanged button says. A new key gets a fresh,
		monotonic id.
	**/
	public function registerAt(key:String, callback:PropValue):Int {
		_renewed.set(key, true);
		var existing = _idsByKey.get(key);
		if (existing != null) {
			_actions.set(existing, callback);
			return existing;
		}
		var id = _next++;
		_idsByKey.set(key, id);
		_actions.set(id, callback);
		return id;
	}

	/** Close a generation: keys the projection no longer declared retire —
		their ids become holes that `invoke` answers with a word. **/
	public function sweep():Void {
		for (key in _idsByKey.keys()) {
			if (_renewed.exists(key)) continue;
			var id = _idsByKey.get(key);
			_idsByKey.remove(key);
			if (id != null) _actions.remove(id);
		}
	}

	/**
		Run action `id`, with the control's live value when the shape takes
		one. The argument crosses as a string; the recorded shape says how to
		read it — a wire has no types, the table does. Unknown or cleared ids
		and unparsable arguments degrade with a word: a remote tap can arrive
		a generation late, and that is data, never a crash.
	**/
	public function invoke(id:Int, ?arg:String):Void {
		var action = _actions.get(id);
		if (action == null) {
			trace('nui.ActionTable: action $id is not live (a stale remote tap?); ignored');
			return;
		}
		// One gesture, one re-projection. A closure that writes three cells
		// would otherwise wake the follower three times and publish three
		// pictures, of which only the last was ever going to be seen — and on
		// a snapshot surface those intermediate frames are not just wasted
		// work, they are a widget reload budget spent on nothing.
		rui.Signal.Scheduler.batch(() -> switch (action) {
			case PCallback(fn): fn();
			case PCallbackString(fn): fn(arg != null ? arg : "");
			case PCallbackFloat(fn):
				var v = arg != null ? Std.parseFloat(arg) : Math.NaN;
				if (Math.isNaN(v)) trace('nui.ActionTable: action $id wanted a number, got "$arg"; ignored');
				else fn(v);
			case PCallbackInt(fn):
				var v = arg != null ? Std.parseInt(arg) : null;
				if (v == null) trace('nui.ActionTable: action $id wanted an integer, got "$arg"; ignored');
				else fn(v);
			case PCallbackBool(fn): fn(arg == "true" || arg == "1");
			case _:
				trace('nui.ActionTable: action $id holds no callback; ignored');
		});
	}

	/** Retire every id — the previous generation's answer to a late tap is
		"not live", said once per id by `invoke`. **/
	public function clear():Void {
		_actions.clear();
		_idsByKey.clear();
		_renewed.clear();
	}
}
