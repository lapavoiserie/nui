import nui.Node;
import nui.Modifier;
import nui.PropValue;
import nui.PropValue.PropValueTools;

/**
	Standalone check of the node model, and a toy implementation of each
	contract to prove both are satisfiable.

	    haxe -cp src -cp test -lib rui -main Check --interp
**/
class Check {
	static var fails = 0;
	static var tapped = 0;
	// Counted rather than written down: a total in the docs that nobody
	// recomputes drifts, and this one had - the docs said 23 for 29 checks.
	static var checks = 0;

	static function check(label:String, ok:Bool, ?got:Dynamic) {
		checks++;
		if (!ok) fails++;
		Sys.println((ok ? "ok   " : "FAIL ") + label + (ok || got == null ? "" : '  (got: $got)'));
	}

	/**
		A TrueType file with a `name` and an `OS/2` table, and nothing else.

		Enough for `FontFile`: the table directory, the two records it reads,
		and the version that begins every TrueType file.
	**/
	static function font(family:String, subfamily:String, weight:Int, italic:Bool):haxe.io.Bytes {
		var out = new haxe.io.BytesBuffer();
		function u16(v:Int) {
			out.addByte((v >> 8) & 0xFF);
			out.addByte(v & 0xFF);
		}
		function u32(v:Int) {
			out.addByte((v >>> 24) & 0xFF);
			out.addByte((v >> 16) & 0xFF);
			out.addByte((v >> 8) & 0xFF);
			out.addByte(v & 0xFF);
		}

		// The name table: two records (family is 1, subfamily 2), Macintosh
		// platform, so one byte a character.
		var names = new haxe.io.BytesBuffer();
		var storage = 6 + 2 * 12;
		names.addByte(0); names.addByte(0);                 // format
		names.addByte(0); names.addByte(2);                 // two records
		names.addByte((storage >> 8) & 0xFF); names.addByte(storage & 0xFF);
		var at = 0;
		for (entry in [{id: 1, text: family}, {id: 2, text: subfamily}]) {
			names.addByte(0); names.addByte(1);              // platform: Macintosh
			names.addByte(0); names.addByte(0);              // encoding
			names.addByte(0); names.addByte(0);              // language
			names.addByte(0); names.addByte(entry.id);
			names.addByte((entry.text.length >> 8) & 0xFF); names.addByte(entry.text.length & 0xFF);
			names.addByte((at >> 8) & 0xFF); names.addByte(at & 0xFF);
			at += entry.text.length;
		}
		names.addString(family);
		names.addString(subfamily);
		var nameTable = names.getBytes();

		// OS/2: only usWeightClass (offset 4) and fsSelection (62) are read.
		var os2 = haxe.io.Bytes.alloc(78);
		os2.set(4, (weight >> 8) & 0xFF);
		os2.set(5, weight & 0xFF);
		os2.set(63, italic ? 1 : 0);

		var directory = 12 + 2 * 16;
		u32(0x00010000);                                     // the version that broke on HashLink
		u16(2); u16(0); u16(0); u16(0);                      // two tables
		out.addString("OS/2");
		u32(0); u32(directory); u32(os2.length);
		out.addString("name");
		u32(0); u32(directory + os2.length); u32(nameTable.length);
		out.add(os2);
		out.add(nameTable);
		return out.getBytes();
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
		// --- ...and the place is not enough: an insertion must not misdirect ---
		// A tap one generation late on "Delete b", after a row was inserted
		// above it, used to run whatever had taken its slot.
		var ran = [];
		var rows = new nui.Snapshot.ActionTable();
		var beforeInsert = nui.Snapshot.project(new Node("VStack")
			.child(new Node("Button").prop("label", PString("Delete a")).prop("onClick", PCallback(() -> ran.push("a"))))
			.child(new Node("Button").prop("label", PString("Delete b")).prop("onClick", PCallback(() -> ran.push("b")))), rows);
		var deleteB = beforeInsert.children[1].actions.get("onClick");
		var afterInsert = nui.Snapshot.project(new Node("VStack")
			.child(new Node("Button").prop("label", PString("Delete new")).prop("onClick", PCallback(() -> ran.push("new"))))
			.child(new Node("Button").prop("label", PString("Delete a")).prop("onClick", PCallback(() -> ran.push("a"))))
			.child(new Node("Button").prop("label", PString("Delete b")).prop("onClick", PCallback(() -> ran.push("b")))), rows);
		rows.invoke(deleteB);
		check("a late tap after an insertion is dropped, never run on the control that took the place",
			ran.length == 0);
		check("...and the control itself, moved down, answers under a new id",
			afterInsert.children[2].actions.get("onClick") != deleteB);
		var toggled = new nui.Snapshot.ActionTable();
		var asButton = nui.Snapshot.project(new Node("VStack")
			.child(new Node("Button").prop("onClick", PCallback(() -> ran.push("button")))), toggled);
		nui.Snapshot.project(new Node("VStack")
			.child(new Node("Tappable").prop("onClick", PCallback(() -> ran.push("tappable")))), toggled);
		toggled.invoke(asButton.children[0].actions.get("onClick"));
		check("a different TYPE at the same place is a different control", ran.length == 0);
		var typing = new nui.Snapshot.ActionTable();
		var t1 = nui.Snapshot.project(new Node("VStack")
			.child(new Node("TextInput").prop("text", PString("a")).prop("onText", PCallbackString(v -> ran.push(v)))), typing);
		var t2 = nui.Snapshot.project(new Node("VStack")
			.child(new Node("TextInput").prop("text", PString("ab")).prop("onText", PCallbackString(v -> ran.push(v)))), typing);
		check("a field's VALUE is not part of what it is: its id survives typing",
			t1.children[0].actions.get("onText") == t2.children[0].actions.get("onText"));

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

		// --- SelfSource: the pull contract over nui's own nodes ---
		//
		// What a sink needs: a tree that ARRIVED is already Nodes, with nothing
		// underneath to walk. Reading it directly is the identity, so unlike an
		// inverse describer there is no name table that can drift.
		var received = new Node("VStack")
			.prop("spacing", PInt(4))
			.modifier({type: "padding", floats: [8]})
			.child(new Node("Text").prop("text", PString("hello")))
			.child(new Node("Button", "act")
				.prop("label", PString("Tap"))
				.prop("onClick", PCallbackString(_ -> tapped++)));

		var src = new nui.SelfSource(() -> received);
		check("the source reads the root type", src.typeOf(src.root()) == "VStack");
		check("children are counted", src.childCount(src.root()) == 2);
		check("a string prop reads through", src.stringProp(src.childAt(src.root(), 0), "text") == "hello");
		check("an int prop reads through", src.intProp(src.root(), "spacing") == 4);
		check("modifiers survive", src.modifierType(src.root(), 0) == "padding" && src.modifierFloat(src.root(), 0, 0) == 8);
		check("a key the sender gave is passed on", src.keyOf(src.childAt(src.root(), 1)) == "act");
		check("a node with no action says so", src.actionId(src.childAt(src.root(), 0)) < 0);

		var button = src.childAt(src.root(), 1);
		var id = src.actionId(button);
		check("a node with one gets an id", id >= 0);
		src.invokeActionId(id);
		check("and the id runs the closure", tapped == 1);

		// A picker: its options are children, its action carries a position.
		var picked = -1;
		var pickerTree = new Node("Picker")
			.prop("selectedIndex", PInt(2))
			.prop("onSelect", PCallbackInt(i -> picked = i))
			.child(new Node("Text").prop("text", PString("Cut")))
			.child(new Node("Text").prop("text", PString("Fade")))
			.child(new Node("Text").prop("text", PString("Wipe")));
		var pickerSource = new nui.SelfSource(() -> pickerTree);
		check("a picker's onSelect is an action", pickerSource.actionId(pickerSource.root()) >= 0);
		pickerSource.invokeAction(pickerSource.root());
		check("invoking it hands over the selected position", picked == 2);

		// Across a wire: options stay children, and the position comes home as
		// the text every inflated action carries.
		var pickerTable = new nui.Snapshot.ActionTable();
		var wire = nui.Snapshot.fromJson(nui.Snapshot.toJson(nui.Snapshot.project(pickerTree, pickerTable)));
		var far = nui.Snapshot.inflate(wire, (actionId, arg) -> pickerTable.invoke(actionId, arg));
		check("across a wire the options stay children, in order", far.children.length == 3
			&& PropValueTools.asString(far.children[2].props.get("text")) == "Wipe");
		var farSource = new nui.SelfSource(() -> far);
		check("and the received picker still has its action", farSource.actionId(far) >= 0);
		picked = -1;
		switch (PropValueTools.resolve(far.props.get("onSelect"))) {
			case PCallbackString(fn): fn("1");
			case _:
		}
		check("a choice made far away runs the sender's closure with its position", picked == 1);

		// --- Image sources: what a src names, and what may be loaded ---
		var hex = [for (_ in 0...64) "a"].join("");
		function kindOf(k:nui.ImageSource.ImageSourceKind):String return Type.enumConstructor(k);
		check("asset: a shipped file", switch (nui.ImageSource.parse("asset:farceur/logo.png")) {
			case Asset("farceur/logo.png", null): true;
			case _: false;
		});
		check("asset: with its sender's digest", switch (nui.ImageSource.parse('asset:logo.png#sha256=$hex')) {
			case Asset("logo.png", d): d == hex;
			case _: false;
		});
		check("an asset path may not climb out", kindOf(nui.ImageSource.parse("asset:../secret.png")) == "Invalid"
			&& kindOf(nui.ImageSource.parse("asset:/etc/passwd")) == "Invalid"
			&& kindOf(nui.ImageSource.parse("asset:a//b.png")) == "Invalid");
		check("a malformed digest is refused", kindOf(nui.ImageSource.parse("asset:logo.png#sha256=zz")) == "Invalid");
		check("blob: named by its content", switch (nui.ImageSource.parse('blob:sha256=$hex')) {
			case Blob(d): d == hex;
			case _: false;
		});
		check("https: with its host, lower-case", switch (nui.ImageSource.parse("https://Example.ORG:8443/a.png?x#y")) {
			case Https(_, "example.org"): true;
			case _: false;
		});
		check("a user part is not the host", switch (nui.ImageSource.parse("https://trusted.org@evil.net/a.png")) {
			case Https(_, "evil.net"): true;
			case _: false;
		});
		check("data: png or jpeg, base64", kindOf(nui.ImageSource.parse("data:image/png;base64,iVBORw0KGgo=")) == "Data"
			&& kindOf(nui.ImageSource.parse("data:image/svg+xml;base64,PHN2Zz4=")) == "Invalid"
			&& kindOf(nui.ImageSource.parse("data:image/png,rawbytes")) == "Invalid");
		check("http, relative paths and nothing are never loaded", kindOf(nui.ImageSource.parse("http://example.org/a.png")) == "Invalid"
			&& kindOf(nui.ImageSource.parse("logo.png")) == "Invalid" && kindOf(nui.ImageSource.parse("")) == "Invalid"
			&& kindOf(nui.ImageSource.parse(null)) == "Invalid");
		check("a tree built here may name a local file", kindOf(nui.ImageSource.check("file:///Users/a/b.png", false)) == "File");
		check("a received one may not", kindOf(nui.ImageSource.check("file:///Users/a/b.png", true)) == "Invalid");
		check("a received https: loads only from a trusted host", kindOf(nui.ImageSource.check("https://cdn.example.org/a.png", true)) == "Invalid"
			&& kindOf(nui.ImageSource.check("https://cdn.example.org/a.png", true, ["cdn.example.org"])) == "Https"
			&& kindOf(nui.ImageSource.check("https://cdn.example.org@evil.net/a.png", true, ["cdn.example.org"])) == "Invalid");
		var big = [for (_ in 0...Std.int(256 * 1024 / 3 + 10)) "AAAA"].join("");
		check("a received data: source is bounded at 256 KiB", kindOf(nui.ImageSource.check("data:image/png;base64," + big, true)) == "Invalid"
			&& kindOf(nui.ImageSource.check("data:image/png;base64," + big, false)) == "Data");
		check("assets and blobs arrive from anywhere they are sent", kindOf(nui.ImageSource.check("asset:logo.png", true)) == "Asset"
			&& kindOf(nui.ImageSource.check('blob:sha256=$hex', true)) == "Blob");

		// --- Icon names ---
		check("57 icon names, each lower-case words joined by dashes", nui.Icons.NAMES.length == 57
			&& Lambda.foreach(nui.Icons.NAMES, n -> ~/^[a-z]+(-[a-z]+)*$/.match(n)));
		check("no name twice", Lambda.count([for (n in nui.Icons.NAMES) n => true]) == nui.Icons.NAMES.length);
		check("a name is known, a cut is not", nui.Icons.knows("mic-off") && !nui.Icons.knows("cut") && !nui.Icons.knows(null));
		check("an unlabelled icon still says something", nui.Icons.spoken("speaker-off") == "speaker off");

		// --- What a font file says about itself ---
		//
		// The file is made here rather than shipped: a real font is somebody
		// else's to license, and what has to be exercised is the parsing --
		// including the four bytes 00 01 00 00 that begin a TrueType file,
		// which is where this broke on HashLink when they were read as text.
		var regular = nui.FontFile.read(font("Farceur Sans", "Regular", 400, false));
		check("a font file says its family", regular != null && regular.family == "Farceur Sans", regular);
		check("its weight", regular.weight == 400);
		check("and whether it is italic", !regular.italic);
		var bold = nui.FontFile.read(font("Farceur Sans", "Bold Italic", 700, true));
		check("a bold italic face says both", bold != null && bold.weight == 700 && bold.italic, bold);
		check("and what is not a font is not read", nui.FontFile.read(haxe.io.Bytes.ofString("not a font at all")) == null
			&& nui.FontFile.read(haxe.io.Bytes.alloc(0)) == null);

		// --- How a Text is set ---
		check("the four scales, and anything else is running text", nui.TextStyle.SCALES.length == 4
			&& nui.TextStyle.scaleOf("Title") == "title" && nui.TextStyle.scaleOf("caption") == "caption"
			&& nui.TextStyle.scaleOf("largeTitle") == "body" && nui.TextStyle.scaleOf(null) == "body");
		check("a scale is known or it is not", nui.TextStyle.knowsScale("subtitle") && !nui.TextStyle.knowsScale("headline")
			&& !nui.TextStyle.knowsScale(null));
		check("a weight is one a font file has: hundreds, 100 to 900", nui.TextStyle.weightOf(null) == 400
			&& nui.TextStyle.weightOf(650) == 700 && nui.TextStyle.weightOf(1) == 100
			&& nui.TextStyle.weightOf(20000) == 900 && nui.TextStyle.weightOf(Math.NaN) == 400);
		check("and past six hundred it asks for more than ordinary text",
			nui.TextStyle.isBold(600) && nui.TextStyle.isBold(900) && !nui.TextStyle.isBold(500));
		check("numbers of one width are asked for by name", nui.TextStyle.isTabular("tabular")
			&& nui.TextStyle.isTabular("Tabular") && !nui.TextStyle.isTabular("proportional") && !nui.TextStyle.isTabular(null));

		// The two conversions above, carried by a type instead of by whoever
		// remembers to call them. Every backend wrote them itself on the way
		// in and on the way out, which is how a describer and a renderer end
		// up disagreeing about one value.
		var wire:nui.Scale = "largeTitle";
		check("a scale arriving from elsewhere is one of the four", (wire : String) == "body"
			&& (nui.Scale.Title : String) == "title" && (("Caption" : nui.Scale) : String) == "caption");
		var asked:nui.Numbers = true;
		var absent:nui.Numbers = false;
		check("digits of one width cross as a word, and their absence as nothing",
			(asked : Null<String>) == nui.TextStyle.TABULAR && (absent : Null<String>) == null);
		check("and read back as the Bool an application wrote", (asked : Bool) && !(absent : Bool)
			&& ((("Tabular" : nui.Numbers)) : Bool));

		// --- Colour ---
		//
		// A role crosses as a role: resolved here, it would be a number sent to
		// a machine that knows better -- dark mode, high contrast, or a
		// platform whose accent the person chose themselves.
		check("a role crosses as its word", (nui.Color.role(Danger) : String) == "role:danger"
			&& (nui.Color.role(Accent) : String) == "role:accent");
		check("and is read back as the role it was", nui.Color.roleOf("role:danger") == Danger
			&& nui.Color.roleOf("role:accent") == Accent);
		check("a component colour is not a role", nui.Color.roleOf("#c8323c") == null);
		check("and a role has no components -- ask your palette, not black",
			nui.Color.rgbOf("role:danger") == null);

		check("components cross as six digits", (nui.Color.rgb(200, 50, 60) : String) == "#c8323c");
		check("and out of range is clamped rather than wrapped",
			(nui.Color.rgb(-5, 300, 0) : String) == "#00ff00");
		var back = nui.Color.rgbOf("#c8323c");
		check("and come back as the numbers that went in",
			back != null && back.r == 200 && back.g == 50 && back.b == 60, back);

		check("an opacity is written last, as CSS writes it",
			(nui.Color.rgba(200, 50, 60, 128) : String) == "#c8323c80");
		var solid = nui.Color.rgbOf("#c8323c");
		var faded = nui.Color.rgbOf("#c8323c80");
		// A colour written without one is solid: nobody writing `#c8323c`
		// meant invisible.
		check("and a colour written without one is solid, not invisible",
			solid != null && solid.a == 255 && faded != null && faded.a == 128, solid);

		check("the short form is each digit doubled",
			(nui.Color.hex("#f00") : String) == "#ff0000" && (nui.Color.hex("0AF") : String) == "#00aaff"
			&& (nui.Color.hex("#f008") : String) == "#ff000088");
		// A colour is written by hand, and a typo in one shows up as a wrong
		// pixel nobody traces. Refused rather than quietly black.
		check("and anything else is refused rather than quietly black",
			nui.Color.hex("#ggg") == null && nui.Color.hex("#12345") == null
			&& nui.Color.hex("rouge") == null);
		check("a role nobody declared is refused too",
			nui.Color.said("role:chartreuse") == null && nui.Color.said("role:danger") != null);

		check("the eight roles, and no named colours", nui.Role.ALL.length == 8
			&& nui.Role.of("DANGER") == Danger && nui.Role.of("red") == null);

		// --- The modifier canon ---
		//
		// `nui.Modifier` always said a modifier is ordered and typed. It never
		// said what `type` may BE, so six backends each invented their own set
		// -- pui never sent a foregroundColor at all, and aui sent font, bold
		// and italic as modifiers while the fonts canon had already made them
		// props of Text.
		check("nine names, and knowing them is the point", nui.Modifiers.NAMES.length == 9
			&& nui.Modifiers.knows("backgroundColor") && nui.Modifiers.knows("clip"));
		// `pui` read this before there was a canon, and nothing named it -- so
		// the markup refused to write one, and a panel could not give two
		// thirds of a row to its monitors.
		check("including the share of what is left over",
			nui.Modifiers.knows("flex") && nui.Modifiers.kindOf("flex") == "KFloat");
		check("a misspelling is not one", !nui.Modifiers.knows("backgroundColour")
			&& !nui.Modifiers.knows(null));
		// What the fonts canon already owns does not get a second home here.
		check("and nor is anything Text says about itself",
			!nui.Modifiers.knows("font") && !nui.Modifiers.knows("bold")
			&& !nui.Modifiers.knows("italic"));
		// A radius belongs to the thing being rounded; a free-standing one has
		// to apply to whatever comes next, which nobody can read off a list.
		check("nor a radius with nothing to round", !nui.Modifiers.knows("cornerRadius"));
		check("a colour modifier takes a colour, which is a string",
			nui.Modifiers.kindOf("backgroundColor") == "KString"
			&& nui.Modifiers.kindOf("border") == "KString");
		check("and the measures take numbers", nui.Modifiers.kindOf("padding") == "KFloat"
			&& nui.Modifiers.kindOf("opacity") == "KFloat");
		check("clip takes nothing, so it is written as a flag",
			nui.Modifiers.kindOf("clip") == "KBool");
		check("and an unknown name has no kind, which is what refuses it",
			nui.Modifiers.kindOf("cornerRadius") == null);

		// --- Presentation ---
		//
		// A hint that fails soft, unlike masking: a forgotten presentation
		// shows the same choices in another shape, a forgotten password shows
		// the password.
		check("a segmented picker is asked for by name",
			nui.Presentation.isSegmented("segmented") && nui.Presentation.isSegmented("Segmented"));
		check("and anything else is an ordinary one",
			!nui.Presentation.isSegmented("segment") && !nui.Presentation.isSegmented(null));

		// --- Orientation ---
		//
		// Low at the bottom is MEANING: a fader growing downwards reads as the
		// opposite of every mixing desk, and a tree drawn the other way would
		// be showing the wrong value rather than another shape.
		check("a vertical control is asked for by name",
			(nui.Orientation.Vertical : String) == "vertical"
			&& nui.Orientation.said("Vertical") == nui.Orientation.Vertical);
		check("and anything else runs the usual way",
			nui.Orientation.said(null) == nui.Orientation.Horizontal
			&& nui.Orientation.said("sideways") == nui.Orientation.Horizontal);
		check("which is the question a layout asks",
			nui.Orientation.Vertical.isVertical() && !nui.Orientation.Horizontal.isVertical());

		// A modifier says what it carries and in what order, so an attribute
		// can be written whole: `border={{colour: …, width: 3, radius: 6}}`.
		// The wire always carried the three; only the markup could not write
		// them.
		var borderParts = nui.Modifiers.partsOf("border");
		check("a border is a colour, then a width and a radius",
			borderParts != null && borderParts.strings.join(",") == "colour"
			&& borderParts.floats.join(",") == "width,radius");
		var padParts = nui.Modifiers.partsOf("padding");
		check("and a padding is four edges, clockwise from the top",
			padParts != null && padParts.floats.join(",") == "top,right,bottom,left");
		check("something that is not a modifier carries nothing",
			nui.Modifiers.partsOf("cornerRadius") == null);
		// The two modifiers with several floats do not mean the same thing by
		// silence: an unmentioned edge has no padding, an unmentioned radius is
		// the one the control draws with.
		check("an edge nobody named is a zero", padParts.fill == true);
		check("a radius nobody named is absent, not square", borderParts.fill == false);

		// --- Icon shapes ---
		var shapeless = [for (n in nui.Icons.NAMES) if (nui.IconShapes.of(n) == null) n];
		check("every icon name has a shape", shapeless.length == 0, shapeless);
		check("and nothing else has one", Lambda.count(nui.IconShapes.PATHS) == nui.Icons.NAMES.length && nui.IconShapes.of("cut") == null);
		var outside = [];
		var empty = [];
		for (n in nui.Icons.NAMES) {
			var cs = nui.SvgPath.contoursOf(nui.IconShapes.of(n));
			if (cs.length == 0) empty.push(n);
			for (c in cs) for (v in c) if (Math.isNaN(v) || v < -0.5 || v > 24.5) { outside.push(n); break; }
		}
		check("every shape reads to contours", empty.length == 0, empty);
		check("inside its 24-unit square", outside.length == 0, outside);

		var square = nui.SvgPath.contours("M2 2h4v4H2z");
		check("a square is one contour of four points, closed without repeating the first", square.length == 1 && square[0].join(",") == "2,2,6,2,6,6,2,6", square);
		var relative = nui.SvgPath.contours("m1,1 l2,0 0,2 -2,0z m5,5 h1 v1 h-1 z");
		check("relative commands, implicit linetos, two subpaths", relative.length == 2
			&& relative[0].join(",") == "1,1,3,1,3,3,1,3" && relative[1].slice(0, 2).join(",") == "6,6", relative);
		check("numbers that touch: -0.3-0.4 and .5.5", nui.SvgPath.contours("M0-0.3L.5.5 1-1z")[0].join(",") == "0,-0.3,0.5,0.5,1,-1");
		var circle = nui.SvgPath.contours("M4,12a8,8 0 1,0 16,0a8,8 0 1,0 -16,0");
		var off = 0.0;
		for (c in circle) { var i = 0; while (i < c.length) { off = Math.max(off, Math.abs(Math.sqrt((c[i] - 12) * (c[i] - 12) + (c[i + 1] - 12) * (c[i + 1] - 12)) - 8)); i += 2; } }
		check("an arc stays on its circle", circle.length == 1 && off < 0.01 && circle[0].length > 40, off);
		check("and sweeps the way its flags say: through the bottom first", circle[0][3] > 12, circle[0].slice(0, 4));
		var curve = nui.SvgPath.contours("M0 0C0 10 10 10 10 0z", 0.01)[0];
		check("a cubic ends where it says and passes its midpoint", curve[curve.length - 2] == 10 && curve[curve.length - 1] == 0
			&& Lambda.exists([for (k in 0...Std.int(curve.length / 2)) k], k -> Math.abs(curve[2 * k] - 5) < 0.2 && Math.abs(curve[2 * k + 1] - 7.5) < 0.2));
		check("malformed data keeps what it read", nui.SvgPath.contours("M0 0L5 0L5 5L0 5Z M1 1 L ?").length == 1);

		// A sink replaces its tree on every generation; the renderer must see
		// the new one after `rebuild` without being handed a new source.
		received = new Node("VStack").child(new Node("Text").prop("text", PString("second")));
		check("before rebuild the old tree is still served", src.stringProp(src.childAt(src.root(), 0), "text") == "hello");
		src.rebuild();
		check("after rebuild the new one is", src.stringProp(src.childAt(src.root(), 0), "text") == "second");

		// --- a secret's id is derivable, so no log has to be told ---
		//
		// The whole point: a trace prints "[secret, N characters]" because it
		// can work out which ids those are from the snapshot it already has,
		// not because somebody remembered to pass a flag.
		var table = new nui.Snapshot.ActionTable();
		var panel = new Node("VStack")
			.child(new Node("Button")
				.prop("label", PString("TAKE"))
				.prop("onClick", PCallback(() -> {})))
			.child(new Node("SecretInput")
				.prop("placeholder", PString("Key"))
				.prop(nui.SelfSource.SECRET_KEY, PCallbackString(_ -> {})));
		var snap = nui.Snapshot.project(panel, table);

		var secrets = nui.Snapshot.secretIds(snap);
		check("one action of this tree is a secret", secrets.length == 1,
			Std.string(secrets.length));
		var clicked = snap.children[0].actions.get("onClick");
		check("and it is not the button's", secrets[0] != clicked,
			secrets[0] + " vs " + clicked);
		check("it is the secret field's",
			secrets[0] == snap.children[1].actions.get(nui.SelfSource.SECRET_KEY));

		check("a tree with no secret has none", nui.Snapshot.secretIds(
			nui.Snapshot.project(new Node("Text").prop("text", PString("x")),
				new nui.Snapshot.ActionTable())).length == 0);
		check("and neither has nothing at all", nui.Snapshot.secretIds(null).length == 0);

		check("what a log prints instead says how long it was",
			nui.Snapshot.redacted("abc123") == "[secret, 6 characters]",
			nui.Snapshot.redacted("abc123"));
		check("and tells an empty one apart from a missing one",
			nui.Snapshot.redacted("") == "[secret, 0 characters]");
		check("the value itself is never in it",
			nui.Snapshot.redacted("hunter2").indexOf("hunter2") < 0);

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
