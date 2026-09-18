package nui;

/**
	Whether digits are of one width, as the wire spells it.

	An application says `true`; the wire says `"tabular"` or says nothing; and
	`nui.TextStyle` has held both halves of that conversion since the canon
	added the prop (`TABULAR`, `isTabular`). What it did not hold was a type, so
	every backend wrote the conversion itself on the way in and on the way out
	-- and one of them, on one side, forgot.

	Here the type is the wire form and the conversion is the cast:

	```haxe
	@:prop("numbers") public var tabular:nui.Numbers = false;   // an application writes true
	if (tabular) …                                              // painting code reads a Bool
	node.prop("numbers", PString(tabular));                     // and the wire gets the word
	```

	## Why not a `Bool` with the conversion in the describer

	Because `pui.nui.Vocabulary` reads a declared field's Haxe type to know what
	crosses, and a `Bool` field that crosses as a string makes the declaration
	say one thing and the wire carry another. The alternative was a third word
	on `@:prop` naming the wire's type -- which says that a conversion exists
	without saying which, so the describer would still have written it by hand.
	A declaration whose type is the answer needs no extra word at all.

	## `false` is absent, not `"proportional"`

	The canon's `numbers` is a request, and its absence is "however this
	renderer sets digits". Saying `"proportional"` would be a second way to
	spell the default, and two spellings of one thing is how the six backends
	drifted apart over fonts in the first place.
**/
abstract Numbers(Null<String>) to Null<String> {
	inline function new(said:Null<String>) this = said;

	/** How an application says it. **/
	@:from public static inline function of(tabular:Bool):Numbers
		return new Numbers(tabular ? TextStyle.TABULAR : null);

	/** How a node says it, whatever case it used. **/
	@:from public static inline function said(v:Null<String>):Numbers
		return new Numbers(TextStyle.isTabular(v) ? TextStyle.TABULAR : null);

	/** How painting code reads it. **/
	@:to public inline function tabular():Bool
		return this == TextStyle.TABULAR;
}
