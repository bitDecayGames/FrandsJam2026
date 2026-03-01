package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

class WaterSparkle extends FlxSprite {
	static inline var DURATION:Float = 0.3;
	static inline var FADE_IN:Float = 0.1;

	var elapsed:Float = 0;

	public function new(wx:Float, wy:Float) {
		super(wx, wy);
		makeGraphic(2, 2, FlxColor.WHITE);
		x -= 1;
		y -= 1;
		alpha = 0;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		if (elapsed >= DURATION) {
			kill();
			return;
		}
		if (elapsed < FADE_IN) {
			alpha = 0.8 * (elapsed / FADE_IN);
		} else {
			alpha = 0.8 * (1 - (elapsed - FADE_IN) / (DURATION - FADE_IN));
		}
	}
}
