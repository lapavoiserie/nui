package nui;

/**
	What an `Image` node's `src` names, and whether it may be loaded here.

	One key with a scheme, rather than a key per kind: a tree that arrives has to
	be understood without the program that built it, and the scheme is the part
	of the value that says how.

	| scheme | names | in a tree built here | in a tree received |
	|---|---|---|---|
	| `asset:path` | a file shipped in the application | yes | yes |
	| `asset:path#sha256=…` | the same, with the digest its sender computed | yes | yes |
	| `blob:sha256=…` | a picture made at run time, served by its sender | yes | yes |
	| `https://…` | a picture on the web | yes | only from a trusted host |
	| `data:image/png;base64,…` | a small picture in the tree itself | yes | up to 256 KiB decoded |
	| `file:///…` | a local path | yes | never |

	Anything else — `http:`, a relative path, a typo — is never loaded.

	## Why these rules, once, here

	A received `https:` is refused unless the panel trusts the host: a panel that
	fetched whatever URL a tree named would contact any host its sender chose, a
	tracking pixel by construction. A received `file:` is refused outright: a
	peer must not make a device read its own disk. Six renderers answering those
	questions each would be six chances to answer one of them wrongly, so they
	ask this class.

	A refused source is an `Invalid` with a reason. The renderer draws the
	image's `alt` in its place — never a broken-image glyph.
**/
class ImageSource {
	/** The largest picture a received `data:` source may decode to. **/
	public static inline var MAX_RECEIVED_DATA_BYTES = 256 * 1024;

	/** Parse without judging where it came from. **/
	public static function parse(src:Null<String>):ImageSourceKind {
		if (src == null || src == "") return Invalid("no source");
		if (StringTools.startsWith(src, "asset:")) return asset(src.substr(6));
		if (StringTools.startsWith(src, "blob:")) {
			var digest = digestOf(src.substr(5));
			return digest == null ? Invalid("a blob is named by sha256=<64 hex digits>") : Blob(digest);
		}
		if (StringTools.startsWith(src, "https://")) {
			var host = hostOf(src);
			return host == "" ? Invalid("an https source needs a host") : Https(src, host);
		}
		if (StringTools.startsWith(src, "data:")) return data(src.substr(5));
		if (StringTools.startsWith(src, "file:///")) {
			var path = src.substr(7);
			return path.length > 1 ? File(path) : Invalid("an empty file path");
		}
		if (StringTools.startsWith(src, "http://")) return Invalid("http is not loaded: use https");
		return Invalid("unknown scheme");
	}

	/**
		Parse, then judge: what may be loaded for a tree built here, or for one
		received — `trustedHosts` being the hosts a panel accepts `https:` from.
	**/
	public static function check(src:Null<String>, received:Bool, ?trustedHosts:Array<String>):ImageSourceKind {
		var kind = parse(src);
		if (!received) return kind;
		return switch (kind) {
			case File(_): Invalid("a received tree may not name a local file");
			case Https(_, host) if (trustedHosts == null || trustedHosts.indexOf(host) < 0):
				Invalid('a received tree may not load from $host: it is not a trusted host');
			case Data(_, base64) if (decodedLength(base64) > MAX_RECEIVED_DATA_BYTES):
				Invalid("a received data source is larger than 256 KiB");
			case _: kind;
		}
	}

	static function asset(rest:String):ImageSourceKind {
		var digest:Null<String> = null;
		var hash = rest.indexOf("#");
		if (hash >= 0) {
			digest = digestOf(rest.substr(hash + 1));
			if (digest == null) return Invalid("an asset digest is written sha256=<64 hex digits>");
			rest = rest.substr(0, hash);
		}
		if (rest == "") return Invalid("an empty asset path");
		if (StringTools.startsWith(rest, "/") || rest.indexOf("\\") >= 0)
			return Invalid("an asset path is relative, with forward slashes");
		for (part in rest.split("/"))
			if (part == "" || part == "." || part == "..")
				return Invalid("an asset path may not climb out of the assets");
		return Asset(rest, digest);
	}

	static function data(rest:String):ImageSourceKind {
		var comma = rest.indexOf(",");
		if (comma < 0) return Invalid("a data source has no comma");
		var header = rest.substr(0, comma);
		if (!StringTools.endsWith(header, ";base64")) return Invalid("a data source must be base64");
		var mime = header.substr(0, header.length - 7);
		if (mime != "image/png" && mime != "image/jpeg") return Invalid("a data source is image/png or image/jpeg");
		var base64 = rest.substr(comma + 1);
		if (base64 == "" || !~/^[A-Za-z0-9+\/]*={0,2}$/.match(base64)) return Invalid("a data source is not base64");
		return Data(mime, base64);
	}

	static function digestOf(text:String):Null<String> {
		if (!StringTools.startsWith(text, "sha256=")) return null;
		var hex = text.substr(7);
		return ~/^[0-9a-f]{64}$/.match(hex) ? hex : null;
	}

	static function hostOf(url:String):String {
		var rest = url.substr(8);
		var end = rest.length;
		for (stop in ["/", "?", "#"]) {
			var at = rest.indexOf(stop);
			if (at >= 0 && at < end) end = at;
		}
		var authority = rest.substr(0, end);
		// A user part is not a host: `https://trusted@evil` goes to evil.
		var at = authority.lastIndexOf("@");
		if (at >= 0) authority = authority.substr(at + 1);
		var colon = authority.indexOf(":");
		if (colon >= 0) authority = authority.substr(0, colon);
		return authority.toLowerCase();
	}

	/** How many bytes a base64 text decodes to, without decoding it. **/
	static function decodedLength(base64:String):Int {
		var padding = StringTools.endsWith(base64, "==") ? 2 : StringTools.endsWith(base64, "=") ? 1 : 0;
		return Std.int(base64.length / 4) * 3 - padding;
	}
}

enum ImageSourceKind {
	/** A file shipped in the application, and the digest its sender gave, if any. **/
	Asset(path:String, digest:Null<String>);

	/** A picture made at run time, named by its content. **/
	Blob(digest:String);

	/** A picture on the web, and its host, lower-case. **/
	Https(url:String, host:String);

	/** A picture carried in the source itself. **/
	Data(mime:String, base64:String);

	/** A local path, absolute. **/
	File(path:String);

	/** Nothing to load, and why: the renderer shows the `alt`. **/
	Invalid(reason:String);
}
