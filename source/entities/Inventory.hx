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

	public function hasWaders():Bool {
		return has(Waders);
	}

	static function matchesItem(a:InventoryItem, b:InventoryItem):Bool {
		return switch [a, b] {
			case [Rock, Rock]: true;
			case [BigRock, BigRock]: true;
			case [Fish(_, _), Fish(_, _)]: true;
			case [Waders, Waders]: true;
			default: false;
		};
	}
}

enum InventoryItem {
	Rock;
	BigRock;
	Fish(fishSpriteIndex:Int, lengthCm:Int);
	Waders;
}
