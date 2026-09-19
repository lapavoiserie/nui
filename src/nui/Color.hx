package nui;

/**
	A colour, as the wire carries it: `"role:danger"` or `"#c8323c"`.

	Two ways to say one, and they are not the same kind of thing:

	```haxe
	Color.role(Danger)             // what it is FOR — the receiver resolves it
	Color.rgb(200, 50, 60)         // what it IS — nobody resolves anything
	Color.rgba(200, 50, 60, 128)   // the same, half transparent
	Color.hex("#C8323C")           // the same again, written the other way
	```

	## Why a role stays a role

	A role resolved here is a number sent to a machine that knows better. The
	panel receiving it may be in dark mode, in high contrast, or on a platform
	whose accent the person chose themselves, and a `#C8323C` arriving from
	elsewhere carries no trace of having once meant "danger". So the word
	crosses and the receiver resolves — `nui.Role` says why at more length.

	An application that wants a particular red is not doing that. It says
	`rgb(200, 50, 60)`, which travels as itself and means the same everywhere,
	and the declaration of intent is that it did not ask for a role.

	## One type, one kind on the wire

	An abstract over the `String` the wire carries, like `nui.Scale`. That is
	not a detail: it means a colour is a `KString` everywhere — the markup needs
	nothing new to write one, `@:prop` reads it with no extra word, and a
	backend reading a modifier gets what it already got, only with a canon
	behind it.

	## What a backend does with one

	```haxe
	switch (Color.roleOf(said)) {
		case null:  // a component colour; Color.rgbOf gives the three numbers
		case role:  // this platform's own colour for that role
	}
	```

	A backend that cannot represent a colour exactly **approximates and says so
	in its documentation** — `cui` has sixteen and picks the nearest. That is the
	same answer the fonts canon gives for a terminal with one font: it honours
	what it can and ignores the rest, and the place to learn that is its page,
	not a surprise on screen.
**/
abstract Color(String) to String {
	inline function new(said:String) this = said;

	/** The prefix that tells a role from a component colour. **/
	public static inline var ROLE = "role:";

	/** A colour named by what it is for. **/
	public static inline function role(of:Role):Color
		return new Color(ROLE + (of : String));

	/** A colour named by its components, each 0 to 255. **/
	public static function rgb(r:Int, g:Int, b:Int):Color
		return new Color("#" + pair(r) + pair(g) + pair(b));

	/**
		The same, with an opacity: 0 invisible, 255 solid.

		**Alpha last**, as CSS writes it and as every recent format does.
		`pui.render.Color` puts it first, which is the platform's order and not
		the wire's -- a backend converts, and that conversion is the reason to
		have one form written down at all.
	**/
	public static function rgba(r:Int, g:Int, b:Int, a:Int):Color
		return new Color("#" + pair(r) + pair(g) + pair(b) + pair(a));

	/**
		A colour written as `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`, in either
		case. The short forms are each digit doubled, and the opacity is last.

		Anything else is **refused** rather than quietly becoming black: a
		colour is a thing an author writes by hand, and a typo in one is
		exactly the kind of mistake that shows up as a wrong pixel nobody
		traces. Null, and the caller decides.
	**/
	public static function hex(said:Null<String>):Null<Color> {
		if (said == null) return null;
		var body = StringTools.startsWith(said, "#") ? said.substr(1) : said;
		// 3 and 4 are the short forms, each digit doubled; 6 and 8 the long
		// ones. The fourth is the opacity, and it is LAST.
		if (body.length != 3 && body.length != 4 && body.length != 6 && body.length != 8)
			return null;
		var short = body.length <= 4;
		var out = new StringBuf();
		for (i in 0...body.length) {
			var c = body.charAt(i).toLowerCase();
			if ("0123456789abcdef".indexOf(c) < 0) return null;
			out.add(c);
			// `#f00` is `#ff0000`: each digit doubled, which is what every
			// other language that accepts the short form does.
			if (short) out.add(c);
		}
		return new Color("#" + out.toString());
	}

	/** What a node said, whatever it said. **/
	@:from public static function said(v:Null<String>):Null<Color> {
		if (v == null) return null;
		if (StringTools.startsWith(v, ROLE))
			return Role.of(v.substr(ROLE.length)) == null ? null : new Color(v.toLowerCase());
		return hex(v);
	}

	/** The role this names, or null when it names components instead. **/
	public static function roleOf(said:Null<String>):Null<Role> {
		if (said == null || !StringTools.startsWith(said, ROLE)) return null;
		return Role.of(said.substr(ROLE.length));
	}

	/**
		The components and the opacity, or null for a role.

		Null is the answer a backend has to handle: it means "ask your palette",
		not "no colour". Returning black for a role is how a `danger` button
		comes out black on the one platform that forgot to resolve it.
	**/
	public static function rgbOf(said:Null<String>):Null<{r:Int, g:Int, b:Int, a:Int}> {
		var colour = said == null ? null : hex(said);
		if (colour == null) return null;
		var body = (colour : String).substr(1);
		return {
			r: Std.parseInt("0x" + body.substr(0, 2)),
			g: Std.parseInt("0x" + body.substr(2, 2)),
			b: Std.parseInt("0x" + body.substr(4, 2)),
			// A colour written without one is solid. Absent is not
			// transparent: nobody writing `#c8323c` meant invisible.
			a: body.length == 8 ? Std.parseInt("0x" + body.substr(6, 2)) : 255,
		};
	}

	public inline function toString():String
		return this;

	static function pair(v:Int):String {
		var clamped = v < 0 ? 0 : v > 255 ? 255 : v;
		var hex = StringTools.hex(clamped, 2).toLowerCase();
		return hex;
	}
}
