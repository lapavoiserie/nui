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
