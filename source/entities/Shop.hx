package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import levels.ldtk.Level;

class Shop extends FlxSprite {
	var playerInside:Bool = false;

	public function new() {
		super();
		loadGraphic(AssetPaths.baitShop__png, false, 64, 48);
		immovable = true;
	}

	public static function onCollide(shop:Shop, _:Player) {
		// TODO Shop until you drop
	}

	// Re-written by Lumo, Proton’s multi‑model AI assistant
	// with some slight hooman modifications.
	public function spawnRandom(level:Level) {
		// Level grid information
		var layer = level.fishSpawnerLayer;
		var cols = layer.cWid; // number of cells horizontally
		var rows = layer.cHei; // number of cells vertically
		var gridSize = layer.gridSize; // size of one cell in pixels

		// Pixel dimensions of the whole level
		var levelPxW = cols * gridSize;
		var levelPxH = rows * gridSize;

		// Size of the shop sprite (set when the graphic is loaded)
		var shopW = this.width; // 64 px in the original asset
		var shopH = this.height; // 48 px in the original asset

		// Extra clearance we want around the shop (16 px on each side)
		var margin = 16;

		// Collect all cells that are walkable (value != 1) **and**
		// leave enough room for the shop + margin.
		var candidates = new Array<Int>();
		for (cy in 0...rows) {
			for (cx in 0...cols) {
				// 1️⃣  Cell must be walkable
				// TODO Handle water layer, shop will sometimes spawn partially in water
				if (layer.getInt(cx, cy) != 1) {
					// 2️⃣  Compute the pixel position where the shop’s top‑left corner would land
					var posX = cx * gridSize;
					var posY = cy * gridSize;

					// 3️⃣  Verify the margin constraints
					var fitsHorizontally = (posX - margin >= 0) && (posX + shopW + margin <= levelPxW);
					var fitsVertically = (posY - margin >= 0) && (posY + shopH + margin <= levelPxH);

					if (fitsHorizontally && fitsVertically) {
						// Store the linear index so we can pick a random one later
						candidates.push(cx + cy * cols);
					}
				}
			}
		}

		// No viable spots – just bail out
		if (candidates.length == 0) {
			QLog.error("Shop: no suitable location found to spawn.");
			return;
		}

		// Pick a random candidate and place the shop there
		var idx = candidates[FlxG.random.int(0, candidates.length - 1)];
		var finalCx = idx % cols;
		var finalCy = Std.int(idx / cols);
		setPosition(finalCx * gridSize, finalCy * gridSize);
	}

	public function checkInteraction(player:Player) {
		var overlapping = FlxG.overlap(this, player);
		if (overlapping && !playerInside) {
			sellFish(player);
			playerInside = true;
		} else if (!overlapping) {
			playerInside = false;
		}
	}

	function sellFish(player:Player) {
		var count = 0;
		while (player.inventory.removeAnyFish() != -1) {
			count++;
		}
		if (count > 0) {
			player.score += count * 10;
			QLog.notice('Sold $count fish for ${count * 10} points. Total score: ${player.score}');
		}
	}
}
