package nui;

/**
	A property value carried by a `Node`.

	The scalar cases are what a pull-mode host reads through typed accessors.
	The last three have **no equivalent in pull mode**, because they only make
	sense when Haxe is the side that pushes:

	- `PReactive` — the value is a thunk. A renderer wraps the application of
	  *this one property* in `NodeSink.bindReactive`, which is what gives
	  per-binding granularity: a write re-applies one property, with no tree
	  walk and no diff.
	- `PCallbackString` / `PCallbackFloat` / `PCallbackInt` — the renderer reads
	  the **live value of the native control** and passes it to the callback.
	  This is what makes a two-way control work: the text in the field is the
	  truth at the moment of the tap, not what Haxe last wrote.
**/
enum PropValue {
	PString(v:String);
	PInt(v:Int);
	PFloat(v:Float);
	PBool(v:Bool);

	/** Plain event handler. **/
	PCallback(fn:Void->Void);

	/** Handler that receives the control's live text. **/
	PCallbackString(fn:String->Void);

	/** Handler that receives the control's live numeric value. **/
	PCallbackFloat(fn:Float->Void);

	/** Handler that receives the control's live integer value. **/
	PCallbackInt(fn:Int->Void);

	/** Deferred value; the renderer binds it through `bindReactive`. **/
	PReactive(thunk:Void->PropValue);
}

class PropValueTools {
	/**
		Resolve a `PReactive` down to a concrete value. Non-reactive values are
		returned as-is. Nested reactives are resolved to a fixed point, so a
		thunk returning a thunk is not a trap.
	**/
	public static function resolve(v:Null<PropValue>):Null<PropValue> {
		var current = v;
		var guard = 0;
		while (current != null && guard++ < 32) {
			switch (current) {
				case PReactive(thunk): current = thunk();
				case _: return current;
			}
		}
		return current;
	}

	/**
		Compare two property values by their **resolved** content, so the coarse
		reconcile path can tell a real change from a re-evaluated thunk that
		produced the same thing. Callbacks compare by reference.
	**/
	public static function equals(a:Null<PropValue>, b:Null<PropValue>):Bool {
		var ra = resolve(a);
		var rb = resolve(b);
		if (ra == null || rb == null) return ra == rb;
		return switch [ra, rb] {
			case [PString(x), PString(y)]: x == y;
			case [PInt(x), PInt(y)]: x == y;
			case [PFloat(x), PFloat(y)]: x == y;
			case [PBool(x), PBool(y)]: x == y;
			case [PCallback(x), PCallback(y)]: Reflect.compareMethods(x, y);
			case [PCallbackString(x), PCallbackString(y)]: Reflect.compareMethods(x, y);
			case [PCallbackFloat(x), PCallbackFloat(y)]: Reflect.compareMethods(x, y);
			case [PCallbackInt(x), PCallbackInt(y)]: Reflect.compareMethods(x, y);
			case _: false;
		}
	}

	/**
		Typed, null-safe readers. **Use these rather than switching yourself.**

		A property that is absent resolves to `null`, and on a compiled target
		(hxcpp) `switch` on a null enum is a **segmentation fault**, not a caught
		error. Interpreted runs never show it, so hand-rolled switches pass every
		`--interp` check and crash the first compiled backend that reads a
		property a node does not carry.
	**/
	public static function asString(v:Null<PropValue>, def:String = ""):String {
		var r = resolve(v);
		if (r == null) return def;
		return switch (r) {
			case PString(x): x;
			case _: def;
		}
	}

	public static function asInt(v:Null<PropValue>, def:Int = 0):Int {
		var r = resolve(v);
		if (r == null) return def;
		return switch (r) {
			case PInt(x): x;
			case _: def;
		}
	}

	/** Accepts an `PInt` too: a whole number is a valid float. **/
	public static function asFloat(v:Null<PropValue>, def:Float = 0.0):Float {
		var r = resolve(v);
		if (r == null) return def;
		return switch (r) {
			case PFloat(x): x;
			case PInt(x): x;
			case _: def;
		}
	}

	public static function asBool(v:Null<PropValue>, def:Bool = false):Bool {
		var r = resolve(v);
		if (r == null) return def;
		return switch (r) {
			case PBool(x): x;
			case _: def;
		}
	}
}
