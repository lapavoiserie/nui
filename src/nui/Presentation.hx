package nui;

/**
	How a control should be shown, when the choice is only about shape.

	A **hint**, and it fails soft: a backend that has no such presentation draws
	its ordinary one, and nothing is lost but the shape.

	That is the right answer here and the wrong one for `PasswordInput`, and the
	difference is worth naming rather than leaving to taste. A forgotten
	presentation shows the same choices in a different shape; a forgotten
	password shows the password. **A flag may fail open only where opening is
	harmless** — which is why masking is a type and this is a string.
**/
class Presentation {
	/**
		A `Picker` shown as a row of buttons rather than a list that opens.

		Two or three short labels — Preview/Program, 30/60 — read better side by
		side; a dozen sources do not, which is why this is asked for rather than
		assumed.
	**/
	public static inline var SEGMENTED = "segmented";

	/** Whether a control was asked to be shown this way. **/
	public static function isSegmented(said:Null<String>):Bool
		return said != null && said.toLowerCase() == SEGMENTED;

	/** A `Button` that is the one act its screen is for: prominent, in the accent. **/
	public static inline var PRIMARY = "primary";

	/** A `Button` without chrome, for the secondary acts of a row. **/
	public static inline var PLAIN = "plain";

	/**
		A `Button` drawn as a round mark that ticks a thing off; its `checked`
		says whether it is ticked, and its label is spoken rather than shown.
	**/
	public static inline var CHECK = "check";

	/** Whether a control was asked for `style` (any of the above), in any case. **/
	public static function is(said:Null<String>, style:String):Bool
		return said != null && said.toLowerCase() == style;
}
