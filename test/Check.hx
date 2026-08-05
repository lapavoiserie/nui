import nui.Node;
import nui.Modifier;
import nui.PropValue;

/**
	Standalone check of the node model, and a toy implementation of each
	contract to prove both are satisfiable.

	    haxe -cp src -cp test -main Check --interp
**/
class Check {
	static var fails = 0;

	static function check(label:String, ok:Bool) {
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
		sink.bindReactive = function(f) { wrapped++; f(); };
		sink.applyProp(native, "VStack", "label", PReactive(() -> PString("différé")));
		check("NodeSink.bindReactive enveloppe l'application", wrapped == 1);
		check("bindReactive résout le thunk", sink.log[sink.log.length - 1] == "prop:label=différé");

		// --- Propriété absente : le piège qui ne se voit qu'en compilé ---
		// resolve(null) renvoie null, et un switch sur un enum null SEGFAULTE
		// sur hxcpp. Ces lectures doivent renvoyer le défaut, pas planter.
		var empty = new Node("Empty");
		check("asString sur absente", PropValueTools.asString(empty.props.get("nope")) == "");
		check("asInt sur absente", PropValueTools.asInt(empty.props.get("nope"), -1) == -1);
		check("asFloat sur absente", PropValueTools.asFloat(empty.props.get("nope"), 1.5) == 1.5);
		check("asBool sur absente", PropValueTools.asBool(empty.props.get("nope"), true) == true);
		check("stringProp sur absente ne plante pas", src.stringProp(empty, "nope") == "");
		check("equals tolère null", !PropValueTools.equals(null, PInt(1)) && PropValueTools.equals(null, null));

		Sys.println(fails == 0 ? "\nTOUT PASSE" : '\n$fails ÉCHEC(S)');
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

	var _bind:(Void->Void)->Void = function(fn) fn();

	public var bindReactive(get, set):(Void->Void)->Void;

	function get_bindReactive() return _bind;

	function set_bindReactive(v) return _bind = v;

	public function new() {}

	public function create(node:Node, parent:Null<String>):String {
		log.push("create:" + node.type);
		return node.type;
	}

	public function applyProp(target:String, type:String, key:String, value:PropValue):Void {
		_bind(function() {
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
	}

	public function applyModifiers(target:String, type:String, modifiers:Array<Modifier>):Void {
		for (m in modifiers) log.push("mod:" + m.type);
	}

	public function insert(parent:String, child:String, index:Int):Void log.push("insert:" + child);

	public function remove(parent:String, child:String):Void log.push("remove:" + child);

	public function destroy(target:String):Void log.push("destroy:" + target);
}
