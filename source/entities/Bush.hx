package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;

class Bush extends FlxSprite {
	static inline var SHAKE_DURATION:Float = 0.3;
	static inline var SHAKE_AMPLITUDE:Float = 2.0;
	static inline var SHAKE_FREQUENCY:Float = 30.0;
	static inline var COOLDOWN:Float = 0.5;

	var shakeTimer:Float = 0;
	var cooldownTimer:Float = 0;
	var baseX:Float;
	var baseY:Float;
	var shakeDirX:Float = 1;
	var shakeDirY:Float = 0;
	var parentState:FlxState;

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

	public function rustleFrom(dirX:Float, dirY:Float) {
		if (cooldownTimer > 0) {
			return;
		}
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

	override public function setPosition(X:Float = 0, Y:Float = 0) {
		super.setPosition(X, Y);
		baseX = X;
		baseY = Y;
	}
}
