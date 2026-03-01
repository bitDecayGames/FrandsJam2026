package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

class Ripple extends FlxSprite {
	static inline var DURATION:Float = 0.6;
	static inline var START_SCALE:Float = 0.5;
	static inline var END_SCALE:Float = 2.5;
	// Squash vertically to make an oval (top-down perspective)
	static inline var Y_SQUASH:Float = 0.55;

	var elapsed:Float = 0;

	public function new(cx:Float, cy:Float) {
		super(cx, cy);

		var size = 16;
		makeGraphic(size, size, FlxColor.TRANSPARENT, true);

		var r = Std.int(size / 2) - 1;
		var centerX = Std.int(size / 2);
		var centerY = Std.int(size / 2);
		var color = FlxColor.fromRGB(200, 220, 255, 180);
		drawCirclePixels(centerX, centerY, r, color);

		x -= size / 2;
		y -= size / 2;

		scale.set(START_SCALE, START_SCALE * Y_SQUASH);
		alpha = 0.7;
	}

	function drawCirclePixels(cx:Int, cy:Int, r:Int, color:FlxColor) {
		var px = r;
		var py = 0;
		var err = 1 - r;
		while (px >= py) {
			setPixelSafe(cx + px, cy + py, color);
			setPixelSafe(cx - px, cy + py, color);
			setPixelSafe(cx + px, cy - py, color);
			setPixelSafe(cx - px, cy - py, color);
			setPixelSafe(cx + py, cy + px, color);
			setPixelSafe(cx - py, cy + px, color);
			setPixelSafe(cx + py, cy - px, color);
			setPixelSafe(cx - py, cy - px, color);
			py++;
			if (err < 0) {
				err += 2 * py + 1;
			} else {
				px--;
				err += 2 * (py - px) + 1;
			}
		}
	}

	function setPixelSafe(px:Int, py:Int, color:FlxColor) {
		if (px >= 0 && px < Std.int(frameWidth) && py >= 0 && py < Std.int(frameHeight)) {
			pixels.setPixel32(px, py, color);
		}
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		var t = elapsed / DURATION;
		if (t >= 1) {
			kill();
			return;
		}
		var s = START_SCALE + (END_SCALE - START_SCALE) * t;
		scale.set(s, s * Y_SQUASH);
		alpha = 0.7 * (1 - t);
	}
}
