package entities;

import entities.Inventory.InventoryItem;
import flixel.FlxG;
import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import levels.ldtk.Level;
import managers.GameManager;

class RockGroup extends FlxTypedGroup<Rock> {
	static inline var SPAWN_CHANCE:Float = 0.0025;

	var fishSpawner:FishSpawner;
	var parentState:FlxState;

	public function new(fishSpawner:FishSpawner, state:FlxState) {
		super();
		this.fishSpawner = fishSpawner;
		this.parentState = state;
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

	public function checkPickup(player:Player) {
		FlxG.overlap(player, this, handleOverlap);
	}

	function handleOverlap(player:Player, rock:Rock) {
		if (!player.inventory.isFull()) {
			player.pickupItem(Rock);
			rock.kill();
		}
	}

	public function addRock(x:Float, y:Float) {
		add(new Rock(x, y));
	}

	public function onLocalSplash(x:Float, y:Float) {
		FmodManager.PlaySoundOneShot(FmodSFX.RockSplash);
		fishSpawner.scareFish(x, y);
		GameManager.ME.net.sendMessage("rock_splash", {x: x, y: y});
		spawnSplash(x, y);
	}

	public function onRemoteSplash(x:Float, y:Float) {
		fishSpawner.scareFish(x, y);
		spawnSplash(x, y);
	}

	function spawnSplash(x:Float, y:Float) {
		// x, y is the rock's top-left; offset to rock center (8x8 sprite)
		parentState.add(new Splash(x + 4, y + 4));
		FlxG.camera.shake(0.005, 0.15);
	}

	public function clearAll() {
		for (r in this) {
			r.destroy();
		}
		clear();
	}
}
