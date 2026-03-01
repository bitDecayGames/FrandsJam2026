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
	var parentState:FlxState;

	public function new(bx:Float, by:Float, state:FlxState) {
		super(bx, by);
		baseX = bx;
		parentState = state;
		loadGraphic(AssetPaths.bush__png);
		setSize(14, 6);
		offset.set(9, 20);
		immovable = true;
	}

	public static function onCollide(bush:Bush, _:Player) {
		bush.rustle();
	}

	public function rustle() {
		if (cooldownTimer > 0) {
			return;
		}
		shakeTimer = SHAKE_DURATION;
		cooldownTimer = COOLDOWN;

		for (_ in 0...4) {
			parentState.add(new LeafParticle(x + width / 2 + FlxG.random.float(-6, 6), y + height / 2 + FlxG.random.float(-6, 6)));
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
			} else {
				x = baseX + Math.sin(shakeTimer * SHAKE_FREQUENCY) * SHAKE_AMPLITUDE * (shakeTimer / SHAKE_DURATION);
			}
		}
	}

	override public function setPosition(X:Float = 0, Y:Float = 0) {
		super.setPosition(X, Y);
		baseX = X;
	}
}
