package nui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.Tools;
#end

/**
	What a backend can build and describe, read from its controls themselves.

	## Why this exists

	A control's canonical shape was written out **twice**, by hand, in opposite
	directions: `pui.nui.NodeRenderer` turns a node into a view (35 branches),
	and `pui.nui.Describe` turns a view into a node (20 branches), for 27
	controls. Two lists that size will drift, and these already did — three
	times in one week:

	- `NodeRenderer` read `value`/`onChange` for a Toggle and a Slider while the
	  canon and `Describe` said `isOn`/`onToggle` and `onValue`, so a received
	  control ignored what it was sent and reported nothing back;
	- `report` had no `PCallbackInt`, so a local picker's choice reached nobody;
	- and the branch ORDER of `Describe` nearly sent a `SecretInput` as an
	  ordinary field, with its secret in `text` — twice in twenty-four hours,
	  caught both times only by remembering.

	That last one is the argument. `Std.isOfType` on a hierarchy decides by the
	order the branches were written, so every future subclass is a trap armed
	for whoever adds it. Dispatch by **declared type** does not manage that
	hazard, it removes it.

	## How a control declares itself

	```haxe
	@:node("Slider")
	class Slider extends View {
		@:prop("value", "onValue") final state:pui.state.State<Float>;
		@:prop("min") final min:Float;
		@:prop("max") final max:Float;

		public function new(binding:SliderBinding, min = 0.0, max = 1.0) { … }
	}
	```

	`@:node` is the node type, and it is the class's own answer: never derived
	from the class name, and never matched against anything else. **Two controls
	may not claim one type.** That is not a style rule — `wui` has the tolerant
	version, where a lookup accepts either the node name or the platform name,
	and adding a second masked control there silently put a value setter on the
	SECRET field's node type. One name, one class, no fallback.

	`@:prop(name)` is a plain property: the canonical name it travels under, and
	its kind read from the Haxe type.

	`@:prop` with nothing said takes the **field's own name**, which is right
	whenever the Haxe name already IS the canonical one — `label`, `name`,
	`value`, `src`. Said once rather than twice, and a rename then cannot make
	the two disagree because there is only one.

	`@:prop(name, callback)` is a two-way value: it lives in a
	`pui.state.State<T>`, crosses as `name`, and the writes come back through
	`callback`. Declaring the pair together is what stops the two sides from
	disagreeing about which key is which.

	A control that declares **no** value has none, and that is how
	`pui.ui.SecretInput` states its whole guarantee: there is no property for a
	tree to set because none is declared.

	`@:action(key)` is an act rather than a value: nothing sets it from a tree,
	and it crosses as one of `nui.SelfSource.ACTION_KEYS` and never as the
	closure itself. The field's type says what the act carries, so a
	`String->Void` is the one-argument form without a second word.

	`@:children(type, prop)` is for children that are not views:
	`pui.ui.Picker` holds `Array<String>` and the canon says each option
	crosses as a `Text` child, because a renderer that draws pictures in its
	options reads them as children.

	## A subclass borrows, it does not inherit

	`@:prop`, `@:action` and `@:children` are read from the class's **own**
	fields. A superclass's are not, and that is the point rather than a
	limitation: `pui.ui.SecretInput` extends `pui.ui.TextInput` for the caret,
	the selection and the layout, and inheriting metadata would have handed it
	back the `text` and `onText` whose absence is the type's whole guarantee --
	put there by nothing more than an `extends`, seen by nobody. That is this
	module's own hazard wearing a different hat.

	So a subclass says what it borrows, on the class, naming the field:

	```haxe
	@:node("PasswordInput")
	@:prop("placeholder")
	@:prop("state", "text", "onText")
	class PasswordInput extends TextInput { … }
	```

	Two lines, because the canon says a `PasswordInput` is "a `TextInput` in
	every respect but one". `SecretInput` writes one, `@:prop("placeholder")`,
	and its silence about `text` is now a fact a test can read.

	## Matched by name, not by rank

	A field whose name is a constructor parameter's fills that argument;
	anything else is assigned after the control is made. An earlier version
	matched by RANK, and rank is an arithmetic nobody can check by reading: it
	made declaration order load-bearing, said nothing when a required argument
	was simply missing, and broke the moment a control had one property more
	than it had arguments -- which four of the first seven did.

	Names cost one rename: the bound value's parameter was `binding` in five
	controls and the field is `state`, so the parameter is now `state` too. The
	rule has no exception left.

	## Shared, because four copies would drift

	`pui` wrote this first and `cui`, `sui` and `aui` have the same shape: a
	package of controls, a view base class, and two hand-written directions
	facing each other. Copying the reader four times would have been four
	things to keep in step -- which is the defect this module exists to remove,
	one level up. What differs between backends is a `Dialect`: where the
	controls live, what a view is, and (for `nui.macros.Derive`) the cell, the
	readers and the splice. Everything else is one sentence for all of them.

	The examples throughout are `pui`'s, because that is where each rule was
	learned. They are examples, not a dependency: nothing here names a backend.

	## Read on demand, at macro time

	Like `wui.nui.Vocabulary`, and for a reason that matters less here: no
	`pui.ui.*` class carries `@:build`, so nothing forbids using them in a
	macro. Read on demand anyway, because a generated table is a third list to
	keep in step and this module exists to have fewer of those.
**/
class Declarations {
	/** One property of one control, as the two directions both need it. **/
	public static var DUMMY(default, never):Int = 0;

	#if macro
	/**
		Every control that declares a node type, as `type => class path`.

		A type claimed twice is a compile error naming both classes: see the
		class doc for what the tolerant version cost `wui`.
	**/
	public static function types(d:Dialect):Map<String, String> {
		var cache = caches.get(d.pack);
		if (cache != null) return cache;
		cache = new Map();
		caches.set(d.pack, cache);
		var owners = new Map<String, String>();
		for (module in modules(d)) {
			var path = d.pack + "." + module;
			var cls = resolveClass(path);
			if (cls == null) continue;
			var declared = nodeOf(cls);
			if (declared == null) continue;
			var already = owners.get(declared);
			if (already != null) {
				Context.error('Two controls declare the node type "$declared": '
					+ '$already and $path. One name, one class -- see nui.macros.Declarations.',
					cls.pos);
			}
			owners.set(declared, path);
			cache.set(declared, path);
		}
		return cache;
	}

	static var caches:Map<String, Map<String, String>> = new Map();

	/**
		Every declared property of a type, matched to the constructor BY NAME.

		A field whose name is a constructor parameter's fills that argument;
		anything else is assigned after the control is made. Names rather than
		ranks, because a rank is an arithmetic nobody can check by reading: it
		makes declaration order load-bearing, says nothing when a required
		argument is simply missing, and breaks the moment a control has one
		property more than it has arguments -- which four of the first seven
		did.

		Three things are refused here, each naming what to do:

		- a declared name that is neither an argument nor assignable, because
		  there is then no way to put the value in;
		- a required argument no declaration covers, which is the gap a rank
		  rule could not see at all;
		- a type that does not fit the argument of that name.
	**/
	public static function propsFor(d:Dialect, type:String):Array<Prop> {
		var out:Array<Prop> = [];
		var path = types(d).get(type);
		if (path == null) return out;
		var cls = resolveClass(path);
		if (cls == null) return out;

		var params = constructorParams(cls);
		var byName = new Map<String, {name:String, opt:Bool, t:Type}>();
		if (params != null) for (p in params) byName.set(p.name, p);
		var covered = new Map<String, Bool>();

		for (decl in declarations(cls, path, ":prop")) {
			var field = decl.field;
			// `@:prop` with nothing said takes the field's own name.
			var name = decl.args.length == 0 ? field.name : decl.args[0];
			var callback = decl.args.length > 1 ? decl.args[1] : null;

			var arg = byName.get(field.name);
			if (arg != null) {
				covered.set(field.name, true);
				if (!Context.unify(field.type, arg.t)) {
					Context.error('$path: "${field.name}" is the constructor argument of '
						+ "that name, of type " + haxe.macro.TypeTools.toString(arg.t)
						+ ", and the field is " + haxe.macro.TypeTools.toString(field.type)
						+ ".", decl.pos);
				}
			} else if (!writable(field)) {
				Context.error('$path: "${field.name}" is neither a constructor argument '
					+ "nor assignable, so nothing could ever put a value in it.\n"
					+ "  Either name a constructor argument after it, or make the field "
					+ "settable -- see nui.macros.Declarations.", decl.pos);
			}

			out.push({
				field: field.name,
				name: name,
				callback: callback,
				kind: kindOf(field.type, callback != null, decl.pos),
				argument: arg == null ? null : arg.name,
				optional: arg == null ? true : arg.opt,
				nullable: nullable(field.type),
			});
		}

		for (decl in declarations(cls, path, ":children"))
			covered.set(decl.field.name, true);
		for (decl in declarations(cls, path, ":action"))
			covered.set(decl.field.name, true);
		var slot = contentOf(d, cls, path);
		if (slot != null) covered.set(slot, true);

		// A required argument nobody declared: the control cannot be built from
		// a node at all, and a rank rule said nothing about it.
		if (params != null) for (p in params)
			if (!p.opt && !covered.exists(p.name))
				Context.error('$path: the constructor needs "${p.name}", and no property '
					+ "declares it. Add `@:prop` to the field of that name.", cls.pos);

		return out;
	}

	/**
		Read every declaration in the library, so every refusal fires.

		The three checks in `propsFor` only run for a type somebody ASKS about,
		and until the two directions are generated from these declarations
		nobody asks about most of them -- so a control could carry a broken
		declaration for weeks and compile. Proven rather than supposed: adding
		an `Array<Int>` property to `Divider` produced no error at all until
		this existed.

		Called from the tests today, and from the generators when they arrive,
		at which point it becomes what it should be: a thing the build does.
	**/
	public static function verify(d:Dialect):Int {
		var seen = 0;
		for (type in types(d).keys()) {
			propsFor(d, type);
			actionsFor(d, type);
			childrenFor(d, type);
			contentFor(d, type);
			seen++;
		}
		return seen;
	}

	/**
		Every act a control offers, as the wire names it.

		An action is not a property with a function in it: nothing sets it from
		a tree, and it crosses as an action key rather than a value
		(`nui.SelfSource.ACTION_KEYS`). `@:action("onClick")` on a
		`Null<Void->Void>` field says the control has that act; the field's own
		type says what the act carries, so a `String->Void` is the one-argument
		form and needs no second word.
	**/
	public static function actionsFor(d:Dialect, type:String):Array<Action> {
		var out:Array<Action> = [];
		var path = types(d).get(type);
		if (path == null) return out;
		var cls = resolveClass(path);
		if (cls == null) return out;

		for (decl in declarations(cls, path, ":action")) {
			if (decl.args.length == 0) {
				Context.error('$path: `@:action` needs the key it crosses under, '
					+ 'such as `@:action("onClick")`. Unlike `@:prop` there is no '
					+ "field name to fall back on -- a Haxe field called `action` "
					+ "is not an action key.", decl.pos);
			}
			out.push({field: decl.field.name, name: decl.args[0],
				carries: carriedBy(decl.field.type, decl.pos)});
		}
		return out;
	}

	/**
		What a control's children ARE, when they are not views.

		`pui.ui.Picker` holds its options as an `Array<String>`, and the canon
		says a picker's options cross as one `Text` child each -- because a
		renderer that draws pictures in its options reads them as children.
		`@:children("Text", "text")` is that sentence: one child node of that
		type per element, carrying the element under that property.
	**/
	public static function childrenFor(d:Dialect, type:String):Null<Children> {
		var path = types(d).get(type);
		if (path == null) return null;
		var cls = resolveClass(path);
		if (cls == null) return null;

		var found:Null<Children> = null;
		for (decl in declarations(cls, path, ":children")) {
			if (decl.args.length < 2) {
				Context.error('$path: `@:children` needs the child type and the '
					+ 'property each element travels under, such as '
					+ '`@:children("Text", "text")`.', decl.pos);
			}
			if (found != null) {
				Context.error('$path: two fields claim to be the children. A node '
					+ "has one list of them.", decl.pos);
			}
			found = {field: decl.field.name, type: decl.args[0], prop: decl.args[1]};
		}
		return found;
	}

	/**
		Which constructor argument the child views go into, if any.

		A container's children are not one of its fields: `pui.ui.Stack` hands
		them to `View` and keeps nothing, which is right -- `View.children` is
		where a child lives, for every view in the library. So `@:content` names
		the **argument**, on the class, and says only that a node's children
		belong there.

		`@:node("VStack") @:content("content") @:prop("spacing")` is a whole
		column, and the three lines are three different questions: what it is
		called on the wire, where its children go, and what else it carries.
	**/
	public static function contentOf(d:Dialect, cls:ClassType, path:String):Null<String> {
		var meta = cls.meta.extract(":content");
		if (meta.length == 0) return null;
		if (meta[0].params.length == 0) {
			Context.error('$path: `@:content` has to name the constructor argument '
				+ 'the child views go into, such as `@:content("content")`.', meta[0].pos);
		}
		var named = stringOf(meta[0].params[0]);
		var params = constructorParams(cls);
		var found = null;
		if (params != null) for (p in params) if (p.name == named) found = p;
		if (found == null) {
			Context.error('$path: `@:content("$named")` names no constructor argument.',
				meta[0].pos);
		}
		var views = Context.resolveType(arrayOfViews(d), Context.currentPos());
		if (!Context.unify(views, found.t)) {
			Context.error('$path: "$named" is ' + haxe.macro.TypeTools.toString(found.t)
				+ ", and children arrive as Array<" + d.view + ">.", meta[0].pos);
		}
		return named;
	}

	/** Which constructor argument a node's children go into, by node type. **/
	public static function contentFor(d:Dialect, type:String):Null<String> {
		var path = types(d).get(type);
		if (path == null) return null;
		var cls = resolveClass(path);
		return cls == null ? null : contentOf(d, cls, path);
	}

	/**
		One declaration: the field it is about, and the words it was given.

		Written on the field itself, or on the CLASS when the field belongs to a
		superclass -- `@:prop("placeholder")` at the top of `pui.ui.SecretInput`,
		whose `placeholder` is `pui.ui.TextInput`'s field.

		**Metadata is not inherited here, and that is the point.** Reading a
		superclass's `@:prop` would have given `SecretInput` the `text` and
		`onText` of the `TextInput` it extends for the drawing code -- the very
		property whose absence is the type's whole guarantee, put back by
		nothing more than an `extends`. That is the branch-order trap this
		module exists to remove, wearing a different hat. So a subclass says
		what it borrows, one line per property, and `pui.ui.PasswordInput` says
		both of `TextInput`'s because the canon says it is "a `TextInput` in
		every respect but one".
	**/
	static function declarations(cls:ClassType, path:String, of:String):Array<Decl> {
		var out:Array<Decl> = [];

		for (meta in cls.meta.extract(of)) {
			if (meta.params.length == 0) {
				Context.error('$path: `@$of` on a class has to name the field it is '
					+ "about -- that is what it is for, since the field is a "
					+ "superclass's. See nui.macros.Declarations.", meta.pos);
			}
			var borrowed = stringOf(meta.params[0]);
			var field = borrowed == null ? null : fieldNamed(cls, borrowed);
			if (field == null) {
				Context.error('$path: `@$of("$borrowed")` names no field of this class '
					+ "or of anything it extends.", meta.pos);
			}
			out.push({field: field, args: words(meta.params.slice(1)), pos: meta.pos});
		}

		for (field in cls.fields.get()) {
			var meta = field.meta.extract(of);
			if (meta.length == 0) continue;
			out.push({field: field, args: words(meta[0].params), pos: field.pos});
		}
		return out;
	}

	static function words(params:Array<haxe.macro.Expr>):Array<String> {
		var out:Array<String> = [];
		for (p in params) {
			var s = stringOf(p);
			if (s != null) out.push(s);
		}
		return out;
	}

	/** `Array<<the dialect's view>>`, which is how children arrive. **/
	static function arrayOfViews(d:Dialect):haxe.macro.Expr.ComplexType {
		var parts = d.view.split(".");
		var view:haxe.macro.Expr.TypePath = {
			pack: parts.slice(0, parts.length - 1),
			name: parts[parts.length - 1],
			params: [],
		};
		return TPath({pack: [], name: "Array", params: [TPType(TPath(view))]});
	}

	/** A field of this class or of anything it extends. **/
	static function fieldNamed(cls:Null<ClassType>, name:String):Null<ClassField> {
		while (cls != null) {
			for (field in cls.fields.get()) if (field.name == name) return field;
			cls = cls.superClass == null ? null : cls.superClass.t.get();
		}
		return null;
	}

	/** What an action's closure is handed: `Bool`, `Int`, `Float`, `String`, or nothing. **/
	static function carriedBy(t:Type, at:haxe.macro.Expr.Position):Null<String> {
		return switch (t.follow()) {
			case TFun(args, _) if (args.length > 0): kindOf(args[0].t, false, at);
			case _: null;
		}
	}

	/**
		Whether this field can hold null, and so whether a describer has to ask.

		`Text.family` is `Null<String>` and a text that named no family must not
		cross carrying one; `Text.content` is a `String` and always crosses.
		Read from the declared type rather than guessed, because comparing a
		plain `Float` to null is a compile error on a static target -- the
		generated describer would not build at all.
	**/
	static function nullable(t:Type):Bool {
		return switch (t) {
			case TAbstract(ref, _) if (ref.get().name == "Null"): true;
			// An abstract is as nullable as what it is an abstract OVER.
			// `nui.Numbers` is one over `Null<String>`, and reading it as
			// never-null made a text that asked for no particular digits cross
			// carrying `PString(null)` -- a prop present, saying nothing, which
			// is worse than absent.
			case TAbstract(_, _):
				var under = Context.followWithAbstracts(t);
				Std.string(under) == Std.string(t) ? false : nullable(under);
			case TType(_, _): nullable(Context.follow(t, true));
			case TInst(_, _): true;
			case TDynamic(_): true;
			case _: false;
		};
	}

	/** The constructor's arguments, in order, for a generated `new`. **/
	public static function argumentsOf(d:Dialect, type:String):Array<{name:String, opt:Bool}> {
		var path = types(d).get(type);
		if (path == null) return [];
		var cls = resolveClass(path);
		if (cls == null) return [];
		var params = constructorParams(cls);
		return params == null ? [] : [for (p in params) {name: p.name, opt: p.opt}];
	}

	/** What each optional argument falls back to. See `constructorDefaults`. **/
	public static function defaultsOf(d:Dialect, type:String):Map<String, haxe.macro.Expr> {
		var path = types(d).get(type);
		if (path == null) return new Map();
		var cls = resolveClass(path);
		return cls == null ? new Map() : constructorDefaults(cls);
	}

	/** The class that declares a node type, as a path. **/
	public static function classOf(d:Dialect, type:String):Null<String> {
		return types(d).get(type);
	}

	/** Whether a value can be put into this field after construction. **/
	static function writable(field:ClassField):Bool {
		return switch (field.kind) {
			case FVar(_, write):
				switch (write) {
					case AccNormal | AccCall: true;
					case _: false;
				}
			case _: false;
		}
	}

	static function constructorParams(cls:ClassType):Null<Array<{name:String, opt:Bool, t:Type}>> {
		var ctor = cls.constructor;
		if (ctor == null) return null;
		return switch (Context.follow(ctor.get().type)) {
			case TFun(args, _): args;
			case _: null;
		}
	}

	/**
		What an optional constructor argument falls back to, read from the
		constructor itself.

		A generated builder has to pass every argument up to the last one it
		wants to set, so it has to know what "not said" means for the ones in
		between -- `pui.ui.Slider`'s `max` is 1.0, `pui.ui.Image`'s `fit` is
		"contain". Those numbers exist once, in the signature.

		The hand-written renderer restated them (`p.exists("min") ? num(...) :
		0`), which is the same two-lists problem as everything else here: a
		control that changed its default had a renderer that did not. `TFun`
		does not carry defaults, but the constructor's TYPED expression does.
	**/
	static function constructorDefaults(cls:ClassType):Map<String, haxe.macro.Expr> {
		var out = new Map<String, haxe.macro.Expr>();
		var ctor = cls.constructor;
		if (ctor == null) return out;

		var body = try ctor.get().expr() catch (_:Dynamic) null;
		if (body == null) return out;

		switch (body.expr) {
			case TFunction(f):
				for (arg in f.args) {
					if (arg.value == null) continue;
					var literal = switch (arg.value.expr) {
						case TConst(TInt(v)): macro $v{v};
						case TConst(TFloat(v)): macro $v{Std.parseFloat(v)};
						case TConst(TString(v)): macro $v{v};
						case TConst(TBool(v)): macro $v{v};
						case TConst(TNull): macro null;
						case _: null;
					}
					if (literal != null) out.set(arg.v.name, literal);
				}
			case _:
		}
		return out;
	}

	static function stringOf(e:haxe.macro.Expr):Null<String> {
		return switch (e.expr) {
			case EConst(CString(s, _)): s;
			case _: null;
		};
	}

	/**
		What a property carries, as the wire spells it.

		A bound value is read through its `State<T>`, so the kind is the
		parameter's and not the state's.
	**/
	static function kindOf(t:Type, bound:Bool, at:haxe.macro.Expr.Position):String {
		var read = bound ? boundType(t) : t;
		if (read == null) return "String";
		return switch (read.follow()) {
			case TInst(ref, _) if (ref.get().name == "String"): "String";
			case TAbstract(ref, _):
				switch (ref.get().name) {
					case "Bool": "Bool";
					case "Int": "Int";
					case "Float": "Float";
					// Anything else is an abstract over one of those, and the
					// underlying type is what crosses. `nui.Numbers` is the
					// case that made this explicit: it reads as a `Bool` and
					// travels as a string, and answering "String" by falling
					// off the end of a switch would have been right by
					// accident -- which is the failure mode this whole module
					// is against.
					case _:
						// Guarded against an abstract that follows to itself.
						var under = Context.followWithAbstracts(read);
						Std.string(under) == Std.string(read)
							? unspellable(read, at) : kindOf(under, false, at);
				}
			case _: unspellable(read, at);
		}
	}

	/**
		A declared property whose type this module cannot spell.

		It used to answer "String" by falling off the end of a switch, which is
		a guess that looks like an answer -- the describer would have emitted a
		`PString` of whatever `Std.string` made of it, and the renderer would
		have read a string back into a field that is not one.

		`wui` had the same shape and it cost more: a `@:winrt` property of an
		unrecognised type was SKIPPED, its setter never emitted, and a received
		value dropped in silence. A generator that cannot spell a type has to
		say so.
	**/
	static function unspellable(t:Type, at:haxe.macro.Expr.Position):String {
		Context.error("a declared property of type " + haxe.macro.TypeTools.toString(t)
			+ ", which this vocabulary cannot spell.\n"
			+ "  A property crosses as Bool, Int, Float or String. Use one of those, "
			+ "or an abstract over one -- see nui.Numbers for a value whose Haxe form "
			+ "is not its wire form.", at);
		return "String";
	}

	/**
		What a two-way value carries, read from the cell it lives in.

		Any type with `get():T` and `set(T):Void` is a cell: `pui.state.State`
		is one, and so is every one of `cui`'s bindings, which are get/set pairs
		and not `rui` cells at all. Matching on the NAME `State` would have said
		`cui` has no two-way values -- and matching on `rui.state.State` would
		have said the same, which is worse because it would have looked
		principled.

		The shape is the definition. That is the same answer the rest of this
		module gives everywhere else.
	**/
	static function boundType(t:Type):Null<Type> {
		var cls = switch (t.follow()) {
			case TInst(ref, _): ref.get();
			case _: null;
		};
		// A `State<T>` says it directly; anything else is asked for its `get`.
		var params = switch (t.follow()) {
			case TInst(ref, p) if (p.length == 1 && ref.get().name == "State"): p;
			case _: null;
		};
		if (params != null) return params[0];

		var getter = cls == null ? null : fieldNamed(cls, "get");
		if (getter == null) return null;
		return switch (Context.follow(getter.type)) {
			case TFun(args, ret) if (args.length == 0): ret;
			case _: null;
		};
	}

	static function nodeOf(cls:ClassType):Null<String> {
		var meta = cls.meta.extract(":node");
		if (meta.length == 0 || meta[0].params.length == 0) return null;
		return stringOf(meta[0].params[0]);
	}

	static function resolveClass(path:String):Null<ClassType> {
		try {
			return switch (Context.getType(path)) {
				case TInst(ref, _): ref.get();
				case _: null;
			};
		} catch (_:Dynamic) {
			return null;
		}
	}

	/** The `pui.ui` modules on the class path. **/
	static function modules(d:Dialect):Array<String> {
		var found:Array<String> = [];
		for (root in Context.getClassPath()) {
			var dir = root + d.pack.split(".").join("/");
			if (!sys.FileSystem.exists(dir) || !sys.FileSystem.isDirectory(dir)) continue;
			for (file in sys.FileSystem.readDirectory(dir))
				if (StringTools.endsWith(file, ".hx")) {
					var name = file.substr(0, file.length - 3);
					if (found.indexOf(name) < 0) found.push(name);
				}
		}
		return found;
	}
	#end
}

/**
	Which backend's controls are being read, and what a view is there.

	The two things that differ between `pui`, `cui`, `sui` and `aui`: where the
	controls live, and the base class their children arrive as. Everything else
	in this module is the same sentence for all of them, which is why it is here
	rather than copied four times -- four copies of a reader of declarations
	would drift exactly the way the four pairs of hand-written renderers did.
**/
typedef Dialect = {
	/** The package the controls live in, such as `pui.ui`. **/
	var pack:String;

	/** The base class a view is, such as `pui.View`. **/
	var view:String;

	/**
		The cell a two-way value lives in, such as `pui.state.State`.

		Every backend's is a subclass of `rui.state.State`, and every backend
		has its own for its own reasons -- `cui` marks a global dirty flag,
		`sui` notifies Swift, `aui` writes through a Compose bridge. The
		generated builder makes one, so it has to name it.

		Only needed by `nui.macros.Derive`: a backend that declares its controls
		for the markup alone can leave it out.
	**/
	@:optional var state:String;

	/**
		Where the backend keeps `report` and its tolerant callback readers,
		such as `pui.nui.NodeRenderer`. See `nui.macros.Derive`.
	**/
	@:optional var readers:String;

	/**
		What splices a container's view children into its node, such as
		`pui.nui.Describe.appendChildren`.
	**/
	@:optional var appendChildren:String;

	/**
		Where the backend makes a cell out of a received value and a callback.

		Four static functions -- `boolCell`, `intCell`, `floatCell`,
		`stringCell` -- each taking the value the node carried and what to call
		when the control writes. This is the one step a declaration cannot
		describe, because the cell a control takes is the backend's own idea:
		`pui` makes a `pui.state.State` and points its sink at the callback,
		`cui` makes a get/set binding over the captured value. Four functions
		per backend, and the generator calls them by kind.
	**/
	@:optional var cells:String;
}

/** One declared property of one control. **/
typedef Prop = {
	/** The Haxe field it is read from. **/
	var field:String;

	/** The canonical name it travels under. **/
	var name:String;

	/** The action key its writes come back through, for a two-way value. **/
	var callback:Null<String>;

	/** `Bool`, `Int`, `Float` or `String`. **/
	var kind:String;

	/** The constructor argument it fills, by name. For a reader that wants to
		say which one, in a message a person has to act on. **/
	var argument:Null<String>;

	/** Whether that argument may be left out. **/
	var optional:Bool;

	/** Whether the field can hold null, and so whether describing must ask. **/
	var nullable:Bool;
}

/** One act a control offers. **/
typedef Action = {
	/** The Haxe field holding the closure. **/
	var field:String;

	/** The action key it crosses under -- one of `nui.SelfSource.ACTION_KEYS`. **/
	var name:String;

	/** What the closure is handed, or null when it takes nothing. **/
	var carries:Null<String>;
}

/** What a control's children are, when they are not views. **/
typedef Children = {
	/** The Haxe field holding the elements. **/
	var field:String;

	/** The node type each element becomes. **/
	var type:String;

	/** The property that element travels under. **/
	var prop:String;
}

#if macro
/** One `@:prop`, `@:action` or `@:children`, and the field it is about. **/
private typedef Decl = {
	var field:ClassField;
	var args:Array<String>;
	var pos:haxe.macro.Expr.Position;
}
#end
