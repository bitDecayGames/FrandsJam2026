package entities;

import entities.Inventory.InventoryItem;
import flixel.FlxG;
import flixel.FlxSprite;
import levels.ldtk.Level;

class WadersPickup extends FlxSprite {
	public function new() {
		super();
		loadGraphic(AssetPaths.inventoryItems__png, true, 16, 16);
		animation.add("waders", [1]);
		animation.play("waders");
		visible = false;
	}

	public function spawn(level:Level) {
		var layer = level.fishSpawnerLayer;
		var w = layer.cWid;
		var h = layer.cHei;
		var grid = layer.gridSize;

		var landTiles:Array<{cx:Int, cy:Int}> = [];
		for (cy in 0...h) {
			for (cx in 0...w) {
				if (layer.getInt(cx, cy) != 1) {
					landTiles.push({cx: cx, cy: cy});
				}
			}
		}

		if (landTiles.length > 0) {
			var tile = landTiles[FlxG.random.int(0, landTiles.length - 1)];
			var px = tile.cx * grid + grid / 2;
			var py = tile.cy * grid + grid / 2;
			setPosition(px, py);
			centerOffsets();
			visible = true;
		}
	}

	public function checkPickup(player:Player) {
		if (!alive) {
			return;
		}
		FlxG.overlap(player, this, handleOverlap);
	}

	function handleOverlap(player:Player, waders:WadersPickup) {
		if (!player.inventory.isFull()) {
			player.pickupItem(Waders);
			kill();
		}
	}
}
