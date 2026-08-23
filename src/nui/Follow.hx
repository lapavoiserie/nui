package nui;

import nui.Snapshot;
import nui.Snapshot.ActionTable;
import rui.Signal.Effect;

/**
	A sampled tree that keeps itself current.

	## What this is for

	Some surfaces are drawn by somebody else: a home-screen widget, a cover, a
	tree projected onto another machine. The drawer decides when to draw, and it
	cannot see our state — there is no reactive system of theirs on our side of
	that boundary to hand a value to. Noticing that a cell changed is therefore
	always ours to do, wherever such a surface lives.

	So: evaluate the thunk inside an effect, and every cell it read becomes a
	reason to sample again. `rui` recaptures dependencies on each run, so a tree
	whose branches read different cells is followed with nothing special.

	## Why here and not one level up

	Because what is followed is a tree of `nui.Node`, and what comes out is a
	`Snapshot` — both of which live here. The layer above (`mui`) knows about
	views and declarations; the layer beside (`cafos`) knows about wires and
	machines. Neither of them is where "a sampled tree stays current" belongs,
	and putting it in either forced the other to write its own.

	That is not hypothetical: it was written three times. `cafos` had it for the
	Companion surface — a transport library owning it, and serving five of the
	six backends — while `sui` and `aui` each wrote another for their widget.

	## What a caller owns

	One thing: **what to do with the snapshot**. A widget writes it to a shared
	container, a projector wraps it in a generation and sends it, a pull-model
	host throws it away and asks its own question later.
**/
class Follow {
	/**
		Follow `content`, handing each fresh snapshot to `publish`.

		`publishFirst` decides whether the run that starts it all also
		publishes. **A process seeding a picture at launch says yes; a process
		that woke up to service a tap says no** — what it would publish is its
		own state from before the tap, which where two processes share one
		picture overwrites what the other put there. Asked here so that it is
		asked once.
	**/
	public static function tree(content:() -> Node, publish:SnapshotNode->Void, publishFirst:Bool = true):Follower {
		return new Follower(content, publish, publishFirst);
	}
}

/**
	One followed tree: its effect and its action table.

	Disposed by whoever started it. An effect still watching state that left
	the screen is the shape of every stale-surface bug this ecosystem has had.
**/
class Follower {
	/**
		The table is kept across samples and **never cleared between them**.

		`Snapshot.project` keys ids by PLACE, so the control in the same slot
		keeps its id from one generation to the next, and a tap that raced the
		state beat invokes the CURRENT closure rather than a hole. Clearing here
		is exactly how the first interactive Companion turned every Enter into a
		stale remote tap. Only controls that left the tree retire, which
		`project` does itself through `beginGeneration` and `sweep`.

		It lives with the effect that fills it, rather than in a static beside
		it, because that is what keeps ids and closures from drifting apart.
	**/
	public final table:ActionTable = new ActionTable();

	final content:() -> Node;
	final publish:SnapshotNode->Void;

	var effect:Null<Effect>;
	var seeding:Bool;

	public function new(content:() -> Node, publish:SnapshotNode->Void, publishFirst:Bool) {
		this.content = content;
		this.publish = publish;
		this.seeding = !publishFirst;
		this.effect = new Effect(run);
	}

	function run():Void {
		var snap = Snapshot.project(content(), table);
		if (seeding) {
			seeding = false;
			return;
		}
		publish(snap);
	}

	/**
		Sample without waiting for a change.

		For a host that **pulls**: it asks for the picture when it decides to
		draw, and what it gets must be current. Sampling here rather than
		re-running the effect leaves the dependency set alone — a pull is not a
		change.
	**/
	public function sampleNow():SnapshotNode {
		return Snapshot.project(content(), table);
	}

	/**
		Run what a tap names.

		An id the table has retired is answered with a word, never a crash: it
		may legitimately name a control that left the tree between the picture
		the host kept and the user's finger.
	**/
	public function invoke(id:Int, ?arg:String):Void {
		table.invoke(id, arg);
	}

	/** Stop following. Idempotent. **/
	public function dispose():Void {
		var e = effect;
		effect = null;
		if (e != null) e.dispose();
	}
}
