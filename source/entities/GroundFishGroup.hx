package entities;

import entities.Inventory.InventoryItem;
import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;

class GroundFishGroup extends FlxTypedGroup<GroundFish> {
	public function new() {
		super();
	}

	public function checkPickup(player:Player) {
		FlxG.overlap(player, this, handleOverlap);
	}

	function handleOverlap(player:Player, fish:GroundFish) {
		if (!player.inventory.isFull()) {
			player.pickupItem(Fish);
			fish.kill();
		}
	}

	public function addFish(x:Float, y:Float) {
		add(new GroundFish(x, y));
	}

	public function clearAll() {
		for (f in this) {
			f.destroy();
		}
		clear();
	}
}
