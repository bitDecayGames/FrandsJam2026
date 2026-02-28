package entities;

import flixel.util.FlxSignal;

class Inventory {
	public static inline var MAX_SLOTS:Int = 4;

	public var items:Array<InventoryItem> = [];
	public var onChange = new FlxSignal();

	public function new() {}

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
		return items.indexOf(item) != -1;
	}

	public function remove(item:InventoryItem):Bool {
		var idx = items.indexOf(item);
		if (idx == -1)
			return false;
		items.splice(idx, 1);
		onChange.dispatch();
		return true;
	}

	public function count():Int {
		return items.length;
	}
}

enum InventoryItem {
	Rock;
}
