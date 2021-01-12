import haxe.CallStack;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.net.Host;
import sys.net.Socket;
using StringTools;

/**
 * ...
 * @author YellowAfterlife
 */
class WebServerFor {
	static inline function addln(b:StringBuf, s:String) {
		b.add(s);
		b.addChar("\r".code);
		b.addChar("\n".code);
	}
	static var status:Int;
	static var noBody:Bool = false;
	static var mimeType:String = null;
	static var isIndex:Bool = false;
	
	static var indexPath:String;
	static var indexDir:String;
	static var cache:Map<String, WebServerCache> = new Map();
	
	static function error(i:Int, s:String = "") {
		status = i; return Bytes.ofString(s);
	}
	//
	static var reqURL:String;
	static var reqLen:Int;
	static var reqMethod:String;
	static function handle(req:String):Bytes {
		noBody = false;
		mimeType = MimeType.defValue;
		isIndex = false;
		reqURL = null;
		reqLen = -1;
		reqMethod = null;
		try {
			status = 200;
			//
			var lp = req.indexOf("\r");
			if (lp >= 0) req = req.substring(0, lp);
			//
			var sp = req.indexOf(" ");
			var kind = req.substring(0, sp);
			reqMethod = kind;
			var isHead = switch (kind) {
				case "GET": false;
				case "HEAD": true;
				default: return error(405, 'Wrong kind $kind');
			};
			noBody = isHead;
			sp += 1;
			//
			var qp = req.indexOf("?");
			if (qp < 0) qp = req.indexOf("#");
			if (qp < 0) qp = req.indexOf(" ", sp);
			if (qp < 0) qp = req.length;
			//
			var url = req.substring(sp, qp);
			reqURL = url;
			//trace(url);
			isIndex = (url == "/" || url == "/index.html");
			//
			var dir = indexDir;
			var full:String = isIndex ? indexPath : dir + url;
			if (!full.startsWith(dir)) {
				trace(full, dir);
				return error(403);
			} else if (!FileSystem.exists(full)) {
				return error(404);
			} else {
				mimeType = MimeType.get(Path.extension(full));
				var wantCache:Bool;
				if (isIndex) {
					wantCache = true;
				} else switch (mimeType) {
					case "text/html"
						|"text/css"
						|"application/javascript"
					: wantCache = true;
					default: wantCache = false;
				}
				if (wantCache) {
					var stat = FileSystem.stat(full);
					var item = cache[full];
					var bytes:Bytes;
					var statTime = stat.mtime.getTime();
					if (item == null) {
						if (isHead) {
							reqLen = stat.size;
							return null;
						}
						item = new WebServerCache();
						item.time = statTime;
						item.bytes = bytes = File.getBytes(full);
						cache[full] = item;
					} else if (item.time == statTime) {
						return item.bytes;
					} else {
						bytes = File.getBytes(full);
						if (bytes.length == item.bytes.length && isHead) {
							// for live.js HEAD we pretend that file size changed
							// so that non-size-altering changes are recognized
							// (e.g. tweaking hex colors in CSS)
							reqLen = bytes.length + 1;
						}
						item.bytes = bytes;
						item.time = statTime;
					}
					return bytes;
				}
				try {
					return File.getBytes(full);
				} catch (x:Dynamic) {
					return error(500, "" + x);
				}
			}
		} catch (x:Dynamic) {
			Sys.println("An error occurred: " + x);
			Sys.println(CallStack.toString(CallStack.exceptionStack()));
			return error(500);
		}
	}
	//
	public static function start(port:Int) {
		MimeType.init();
		var server = new Socket();
		while (true) {
			try {
				server.bind(new Host("0.0.0.0"), port);
				server.listen(8);
				break;
			} catch (e:Dynamic) {
				Sys.println('Failed to start server on port $port:');
				Sys.println(Std.string(e));
				Sys.print("New port (blank to exit)?: ");
				var v = Sys.stdin().readLine();
				if (v == "") return;
				var nport = Std.parseInt(v);
				if (nport == null) {
					Sys.println('Invalid port $v');
					Sys.stdin().readLine();
					return;
				} else port = nport;
			}
		}
		var bytes = Bytes.alloc(16384);
		Sys.println("Root directory: " + indexDir);
		Sys.println('Listening on port $port...');
		var lastTime = 0.;
		while (true) try {
			var client = server.accept();
			var length = client.input.readBytes(bytes, 0, bytes.length);
			var request = bytes.getString(0, length);
			//Sys.println(request);
			var peer = client.peer();
			var origin = peer.host.toString() + ":" + peer.port;
			var result = handle(request);
			if (status != 200) {
				Sys.println('[$origin] HTTP $status [$reqURL]');
			}
			var sb = new StringBuf();
			var rl = reqLen != -1 ? reqLen : result.length;
			addln(sb, 'HTTP/1.1 $status OK');
			addln(sb, "Server: WebServerFor");
			var ct = "Content-Type: " + mimeType;
			if (mimeType.startsWith("text/") || mimeType.indexOf("javascript") >= 0) ct += "; charset=utf-8";
			addln(sb, ct);
			addln(sb, "X-Content-Type-Options: nosniff");
			addln(sb, "Connection: close");
			addln(sb, "Content-length: " + rl);
			addln(sb, "Content-Range: bytes 0-" + rl + "/" + (rl + 1));
			addln(sb, "Cache-Control: no-cache");
			addln(sb, "Access-Control-Allow-Origin: *");
			addln(sb, "Accept-Ranges: bytes");
			addln(sb, "");
			client.output.writeString(sb.toString());
			if (!noBody) {
				client.output.writeBytes(result, 0, rl);
			}
			client.output.flush();
			client.close();
		} catch (_:Eof) {
			// that's an OK
		} catch (x:Dynamic) {
			Sys.println(x);
			Sys.println(CallStack.toString(CallStack.exceptionStack()));
		}
	}
	public static function main() {
		var args = Sys.args();
		var port:Null<Int> = null;
		var argi = 0;
		while (argi < args.length) {
			switch (args[argi]) {
				case "--port": {
					port = Std.parseInt(args[argi + 1]);
					args.splice(argi, 2);
				};
				default: argi += 1;
			}
		}
		//
		indexPath = Path.normalize(args[0]);
		if (indexPath == null) {
			Sys.println("Expected a path");
			Sys.getChar(false);
			return;
		}
		//
		indexDir = Path.directory(indexPath);
		if (indexDir == "") {
			var dir = Sys.getCwd();
			switch (dir.charAt(dir.length - 1)) {
				case "/", "\\": dir = dir.substr(0, dir.length - 1);
			}
			indexDir = Path.normalize(dir);
		}
		//
		var indexRel = Path.withoutDirectory(indexPath);
		if (indexRel == "index.html") indexRel = Path.withoutDirectory(Path.directory(indexPath));
		Sys.command("title", ["web:" + indexRel]);
		//
		var configPath = Path.directory(Sys.programPath()) + "/config.json";
		var config:WebServerConfig = {};
		if (FileSystem.exists(configPath)) try {
			config = haxe.Json.parse(File.getContent(configPath));
		} catch (x:Dynamic) {
			Sys.println("Error loading config: " + x);
		}
		if (config.port == null) config.port = 2000;
		//
		if (port == null) port = config.port;
		start(port);
	}
}
class WebServerCache {
	public var time:Float = 0;
	public var bytes:Bytes = null;
	public function new() {
		//
	}
}
typedef WebServerConfig = {
	?port:Int
}