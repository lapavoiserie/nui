package nui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Both directions of a backend, written by its declarations rather than by hand.

	`pui.nui.NodeRenderer` turned a node into a view in thirty-two cases and
	`pui.nui.Describe` turned a view into a node in twenty, for the same
	controls, in opposite directions. Two lists that size drift, and these did
	three times in one week — the worst of them nearly sending a `SecretInput`
	as an ordinary field with its secret in `text`.

	`pui.nui.Vocabulary` closed half of that: a control declares itself, once,
	and a declaration nobody can read is a compile error. This closes the other
	half. The two lists are now **one**, and it is generated:

	```haxe
	Derived.BUILDERS.get("Slider")   // node -> view
	Derived.DESCRIBERS.get("pui.ui.Slider")  // view -> node
	```

	## Dispatch by class, not by the order somebody wrote ifs

	`Describe` chose its branch with a chain of `Std.isOfType`, which answers by
	the order the branches were written: `SecretInput` extends `TextInput`, so
	putting it second described a secret as an ordinary field. Twice in
	twenty-four hours, caught both times only by remembering.

	`DESCRIBERS` is keyed by the exact class path, and the caller walks up the
	superclass chain until a key matches. The **nearest declared ancestor**
	wins, which is what the `isOfType` chain was trying to express and could
	only approximate: `pui.mui.Text` finds `pui.ui.Text` because that is its
	nearest declared ancestor, and `pui.ui.SecretInput` finds itself because it
	declares itself. Adding a subclass tomorrow cannot arm a trap, because
	nothing is ordered.

	## What is still written by hand, and why each one is

	Structure, not vocabulary — none of it was ever duplicated:

	- the **expansion** of `ForEach` and `ConditionalView`, which splice into
	  their siblings and have no node of their own;
	- the **flattening** of `ListView` and `TabView`, which cross as their rows
	  and their selected page, and say so in a trace;
	- the **decorations**, which are modifiers rather than props;
	- the **registry** a component library writes into (`vui`'s level meter),
	  and the marker for a type nothing draws;
	- three rules about a RECEIVED tree that no declaration could state:
	  `receivesValue` on a field whose value is somebody else's, the secret key
	  a `SecretInput` reports through, and the fact that a node's children are
	  already built by the time a builder is called.

	## Defaults come from the constructor

	A generated `new` passes every argument up to the last one it sets, so it
	has to know what "not said" means in between. It reads that from the
	constructor's own typed expression rather than restating it -- which is
	what the hand-written renderer did, and how `pui.ui.Slider`'s maximum could
	have become 1.0 in one file and something else in the other.
**/
class Derive {
	#if macro
	/** Build `pui.nui.Derived`'s two maps from what the controls declare. **/
	public static function build(d:Declarations.Dialect):Array<Field> {
		var fields = Context.getBuildFields();
		var builders:Array<Expr> = [];
		var describers:Array<Expr> = [];

		var types = [for (type in Declarations.types(d).keys()) type];
		types.sort(Reflect.compare);

		for (type in types) {
			var path = Declarations.classOf(d, type);
			builders.push(macro $v{type} => ${builderFor(d, type, path)});
			describers.push(macro $v{path} => ${describerFor(d, type, path)});
		}

		fields.push(mapField("BUILDERS", fn2(macro :nui.Node, arrayOf(d.view), pathOf(d.view)), builders));
		fields.push(mapField("DESCRIBERS", fn1(pathOf(d.view), macro :nui.Node), describers));
		return fields;
	}

	static function mapField(name:String, of:ComplexType, entries:Array<Expr>):Field {
		var value:Expr = entries.length == 0
			? macro new Map<String, $of>()
			: {expr: EArrayDecl(entries), pos: Context.currentPos()};
		return {
			name: name,
			access: [APublic, AStatic, AFinal],
			kind: FVar(macro :Map<String, $of>, value),
			pos: Context.currentPos(),
		};
	}

	// ---- node -> view ----

	static function builderFor(d:Declarations.Dialect, type:String, path:String):Expr {
		var props = Declarations.propsFor(d, type);
		var actions = Declarations.actionsFor(d, type);
		var children = Declarations.childrenFor(d, type);
		var content = Declarations.contentFor(d, type);
		var defaults = Declarations.defaultsOf(d, type);

		var byField = new Map<String, Declarations.Prop>();
		for (prop in props) byField.set(prop.field, prop);
		var actionByField = new Map<String, Declarations.Action>();
		for (action in actions) actionByField.set(action.field, action);

		var body:Array<Expr> = [macro var p = node.props];

		// A two-way value needs a cell before the control exists, so the
		// control can be given it and the callback can be pointed at it.
		for (prop in props) {
			if (prop.callback == null) continue;
			var cell = "__cell_" + prop.field;
			var seed = readProp(prop, defaults.get(prop.argument), false);
			var tell = readAction(d, {field: prop.field, name: prop.callback, carries: prop.kind});
			body.push(macro var $cell = ${cellOf(d, prop.kind, seed, tell)});
		}

		// The constructor, argument by argument, in its own order.
		var args:Array<Expr> = [];
		for (arg in Declarations.argumentsOf(d, type)) {
			if (content != null && arg.name == content) {
				args.push(macro kids);
			} else if (children != null && arg.name == children.field) {
				args.push(readChildren(children));
			} else if (byField.exists(arg.name)) {
				var prop = byField.get(arg.name);
				args.push(prop.callback != null
					? macro $i{"__cell_" + prop.field}
					: readProp(prop, defaults.get(arg.name), arg.opt));
			} else if (actionByField.exists(arg.name)) {
				args.push(readAction(d, actionByField.get(arg.name)));
			} else {
				var fallback = defaults.get(arg.name);
				args.push(fallback == null ? macro null : fallback);
			}
		}
		body.push(macro var __view = ${{expr: ENew(typePath(path), args), pos: Context.currentPos()}});

		// Everything the constructor did not take is assigned afterwards, and
		// only when the node said it -- a control's own default is better than
		// a zero this would otherwise write over it.
		for (prop in props) {
			if (prop.argument != null) continue;
			var field = prop.field;
			var value = readProp(prop, null, false);
			body.push(macro if (p.exists($v{prop.name})) __view.$field = $value);
		}
		for (action in actions) {
			if (Declarations.argumentsOf(d, type).filter(a -> a.name == action.field).length > 0) continue;
			var field = action.field;
			var value = readAction(d, action);
			body.push(macro if (p.exists($v{action.name})) __view.$field = $value);
		}

		body.push(macro return __view);
		var block = {expr: EBlock(body), pos: Context.currentPos()};
		var kidsType = arrayOf(d.view);
		var viewType = pathOf(d.view);
		return macro @:privateAccess function(node:nui.Node, kids:$kidsType):$viewType $block;
	}

	/**
		One prop's value, or what the constructor would have used.

		`allowAbsent` is whether "the node did not say" is a legal answer here.
		For a REQUIRED constructor argument it is not: `pui.ui.Text`'s content
		has no default and no meaningful null, so a node that carries no `text`
		gets the empty string `PropValueTools` already answers with. Reading a
		null into it produced a `Text` whose content was null, and the first
		thing to touch it fell over inside `StringTools`.
	**/
	static function readProp(prop:Declarations.Prop, fallback:Null<Expr>, allowAbsent:Bool):Expr {
		var name = prop.name;
		var got:Expr = switch (prop.kind) {
			case "Bool": macro nui.PropValue.PropValueTools.asBool(p.get($v{name}));
			case "Int": macro Std.int(nui.PropValue.PropValueTools.asFloat(p.get($v{name})));
			case "Float": macro nui.PropValue.PropValueTools.asFloat(p.get($v{name}));
			case _: macro nui.PropValue.PropValueTools.asString(p.get($v{name}));
		};
		// An optional argument with no written default falls back to null when
		// it can hold one. Without this, `pui.ui.SecretInput`'s `whenRefused`
		// arrives as "" rather than absent, and a refusal the application never
		// wrote would be shown as an empty sentence.
		var absent = fallback != null
			? fallback
			: (allowAbsent && prop.nullable ? macro null : null);
		if (absent == null) return got;
		return macro p.exists($v{name}) ? $got : $absent;
	}

	/**
		One act, read through `NodeRenderer`'s tolerant adapters.

		Not a `switch` on the shape here, because a tree that crossed a wire
		carries every action as `PCallbackString` -- the shapes live in the far
		table, not on the props. A generated reader matching only its own shape
		would find nothing, in silence, and only on a wire. Those adapters had
		that right already; there is nothing to generate.
	**/
	static function readAction(d:Declarations.Dialect, action:Declarations.Action):Expr {
		var name = action.name;
		var got = macro p.get($v{name});
		return switch (action.carries) {
			case "Bool": readersCall(d, "flag", [got]);
			case "Int": readersCall(d, "index", [got]);
			case "Float": readersCall(d, "amount", [got]);
			case "String": readersCall(d, "words", [got]);
			case _: readersCall(d, "action", [got]);
		}
	}

	/** Children that are data rather than views, read back out of the tree. **/
	static function readChildren(children:Declarations.Children):Expr {
		var prop = children.prop;
		return macro [
			for (__child in node.resolveChildren())
				nui.PropValue.PropValueTools.asString(__child.props.get($v{prop}))
		];
	}

	// ---- view -> node ----

	static function describerFor(d:Declarations.Dialect, type:String, path:String):Expr {
		var props = Declarations.propsFor(d, type);
		var actions = Declarations.actionsFor(d, type);
		var children = Declarations.childrenFor(d, type);

		var of = typeOf(path);
		// Each on its own line: `macro var a = x, macro var b = y` inside an
		// array literal parses as ONE var declaration with two names, and the
		// second `macro` becomes a variable name.
		var body:Array<Expr> = [];
		body.push(macro var __it:$of = cast view);
		body.push(macro var __node = new nui.Node($v{type}, view.key));

		for (prop in props) {
			var field = prop.field;
			var name = prop.name;

			if (prop.callback != null) {
				var value = wrap(prop.kind, macro __it.$field.get());
				body.push(macro __node.prop($v{name}, $value));
				body.push(macro __node.prop($v{prop.callback},
					${reportBack(prop.kind, field)}));
				continue;
			}

			var value = wrap(prop.kind, macro __it.$field);
			body.push(prop.nullable
				? macro if (__it.$field != null) __node.prop($v{name}, $value)
				: macro __node.prop($v{name}, $value));
		}

		for (action in actions) {
			var field = action.field;
			var carried = wrapCallback(action.carries, macro __it.$field);
			body.push(macro if (__it.$field != null) __node.prop($v{action.name}, $carried));
		}

		// A container's children are views, and splicing them is structure --
		// `ForEach` dissolves into its siblings, `ConditionalView` into its one
		// chosen child. That belongs to the describer, not to a declaration.
		if (Declarations.contentFor(d, type) != null)
			body.push(spliceCall(d, macro view, macro __node));

		if (children != null) {
			var field = children.field;
			var of = children.type;
			var prop = children.prop;
			body.push(macro if (__it.$field != null) for (__each in __it.$field)
				__node.child(new nui.Node($v{of}).prop($v{prop}, nui.PropValue.PString(__each))));
		}

		body.push(macro return __node);
		var block = {expr: EBlock(body), pos: Context.currentPos()};
		var viewType = pathOf(d.view);
		return macro @:privateAccess function(view:$viewType):nui.Node $block;
	}

	/** A value in the `PropValue` its declared kind names. **/
	static function wrap(kind:String, value:Expr):Expr {
		return switch (kind) {
			case "Bool": macro nui.PropValue.PBool($value);
			case "Int": macro nui.PropValue.PInt($value);
			case "Float": macro nui.PropValue.PFloat($value);
			case _: macro nui.PropValue.PString($value);
		}
	}

	/** The other half of a two-way value: a write coming back in. **/
	static function reportBack(kind:String, field:String):Expr {
		return switch (kind) {
			case "Bool": macro nui.PropValue.PCallbackBool(__v -> __it.$field.set(__v));
			case "Int": macro nui.PropValue.PCallbackInt(__v -> __it.$field.set(__v));
			case "Float": macro nui.PropValue.PCallbackFloat(__v -> __it.$field.set(__v));
			case _: macro nui.PropValue.PCallbackString(__v -> __it.$field.set(__v));
		}
	}

	static function wrapCallback(carries:Null<String>, value:Expr):Expr {
		return switch (carries) {
			case "Bool": macro nui.PropValue.PCallbackBool($value);
			case "Int": macro nui.PropValue.PCallbackInt($value);
			case "Float": macro nui.PropValue.PCallbackFloat($value);
			case "String": macro nui.PropValue.PCallbackString($value);
			case _: macro nui.PropValue.PCallback($value);
		}
	}

	// ---- the handful of type paths a backend owns ----

	static function pathOf(path:String):ComplexType
		return TPath(typePath(path));

	static function arrayOf(path:String):ComplexType
		return TPath({pack: [], name: "Array", params: [TPType(pathOf(path))]});

	static function fn1(from:ComplexType, to:ComplexType):ComplexType
		return TFunction([from], to);

	static function fn2(a:ComplexType, b:ComplexType, to:ComplexType):ComplexType
		return TFunction([a, b], to);

	/**
		The cell a two-way control is given, made by the backend.

		`<cells>.boolCell(value, tell)` and its three siblings. The generator
		cannot make this itself: `pui` wants a `pui.state.State` whose sink
		reports, `cui` wants a get/set binding closed over the value. What both
		have in common is only the question -- here is what arrived and here is
		where writes go -- so that is what crosses.
	**/
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

	/**
		A call into the backend's own readers.

		`report`, and the tolerant `action`/`words`/`flag`/`index`/`amount`.
		None of it is generated, because none of it is vocabulary: it is what a
		WIRE does to a callback. `nui.Snapshot.inflate` carries every action as
		`PCallbackString`, the shapes living in the far table rather than on the
		props, so a reader matching only its own shape finds nothing -- and
		finds it in silence, and only on a wire.
	**/
	static function readersCall(d:Declarations.Dialect, name:String, args:Array<Expr>):Expr {
		var parts = d.readers.split(".");
		parts.push(name);
		return {expr: ECall(macro $p{parts}, args), pos: Context.currentPos()};
	}

	/** The call that splices a container's view children into its node. **/
	static function spliceCall(d:Declarations.Dialect, view:Expr, node:Expr):Expr {
		var parts = d.appendChildren.split(".");
		return {expr: ECall(macro $p{parts}, [view, node]), pos: Context.currentPos()};
	}

	static function typePath(path:String):TypePath {
		var parts = path.split(".");
		return {pack: parts.slice(0, parts.length - 1), name: parts[parts.length - 1]};
	}

	static function typeOf(path:String):ComplexType {
		return TPath(typePath(path));
	}
	#end
}
