package nui;

/**
	What a colour is *for*, when the application would rather not say which one.

	A role crosses as a role and is resolved by whoever draws it. That is the
	whole point and it is worth stating plainly, because the alternative looks
	simpler and is wrong: an application that resolved `Danger` to `#C8323C`
	here would send that number to a panel whose system is in high contrast, or
	in dark mode, or on a platform whose accent the person chose themselves —
	and the panel would have no way to know it was ever a role.

	Same argument as `nui.Scale`, and the same as the fonts canon's "a family is
	a name, never a file". The wire carries the word; the receiver resolves it
	with what it has.

	## Eight, and no named colours

	These eight because each resolves to something real on at least two
	platforms: Windows has an accent the person picks, Apple has semantic
	colours, Material has a colour scheme, and a terminal has sixteen. `Red`,
	`Blue` and the rest are **not** here: a named colour is an rgb with extra
	steps, it cannot resolve to anything per-platform, and carrying it would
	make it look semantic when it is not. An application that wants red asks for
	red — `nui.Color.rgb` — and says so.

	`mui.enums.ColorValue` had thirteen named ones and three semantic ones, and
	no backend ever read any of them.
**/
enum abstract Role(String) to String {
	/** What this platform highlights with, chosen by the person on Windows. **/
	var Accent = "accent";

	/** Something destructive or live: a delete, a recording, a stream on air. **/
	var Danger = "danger";

	/** Something that needs attention and is not yet wrong. **/
	var Warning = "warning";

	/** Something that went right. **/
	var Success = "success";

	/** What a panel's own background is. **/
	var Surface = "surface";

	/** What ordinary text is drawn in, on that surface. **/
	var Text = "text";

	/** Text that matters less: a caption, a hint, a disabled label. **/
	var Muted = "muted";

	/** A line between things. **/
	var Border = "border";

	/** Every role, for a backend's palette to be checked against. **/
	public static final ALL:Array<Role> = [
		Accent, Danger, Warning, Success, Surface, Text, Muted, Border,
	];

	/** The role that word names, or null for anything else. **/
	public static function of(said:Null<String>):Null<Role> {
		if (said == null) return null;
		var lower = said.toLowerCase();
		for (role in ALL) if ((role : String) == lower) return role;
		return null;
	}
}
