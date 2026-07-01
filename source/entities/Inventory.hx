package entities;

import flixel.util.FlxSignal;

class Inventory {
	public static inline var MAX_SLOTS:Int = 4;

	public var items:Array<InventoryItem> = [];
	public var onChange = new FlxSignal();

	public function new() {
		#if rock
		items.push(Rock);
		#end
		#if bigrock
		items.push(BigRock);
		#end
		#if waders
		items.push(Waders);
		#end
	}

	public function add(item:InventoryItem):Bool {
		if (isFull())
			return false;
		items.push(item);
		onChange.dispatch();
		return true;
	}

	public function isFull():Bool {
		return items.length >= MAX_SLOTS;
	}

	public function has(item:InventoryItem):Bool {
		for (it in items) {
			if (matchesItem(it, item))
				return true;
		}
		return false;
	}

	public function remove(item:InventoryItem):Bool {
		for (i in 0...items.length) {
			if (matchesItem(items[i], item)) {
				items.splice(i, 1);
				onChange.dispatch();
				return true;
			}
		}
		return false;
	}

	/** Removes the first Fish from inventory and returns its fishSpriteIndex, or -1 if none. */
	public function removeAnyFish():Int {
		for (i in 0...items.length) {
			switch (items[i]) {
				case Fish(idx, _):
					items.splice(i, 1);
					onChange.dispatch();
					return idx;
				default:
			}
		}
		return -1;
	}

	/** Removes the first Fish and returns {typeIndex, lengthCm}, or null if none. */
	public function removeAnyFishFull():Null<{typeIndex:Int, lengthCm:Int}> {
		for (i in 0...items.length) {
			switch (items[i]) {
				case Fish(idx, len):
					items.splice(i, 1);
					onChange.dispatch();
					return {typeIndex: idx, lengthCm: len};
				default:
			}
		}
		return null;
	}

	public function count():Int {
		return items.length;
	}

	public function getItems():Array<InventoryItem> {
		return items.copy();
	}

	public function clear() {
		items = [];
		onChange.dispatch();
	}

	public function hasWaders():Bool {
		return has(Waders);
	}

	/** Replace local inventory with server state */
	public function syncFromServer(serverItems:Array<Dynamic>) {
		items = [];
		if (serverItems != null) {
			for (s in serverItems) {
				var decoded = decodeItem(s);
				if (decoded != null) { items.push(decoded); }
			}
		}
		onChange.dispatch();
	}

	public static function encodeItem(item:InventoryItem):Dynamic {
		return switch (item) {
			case Rock: {type: "rock"};
			case BigRock: {type: "big_rock"};
			case Fish(idx, len): {type: "fish", fishType: idx, lengthCm: len};
			case Waders: {type: "waders"};
			case Rocket: {type: "rocket"};
			case HungerPotion: {type: "hunger_potion"};
			case FishBait: {type: "fish_bait"};
		};
	}

	public static function decodeItem(data:Dynamic):InventoryItem {
		var t:String = data.type;
		if (t == "rock") { return Rock; }
		if (t == "big_rock") { return BigRock; }
		if (t == "fish") { return Fish(Std.int(data.fishType), Std.int(data.lengthCm)); }
		if (t == "waders") { return Waders; }
		if (t == "rocket") { return Rocket; }
		if (t == "hunger_potion") { return HungerPotion; }
		if (t == "fish_bait") { return FishBait; }
		return null;
	}

	static function matchesItem(a:InventoryItem, b:InventoryItem):Bool {
		return switch [a, b] {
			case [Rock, Rock]: true;
			case [BigRock, BigRock]: true;
			case [Fish(_, _), Fish(_, _)]: true;
			case [Waders, Waders]: true;
			case [Rocket, Rocket]: true;
			case [HungerPotion, HungerPotion]: true;
			case [FishBait, FishBait]: true;
			default: false;
		};
	}
}

enum InventoryItem {
	Rock;
	BigRock;
	Fish(fishSpriteIndex:Int, lengthCm:Int);
	Waders;
	Rocket;
	HungerPotion;
	FishBait;
}
