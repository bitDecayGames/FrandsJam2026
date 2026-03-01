package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

class ButtFire extends FlxSprite {
	static inline var DURATION:Float = 0.4;
	static inline var RISE_SPEED:Float = -20;

	var elapsed:Float = 0;

	public function new(cx:Float, cy:Float, dirX:Float, dirY:Float) {
		super(cx, cy);

		var size = FlxG.random.int(2, 3);
		var color = FlxG.random.bool(60) ? FlxColor.fromRGB(255, FlxG.random.int(80, 140), 0) : FlxColor.fromRGB(255, FlxG.random.int(140, 200), 0);
		makeGraphic(size, size, color);
		x -= size / 2;
		y -= size / 2;

		// Emit in the opposite direction of movement + some spread
		velocity.x = dirX * FlxG.random.float(15, 35) + FlxG.random.float(-10, 10);
		velocity.y = dirY * FlxG.random.float(15, 35) + RISE_SPEED + FlxG.random.float(-5, 5);

		alpha = 0.9;
		allowCollisions = NONE;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		var t = elapsed / DURATION;
		if (t >= 1) {
			kill();
			return;
		}
		alpha = 0.9 * (1 - t);
	}
}
