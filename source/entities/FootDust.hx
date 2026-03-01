package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

class FootDust extends FlxSprite {
	static inline var DURATION:Float = 0.35;
	static inline var DRIFT_SPEED:Float = 8;

	var elapsed:Float = 0;

	public function new(cx:Float, cy:Float) {
		super(cx, cy);
		makeGraphic(3, 3, FlxColor.fromRGB(170, 155, 130));
		x -= 1;
		y -= 1;

		// Drift outward in a random direction
		var angle = FlxG.random.float(0, 2 * Math.PI);
		velocity.x = Math.cos(angle) * DRIFT_SPEED;
		velocity.y = Math.sin(angle) * DRIFT_SPEED - 6; // slight upward bias
		alpha = 0.6;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		var t = elapsed / DURATION;
		if (t >= 1) {
			kill();
			return;
		}
		alpha = 0.6 * (1 - t);
	}
}
