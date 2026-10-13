package nui;

/**
	How the person reaches the interface: what a control has to be big enough
	for.

	A word, like `nui.Role`, and resolved the same way: by whoever draws. A
	backend says which one it serves -- read from the device, never sniffed
	from an operating-system name -- and its theme turns that into a target
	size, a density and a rounding. The wire never carries a size for this,
	because 44 is a finger on one platform and nothing in particular on the
	next.

	## Four, because there are four ways to aim

	- **pointer** -- a mouse or a trackpad: the most precise, the only one that
	  can hover;
	- **touch** -- a finger on a phone or a tablet;
	- **wrist** -- a finger on a watch, usually while moving;
	- **gaze** -- the eyes, confirmed by a pinch, in a headset.

	They are ordered by how much room a control needs, and not by device: a
	tablet with a trackpad attached is `Pointer` for as long as the trackpad is
	what moves.
**/
enum abstract Modality(String) to String {
	var Pointer = "pointer";
	var Touch = "touch";
	var Wrist = "wrist";
	var Gaze = "gaze";

	/** Every modality, smallest target first. **/
	public static final ALL:Array<Modality> = [Pointer, Touch, Wrist, Gaze];

	/**
		Whether this one can hover: arrive on a control before pressing it. A
		pointer does, and so do the eyes -- looking at a control is the hover
		of a headset. A finger does not, on a phone or on a wrist.
	**/
	public inline function hovers():Bool
		return this == Pointer || this == Gaze;

	/** The modality that word names, or null for anything else. **/
	public static function parse(word:String):Null<Modality> {
		for (m in ALL) if ((m : String) == word) return m;
		return null;
	}
}
