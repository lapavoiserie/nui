package nui;

/**
	SVG path data turned into polygons, for a renderer that fills polygons and
	knows nothing of curves.

	Every command of the path grammar is read -- `M L H V C S Q T A Z`, each in
	its absolute and relative form -- and curves and arcs are replaced by
	straight segments no further than `tolerance` from the true curve, in the
	path's own units. Each subpath becomes one contour: a flat array
	`[x0, y0, x1, y1, …]`, implicitly closed.

	The contours of one path are meant to be filled **together** with the
	non-zero winding rule: a hole is a contour turning the other way, which a
	contour filled on its own would paint over.
**/
class SvgPath {
	/**
		The contours of `d`. Malformed data ends the reading where it stops
		making sense, keeping what was read before: a shape with a stray
		character draws what it can rather than nothing.
	**/
	public static function contours(d:String, tolerance:Float = 0.05):Array<Array<Float>> {
		return new SvgPath(d, tolerance).read();
	}

	/**
		`contours` for several paths, one list: the form `IconShapes` stores a
		shape in.
	**/
	public static function contoursOf(paths:Array<String>, tolerance:Float = 0.05):Array<Array<Float>> {
		var out = [];
		for (d in paths) for (c in contours(d, tolerance)) out.push(c);
		return out;
	}

	final d:String;
	final tolerance:Float;
	var at = 0;

	var out:Array<Array<Float>> = [];
	var current:Null<Array<Float>> = null;
	var x = 0.0;
	var y = 0.0;
	var startX = 0.0;
	var startY = 0.0;
	// The second control point of the last curve, for the smooth commands.
	var lastCubicX = 0.0;
	var lastCubicY = 0.0;
	var lastQuadX = 0.0;
	var lastQuadY = 0.0;

	function new(d:String, tolerance:Float) {
		this.d = d == null ? "" : d;
		this.tolerance = tolerance > 0 ? tolerance : 0.05;
	}

	function read():Array<Array<Float>> {
		var command = "";
		var previous = "";
		while (true) {
			skipSeparators();
			if (at >= d.length) break;
			var c = d.charAt(at);
			if (isCommand(c)) {
				command = c;
				at++;
			} else if (command == "" || !startsNumber(c)) {
				break;
			} else if (command == "M") {
				// Coordinates after a moveto are linetos.
				command = "L";
			} else if (command == "m") {
				command = "l";
			} else if (command == "Z" || command == "z") {
				break;
			}
			if (!step(command, previous)) break;
			previous = command;
		}
		finish();
		return out;
	}

	function step(command:String, previous:String):Bool {
		var relative = command.toLowerCase() == command;
		var ox = relative ? x : 0.0;
		var oy = relative ? y : 0.0;
		switch (command.toUpperCase()) {
			case "M":
				var p = pair();
				if (p == null) return false;
				finish();
				x = ox + p[0];
				y = oy + p[1];
				startX = x;
				startY = y;
				current = [x, y];
			case "L":
				var p = pair();
				if (p == null) return false;
				lineTo(ox + p[0], oy + p[1]);
			case "H":
				var v = number();
				if (v == null) return false;
				lineTo(ox + v, y);
			case "V":
				var v = number();
				if (v == null) return false;
				lineTo(x, oy + v);
			case "C":
				var n = numbers(6);
				if (n == null) return false;
				cubic(ox + n[0], oy + n[1], ox + n[2], oy + n[3], ox + n[4], oy + n[5]);
			case "S":
				var n = numbers(4);
				if (n == null) return false;
				var smooth = "CcSs".indexOf(previous) >= 0 && previous != "";
				var c1x = smooth ? 2 * x - lastCubicX : x;
				var c1y = smooth ? 2 * y - lastCubicY : y;
				cubic(c1x, c1y, ox + n[0], oy + n[1], ox + n[2], oy + n[3]);
			case "Q":
				var n = numbers(4);
				if (n == null) return false;
				quad(ox + n[0], oy + n[1], ox + n[2], oy + n[3]);
			case "T":
				var p = pair();
				if (p == null) return false;
				var smooth = "QqTt".indexOf(previous) >= 0 && previous != "";
				var cx = smooth ? 2 * x - lastQuadX : x;
				var cy = smooth ? 2 * y - lastQuadY : y;
				quad(cx, cy, ox + p[0], oy + p[1]);
			case "A":
				var rx = number();
				var ry = number();
				var rotation = number();
				var large = flag();
				var sweep = flag();
				var p = pair();
				if (rx == null || ry == null || rotation == null || large == null || sweep == null || p == null) return false;
				arc(Math.abs(rx), Math.abs(ry), rotation, large, sweep, ox + p[0], oy + p[1]);
			case "Z":
				x = startX;
				y = startY;
				finish();
			case _:
				return false;
		}
		if ("CcSs".indexOf(command) < 0) {
			lastCubicX = x;
			lastCubicY = y;
		}
		if ("QqTt".indexOf(command) < 0) {
			lastQuadX = x;
			lastQuadY = y;
		}
		return true;
	}

	// ---- geometry ----

	function lineTo(nx:Float, ny:Float) {
		if (current == null) current = [x, y];
		current.push(nx);
		current.push(ny);
		x = nx;
		y = ny;
	}

	function finish() {
		// A contour needs three points to enclose anything.
		if (current != null && current.length >= 6) out.push(current);
		current = null;
	}

	/** Segments for a curve whose control polygon is `length` long. **/
	function segmentsFor(length:Float):Int {
		var n = Math.ceil(Math.sqrt(length / tolerance));
		return n < 1 ? 1 : (n > 64 ? 64 : n);
	}

	function cubic(c1x:Float, c1y:Float, c2x:Float, c2y:Float, ex:Float, ey:Float) {
		var x0 = x;
		var y0 = y;
		var n = segmentsFor(dist(x0, y0, c1x, c1y) + dist(c1x, c1y, c2x, c2y) + dist(c2x, c2y, ex, ey));
		for (i in 1...n + 1) {
			var t = i / n;
			var u = 1 - t;
			var a = u * u * u;
			var b = 3 * u * u * t;
			var c = 3 * u * t * t;
			var e = t * t * t;
			lineTo(a * x0 + b * c1x + c * c2x + e * ex, a * y0 + b * c1y + c * c2y + e * ey);
		}
		x = ex;
		y = ey;
		lastCubicX = c2x;
		lastCubicY = c2y;
	}

	function quad(cx:Float, cy:Float, ex:Float, ey:Float) {
		var x0 = x;
		var y0 = y;
		var n = segmentsFor(dist(x0, y0, cx, cy) + dist(cx, cy, ex, ey));
		for (i in 1...n + 1) {
			var t = i / n;
			var u = 1 - t;
			lineTo(u * u * x0 + 2 * u * t * cx + t * t * ex, u * u * y0 + 2 * u * t * cy + t * t * ey);
		}
		x = ex;
		y = ey;
		lastQuadX = cx;
		lastQuadY = cy;
	}

	/** An elliptical arc, from its endpoints to its centre (SVG 1.1, appendix F.6). **/
	function arc(rx:Float, ry:Float, rotationDeg:Float, large:Bool, sweep:Bool, ex:Float, ey:Float) {
		var x1 = x;
		var y1 = y;
		if (x1 == ex && y1 == ey) return;
		if (rx == 0 || ry == 0) {
			lineTo(ex, ey);
			return;
		}
		var phi = rotationDeg * Math.PI / 180;
		var cos = Math.cos(phi);
		var sin = Math.sin(phi);
		var dx = (x1 - ex) / 2;
		var dy = (y1 - ey) / 2;
		var x1p = cos * dx + sin * dy;
		var y1p = -sin * dx + cos * dy;

		// Radii too small to reach the end are scaled up until they do.
		var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
		if (lambda > 1) {
			var s = Math.sqrt(lambda);
			rx *= s;
			ry *= s;
		}
		var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
		var den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
		var coef = den == 0 ? 0 : Math.sqrt(Math.max(0, num / den));
		if (large == sweep) coef = -coef;
		var cxp = coef * rx * y1p / ry;
		var cyp = -coef * ry * x1p / rx;
		var cx = cos * cxp - sin * cyp + (x1 + ex) / 2;
		var cy = sin * cxp + cos * cyp + (y1 + ey) / 2;

		var theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
		var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
		if (!sweep && delta > 0) delta -= 2 * Math.PI;
		if (sweep && delta < 0) delta += 2 * Math.PI;

		var n = segmentsFor(Math.abs(delta) * Math.max(rx, ry) * 2);
		for (i in 1...n + 1) {
			var t = theta1 + delta * i / n;
			var px = rx * Math.cos(t);
			var py = ry * Math.sin(t);
			lineTo(cos * px - sin * py + cx, sin * px + cos * py + cy);
		}
		x = ex;
		y = ey;
	}

	static inline function dist(ax:Float, ay:Float, bx:Float, by:Float):Float
		return Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));

	/** The signed angle from u to v. **/
	static function angle(ux:Float, uy:Float, vx:Float, vy:Float):Float
		return Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);

	// ---- reading ----

	static inline function isCommand(c:String):Bool
		return "MmLlHhVvCcSsQqTtAaZz".indexOf(c) >= 0;

	static inline function startsNumber(c:String):Bool
		return "0123456789.-+".indexOf(c) >= 0;

	function skipSeparators() {
		while (at < d.length) {
			var c = d.charCodeAt(at);
			if (c == " ".code || c == ",".code || c == "\t".code || c == "\n".code || c == "\r".code) at++;
			else break;
		}
	}

	function pair():Null<Array<Float>> {
		var a = number();
		var b = number();
		return a == null || b == null ? null : [a, b];
	}

	function numbers(count:Int):Null<Array<Float>> {
		var out = [];
		for (_ in 0...count) {
			var v = number();
			if (v == null) return null;
			out.push(v);
		}
		return out;
	}

	/** A number, where "-0.3-0.4" is two and ".5.5" is two as well. **/
	function number():Null<Float> {
		skipSeparators();
		var start = at;
		if (at < d.length && (d.charAt(at) == "-" || d.charAt(at) == "+")) at++;
		var digits = false;
		var dot = false;
		while (at < d.length) {
			var c = d.charAt(at);
			if (c >= "0" && c <= "9") {
				digits = true;
				at++;
			} else if (c == "." && !dot) {
				dot = true;
				at++;
			} else {
				break;
			}
		}
		if (digits && at < d.length && (d.charAt(at) == "e" || d.charAt(at) == "E")) {
			var save = at;
			at++;
			if (at < d.length && (d.charAt(at) == "-" || d.charAt(at) == "+")) at++;
			var exp = false;
			while (at < d.length && d.charAt(at) >= "0" && d.charAt(at) <= "9") {
				exp = true;
				at++;
			}
			if (!exp) at = save;
		}
		if (!digits) {
			at = start;
			return null;
		}
		return Std.parseFloat(d.substring(start, at));
	}

	/** An arc flag: one character, "0" or "1", which may touch the next number. **/
	function flag():Null<Bool> {
		skipSeparators();
		if (at >= d.length) return null;
		var c = d.charAt(at);
		if (c != "0" && c != "1") return null;
		at++;
		return c == "1";
	}
}
