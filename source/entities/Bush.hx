package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.util.FlxColor;
import entities.ButtFire;
import todo.TODO;

class Bush extends FlxSprite {
	static inline var SHAKE_DURATION:Float = 0.3;
	static inline var SHAKE_AMPLITUDE:Float = 2.0;
	static inline var SHAKE_FREQUENCY:Float = 30.0;
	static inline var COOLDOWN:Float = 0.5;
	static inline var BURN_FIRE_DURATION:Float = 3.0;
	static inline var BURN_BLINK_DURATION:Float = 1.0;
	static inline var BLINK_RATE:Float = 0.08;

	var shakeTimer:Float = 0;
	var cooldownTimer:Float = 0;
	var baseX:Float;
	var baseY:Float;
	var shakeDirX:Float = 1;
	var shakeDirY:Float = 0;
	var parentState:FlxState;

	public var burning:Bool = false;
	public var groundGroup:FlxGroup;
	public var onDeath:Void->Void;

	var burnTimer:Float = 0;
	var fireEmitTimer:Float = 0;
	var burnMarkSpawned:Bool = false;

	public function new(bx:Float, by:Float, state:FlxState) {
		super(bx, by);
		baseX = bx;
		baseY = by;
		parentState = state;
		loadGraphic(AssetPaths.bush__png);
		setSize(14, 6);
		offset.set(9, 20);
		immovable = true;
	}

	public static function onCollide(bush:Bush, player:Player) {
		var dx = bush.x + bush.width / 2 - (player.x + player.width / 2);
		var dy = bush.y + bush.height / 2 - (player.y + player.height / 2);
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist > 0) {
			bush.rustleFrom(dx / dist, dy / dist);
		} else {
			bush.rustleFrom(1, 0);
		}
	}

	public function ignite() {
		if (burning) {
			return;
		}
		burning = true;
		burnTimer = BURN_FIRE_DURATION + BURN_BLINK_DURATION;
		color = FlxColor.fromRGB(255, 100, 30);
		TODO.sfx("bush_fire");
	}

	public function rustleFrom(dirX:Float, dirY:Float) {
		if (cooldownTimer > 0) {
			return;
		}
		FmodManager.PlaySoundOneShot(FmodSFX.BushRustle);
		shakeDirX = dirX;
		shakeDirY = dirY;
		shakeTimer = SHAKE_DURATION;
		cooldownTimer = COOLDOWN;

		var gfxX = x - offset.x;
		var gfxY = y - offset.y;
		var gfxW:Float = frameWidth;
		var gfxH:Float = frameHeight;
		var inset = gfxW * 0.2;
		var canopyH = gfxH * 2 / 3;
		for (_ in 0...8) {
			parentState.add(new LeafParticle(gfxX + inset + FlxG.random.float(0, gfxW - inset * 2), gfxY + FlxG.random.float(0, canopyH)));
		}
	}

	override public function update(dt:Float) {
		super.update(dt);

		if (cooldownTimer > 0) {
			cooldownTimer -= dt;
		}

		if (burning) {
			burnTimer -= dt;

			// blink only during the final phase
			if (burnTimer <= BURN_BLINK_DURATION) {
				visible = (Std.int(burnTimer / BLINK_RATE) % 2 == 0);
			}

			// spit fire particles just like the player's butt fire
			fireEmitTimer += dt;
			if (fireEmitTimer >= 0.03) {
				fireEmitTimer = 0;
				var cx = baseX - offset.x + frameWidth * 0.5;
				var cy = baseY - offset.y + frameHeight * 0.5;
				for (_ in 0...3) {
					var fire = new ButtFire(cx + FlxG.random.float(-6, 6), cy + FlxG.random.float(-4, 4), FlxG.random.float(-1, 1), -1);
					parentState.add(fire);
				}
			}

			var totalDuration = BURN_FIRE_DURATION + BURN_BLINK_DURATION;
			if (!burnMarkSpawned && burnTimer <= totalDuration * 0.5) {
				burnMarkSpawned = true;
				spawnBurnMark();
			}

			if (burnTimer <= 0) {
				if (onDeath != null) {
					onDeath();
				}
				kill();
				return;
			}
		}

		if (shakeTimer > 0) {
			shakeTimer -= dt;
			if (shakeTimer <= 0) {
				x = baseX;
				y = baseY;
			} else {
				var wave = Math.sin(shakeTimer * SHAKE_FREQUENCY) * SHAKE_AMPLITUDE * (shakeTimer / SHAKE_DURATION);
				x = baseX + shakeDirX * wave;
				y = baseY + shakeDirY * wave;
			}
		}
	}

	function spawnBurnMark() {
		var mark = new FlxSprite();
		var w = 24;
		var h = 14;
		mark.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		var hw = w / 2.0;
		var hh = h / 2.0;
		for (py in 0...h) {
			for (px in 0...w) {
				var nx = (px - hw) / hw;
				var ny = (py - hh) / hh;
				var dist = nx * nx + ny * ny;
				if (dist <= 1) {
					// darker charred center, scorched edges
					if (dist < 0.4) {
						// inner char — dark black-brown
						mark.pixels.setPixel32(px, py, FlxColor.fromRGB(30, 20, 10, 200));
					} else {
						// outer scorch ring — dark brownish green
						mark.pixels.setPixel32(px, py, FlxColor.fromRGB(50, 40, 15, 160));
					}
				}
			}
		}
		mark.dirty = true;
		mark.solid = false;
		mark.allowCollisions = NONE;
		// center the burn mark on the bottom of the trunk (hitbox bottom)
		var gfxCenterX = baseX - offset.x + frameWidth * 0.5;
		var trunkBottomY = baseY + height;
		mark.setPosition(gfxCenterX - hw, trunkBottomY - hh - 3);
		if (groundGroup != null) {
			groundGroup.add(mark);
		} else {
			parentState.add(mark);
		}
	}

	override public function setPosition(X:Float = 0, Y:Float = 0) {
		super.setPosition(X, Y);
		baseX = X;
		baseY = Y;
	}
}
