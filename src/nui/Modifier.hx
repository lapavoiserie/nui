package nui;

/**
	One entry in a node's modifier chain. The chain is **ordered** — a border
	applied after a padding is not the same as before it — so it is a list, not
	a map.
**/
typedef Modifier = {
	var type:String;
	var ?floats:Array<Float>;
	var ?strings:Array<String>;
}
