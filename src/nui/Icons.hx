package nui;

/**
	The names an `Icon` node may carry.

	A short, shared vocabulary rather than a platform's own: a microphone drawn
	by Apple on a Mac and by Google on a phone is the right answer for native
	applications, so each backend maps these names to its platform's icons —
	SF Symbols, Material, Segoe Fluent Icons, the Sailfish theme, a character in
	a terminal. The mapping tables are the backends'; the names are normative,
	like node names.

	A name exists only when every graphical platform can draw it. A meaning no
	platform draws — a video switcher's *cut*, a test pattern — is the
	application's own picture: an `Image`. Adding a name is a change here and in
	six tables, in one pull request, and that friction is the point.

	Names are lower-case words joined by `-`; an `-off` name is its base with a
	stroke through it.
**/
class Icons {
	public static final NAMES:Array<String> = [
		// general
		"add", "close", "check", "delete", "edit", "search", "settings", "home",
		"info", "warning", "error", "menu", "more", "refresh", "share", "star",
		"person", "lock", "unlock", "mail", "phone", "save",
		// direction
		"back", "forward", "up", "down",
		// media
		"play", "pause", "stop", "record", "swap", "broadcast",
		"mic", "mic-off", "speaker", "speaker-off", "headphones",
		// visibility
		"eye", "eye-off",
		// things
		"folder", "document", "image", "camera", "video", "clock",
		"display", "window", "globe", "text", "palette", "grid",
		// arranging
		"layers", "bring-front", "send-back", "crop", "move", "rotate",
	];

	public static function knows(name:Null<String>):Bool
		return name != null && NAMES.indexOf(name) >= 0;

	/**
		The words a screen reader says for an icon that was given no label:
		the name, its dashes as spaces. An icon means something, and a silent
		one is a button nobody can find.
	**/
	public static function spoken(name:String):String
		return StringTools.replace(name, "-", " ");
}
