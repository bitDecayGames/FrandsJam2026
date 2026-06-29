package entities;

import flixel.group.FlxGroup.FlxTypedGroup;

/**
 * Simple container for WaterFish sprites with an ID→sprite lookup map.
 * All fish AI runs server-side in GameLogic. This class only holds the
 * client-side sprites for rendering.
 **/
class FishSpawner extends FlxTypedGroup<WaterFish> {
	public var fishMap = new Map<String, WaterFish>();

	public function new() {
		super();
	}

	public function clearAll() {
		for (f in this) {
			f.destroy();
		}
		fishMap.clear();
		clear();
	}
}
