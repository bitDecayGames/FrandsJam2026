package entities;

import flixel.FlxG;
import flixel.group.FlxGroup.FlxTypedGroup;
import levels.ldtk.Level;

class RockGroup extends FlxTypedGroup<Rock> {
	static inline var SPAWN_CHANCE:Float = 0.0025;

	public function new() {
		super();
	}

	public function spawn(level:Level) {
		var layer = level.fishSpawnerLayer;
		var w = layer.cWid;
		var h = layer.cHei;
		var grid = layer.gridSize;

		for (cy in 0...h) {
			for (cx in 0...w) {
				if (layer.getInt(cx, cy) == 1)
					continue;
				if (FlxG.random.float() > SPAWN_CHANCE)
					continue;

				var px = cx * grid + FlxG.random.float(0, grid - 8);
				var py = cy * grid + FlxG.random.float(0, grid - 8);
				add(new Rock(px, py));
			}
		}
	}

	public function clearAll() {
		for (r in this) {
			r.destroy();
		}
		clear();
	}
}
