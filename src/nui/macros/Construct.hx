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
/** A control to make: its constructor call, and what to assign after it. **/
typedef Parts = {made:Expr, assigns:Array<Assign>};

/** One property or act the constructor did not take. **/
typedef Assign = {field:String, value:Expr};

class Construct {
	/**
		The expression that makes one control, or null when this one cannot be.

		`given` is keyed by the **canonical** attribute name — `isOn`,
		`onToggle`, `label` — with the value as the author wrote it, unwrapped:
		no `PropValue`, because nothing here crosses a wire.
	**/
	public static function expr(d:Declarations.Dialect, type:String,
			given:Map<String, Expr>, children:Null<Expr>, pos:Position):Null<Expr> {
		var made = parts(d, type, given, children, pos);
		return made == null ? null : assemble(made, pos);
	}

	/**
		The control as two parts: the constructor call, and the assignments
		that follow it -- every property and act the markup wrote and the
		constructor did not take.

		**Why the second part exists.** `Declarations.propsFor` says it in so
		many words: a field whose name is a constructor argument fills it,
		"anything else is assigned after the control is made". `Derive` did
		that for a tree that arrived; this did not, for a tree that was
		written. A property assignable alone was accepted by the markup and
		then dropped on the way, without a word -- `<Text scale="title"
		weight={700}/>` came out as `new sui.ui.Text(...)` and nothing else,
		so a desktop client's titles were body text on the Mac and titles on
		Windows, which builds from nodes.

		Only what was WRITTEN is assigned, like `Derive`: a control's own
		default is better than a value this would otherwise invent for it.

		Separate from `expr` for a backend that has to see the constructor
		alone -- `sui` defers it, and needs the assignments replayed where the
		deferred control is rebuilt. Everyone else calls `expr`.
	**/
	public static function parts(d:Declarations.Dialect, type:String,
			given:Map<String, Expr>, children:Null<Expr>, pos:Position):Null<Parts> {
		var path = Declarations.classOf(d, type);
		if (path == null) return null;

		// Children that are DATA -- a `Picker`'s options. This used to give up
		// here, because turning `<Text text="HDMI"/>` back into a string means
		// reading inside a child element, which happens one layer up. It does
		// now (`mui.macros.Markup.dataChildrenOf`) and hands the array in under
		// the field's name, so the only thing left to refuse is a control whose
		// data children nobody wrote.
		var data = Declarations.childrenFor(d, type);
		if (data != null && !given.exists(data.field)) return null;

		var props = Declarations.propsFor(d, type);
		var actions = Declarations.actionsFor(d, type);
		var content = Declarations.contentFor(d, type);
		var defaults = Declarations.defaultsOf(d, type);

		// Keyed by the constructor ARGUMENT a declaration fills, and by the
		// field only when it does not say. They are usually the same name and
		// were assumed to be: `sui.ui.Text` declares `@:prop("text") var
		// content` and takes `text`, so matching on the field found nothing,
		// the argument fell back to its default, and every string in a
		// transpiled screen came out empty. `Declarations` knew -- `Prop` has
		// carried `argument` all along.
		var byArgument = new Map<String, Declarations.Prop>();
		for (prop in props) {
			// Three keys, least specific first so the surer one wins. A
			// declaration usually names its field after the argument it
			// fills, and matching on the field alone assumed that always.
			// `sui.ui.Text` declares `@:prop("text") var content` and its
			// constructor takes `text`: nothing matched, the argument took
			// its default, and every string in a transpiled screen came out
			// empty. The CANONICAL name is what bridges them, and it is the
			// one thing a declaration always says.
			if (prop.name != null) byArgument.set(prop.name, prop);
			if (prop.field != null) byArgument.set(prop.field, prop);
			if (prop.argument != null) byArgument.set(prop.argument, prop);
		}
		var actionByField = new Map<String, Declarations.Action>();
		for (action in actions) actionByField.set(action.field, action);

		// Nothing to make: a two-way binding IS a cell. Markup writes
		// `isOn={lit_}` and the cell goes straight to the constructor, where
		// each backend's binding abstract takes it through its own `@:from`.
		//
		// It was a value and a callback here, with a factory per backend to
		// turn the two into a cell. That was the wrong shape, and `sui` is
		// where it showed: its controls hold a NAME, so there was nothing to
		// make and no way to make it. Binding the cell is what a view written
		// by hand does, and it costs four fewer modules.

		var args:Array<Expr> = [];
		for (arg in Declarations.argumentsOf(d, type)) {
			if (content != null && arg.name == content) {
				var kids = children == null ? macro [] : children;
				args.push(Declarations.takesOneChild(d, type)
					? macro { var __kids = $kids; __kids.length > 0 ? __kids[0] : null; }
					: kids);
			} else if (data != null && arg.name == data.field) {
				args.push(given.get(data.field));
			} else if (byArgument.exists(arg.name)) {
				var prop = byArgument.get(arg.name);
				if (prop.callback != null) {
					// The cell as written. A control that holds a NAME rather
					// than the cell -- `sui`'s, whose state lives on the Swift
					// side -- is handed it through the backend's own module,
					// because knowing that a cell HAS a name is its business.
					var cell = given.get(prop.name);
					if (cell == null) return null;
					if (prop.named != true) {
						args.push(cell);
					} else {
						if (d.named == null) return null;
						var parts = d.named.split(".");
						parts.push("nameOf");
						args.push({expr: ECall(macro $p{parts}, [cell]), pos: pos});
					}
				} else {
					var written = given.get(prop.name);
					args.push(written != null
						? converted(prop, written)
						: fallback(defaults, arg.name));
				}
			} else if (actionByField.exists(arg.name)) {
				var written = given.get(actionByField.get(arg.name).name);
				args.push(written != null ? written : fallback(defaults, arg.name));
			} else {
				args.push(fallback(defaults, arg.name));
			}
		}

		// What the constructor did not take, in the order it was declared.
		// A name is taken when the constructor matched it by any of the three
		// keys above -- the same rule, so nothing is both passed and set.
		var argNames = [for (arg in Declarations.argumentsOf(d, type)) arg.name];
		inline function taken(name:Null<String>):Bool
			return name != null && argNames.indexOf(name) >= 0;
		var assigns:Array<Assign> = [];
		for (prop in props) {
			if (taken(prop.name) || taken(prop.field) || taken(prop.argument)) continue;
			if (!given.exists(prop.name)) continue;
			// A two-way value is a cell, and a cell only ever goes to the
			// constructor (see above).
			if (prop.callback != null) continue;
			refuseUnassignable(d, type, prop.name, prop.field, pos);
			assigns.push({field: prop.field, value: converted(prop, given.get(prop.name))});
		}
		for (action in actions) {
			if (taken(action.field) || !given.exists(action.name)) continue;
			refuseUnassignable(d, type, action.name, action.field, pos);
			assigns.push({field: action.field, value: given.get(action.name)});
		}

		return {made: {expr: ENew(pathOf(path), args), pos: pos}, assigns: assigns};
	}

	/**
		The constructor call followed by its assignments, as one expression
		whose value is the control. Just the call when there is nothing to
		assign, so every control written with constructor properties only is
		built by exactly the expression it always was.
	**/
	public static function assemble(p:Parts, pos:Position):Expr {
		if (p.assigns.length == 0) return p.made;
		var body:Array<Expr> = [macro var __made = ${p.made}];
		for (a in p.assigns) {
			var field = a.field;
			var value = a.value;
			body.push(macro @:pos(value.pos) __made.$field = $value);
		}
		body.push(macro __made);
		return macro @:pos(pos) @:privateAccess $b{body};
	}

	/**
		A written property with nowhere to go is a compile error, naming it.
		It used to be dropped, which is the one answer this project does not
		give to something knowable while compiling.
	**/
	static function refuseUnassignable(d:Declarations.Dialect, type:String, name:String,
			field:Null<String>, pos:Position):Void {
		if (field != null && Declarations.assignable(d, type, field)) return;
		Context.error('"$type" accepts "$name", but its constructor does not take it '
			+ "and no field can be given it afterwards, so the value would be lost.\n"
			+ "  Make it a constructor argument or a settable field of the control "
			+ "-- see nui.macros.Construct.parts.", pos);
	}

	/**
		The value as the control measures it.

		The canon is in points; a backend whose unit is something else says so
		on the declaration (`@:convert`). Applied here, and by `Derive` for a
		tree that arrived, so a written `spacing={12}` and a received one mean
		the same thing.
	**/
	static function converted(prop:Declarations.Prop, value:Expr):Expr {
		if (prop.convert == null) return value;
		var parts = prop.convert.split(".");
		return {expr: ECall(macro $p{parts}, [value]), pos: value.pos};
	}

	static function fallback(defaults:Map<String, Expr>, name:String):Expr
		return defaults.exists(name) ? defaults.get(name) : macro null;

	static function pathOf(path:String):TypePath {
		var parts = path.split(".");
		var name = parts.pop();
		return {pack: parts, name: name};
	}
}
#end
