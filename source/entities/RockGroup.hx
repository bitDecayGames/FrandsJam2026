package entities;

import entities.Inventory.InventoryItem;
import flixel.FlxG;
import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import levels.ldtk.Level;
import managers.GameManager;

class RockGroup extends FlxTypedGroup<Rock> {
	static inline var SPAWN_CHANCE:Float = 0.0025;
	static inline var BIG_SPAWN_CHANCE:Float = 0.0006;

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

		var landTiles:Array<{cx:Int, cy:Int}> = [];
		for (cy in 0...h) {
			for (cx in 0...w) {
				if (layer.getInt(cx, cy) != 1) {
					landTiles.push({cx: cx, cy: cy});
				}
			}
		}

		var hasBigRock = false;
		for (tile in landTiles) {
			var roll = FlxG.random.float();
			if (roll >= SPAWN_CHANCE + BIG_SPAWN_CHANCE)
				continue;

			var px = tile.cx * grid + FlxG.random.float(0, grid - 8);
			var py = tile.cy * grid + FlxG.random.float(0, grid - 8);

			if (roll < BIG_SPAWN_CHANCE) {
				add(new Rock(px, py, true));
				hasBigRock = true;
			} else {
				add(new Rock(px, py));
			}
		}

		if (!hasBigRock && landTiles.length > 0) {
			var tile = landTiles[FlxG.random.int(0, landTiles.length - 1)];
			var px = tile.cx * grid + FlxG.random.float(0, grid - 8);
			var py = tile.cy * grid + FlxG.random.float(0, grid - 8);
			add(new Rock(px, py, true));
		}
	}

	public function checkPickup(player:Player) {
		FlxG.overlap(player, this, handleOverlap);
	}

	function handleOverlap(player:Player, rock:Rock) {
		if (!player.inventory.isFull()) {
			player.pickupItem(rock.big ? BigRock : Rock);
			rock.kill();
		}
	}

	public function addRock(x:Float, y:Float, big:Bool) {
		add(new Rock(x, y, big));
	}

	public function onLocalSplash(x:Float, y:Float, big:Bool) {
		FmodManager.PlaySoundOneShot(FmodSFX.RockSplash);
		fishSpawner.scareFish(x, y, big ? 160 : 80);
		GameManager.ME.net.sendMessage("rock_splash", {x: x, y: y, big: big});
		spawnSplash(x, y, big);
	}

	public function onRemoteSplash(x:Float, y:Float, big:Bool) {
		FmodManager.PlaySoundOneShot(FmodSFX.RockSplash);
		fishSpawner.scareFish(x, y, big ? 160 : 80);
		spawnSplash(x, y, big);
	}

	function spawnSplash(x:Float, y:Float, big:Bool) {
		// x, y is the rock's top-left; offset to rock center (8x8 sprite)
		parentState.add(new Splash(x + 4, y + 4, big));
		FlxG.camera.shake(big ? 0.008 : 0.005, big ? 0.2 : 0.15);
	}

	public function clearAll() {
		for (r in this) {
			r.destroy();
		}
		clear();
	}
}
