import nui.Node;
import nui.Modifier;
import nui.PropValue;

/**
	Standalone check of the node model, and a toy implementation of each
	contract to prove both are satisfiable.

	    haxe -cp src -cp test -lib rui -main Check --interp
**/
class Check {
	static var fails = 0;
	// Counted rather than written down: a total in the docs that nobody
	// recomputes drifts, and this one had - the docs said 23 for 29 checks.
	static var checks = 0;

	static function check(label:String, ok:Bool) {
		checks++;
		if (!ok) fails++;
		Sys.println((ok ? "ok   " : "FAIL ") + label);
	}

	static function main() {
		// --- Node ---
		var text = new Node("Text").prop("text", PString("bonjour"));
		var root = new Node("VStack").child(text).child(new Node("Button", "add").prop("label", PString("Ajouter")));
		check("type", root.type == "VStack");
		check("children", root.children.length == 2);
		check("key null par défaut", text.key == null);
		check("key explicite", root.children[1].key == "add");

		// --- Modificateurs ordonnés ---
		root.modifier({type: "padding", floats: [12]}).modifier({type: "border", floats: [1], strings: ["#333"]});
		check("chaîne de modificateurs ordonnée", root.modifiers[0].type == "padding" && root.modifiers[1].type == "border");

		// --- Enfants différés ---
		var count = 3;
		var list = new Node("List");
		list.childrenThunk = () -> [for (i in 0...count) new Node("Text", "row" + i)];
		check("thunk évalué à la demande", list.resolveChildren().length == 3);
		count = 5;
		check("thunk ré-évalué", list.resolveChildren().length == 5);

		// --- PropValue réactive ---
		var n = 1;
		var reactive = PReactive(() -> PInt(n));
		check("resolve traverse le thunk", Type.enumEq(PropValueTools.resolve(reactive), PInt(1)));
		n = 2;
		check("resolve relit la valeur vivante", Type.enumEq(PropValueTools.resolve(reactive), PInt(2)));
		check("resolve laisse passer un scalaire", Type.enumEq(PropValueTools.resolve(PString("x")), PString("x")));
		var nested = PReactive(() -> PReactive(() -> PBool(true)));
		check("resolve gère l'imbrication", Type.enumEq(PropValueTools.resolve(nested), PBool(true)));

		// --- equals compare le RÉSOLU ---
		n = 7;
		check("equals compare le résolu", PropValueTools.equals(PReactive(() -> PInt(n)), PInt(7)));
		check("equals distingue", !PropValueTools.equals(PInt(1), PInt(2)));
		var fn = () -> {};
		check("equals sur callback par référence", PropValueTools.equals(PCallback(fn), PCallback(fn)));

		// --- Les deux contrats sont implémentables ---
		var src = new ToySource(root);
		check("NodeSource.root", src.typeOf(src.root()) == "VStack");
		check("NodeSource.childAt", src.typeOf(src.childAt(src.root(), 0)) == "Text");
		check("NodeSource.stringProp", src.stringProp(src.childAt(src.root(), 0), "text") == "bonjour");
		check("NodeSource.keyOf", src.keyOf(src.childAt(src.root(), 1)) == "add");
		check("NodeSource.hasProp", !src.hasProp(src.root(), "text"));
		check("NodeSource.modifierType", src.modifierType(src.root(), 0) == "padding");

		var sink = new ToySink();
		var native = sink.create(root, null);
		sink.applyProp(native, "VStack", "text", PString("posé"));
		check("NodeSink.create + applyProp", sink.log.join(",") == "create:VStack,prop:text=posé");

		var wrapped = 0;
		var stopped = 0;
		sink.bindReactive = function(f) { wrapped++; f(); return () -> stopped++; };
		sink.applyProp(native, "VStack", "label", PReactive(() -> PString("deferred")));
		check("NodeSink.bindReactive wraps the application", wrapped == 1);
		check("bindReactive resolves the thunk", sink.log[sink.log.length - 1] == "prop:label=deferred");

		// A binding outlives its node unless destroy stops it: the effect it
		// made is subscribed to signals the application keeps for its whole run,
		// so a later write would apply a property to a freed handle.
		check("a binding is not stopped before its node goes", stopped == 0);
		sink.destroy(native);
		check("destroy stops every binding made against the handle", stopped == 1);

		// --- Propriété absente : le piège qui ne se voit qu'en compilé ---
		// resolve(null) renvoie null, et un switch sur un enum null SEGFAULTE
		// sur hxcpp. Ces lectures doivent renvoyer le défaut, pas planter.
		var empty = new Node("Empty");
		check("asString sur absente", PropValueTools.asString(empty.props.get("nope")) == "");
		check("asInt sur absente", PropValueTools.asInt(empty.props.get("nope"), -1) == -1);
		check("asFloat sur absente", PropValueTools.asFloat(empty.props.get("nope"), 1.5) == 1.5);
		check("asBool sur absente", PropValueTools.asBool(empty.props.get("nope"), true) == true);
		check("stringProp sur absente ne plante pas", src.stringProp(empty, "nope") == "");
		check("equals tolerates null", !PropValueTools.equals(null, PInt(1)) && PropValueTools.equals(null, null));

		// --- Snapshot: the tree as pure data, closures as ids ---
		var taps = [];
		var typedIn = "";
		var live = new Node("VStack")
			.child(new Node("Text").prop("text", PReactive(() -> PString("sampled"))))
			.child(new Node("Button", "go")
				.prop("label", PString("Go"))
				.prop("onClick", PCallback(() -> taps.push(1)))
				.modifier({type: "padding", floats: [8]}))
			.child(new Node("Field").prop("onText", PCallbackString(t -> typedIn = t)));
		var lazy = new Node("List");
		lazy.childrenThunk = () -> [new Node("Row", "r0")];
		live.child(lazy);

		var table = new nui.Snapshot.ActionTable();
		var snap = nui.Snapshot.project(live, table);
		check("a reactive prop is sampled to its scalar", snap.children[0].props.get("text") == "sampled");
		check("a scalar prop crosses as itself", snap.children[1].props.get("label") == "Go");
		check("a callback becomes an id, not a prop", snap.children[1].props.get("onClick") == null
			&& snap.children[1].actions.get("onClick") != null);
		check("modifiers ride along as plain data", snap.children[1].modifiers[0].type == "padding");
		check("children thunks are forced - a snapshot samples the whole picture",
			snap.children[3].children.length == 1 && snap.children[3].children[0].key == "r0");

		// The wire: Json both ways, then the actions still answer.
		var back = nui.Snapshot.fromJson(nui.Snapshot.toJson(snap));
		check("the snapshot survives the wire", back.children[1].actions.get("onClick") == snap.children[1].actions.get("onClick")
			&& back.children[0].props.get("text") == "sampled");
		table.invoke(back.children[1].actions.get("onClick"));
		check("a remote tap reaches the closure by id", taps.length == 1);
		table.invoke(back.children[2].actions.get("onText"), "hello");
		check("a typed action carries the live value back", typedIn == "hello");
		table.invoke(999);
		check("a stale id is a word, never a crash", true);
		table.clear();
		table.invoke(back.children[1].actions.get("onClick"));
		check("a cleared generation answers nothing", taps.length == 1);

		// --- Inflate: the far side of the wire ---
		// A received snapshot becomes an ordinary Node tree whose actions are
		// closures handing ids back - a NodeRenderer cannot tell the difference.
		var sentIds = [];
		var sentArgs = [];
		var remote = nui.Snapshot.inflate(back, (id, arg) -> { sentIds.push(id); sentArgs.push(arg); });
		check("an inflated tree is ordinary nodes", remote.type == "VStack" && remote.children.length == 4);
		check("scalar props inflate to their shapes",
			PropValueTools.asString(remote.children[0].props.get("text")) == "sampled");
		check("modifiers survive the roundtrip", remote.children[1].modifiers[0].type == "padding");
		var clickBack = remote.children[1].props.get("onClick");
		switch (clickBack) {
			case PCallbackString(fn): fn("");
			case _:
		}
		check("an inflated action hands its id back over the channel",
			sentIds.length == 1 && sentIds[0] == back.children[1].actions.get("onClick"));
		switch (remote.children[2].props.get("onText")) {
			case PCallbackString(fn): fn("typed remotely");
			case _:
		}
		check("a typed action carries the remote value", sentArgs[1] == "typed remotely");

		// --- Stable ids by place: the tap-vs-beat race, closed ---
		// The serving state beat every 2s, each beat cleared the table, and a
		// human's Enter reliably found a freshly-retired id. Same place, same
		// id; the closure is the CURRENT one; only a vanished control retires.
		var hits = [];
		var gen1tree = new Node("VStack")
			.child(new Node("Button").prop("onClick", PCallback(() -> hits.push("old"))));
		var stable = new nui.Snapshot.ActionTable();
		var g1 = nui.Snapshot.project(gen1tree, stable);
		var gen2tree = new Node("VStack")
			.child(new Node("Button").prop("onClick", PCallback(() -> hits.push("new"))));
		var g2 = nui.Snapshot.project(gen2tree, stable);
		check("the same place keeps its id across generations",
			g1.children[0].actions.get("onClick") == g2.children[0].actions.get("onClick"));
		stable.invoke(g1.children[0].actions.get("onClick"));
		check("a late tap runs the CURRENT closure - what the unchanged button says",
			hits.length == 1 && hits[0] == "new");
		var gen3tree = new Node("VStack").child(new Node("Text").prop("text", PString("gone")));
		nui.Snapshot.project(gen3tree, stable);
		stable.invoke(g2.children[0].actions.get("onClick"));
		check("a control that left the tree retires its id", hits.length == 1);
		var keyedA = new Node("List")
			.child(new Node("Row", "a").prop("onClick", PCallback(() -> hits.push("a"))))
			.child(new Node("Row", "b").prop("onClick", PCallback(() -> hits.push("b"))));
		var ka = nui.Snapshot.project(keyedA, stable);
		var keyedB = new Node("List")
			.child(new Node("Row", "b").prop("onClick", PCallback(() -> hits.push("b2"))))
			.child(new Node("Row", "a").prop("onClick", PCallback(() -> hits.push("a2"))));
		var kb = nui.Snapshot.project(keyedB, stable);
		check("a keyed row keeps its id when the list reorders",
			ka.children[1].actions.get("onClick") == kb.children[0].actions.get("onClick"));

		// --- Following: a snapshot keeps itself current ---
		var a = new rui.state.State(0);
		var b = new rui.state.State(0);
		var published = [];
		var followed = nui.Follow.tree(() -> {
			var n = new Node("VStack");
			n.child(new Node("Text").prop("text", PString("a=" + a.get() + " b=" + b.get())));
			// One button whose closure writes BOTH cells: the shape a batch
			// exists for, and the one that used to publish twice.
			n.child(new Node("Button").prop("click", PCallback(() -> {
				a.set(a.peek() + 1);
				b.set(b.peek() + 1);
			})));
			return n;
		}, snap -> published.push(nui.Snapshot.toJson(snap)));

		check("a follower publishes on its first run", published.length == 1);

		a.set(5);
		check("a write republishes", published.length == 2);
		check("and the new picture carries the value", published[1].indexOf("a=5") >= 0);

		var beforeTap = published.length;
		var clickId = -1;
		var lastSnap = nui.Snapshot.fromJson(published[published.length - 1]);
		for (childSnap in lastSnap.children)
			if (childSnap.actions != null && childSnap.actions.exists("click"))
				clickId = childSnap.actions.get("click");
		check("the button's id is in the snapshot", clickId >= 0);

		// The plan's own wording: a closure that writes three cells produces
		// one sample, not three. Two here, and without the batch this was two
		// publishes for one tap.
		followed.invoke(clickId);
		check("a tap writing two cells publishes ONCE", published.length == beforeTap + 1);
		check("and the picture carries both writes", published[published.length - 1].indexOf("a=6 b=1") >= 0);

		// A second process follows in order to ACT, not to show: its first run
		// would otherwise publish its own pre-tap state over the picture the
		// application put there.
		var quiet = [];
		var acting = nui.Follow.tree(() -> new Node("Text").prop("text", PString("v=" + a.get())), snap -> quiet.push(1), false);
		check("publishFirst=false does not publish the seeding run", quiet.length == 0);
		a.set(9);
		check("but follows normally afterwards", quiet.length == 1);
		acting.dispose();

		// Counted here rather than before `acting`: the write above moved a
		// cell BOTH followers read, so it legitimately republished this one
		// too. A test that assumed otherwise would have blamed dispose.
		var beforeDispose = published.length;
		followed.dispose();
		a.set(100);
		check("a disposed follower publishes nothing", published.length == beforeDispose);

		Sys.println(fails == 0 ? '\nall $checks checks passed' : '\n$fails failed');
		#if sys
		Sys.exit(fails == 0 ? 0 : 1);
		#end
	}
}

/** Implémentation jouet du contrat pull, au-dessus d'un arbre `Node`. **/
class ToySource implements nui.NodeSource<Node> {
	var _root:Node;

	public function new(root:Node) _root = root;

	public function root():Node return _root;

	public function rebuild():Void {}

	public function typeOf(n:Node):String return n.type;

	public function keyOf(n:Node):Null<String> return n.key;

	public function childCount(n:Node):Int return n.resolveChildren().length;

	public function childAt(n:Node, index:Int):Node return n.resolveChildren()[index];

	public function hasProp(n:Node, key:String):Bool return n.props.exists(key);

	public function stringProp(n:Node, key:String):String return PropValueTools.asString(n.props.get(key));

	public function intProp(n:Node, key:String):Int return PropValueTools.asInt(n.props.get(key));

	public function floatProp(n:Node, key:String):Float return PropValueTools.asFloat(n.props.get(key));

	public function boolProp(n:Node, key:String):Bool return PropValueTools.asBool(n.props.get(key));

	public function modifierCount(n:Node):Int return n.modifiers.length;

	public function modifierType(n:Node, index:Int):String return n.modifiers[index].type;

	public function modifierFloat(n:Node, index:Int, param:Int):Float {
		var f = n.modifiers[index].floats;
		return (f != null && param < f.length) ? f[param] : 0.0;
	}

	public function modifierString(n:Node, index:Int, param:Int):String {
		var s = n.modifiers[index].strings;
		return (s != null && param < s.length) ? s[param] : "";
	}

	public function actionId(n:Node):Int return n.props.exists("action") ? 1 : -1;

	public function invokeAction(n:Node):Void {
		var v = PropValueTools.resolve(n.props.get("action"));
		if (v == null) return;
		switch (v) {
			case PCallback(fn): fn();
			case _:
		}
	}
}

/** Implémentation jouet du contrat push, qui journalise ce qu'on lui demande. **/
class ToySink implements nui.NodeSink<String> {
	public var log:Array<String> = [];

	var _bind:(Void->Void)->Null<Void->Void> = function(fn) { fn(); return null; };
	var _bindings:Map<String, Array<Void->Void>> = new Map();

	public var bindReactive(get, set):(Void->Void)->Null<Void->Void>;

	function get_bindReactive() return _bind;

	function set_bindReactive(v) return _bind = v;

	public function new() {}

	public function create(node:Node, parent:Null<String>):String {
		log.push("create:" + node.type);
		return node.type;
	}

	public function applyProp(target:String, type:String, key:String, value:PropValue):Void {
		var stop = _bind(function() {
			var resolved = PropValueTools.resolve(value);
			var shown = switch (resolved) {
				case PString(v): v;
				case PInt(v): Std.string(v);
				case PFloat(v): Std.string(v);
				case PBool(v): Std.string(v);
				case _: "<fn>";
			}
			log.push("prop:" + key + "=" + shown);
		});
		if (stop != null) {
			var made = _bindings.get(target);
			if (made == null) { made = []; _bindings.set(target, made); }
			made.push(stop);
		}
	}

	public function applyModifiers(target:String, type:String, modifiers:Array<Modifier>):Void {
		for (m in modifiers) log.push("mod:" + m.type);
	}

	public function insert(parent:String, child:String, index:Int):Void log.push("insert:" + child);

	public function remove(parent:String, child:String):Void log.push("remove:" + child);

	public function destroy(target:String):Void {
		var made = _bindings.get(target);
		if (made != null) {
			_bindings.remove(target);
			for (stop in made) stop();
		}
		log.push("destroy:" + target);
	}
}
