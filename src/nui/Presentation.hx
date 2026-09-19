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
}
