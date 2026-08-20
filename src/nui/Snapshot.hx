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

	A table belongs to one projection *generation*: project the next tree into
	a fresh table (or `clear` this one) and hand the old ids their answer —
	`invoke` on a cleared id is a no-op with a word, because a remote surface
	may tap a button one round-trip after it died. That is a tree received as
	data; it degrades, it never crashes.
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
	public static function project(node:Node, table:ActionTable):SnapshotNode {
		if (node == null) return null;
		var out:SnapshotNode = {type: node.type};
		if (node.key != null) out.key = node.key;

		if (node.props != null) {
			var props:haxe.DynamicAccess<Dynamic> = {};
			var actions:haxe.DynamicAccess<Int> = {};
			var hasProps = false;
			var hasActions = false;
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
						actions.set(key, table.register(resolved));
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
		if (kids != null && kids.length > 0)
			out.children = [for (child in kids) project(child, table)];

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

	public function new() {}

	/** Register one callback-carrying value; the id is what crosses. **/
	public function register(callback:PropValue):Int {
		var id = _next++;
		_actions.set(id, callback);
		return id;
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
		switch (action) {
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
		}
	}

	/** Retire every id — the previous generation's answer to a late tap is
		"not live", said once per id by `invoke`. **/
	public function clear():Void {
		_actions.clear();
	}
}
