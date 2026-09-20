package nui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Build a backend's own control, at compile time, from what it declared.

	## Why this exists beside `Derive`

	`Derive` answers "a node arrived, make a view" — at runtime, reading
	`node.props`. This answers the same question one stage earlier: **the tree
	is known while compiling**, because somebody wrote it in `mui`'s markup, so
	the control can be constructed directly instead of being described and then
	read back.

	That difference is not an optimisation. `mui.macros.Markup` produced a
	`nui.Node` and nothing else, so markup had exactly one first-class consumer:
	`wui`, which is in push mode and wants nodes. `pui` could build views from
	a node, and `sui` and `aui` could not — they read a received tree natively
	and never copy it into views. So an application written in markup could
	only reach those two by pretending to be a remote machine talking to
	itself: actions through a string-id registry, the transpiler bypassed, and
	the fine-grained read tracking that is the whole point of those backends
	thrown away.

	Emitting the constructor makes markup a **syntax over each backend's own
	API**, checked against that backend's declarations exactly as before.
	Closures bind directly. Nothing is described, so nothing has to be read
	back.

	## What it will not do, and says so by answering null

	A type whose children are **data** (`@:children`, like a `Picker`'s options
	written as `Text` children) is refused here: turning those back into an
	array of strings at compile time means reading inside child elements, which
	this does not do yet. Null, and the caller keeps building a node — which
	still works wherever a backend accepts one.

	Likewise a two-way property given only one of its halves. `@:prop("isOn",
	"onToggle")` needs a value AND somewhere to write: with one of them the
	control would be built around a cell nothing reads or nothing writes, which
	is worse than not building it.
**/
class Construct {
	/**
		The expression that makes one control, or null when this one cannot be.

		`given` is keyed by the **canonical** attribute name — `isOn`,
		`onToggle`, `label` — with the value as the author wrote it, unwrapped:
		no `PropValue`, because nothing here crosses a wire.
	**/
	public static function expr(d:Declarations.Dialect, type:String,
			given:Map<String, Expr>, children:Null<Expr>, pos:Position):Null<Expr> {
		var path = Declarations.classOf(d, type);
		if (path == null) return null;
		if (Declarations.childrenFor(d, type) != null) return null;

		var props = Declarations.propsFor(d, type);
		var actions = Declarations.actionsFor(d, type);
		var content = Declarations.contentFor(d, type);
		var defaults = Declarations.defaultsOf(d, type);

		var byField = new Map<String, Declarations.Prop>();
		for (prop in props) if (prop.field != null) byField.set(prop.field, prop);
		var actionByField = new Map<String, Declarations.Action>();
		for (action in actions) actionByField.set(action.field, action);

		// A two-way value needs its cell before the control exists, so the
		// control can be handed it and the callback can be pointed at it --
		// the same order `Derive` builds one in, for the same reason.
		var before:Array<Expr> = [];
		for (prop in props) {
			if (prop.callback == null || prop.field == null) continue;
			var seed = given.get(prop.name);
			var tell = given.get(prop.callback);
			if (seed == null || tell == null) return null;
			if (d.cells == null) return null;
			var cell = "__cell_" + prop.field;
			before.push(macro var $cell = ${cellOf(d, prop.kind, seed, tell)});
		}

		var args:Array<Expr> = [];
		for (arg in Declarations.argumentsOf(d, type)) {
			if (content != null && arg.name == content) {
				var kids = children == null ? macro [] : children;
				args.push(Declarations.takesOneChild(d, type)
					? macro { var __kids = $kids; __kids.length > 0 ? __kids[0] : null; }
					: kids);
			} else if (byField.exists(arg.name)) {
				var prop = byField.get(arg.name);
				if (prop.callback != null) {
					args.push(macro $i{"__cell_" + prop.field});
				} else {
					var written = given.get(prop.name);
					args.push(written != null ? written : fallback(defaults, arg.name));
				}
			} else if (actionByField.exists(arg.name)) {
				var written = given.get(actionByField.get(arg.name).name);
				args.push(written != null ? written : fallback(defaults, arg.name));
			} else {
				args.push(fallback(defaults, arg.name));
			}
		}

		var made:Expr = {expr: ENew(pathOf(path), args), pos: pos};
		if (before.length == 0) return made;
		before.push(made);
		return {expr: EBlock(before), pos: pos};
	}

	static function fallback(defaults:Map<String, Expr>, name:String):Expr
		return defaults.exists(name) ? defaults.get(name) : macro null;

	static function cellOf(d:Declarations.Dialect, kind:String, seed:Expr, tell:Expr):Expr {
		var parts = d.cells.split(".");
		parts.push(switch (kind) {
			case "Bool": "boolCell";
			case "Int": "intCell";
			case "Float": "floatCell";
			case _: "stringCell";
		});
		return {expr: ECall(macro $p{parts}, [seed, tell]), pos: Context.currentPos()};
	}

	static function pathOf(path:String):TypePath {
		var parts = path.split(".");
		var name = parts.pop();
		return {pack: parts, name: name};
	}
}
#end
