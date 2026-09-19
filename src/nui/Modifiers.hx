package nui;

/**
	The modifier names a node may carry, and what each one carries.

	`nui.Modifier` has always said a modifier is `{type, floats, strings}` and an
	ordered list. It never said what `type` may be — so six backends each
	invented their own set, and by the time anybody counted they had drifted
	exactly the way the node types had:

	| | emitted |
	|---|---|
	| `pui` | backgroundColor, border, clip, opacity, padding |
	| `cui` | alignment, backgroundColor, border, foregroundColor, height, padding, width |
	| `aui` | backgroundColor, bold, border, cornerRadius, font, foregroundColor, italic, opacity, padding, paddingHorizontal, paddingVertical |

	`pui` never sent a `foregroundColor`, so text colour did not cross from it at
	all. `aui` sent `font`, `bold` and `italic` as modifiers while the fonts
	canon had already made weight, italic and family **props of `Text`** — the
	same thing said twice, in two vocabularies, and a receiver sees whichever it
	happens to read.

	## The nine

	Named here so they can be checked, and kept to what a backend can honestly
	honour:

	- **`padding`** — four floats, top right bottom left, in that order.
	- **`backgroundColor`** — one `nui.Color`, and optionally one float: the
	  corner radius it is drawn with.
	- **`foregroundColor`** — one `nui.Color`: what text and icons are drawn in.
	- **`border`** — one `nui.Color`, then width and radius as floats.
	- **`opacity`** — one float, 0 to 1.
	- **`clip`** — nothing: children are cut at this view's edge.
	- **`width`** / **`height`** — one float each, a size asked for rather than
	  measured.
	- **`flex`** — one float: this view's share of what is left over along the
	  main axis. `pui` has read it since before there was a canon and nothing
	  named it, so the markup refused to write one.

	## What is deliberately not here

	**`cornerRadius` on its own.** A radius belongs to the thing being rounded,
	and `backgroundColor` and `border` each carry theirs. A free-standing one
	has to be applied to whatever happens to come next, which is an ordering
	rule nobody can read off the list.

	**`font`, `bold`, `italic`.** They are `Text`'s properties since the fonts
	canon, and carrying them here as well is how a text ends up italic on one
	backend and upright on another.

	**`paddingHorizontal` and `paddingVertical`.** `padding` takes four floats
	and says everything they said.

	**`alignment`.** It is not a decoration: it changes how a parent places a
	child, which is the parent's business, and no two backends meant the same
	thing by it.

	## Order is the semantics

	This is a list and not a map, and the reason is in `nui.Modifier`: a border
	applied after a padding is not the same as one applied before it. A backend
	reads the list in order; a backend that cannot honour one skips that entry
	and honours the rest.
**/
class Modifiers {
	/** Four floats: top, right, bottom, left. **/
	public static inline var PADDING = "padding";

	/** A `nui.Color`, and optionally the radius it is drawn with. **/
	public static inline var BACKGROUND_COLOR = "backgroundColor";

	/** A `nui.Color`: what text and icons are drawn in. **/
	public static inline var FOREGROUND_COLOR = "foregroundColor";

	/** A `nui.Color`, then width and radius. **/
	public static inline var BORDER = "border";

	/** One float, 0 to 1. **/
	public static inline var OPACITY = "opacity";

	/** Nothing: children are cut at this view's edge. **/
	public static inline var CLIP = "clip";

	/** One float: a width asked for rather than measured. **/
	public static inline var WIDTH = "width";

	/** One float: a height asked for rather than measured. **/
	public static inline var HEIGHT = "height";

	/**
		One float: this view's share of what is left over along the main axis.

		`pui` has read this since before there was a canon -- its renderer maps
		it to `View.grow` -- and nothing named it, so `ui()` refused to write
		one. A panel could not give two thirds of a row to its monitors and one
		third to its inspector, nor hand a scroll view the rest of a column,
		without building the modifier by hand beside markup that was checked.

		A backend with no notion of leftover space skips it, like any other
		modifier it cannot honour.
	**/
	public static inline var FLEX = "flex";

	/** Every name, in no particular order — a list is not a chain. **/
	public static final NAMES:Array<String> = [
		PADDING, BACKGROUND_COLOR, FOREGROUND_COLOR, BORDER,
		OPACITY, CLIP, WIDTH, HEIGHT, FLEX,
	];

	/** Whether this is a modifier at all. **/
	public static function knows(name:Null<String>):Bool
		return name != null && NAMES.indexOf(name) >= 0;

	/**
		What each modifier carries, in the order it carries it.

		`border` is "a colour, then a width and a radius" -- the wire has always
		said so, and the markup could only write the colour, so an application
		wanting a 3-pixel border had to add the modifier by hand beside markup
		that was checked. Named here so an attribute can be written whole:

		```haxe
		<Tappable border={{colour: Color.role(Success), width: 3, radius: 6}}/>
		<VStack padding={{top: 8, left: 12}}/>
		```

		Three names rather than one -- `borderWidth`, `borderRadius` -- would
		have reopened the door this list closed on a free-standing
		`cornerRadius`: a radius belongs to the thing it rounds, and a floating
		one has to apply to whatever comes next, which nobody can read off a
		list.

		## `fill` — what an unnamed float means

		The two modifiers with several floats do not mean the same thing by
		silence, and that is not an inconsistency to iron out:

		- **`padding` fills.** Its floats are four edges, and an edge nobody
		  mentioned has no padding. Zero is the answer, and writing
		  `{top: 8}` means *only* the top -- not `8` everywhere, which is what
		  the positional short form `padding={8}` means and which is exactly
		  why an object must not be read as a short form.
		- **`border` and `backgroundColor` do not fill.** Their last float is a
		  radius, and an unnamed radius is the one the control draws with
		  naturally -- a zero would square the corners of a button that had
		  round ones, which nobody writing `{colour: …, width: 3}` asked for.
		  So an unnamed trailing float is simply not written, and naming a
		  later part without an earlier one (a radius with no width) is refused
		  rather than filled with a zero that would draw no border at all.
	**/
	public static function partsOf(name:Null<String>):Null<ModifierParts> {
		return switch (name) {
			case BACKGROUND_COLOR: {strings: ["colour"], floats: ["radius"], fill: false};
			case FOREGROUND_COLOR: {strings: ["colour"], floats: [], fill: false};
			case BORDER: {strings: ["colour"], floats: ["width", "radius"], fill: false};
			case PADDING: {strings: [], floats: ["top", "right", "bottom", "left"], fill: true};
			case OPACITY: {strings: [], floats: ["opacity"], fill: false};
			case WIDTH: {strings: [], floats: ["width"], fill: false};
			case HEIGHT: {strings: [], floats: ["height"], fill: false};
			case FLEX: {strings: [], floats: ["flex"], fill: false};
			case _: null;
		}
	}

	/**
		What kind of value this modifier's attribute takes, in `mui`'s alphabet.

		`mui`'s markup writes a modifier as an attribute, so it needs the same
		answer it gets for a property. A colour is a `KString` because
		`nui.Color` is one; a `clip` takes nothing, and the markup writes it as
		a `KBool` so `clip={true}` reads the way it means.
	**/
	public static function kindOf(name:Null<String>):Null<String> {
		return switch (name) {
			case BACKGROUND_COLOR | FOREGROUND_COLOR | BORDER: "KString";
			case PADDING | OPACITY | WIDTH | HEIGHT | FLEX: "KFloat";
			case CLIP: "KBool";
			case _: null;
		}
	}
}

/** What one modifier carries, part by part. See `Modifiers.partsOf`. **/
typedef ModifierParts = {
	/** The strings it carries, in order. Always a colour, so far. **/
	var strings:Array<String>;

	/** The floats it carries, in order. **/
	var floats:Array<String>;

	/** Whether a float nobody named is a zero (true) or simply absent. **/
	var fill:Bool;
}
