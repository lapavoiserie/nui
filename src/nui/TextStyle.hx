package nui;

/**
	What a `Text` node may say about how it is set.

	Five things, and they are the ones every backend can mean: a **scale**, a
	**family**, a **weight**, **italic**, and whether **numbers** are of one
	width. A terminal honours the last three and ignores the first two, which is
	not a lack: a cell is one size and one font.

	## Props, not modifiers

	These cross as properties of the node. `nui`'s modifier chain could carry
	them -- it carried a "font" for a while -- and that is exactly how the six
	backends drifted apart: one sent a step of its own vocabulary in `strings`,
	another read a pixel size from `floats`, a third discards inbound modifiers
	on purpose because it has properties and not modifiers, and a fourth emitted
	none at all, so a heading crossed as ordinary text. A prop with a name
	written down here is what stopped that happening to pictures.

	## The scale is what the text is

	`title`, `subtitle`, `body`, `caption`: a page's title, a heading inside it,
	running text, something set smaller. Four, because eleven steps on one
	platform and none on another intersect at four. Anything finer is a
	backend's own vocabulary, and reaching for it is choosing that platform
	deliberately.

	## The family is one the receiver has

	A name, never a file. A tree carries `family: "Inter"`, and a renderer uses
	it if the application it belongs to ships that family (`mui.Fonts`); a
	renderer that has never heard of it draws its own default, silently. A
	picture is pulled by content and verified because a picture is data on a
	screen; installing a typeface is an act on a machine, and a panel that
	accepted one from whoever is projecting would accept rather more than a
	picture. A wrong picture is a lie; a wrong typeface is a disappointment.
**/
class TextStyle {
	/** The four steps, in the order they are set. **/
	public static final SCALES:Array<String> = ["title", "subtitle", "body", "caption"];

	/** What a `numbers` of `"tabular"` asks for: digits of one width. **/
	public static inline var TABULAR = "tabular";

	/** Running text, when a node says nothing. **/
	public static inline var DEFAULT_SCALE = "body";

	/** The weight of text nobody weighted. **/
	public static inline var DEFAULT_WEIGHT = 400;

	/** A scale a node carries, or `body` for anything else. **/
	public static function scaleOf(said:Null<String>):String {
		if (said == null) return DEFAULT_SCALE;
		var lower = said.toLowerCase();
		return SCALES.indexOf(lower) >= 0 ? lower : DEFAULT_SCALE;
	}

	/** Whether a node's `scale` names one of the four. **/
	public static function knowsScale(said:Null<String>):Bool
		return said != null && SCALES.indexOf(said.toLowerCase()) >= 0;

	/**
		A weight in the vocabulary every font file uses: 100 to 900, in
		hundreds. What is not one of those is rounded to the nearest, because a
		font has the weights it has and a renderer must ask for one of them.
	**/
	public static function weightOf(said:Null<Float>):Int {
		if (said == null || Math.isNaN(said)) return DEFAULT_WEIGHT;
		var rounded = Math.round(said / 100) * 100;
		if (rounded < 100) return 100;
		if (rounded > 900) return 900;
		return Std.int(rounded);
	}

	/** Whether this weight asks for more than ordinary text. **/
	public static inline function isBold(weight:Int):Bool
		return weight >= 600;

	/** Whether a node asks for digits of one width. **/
	public static function isTabular(said:Null<String>):Bool
		return said != null && said.toLowerCase() == TABULAR;
}
