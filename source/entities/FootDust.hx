package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

class FootDust extends FlxSprite {
	static inline var DURATION:Float = 0.8;
	static inline var DRIFT_SPEED:Float = 8;

	var elapsed:Float = 0;
	var startAlpha:Float;

	public function new(cx:Float, cy:Float, color:FlxColor, splash:Bool) {
		super(cx, cy);
		var dustColor = FlxColor.interpolate(color, FlxColor.WHITE, 0.3);
		makeGraphic(2, 2, dustColor);
		x -= 1;
		y -= 1;

		var angle = FlxG.random.float(0, 2 * Math.PI);
		if (splash) {
			var splashSpeed = DRIFT_SPEED * 2.5;
			velocity.x = Math.cos(angle) * splashSpeed;
			velocity.y = Math.sin(angle) * splashSpeed - 10;
			startAlpha = 0.7;
		} else {
			velocity.x = Math.cos(angle) * DRIFT_SPEED;
			velocity.y = Math.sin(angle) * DRIFT_SPEED - 6;
			startAlpha = 0.6;
		}
		alpha = startAlpha;
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
		alpha = startAlpha * (1 - t);
	}
}
