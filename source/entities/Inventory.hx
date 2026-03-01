package entities;

import flixel.util.FlxSignal;

class Inventory {
	public static inline var MAX_SLOTS:Int = 4;

	public var items:Array<InventoryItem> = [];
	public var onChange = new FlxSignal();

	public function new() {
		#if rocks
		for (_ in 0...MAX_SLOTS) {
			items.push(Rock);
		}
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
				case Fish(idx):
					items.splice(i, 1);
					onChange.dispatch();
					return idx;
				default:
			}
		}
		return -1;
	}

	public function count():Int {
		return items.length;
	}

	static function matchesItem(a:InventoryItem, b:InventoryItem):Bool {
		return switch [a, b] {
			case [Rock, Rock]: true;
			case [Fish(_), Fish(_)]: true;
			default: false;
		};
	}
}

enum InventoryItem {
	Rock;
	Fish(fishSpriteIndex:Int);
}
