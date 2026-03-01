package entities;

import bitdecay.flixel.debug.tools.draw.DebugDraw;
import debug.DebugLayers;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.util.FlxColor;
import levels.ldtk.BDTilemap;

class SeagullPoop extends FlxSprite {
	static inline var GRAVITY:Float = 200;
	static inline var SCARE_RADIUS:Float = 30;

	var targetY:Float;
	var parentState:FlxState;
	var terrain:BDTilemap;
	var fishSpawner:FishSpawner;

	public function new(worldX:Float, worldY:Float, fallDistance:Float, birdVelX:Float, state:FlxState, terrain:BDTilemap,
			fishSpawner:FishSpawner) {
		super(worldX, worldY);
		makeGraphic(2, 2, FlxColor.WHITE);
		x -= 1;
		y -= 1;
		targetY = worldY + fallDistance;
		parentState = state;
		this.terrain = terrain;
		this.fishSpawner = fishSpawner;
		velocity.x = birdVelX;
		velocity.y = 0;
		acceleration.y = GRAVITY;
		allowCollisions = NONE;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);
		if (y >= targetY) {
			var landX = x + 1;
			var landY = targetY;
			var isWater = false;
			if (terrain != null) {
				var color = terrain.sampleColorAt(landX, landY);
				if (color != FlxColor.TRANSPARENT) {
					isWater = color.blue > color.red && color.blue > 80;
				}
			}
			if (isWater) {
				parentState.add(new Splash(landX, landY, false));
				if (fishSpawner != null) {
					fishSpawner.scareFish(landX, landY, SCARE_RADIUS);
				}
			} else {
				parentState.add(new PoopSplat(landX, landY));
			}
			kill();
		}
	}
}
