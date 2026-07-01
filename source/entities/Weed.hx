package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.util.FlxColor;
import entities.ButtFire;
import todo.TODO;

class Weed extends FlxSprite {
	static inline var BURN_FIRE_DURATION:Float = 3.0;
	static inline var BURN_BLINK_DURATION:Float = 1.0;
	static inline var BLINK_RATE:Float = 0.08;

	var parentState:FlxState;

	public var spawnCX:Float;
	public var spawnCY:Float;
	public var burning:Bool = false;
	public var groundGroup:FlxGroup;

	var burnTimer:Float = 0;
	var fireEmitTimer:Float = 0;
	var burnMarkSpawned:Bool = false;

	public function new(cx:Float, cy:Float, state:FlxState) {
		super(cx, cy);
		parentState = state;
		spawnCX = cx;
		spawnCY = cy;
		loadGraphic(AssetPaths.weed__png);
		x -= width / 2;
		y -= height / 2;
		var gfxH = frameHeight;
		setSize(frameWidth, 1);
		offset.set(0, gfxH - 1);
	}

	public function burst() {
		FmodManager.PlaySoundOneShot(FmodSFX.WeedsBurst);
		var cx = x - offset.x + frameWidth / 2;
		var cy = y - offset.y + frameHeight / 2;
		for (_ in 0...12) {
			parentState.add(new LeafParticle(cx + FlxG.random.float(-3, 3), cy + FlxG.random.float(-3, 3)));
		}
		kill();
	}

	public function ignite() {
		if (burning) {
			return;
		}
		burning = true;
		burnTimer = BURN_FIRE_DURATION + BURN_BLINK_DURATION;
		color = FlxColor.fromRGB(255, 100, 30);
		TODO.sfx("weed_fire");
	}

	override public function update(dt:Float) {
		super.update(dt);

		if (burning) {
			burnTimer -= dt;

			if (burnTimer <= BURN_BLINK_DURATION) {
				visible = (Std.int(burnTimer / BLINK_RATE) % 2 == 0);
			}

			fireEmitTimer += dt;
			if (fireEmitTimer >= 0.05) {
				fireEmitTimer = 0;
				var cx = x - offset.x + frameWidth * 0.5;
				var cy = y - offset.y + frameHeight * 0.5;
				var fire = new ButtFire(cx + FlxG.random.float(-2, 2), cy + FlxG.random.float(-2, 2), FlxG.random.float(-1, 1), -1);
				parentState.add(fire);
			}

			var totalDuration = BURN_FIRE_DURATION + BURN_BLINK_DURATION;
			if (!burnMarkSpawned && burnTimer <= totalDuration * 0.5) {
				burnMarkSpawned = true;
				spawnBurnMark();
			}

			if (burnTimer <= 0) {
				kill();
			}
		}
	}

	function spawnBurnMark() {
		var mark = new FlxSprite();
		var w = 10;
		var h = 6;
		mark.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		var hw = w / 2.0;
		var hh = h / 2.0;
		for (py in 0...h) {
			for (px in 0...w) {
				var nx = (px - hw) / hw;
				var ny = (py - hh) / hh;
				var dist = nx * nx + ny * ny;
				if (dist <= 1) {
					if (dist < 0.4) {
						mark.pixels.setPixel32(px, py, FlxColor.fromRGB(30, 20, 10, 200));
					} else {
						mark.pixels.setPixel32(px, py, FlxColor.fromRGB(50, 40, 15, 160));
					}
				}
			}
		}
		mark.dirty = true;
		mark.solid = false;
		mark.allowCollisions = NONE;
		var gfxCenterX = x - offset.x + frameWidth * 0.5;
		var baseBottom = y + height;
		mark.setPosition(gfxCenterX - hw, baseBottom - hh - 3);
		if (groundGroup != null) {
			groundGroup.add(mark);
		} else {
			parentState.add(mark);
		}
	}
}
