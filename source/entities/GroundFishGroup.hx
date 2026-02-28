package entities;

import entities.Inventory.InventoryItem;
import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;

class GroundFishGroup extends FlxTypedGroup<GroundFish> {
	var waterLayer:ldtk.Layer_IntGrid;

	public function new() {
		super();
	}

	public function setWaterLayer(layer:ldtk.Layer_IntGrid) {
		waterLayer = layer;
	}

	public function checkPickup(player:Player) {
		FlxG.overlap(player, this, handleOverlap);
	}

	function handleOverlap(player:Player, fish:GroundFish) {
		if (fish.landing)
			return;
		if (!player.inventory.isFull()) {
			player.pickupItem(Fish);
			fish.kill();
		}
	}

	public function addFish(startX:Float, startY:Float, fishFrame:Int = 0) {
		// Pick a random landing spot 16-32px away that isn't water
		var landX = startX;
		var landY = startY;
		var found = false;

		for (_ in 0...20) {
			var angle = FlxG.random.float(0, Math.PI * 2);
			var dist = FlxG.random.float(16, 32);
			var tx = startX + Math.cos(angle) * dist;
			var ty = startY + Math.sin(angle) * dist;

			if (waterLayer != null) {
				var cx = Std.int(tx / waterLayer.gridSize);
				var cy = Std.int(ty / waterLayer.gridSize);
				if (cx >= 0 && cx < waterLayer.cWid && cy >= 0 && cy < waterLayer.cHei) {
					if (waterLayer.getInt(cx, cy) == 1)
						continue;
				}
			}

			landX = tx;
			landY = ty;
			found = true;
			break;
		}

		if (!found) {
			landX = startX + FlxG.random.float(-16, 16);
			landY = startY + FlxG.random.float(-16, 16);
		}

		add(new GroundFish(startX, startY, landX, landY, fishFrame));
	}

	public function clearAll() {
		for (f in this) {
			f.destroy();
		}
		clear();
	}
}
