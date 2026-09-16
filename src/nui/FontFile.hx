package nui;

import haxe.io.Bytes;

/**
	What a font file says about itself, read while the application compiles.

	A family name, a weight and whether the face is italic are written **in the
	file** -- in its `name` and `OS/2` tables -- and every platform that
	registers a font reads them from there. So an application that ships
	`Inter-Bold.ttf` should not also have to tell `mui` that it is Inter, that
	it is bold, and that it is upright: it would be saying again, in a place
	nothing checks, what the file already says in the place every platform
	looks.

	Read here rather than in one backend because every build needs it: a font
	an application ships must be registered with the platform, and what to
	register it as is written in the file. TrueType and OpenType alike --
	`ttf`, `otf`, and the `ttc` collection's first face -- because the table
	directory is the same in all of them.
**/
class FontFile {
	/** What a face is, as its own file says. **/
	public static function read(bytes:Bytes):Null<Face> {
		if (bytes == null || bytes.length < 12) return null;
		var at = 0;
		// A collection: take the first face's table directory.
		if (bytes.getString(0, 4) == "ttcf") {
			if (bytes.length < 16) return null;
			at = int32(bytes, 12);
			if (at < 0 || at + 12 > bytes.length) return null;
		}
		var version = bytes.getString(at, 4);
		if (version != "\x00\x01\x00\x00" && version != "OTTO" && version != "true") return null;

		var tables = int16(bytes, at + 4);
		var name:Null<{offset:Int, length:Int}> = null;
		var os2:Null<{offset:Int, length:Int}> = null;
		var head:Null<{offset:Int, length:Int}> = null;
		for (i in 0...tables) {
			var entry = at + 12 + i * 16;
			if (entry + 16 > bytes.length) return null;
			var kind = bytes.getString(entry, 4);
			var record = {offset: int32(bytes, entry + 8), length: int32(bytes, entry + 12)};
			switch (kind) {
				case "name": name = record;
				case "OS/2": os2 = record;
				case "head": head = record;
				case _:
			}
		}
		if (name == null) return null;

		var family = nameOf(bytes, name, [16, 1]);
		if (family == null || family == "") return null;
		var subfamily = nameOf(bytes, name, [17, 2]);

		// The weight is a number in OS/2; without that table the subfamily's
		// word is the only thing left to read, which is what it is for.
		var weight = 400;
		var italic = false;
		if (os2 != null && os2.offset + 64 <= bytes.length) {
			weight = int16(bytes, os2.offset + 4);
			// fsSelection, bit 0: italic.
			var selection = int16(bytes, os2.offset + 62);
			italic = (selection & 1) != 0;
		} else if (head != null && head.offset + 46 <= bytes.length) {
			// macStyle, bit 1: italic. Bit 0 says bold, which is not a weight.
			var style = int16(bytes, head.offset + 44);
			italic = (style & 2) != 0;
			if ((style & 1) != 0) weight = 700;
		}
		if (subfamily != null) {
			var said = subfamily.toLowerCase();
			if (said.indexOf("italic") >= 0 || said.indexOf("oblique") >= 0) italic = true;
			if (os2 == null) weight = weightOf(said, weight);
		}
		if (weight < 1 || weight > 1000) weight = 400;
		return {family: family, weight: weight, italic: italic};
	}

	/** The weight a subfamily's word names, for a file with no `OS/2` table. **/
	static function weightOf(subfamily:String, fallback:Int):Int {
		for (word => weight in [
			"thin" => 100, "extralight" => 200, "ultralight" => 200, "light" => 300,
			"regular" => 400, "normal" => 400, "medium" => 500, "semibold" => 600,
			"demibold" => 600, "bold" => 700, "extrabold" => 800, "ultrabold" => 800,
			"black" => 900, "heavy" => 900
		])
			if (subfamily.indexOf(word) >= 0) return weight;
		return fallback;
	}

	/**
		A string from the `name` table, by the ids given in order of preference.

		The typographic family (16) before the legacy one (1): a family with
		more than four faces splits itself across several legacy families --
		"Inter" and "Inter Semibold" -- and the typographic name is the one that
		holds them together, which is what a renderer is asked for.

		Only Macintosh records (platform 1) are a single byte per character;
		Windows (3) and Unicode (0) ones are UTF-16, and reading one of those a
		byte at a time gives " . S F" for ".SF NS" -- which is how this was
		found. Both kinds are read; a file usually has both, saying the same
		thing.
	**/
	static function nameOf(bytes:Bytes, table:{offset:Int, length:Int}, ids:Array<Int>):Null<String> {
		if (table.offset + 6 > bytes.length) return null;
		var count = int16(bytes, table.offset + 2);
		var storage = table.offset + int16(bytes, table.offset + 4);
		for (wanted in ids) {
			for (i in 0...count) {
				var record = table.offset + 6 + i * 12;
				if (record + 12 > bytes.length) return null;
				if (int16(bytes, record + 6) != wanted) continue;
				var platform = int16(bytes, record);
				var length = int16(bytes, record + 8);
				var offset = storage + int16(bytes, record + 10);
				if (offset + length > bytes.length) continue;
				var said = platform == 1 ? bytes.getString(offset, length) : utf16(bytes, offset, length);
				if (said != null && said != "") return said;
			}
		}
		return null;
	}

	static function utf16(bytes:Bytes, offset:Int, length:Int):String {
		var out = new StringBuf();
		var i = 0;
		while (i + 1 < length) {
			out.addChar((bytes.get(offset + i) << 8) | bytes.get(offset + i + 1));
			i += 2;
		}
		return out.toString();
	}

	static inline function int16(bytes:Bytes, at:Int):Int
		return (bytes.get(at) << 8) | bytes.get(at + 1);

	static inline function int32(bytes:Bytes, at:Int):Int
		return (bytes.get(at) << 24) | (bytes.get(at + 1) << 16) | (bytes.get(at + 2) << 8) | bytes.get(at + 3);
}

/** One face of a family, as its file says: a weight, upright or italic. **/
typedef Face = {
	var family:String;
	var weight:Int;
	var italic:Bool;
}
