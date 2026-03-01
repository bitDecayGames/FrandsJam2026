package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import levels.ldtk.Level;

class Shop extends FlxSprite {
	var playerInside:Bool = false;

	public function new() {
		super();
		makeGraphic(16, 16, FlxColor.YELLOW);
	}

	public function spawnRandom(level:Level) {
		var layer = level.fishSpawnerLayer;
		var w = layer.cWid;
		var h = layer.cHei;
		var grid = layer.gridSize;

		var candidates = new Array<Int>();
		for (cy in 0...h) {
			for (cx in 0...w) {
				if (layer.getInt(cx, cy) != 1) {
					candidates.push(cx + cy * w);
				}
			}
		}

		if (candidates.length == 0)
			return;

		var idx = candidates[FlxG.random.int(0, candidates.length - 1)];
		var cx = idx % w;
		var cy = Std.int(idx / w);
		setPosition(cx * grid, cy * grid);
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
