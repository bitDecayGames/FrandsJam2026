package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

class LeafParticle extends FlxSprite {
	static inline var DURATION:Float = 0.4;
	static inline var DRIFT_SPEED:Float = 12;

	var elapsed:Float = 0;

	public function new(cx:Float, cy:Float) {
		super(cx, cy);
		makeGraphic(2, 2, FlxColor.fromRGB(60, 140, 50));
		x -= 1;
		y -= 1;

		var angle = FlxG.random.float(0, 2 * Math.PI);
		velocity.x = Math.cos(angle) * DRIFT_SPEED;
		velocity.y = Math.sin(angle) * DRIFT_SPEED - 10;
		alpha = 0.8;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		var t = elapsed / DURATION;
		if (t >= 1) {
			kill();
			return;
		}
		alpha = 0.8 * (1 - t);
	}
}
