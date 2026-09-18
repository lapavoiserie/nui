package nui;

/**
	One of the four steps a `Text` is set in, as the wire spells it.

	`nui.TextStyle` already owned this conversion -- `scaleOf` normalises what a
	node said, and every backend called it by hand on the way in. What it did
	not own was a **type**, so a backend was free to keep its scale as something
	else and convert at each boundary. `pui` kept an `enum`, and converted in
	three places: once describing, once building, once mapping `mui`'s enum onto
	its own.

	Here the type IS the wire form, and the conversion is the cast. Three of the
	six backends already stored a normalised `String`, which is this abstract
	without the name.

	## An `enum abstract`, so `Title` is still written `Title`

	Four named values that a `switch` can be exhaustive over, and that resolve
	unqualified where a `Scale` is expected -- which is what an `enum` gave and
	what replacing it must not take away. The difference is underneath: the
	value IS the word the wire carries, so describing it is a cast and not a
	four-armed conversion.

	## Anything unknown is `body`

	`@:from` normalises rather than refuses, which is `scaleOf`'s rule and the
	right one for a value arriving from elsewhere: a node that says `largeTitle`
	is a node from a platform with eleven steps, and running text is what the
	four intersect at. A scale an APPLICATION writes is a different matter --
	there the four constants below are the whole vocabulary, and a typo is a
	compile error because no other name exists to write.
**/
enum abstract Scale(String) to String {
	/** A page's title. **/
	var Title = "title";

	/** A heading inside it. **/
	var Subtitle = "subtitle";

	/** Running text, and what anything unrecognised becomes. **/
	var Body = "body";

	/** Something set smaller. **/
	var Caption = "caption";

	/** What a node said, normalised to one of the four. **/
	@:from public static inline function said(v:Null<String>):Scale
		return cast TextStyle.scaleOf(v);

	public inline function toString():String
		return this;
}
