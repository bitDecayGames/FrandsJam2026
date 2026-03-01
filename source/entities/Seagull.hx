package entities;

import flixel.FlxG;
import flixel.FlxSprite;

class Seagull extends FlxSprite {
	static inline var SPEED_MIN:Float = 40;
	static inline var SPEED_MAX:Float = 70;
	static inline var MARGIN:Float = 32;
	static inline var SOAR_MIN:Float = 0.8;
	static inline var SOAR_MAX:Float = 2.0;
	static inline var FLAP_MIN:Float = 1.5;
	static inline var FLAP_MAX:Float = 4.0;
	static inline var DRIFT_SPEED:Float = 10;
	static inline var DRIFT_MIN:Float = 0.5;
	static inline var DRIFT_MAX:Float = 1.5;

	var goingRight:Bool;
	var stateTimer:Float;
	var soaring:Bool = false;
	var driftTimer:Float;

	public function new(goingRight:Bool) {
		super();
		this.goingRight = goingRight;
		loadGraphic(AssetPaths.seagull__png, true, 24, 24);
		animation.add("fly", [1, 2, 3, 4], 8, true);
		animation.add("soar", [0], 1, false);
		animation.play("fly");
		flipX = goingRight;
		scrollFactor.set(0, 0);

		var speed = FlxG.random.float(SPEED_MIN, SPEED_MAX);
		velocity.x = goingRight ? speed : -speed;

		stateTimer = FlxG.random.float(FLAP_MIN, FLAP_MAX);
		driftTimer = FlxG.random.float(DRIFT_MIN, DRIFT_MAX);
		spawnAtEdge();
	}

	function spawnAtEdge() {
		if (goingRight) {
			x = -width - MARGIN;
		} else {
			x = FlxG.width + MARGIN;
		}
		y = FlxG.random.float(-8, FlxG.height * 0.4);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		stateTimer -= elapsed;
		if (stateTimer <= 0) {
			if (soaring) {
				soaring = false;
				animation.play("fly");
				stateTimer = FlxG.random.float(FLAP_MIN, FLAP_MAX);
			} else {
				soaring = true;
				animation.play("soar");
				stateTimer = FlxG.random.float(SOAR_MIN, SOAR_MAX);
			}
		}

		driftTimer -= elapsed;
		if (driftTimer <= 0) {
			driftTimer = FlxG.random.float(DRIFT_MIN, DRIFT_MAX);
			velocity.y = FlxG.random.float(-1, 1) * DRIFT_SPEED;
		}

		if ((goingRight && x > FlxG.width + MARGIN) || (!goingRight && x < -width - MARGIN)) {
			kill();
		}
	}
}
