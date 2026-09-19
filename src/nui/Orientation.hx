package nui;

/**
	Which way a control runs.

	Only two, and the second exists because a mixer is columns: a fader and a
	meter per track, side by side.

	## Low at the bottom is meaning, not presentation

	A vertical control runs low at the bottom and high at the top. That is not
	a choice an implementation makes: a fader growing downwards reads as the
	opposite of every mixing desk ever built, and a tree crossing to a machine
	that drew it the other way would be showing the wrong *value*, not a
	different shape.

	The orientation says how it is laid out; which end is the minimum says what
	it means, and the canon states it so no backend has to decide.
**/
enum abstract Orientation(String) to String {
	var Horizontal = "horizontal";
	var Vertical = "vertical";

	/** What a node said, or horizontal for anything else. **/
	@:from public static function said(v:Null<String>):Orientation
		return v != null && v.toLowerCase() == "vertical" ? Vertical : Horizontal;

	/** Whether this one runs bottom to top. **/
	public inline function isVertical():Bool
		return this == "vertical";
}
