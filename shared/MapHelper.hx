package;

/**
 * Cross-platform MapSchema helpers.
 * The Colyseus server SDK (JS) and client SDK (HL) have different MapSchema APIs.
 * Server: map.set(k,v), map.delete(k), map.has(k), map.get(k), map.size
 * Client: map.items.set(k,v), map.items.remove(k), map.items.exists(k), map.items.get(k)
 * These use Dynamic + Reflect to work on both without type conflicts from schema macros.
**/
class MapHelper {
	public static function set(map:Dynamic, key:String, value:Dynamic):Void {
		#if server
		map.set(key, value);
		#else
		var items:Dynamic = map.items;
		items.set(key, value);
		#end
	}

	public static function delete(map:Dynamic, key:String):Void {
		#if server
		map.delete(key);
		#else
		var items:Dynamic = map.items;
		items.remove(key);
		#end
	}

	public static function has(map:Dynamic, key:String):Bool {
		#if server
		return map.has(key);
		#else
		var items:Dynamic = map.items;
		return items.exists(key);
		#end
	}

	public static function get(map:Dynamic, key:String):Dynamic {
		#if server
		return map.get(key);
		#else
		var items:Dynamic = map.items;
		return items.get(key);
		#end
	}
}
