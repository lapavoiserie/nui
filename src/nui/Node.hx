package nui;

/**
	A node in push mode.

	In **pull mode** there is no such class: the node *is* the backend's own view
	object, read through `NodeSource`. This class exists for **push mode**, where
	Haxe builds the tree, diffs it and applies targeted patches — because the
	host (Qt/Silica, a terminal) does no diffing of its own.

	Both modes describe the same vocabulary; only who holds the tree differs.
**/
class Node {
	/** Discriminant a renderer switches on: `"VStack"`, `"Text"`, `"Button"`… **/
	public var type:String;

	/**
		Stable identity among siblings. `null` means positional identity.

		Worth setting on anything the user interacts with: without it a
		reconciler can destroy and rebuild a control that only moved, which on a
		text field means losing focus and caret mid-typing.
	**/
	public var key:Null<String>;

	public var props:Map<String, PropValue>;

	/** Ordered; the order is significant. **/
	public var modifiers:Array<Modifier>;

	public var children:Array<Node>;

	/**
		Deferred children. When set, `children` is produced by calling this, and
		a renderer may re-evaluate **only this node's** list when its dependencies
		change — a list re-reconciles itself without touching its surroundings.
	**/
	public var childrenThunk:Null<Void->Array<Node>>;

	public function new(type:String, ?key:String) {
		this.type = type;
		this.key = key;
		this.props = new Map();
		this.modifiers = [];
		this.children = [];
		this.childrenThunk = null;
	}

	public function prop(key:String, value:PropValue):Node {
		props.set(key, value);
		return this;
	}

	public function modifier(m:Modifier):Node {
		modifiers.push(m);
		return this;
	}

	public function child(node:Node):Node {
		children.push(node);
		return this;
	}

	/** Resolve the children, whether they are eager or deferred. **/
	public function resolveChildren():Array<Node> {
		if (childrenThunk != null) {
			children = childrenThunk();
		}
		return children;
	}

	public function toString():String {
		return "Node(" + type + (key != null ? "#" + key : "") + ", " + children.length + " children)";
	}
}
